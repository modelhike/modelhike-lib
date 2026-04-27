import Testing
@testable import ModelHike

@Suite struct FlowParser_Tests {
    private func parseModel(_ dsl: String) async throws -> (LoadContext, ModelSpace) {
        let ctx = LoadContext(config: PipelineConfig())
        let modelSpace = try await ModelFileParser(with: ctx).parse(string: dsl, identifier: "FlowParser_Tests")
        await ctx.model.append(contentsOf: modelSpace)
        try await ctx.model.resolveAndLinkItems(with: ctx)
        return (ctx, modelSpace)
    }

    private func moduleNamed(_ name: String, space: ModelSpace) async -> C4Component? {
        for module in await space.modules.snapshot() {
            if await module.name == name { return module }
        }
        return nil
    }

    private func flowNamed(_ name: String, in module: C4Component) async throws -> FlowObject {
        for item in await module.items {
            if let flow = item as? FlowObject, await flow.name == name {
                return flow
            }
        }
        return try #require(nil as FlowObject?)
    }

    @Test func lifecycleFlowParsesStatesTransitionsDirectivesAndMode() async throws {
        let (_, space) = try await parseModel(#"""
            ===
            Svc
            ===
            + Orders

            === Orders ===

            Order Lifecycle
            >>>>>>
            @ trigger:: order.created
            state Draft
            | enter create draft
            state Submitted
            \__ [*] -> Draft : create
            \__ Draft -> Submitted : submit { total > 0 } [customer, admin]
            \__ Submitted -> [*] : archive
            """#)

        let module = try #require(await moduleNamed("Orders", space: space))
        let flow = try await flowNamed("OrderLifecycle", in: module)

        #expect(await flow.dataType == .lifecycle)
        #expect(await flow.mode == .lifecycle)
        #expect(await flow.directives.map(\.name) == ["trigger"])
        #expect(await flow.states.map(\.name) == ["Draft", "Submitted"])

        let transitions = await flow.transitions
        #expect(transitions.count == 3)
        #expect(transitions[0].from == "[*]")
        #expect(transitions[0].to == "Draft")
        #expect(transitions[1].guardExpression == "total > 0")
        #expect(transitions[1].roles == ["customer", "admin"])
        #expect(transitions[2].to == "[*]")
    }

    @Test func workflowFlowParsesParticipantsMessagesWaitsCallsAndSteps() async throws {
        let (_, space) = try await parseModel(#"""
            ===
            Svc
            ===
            + Orders

            === Orders ===

            Checkout Flow
            >>>>>>
            [Customer] as human
            [API] as service
            Customer --> API : submit(order)
            wait Customer : confirm -> confirmation
            | sla: 3 days
            run @"ValidateOrder" with order -> validation
            ==> Validate order
            """#)

        let module = try #require(await moduleNamed("Orders", space: space))
        let flow = try await flowNamed("CheckoutFlow", in: module)

        #expect(await flow.dataType == .workflow)
        #expect(await flow.mode == .workflow)
        #expect(await flow.participants.map(\.name) == ["Customer", "API"])
        #expect(await flow.messages.first?.arrow == .sync)
        #expect(await flow.waits.first?.result == "confirmation")
        #expect(await flow.waits.first?.directives.first?.text == "sla: 3 days")
        #expect(await flow.calls.first?.target == "ValidateOrder")
        #expect(await flow.steps.first?.title == "Validate order")
    }

    @Test func unifiedFlowUsesFlowArtifactKind() async throws {
        let (_, space) = try await parseModel(#"""
            ===
            Svc
            ===
            + Orders

            === Orders ===

            Fulfillment Flow
            >>>>>>
            [Worker] as human
            state Pending
            \__ [*] -> Pending : start
            """#)

        let module = try #require(await moduleNamed("Orders", space: space))
        let flow = try await flowNamed("FulfillmentFlow", in: module)

        #expect(await flow.dataType == .flow)
        #expect(await flow.mode == .unified)
    }

    @Test func flowParsesBranchesParallelReturnsTerminalAndAdditionalCallKinds() async throws {
        let (_, space) = try await parseModel(#"""
            ===
            Svc
            ===
            + Orders

            === Orders ===

            Advanced Flow
            >>>>>>
            [API] as service
            [Rules] as service
            API ~~> Rules : evaluate(order)
            Rules <-- API : decision
            state Pending
            | terminal
            \__ [*] -> Pending : start
            decide @"RiskRules" with order -> risk
            generate @"InvoicePrintable" with order -> document
            |> IF risk > 80
            | return reject
            end
            --- fraud checks
            | run fraud service
            """#)

        let module = try #require(await moduleNamed("Orders", space: space))
        let flow = try await flowNamed("AdvancedFlow", in: module)

        let messages = await flow.messages
        var arrows: [FlowMessageArrow] = []
        for message in messages {
            arrows.append(message.arrow)
        }
        #expect(arrows == [.async, .response])
        #expect(await flow.states.first?.isTerminal == true)
        #expect(await flow.calls.map(\.kind) == ["decide", "generate"])
        #expect(await flow.parallelRegions.first?.name == "fraud checks")
        #expect(await flow.parallelRegions.first?.actions.first?.text == "run fraud service")
        #expect(await flow.branches.first?.keyword == "if")
        #expect(await flow.branches.first?.condition == "risk > 80")
        #expect(await flow.returns.first?.text == "reject")
    }

    @Test func flowParsesMultipleStatesWithActions() async throws {
        let (_, space) = try await parseModel(#"""
            ===
            Svc
            ===
            + Orders

            === Orders ===

            Shipment Flow
            >>>>>>
            state Created
            | validate address
            | assign warehouse
            state Shipped
            | notify customer
            state Delivered
            \__ [*] -> Created : create
            \__ Created -> Shipped : ship
            \__ Shipped -> Delivered : deliver
            \__ Delivered -> [*] : archive
            """#)

        let module = try #require(await moduleNamed("Orders", space: space))
        let flow = try await flowNamed("ShipmentFlow", in: module)

        #expect(await flow.states.count == 3)
        #expect(await flow.states[0].actions.count == 2)
        #expect(await flow.states[1].actions.first?.text == "notify customer")
        #expect(await flow.transitions.count == 4)
        #expect(await flow.transitions[1].event == "ship")
        #expect(await flow.transitions[1].guardExpression == nil)
        #expect(await flow.transitions[1].roles.isEmpty)
    }

    @Test func flowParsesElseIfElseBranchesAndReturnWithMultipleReturns() async throws {
        let (_, space) = try await parseModel(#"""
            ===
            Svc
            ===
            + Orders

            === Orders ===

            Routing Flow
            >>>>>>
            [Router] as service
            |> IF priority == "high"
            | return fast-lane
            |> ELSEIF priority == "medium"
            | return standard
            |> ELSE
            | return batch
            end
            """#)

        let module = try #require(await moduleNamed("Orders", space: space))
        let flow = try await flowNamed("RoutingFlow", in: module)

        #expect(await flow.mode == .workflow)
        let branches = await flow.branches
        #expect(branches.count == 4)
        #expect(branches[0].keyword == "if")
        #expect(branches[0].condition == "priority == \"high\"")
        #expect(branches[1].keyword == "elseif")
        #expect(branches[1].condition == "priority == \"medium\"")
        #expect(branches[2].keyword == "else")
        #expect(branches[2].condition == nil)
        #expect(branches[3].keyword == "end")
        #expect(await flow.returns.count == 3)
    }

    @Test func flowParsesRunCallWithArgumentsAndResult() async throws {
        let (_, space) = try await parseModel(#"""
            ===
            Svc
            ===
            + Orders

            === Orders ===

            Payment Flow
            >>>>>>
            [Gateway] as service
            run @"ChargeCard" with card, amount -> receipt
            """#)

        let module = try #require(await moduleNamed("Orders", space: space))
        let flow = try await flowNamed("PaymentFlow", in: module)

        let call = try #require(await flow.calls.first)
        #expect(call.kind == "run")
        #expect(call.target == "ChargeCard")
        #expect(call.arguments == "card, amount")
        #expect(call.result == "receipt")
    }

    @Test func flowStopsBeforeFollowingTopLevelObject() async throws {
        let (ctx, space) = try await parseModel(#"""
            ===
            Svc
            ===
            + Orders

            === Orders ===

            Tiny Flow
            >>>>>>
            state Pending
            \__ [*] -> Pending : start

            Customer
            ========
            ** id: Id
            """#)

        let module = try #require(await moduleNamed("Orders", space: space))
        _ = try await flowNamed("TinyFlow", in: module)
        let customer = try #require(await ctx.model.types.get(for: "Customer") as? DomainObject)
        #expect(await customer.name == "Customer")
    }

    @Test func emptyFlowBlockStillCreatesObjectWithDefaultMode() async throws {
        let (_, space) = try await parseModel(#"""
            ===
            Svc
            ===
            + Orders

            === Orders ===

            Empty Flow
            >>>>>>
            """#)

        let module = try #require(await moduleNamed("Orders", space: space))
        let flow = try await flowNamed("EmptyFlow", in: module)

        #expect(await flow.mode == .workflow)
        #expect(await flow.states.isEmpty)
        #expect(await flow.transitions.isEmpty)
        #expect(await flow.participants.isEmpty)
    }

    @Test func flowWithWaitDirectivesAndSteps() async throws {
        let (_, space) = try await parseModel(#"""
            ===
            Svc
            ===
            + Orders

            === Orders ===

            Approval Flow
            >>>>>>
            [Service] as service
            wait Service:processPayment -> result
            | retry 3
            ==> Review
            ==> Finalize
            """#)

        let module = try #require(await moduleNamed("Orders", space: space))
        let flow = try await flowNamed("ApprovalFlow", in: module)

        let wait = try #require(await flow.waits.first)
        #expect(wait.participant == "Service")
        #expect(wait.task == "processPayment")
        #expect(wait.result == "result")
        #expect(wait.directives.first?.text == "retry 3")

        #expect(await flow.steps.count == 2)
        #expect(await flow.steps[0].title == "Review")
        #expect(await flow.steps[1].title == "Finalize")
    }

    @Test func flowWithAsyncAndResponseMessages() async throws {
        let (_, space) = try await parseModel(#"""
            ===
            Svc
            ===
            + Orders

            === Orders ===

            Messaging Flow
            >>>>>>
            [Client] as human
            [Server] as service
            Client --> Server : sendRequest
            Server ~~> Client : pushNotification
            Server <-- Client : acknowledge
            """#)

        let module = try #require(await moduleNamed("Orders", space: space))
        let flow = try await flowNamed("MessagingFlow", in: module)

        let messages = await flow.messages
        #expect(messages.count == 3)
        #expect(messages[0].arrow == .sync)
        #expect(messages[0].call == "sendRequest")
        #expect(messages[1].arrow == .async)
        #expect(messages[1].call == "pushNotification")
        #expect(messages[2].arrow == .response)
        #expect(messages[2].call == "acknowledge")
    }

    @Test func twoFlowBlocksInSameModuleAreIndependent() async throws {
        let (_, space) = try await parseModel(#"""
            ===
            Svc
            ===
            + Orders

            === Orders ===

            First Flow
            >>>>>>
            state Open
            \__ [*] -> Open : create

            Second Flow
            >>>>>>
            [Worker] as service
            Worker --> Queue : dequeue
            """#)

        let module = try #require(await moduleNamed("Orders", space: space))
        let flows = await module.flowObjects
        #expect(flows.count == 2)

        let first = try await flowNamed("FirstFlow", in: module)
        #expect(await first.mode == .lifecycle)
        #expect(await first.states.count == 1)
        #expect(await first.participants.isEmpty)

        let second = try await flowNamed("SecondFlow", in: module)
        #expect(await second.mode == .workflow)
        #expect(await second.states.isEmpty)
        #expect(await second.participants.count == 1)
    }
}
