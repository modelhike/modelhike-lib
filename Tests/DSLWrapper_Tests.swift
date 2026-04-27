import Testing
@testable import ModelHike

@Suite struct DSLWrapper_Tests {
    private func parseModel(_ dsl: String) async throws -> (LoadContext, ModelSpace) {
        let ctx = LoadContext(config: PipelineConfig())
        let modelSpace = try await ModelFileParser(with: ctx).parse(string: dsl, identifier: "DSLWrapper_Tests")
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

    @Test func newDSLObjectsAreExposedThroughComponentAndObjectWrappers() async throws {
        let (ctx, space) = try await parseModel(#"""
            ===
            Svc
            ===
            + Billing

            === Billing ===

            Checkout Flow
            >>>>>>
            [Customer] as human
            Customer --> API : checkout

            Pricing Rules
            ??????
            @ input:: order: Order
            @ output:: price: Float
            = price: Float
            | order.total

            Invoice Printable (Order)
            /#####/
            @ output:: pdf
            section Body:
            | Invoice

            Currency Config (currency)
            ::::::::
            base = USD

            Dashboard
            /;;;;;;;/
            * title: String
            """#)

        let module = try #require(await moduleNamed("Billing", space: space))
        let pInfo = await ParsedInfo.dummy(line: "wrapper", identifier: "DSLWrapper_Tests", loadCtx: ctx)

        let appModel = await ctx.model
        let component = C4Component_Wrap(module, model: appModel)
        let flows = try #require(try await component.getValueOf(property: "flows", with: pInfo) as? [FlowObject_Wrap])
        let rules = try #require(try await component.getValueOf(property: "rules", with: pInfo) as? [RulesObject_Wrap])
        let printables = try #require(try await component.getValueOf(property: "printables", with: pInfo) as? [PrintableObject_Wrap])
        let configs = try #require(try await component.getValueOf(property: "configs", with: pInfo) as? [ConfigObject_Wrap])
        let uiViews = try #require(try await component.getValueOf(property: "ui-views", with: pInfo) as? [UIObject_Wrap])

        #expect(flows.count == 1)
        #expect(rules.count == 1)
        #expect(printables.count == 1)
        #expect(configs.count == 1)
        #expect(uiViews.count == 1)
        let hasFlowsValue = try await component.getValueOf(property: "has-flows", with: pInfo)
        let hasRulesValue = try await component.getValueOf(property: "has-rules", with: pInfo)
        let hasPrintablesValue = try await component.getValueOf(property: "has-printables", with: pInfo)
        let hasConfigsValue = try await component.getValueOf(property: "has-configs", with: pInfo)
        let hasUIViewsValue = try await component.getValueOf(property: "has-ui-views", with: pInfo)
        let hasFlows = try #require(hasFlowsValue as? Bool)
        let hasRules = try #require(hasRulesValue as? Bool)
        let hasPrintables = try #require(hasPrintablesValue as? Bool)
        let hasConfigs = try #require(hasConfigsValue as? Bool)
        let hasUIViews = try #require(hasUIViewsValue as? Bool)
        #expect(hasFlows)
        #expect(hasRules)
        #expect(hasPrintables)
        #expect(hasConfigs)
        #expect(hasUIViews)

        let flowMode = try #require(try await flows[0].getValueOf(property: "flow-mode", with: pInfo) as? String)
        let ruleType = try #require(try await rules[0].getValueOf(property: "rule-type", with: pInfo) as? String)
        let outputFormats = try #require(try await printables[0].getValueOf(property: "output-formats", with: pInfo) as? [String])
        let configKind = try #require(try await configs[0].getValueOf(property: "config-kind", with: pInfo) as? String)

        #expect(flowMode == "workflow")
        #expect(ruleType == "formula")
        #expect(outputFormats == ["pdf"])
        #expect(configKind == "currency")
    }

    @Test func flowWrapperExposesStatesTransitionsParticipantsAndBranches() async throws {
        let (ctx, space) = try await parseModel(#"""
            ===
            Svc
            ===
            + Billing

            === Billing ===

            Order Lifecycle
            >>>>>>
            state Draft
            | validate
            state Submitted
            \__ [*] -> Draft : create
            \__ Draft -> Submitted : submit { total > 0 } [customer]
            [Customer] as human
            Customer --> API : checkout
            |> IF priority == "high"
            | return fast-lane
            end
            """#)

        let module = try #require(await moduleNamed("Billing", space: space))
        let flow = try #require(await module.flowObjects.first)
        let wrapper = FlowObject_Wrap(flow)
        let pInfo = await ParsedInfo.dummy(line: "wrapper", identifier: "DSLWrapper_Tests", loadCtx: ctx)

        let states = try #require(try await wrapper.getValueOf(property: "states", with: pInfo) as? [FlowState])
        #expect(states.count == 2)
        #expect(states[0].name == "Draft")
        #expect(states[0].actions.first?.text == "validate")

        let transitions = try #require(try await wrapper.getValueOf(property: "transitions", with: pInfo) as? [FlowTransition])
        #expect(transitions.count == 2)
        #expect(transitions[1].guardExpression == "total > 0")
        #expect(transitions[1].roles == ["customer"])

        let participants = try #require(try await wrapper.getValueOf(property: "participants", with: pInfo) as? [FlowParticipant])
        #expect(participants.count == 1)
        #expect(participants[0].kind == "human")

        let messages = try #require(try await wrapper.getValueOf(property: "messages", with: pInfo) as? [FlowMessage])
        #expect(messages.count == 1)

        let branches = try #require(try await wrapper.getValueOf(property: "branches", with: pInfo) as? [FlowBranch])
        #expect(branches.count == 2)

        let name = try #require(try await wrapper.getValueOf(property: "name", with: pInfo) as? String)
        #expect(name == "OrderLifecycle")

        let givenName = try #require(try await wrapper.getValueOf(property: "given-name", with: pInfo) as? String)
        #expect(givenName == "Order Lifecycle")
    }

    @Test func rulesWrapperExposesInputsOutputsAndConditionalRules() async throws {
        let (ctx, space) = try await parseModel("""
            ===
            Svc
            ===
            + Billing

            === Billing ===

            Discount Rules
            ??????
            @ input:: order: Order
            @ output:: discount: Float
            rule VIP
            | when: tier == "VIP"
            | then: discount = 0.2
            rule Student
            | when: age < 25
            | then: discount = 0.1
            """)

        let module = try #require(await moduleNamed("Billing", space: space))
        let rules = try #require(await module.rulesObjects.first)
        let wrapper = RulesObject_Wrap(rules)
        let pInfo = await ParsedInfo.dummy(line: "wrapper", identifier: "DSLWrapper_Tests", loadCtx: ctx)

        let inputs = try #require(try await wrapper.getValueOf(property: "inputs", with: pInfo) as? [RuleParam])
        #expect(inputs.count == 1)
        #expect(inputs[0].name == "order")
        #expect(inputs[0].typeName == "Order")

        let outputs = try #require(try await wrapper.getValueOf(property: "outputs", with: pInfo) as? [RuleParam])
        #expect(outputs.count == 1)

        let conditionalRules = try #require(try await wrapper.getValueOf(property: "conditional-rules", with: pInfo) as? [ConditionalRule])
        #expect(conditionalRules.count == 2)
        #expect(conditionalRules[0].name == "VIP")
        #expect(conditionalRules[0].whenClauses == ["tier == \"VIP\""])
        #expect(conditionalRules[0].thenClauses == ["discount = 0.2"])
    }

    @Test func printableWrapperExposesSectionsAndPageDirectives() async throws {
        let (ctx, space) = try await parseModel("""
            ===
            Svc
            ===
            + Billing

            === Billing ===

            Invoice (Order)
            /#####/
            @ output:: pdf, html
            @ page:: A4
            @ locale:: en_US
            header:
            | Company Logo
            section Body:
            | Line items
            footer:
            | Page {{ page }}
            pageBreak: after-section
            """)

        let module = try #require(await moduleNamed("Billing", space: space))
        let printable = try #require(await module.printableObjects.first)
        let wrapper = PrintableObject_Wrap(printable)
        let pInfo = await ParsedInfo.dummy(line: "wrapper", identifier: "DSLWrapper_Tests", loadCtx: ctx)

        let boundObjects = try #require(try await wrapper.getValueOf(property: "bound-objects", with: pInfo) as? [String])
        #expect(boundObjects == ["Order"])

        let outputFormats = try #require(try await wrapper.getValueOf(property: "output-formats", with: pInfo) as? [String])
        #expect(outputFormats == ["pdf", "html"])

        let page = try #require(try await wrapper.getValueOf(property: "page", with: pInfo) as? String)
        #expect(page == "A4")

        let locale = try #require(try await wrapper.getValueOf(property: "locale", with: pInfo) as? String)
        #expect(locale == "en_US")

        let headerRows = try #require(try await wrapper.getValueOf(property: "header-rows", with: pInfo) as? [DSLBodyLine])
        #expect(headerRows.count == 1)

        let sections = try #require(try await wrapper.getValueOf(property: "sections", with: pInfo) as? [PrintableSection])
        #expect(sections.count == 1)
        #expect(sections[0].name == "Body")

        let footerRows = try #require(try await wrapper.getValueOf(property: "footer-rows", with: pInfo) as? [DSLBodyLine])
        #expect(footerRows.count == 1)

        let pageBreaks = try #require(try await wrapper.getValueOf(property: "page-breaks", with: pInfo) as? [PrintablePageBreak])
        #expect(pageBreaks.count == 1)
    }

    @Test func configWrapperExposesPropertiesAndGroups() async throws {
        let (ctx, space) = try await parseModel("""
            ===
            Svc
            ===
            + Billing

            === Billing ===

            Rates Config (exchange)
            ::::::::
            base = USD
            rates:
            | EUR -> 0.9
            | GBP -> 0.8
            """)

        let module = try #require(await moduleNamed("Billing", space: space))
        let config = try #require(await module.configObjects.first)
        let wrapper = ConfigObject_Wrap(config)
        let pInfo = await ParsedInfo.dummy(line: "wrapper", identifier: "DSLWrapper_Tests", loadCtx: ctx)

        let configKind = try #require(try await wrapper.getValueOf(property: "config-kind", with: pInfo) as? String)
        #expect(configKind == "exchange")

        let givenName = try #require(try await wrapper.getValueOf(property: "given-name", with: pInfo) as? String)
        #expect(givenName == "Rates Config")

        let properties = try #require(try await wrapper.getValueOf(property: "properties", with: pInfo) as? [ConfigProperty])
        #expect(properties.count == 1)
        #expect(properties[0].key == "base")

        let groups = try #require(try await wrapper.getValueOf(property: "groups", with: pInfo) as? [ConfigGroup])
        #expect(groups.count == 1)
        #expect(groups[0].name == "rates")
        #expect(groups[0].properties.count == 2)
    }

    @Test func newObjectWrappersRejectUnknownProperties() async throws {
        let (ctx, space) = try await parseModel(#"""
            ===
            Svc
            ===
            + Billing

            === Billing ===

            Checkout Flow
            >>>>>>
            state Pending
            \__ [*] -> Pending : start
            """#)

        let module = try #require(await moduleNamed("Billing", space: space))
        let flow = try #require(await module.flowObjects.first)
        let wrapper = FlowObject_Wrap(flow)
        let pInfo = await ParsedInfo.dummy(line: "wrapper", identifier: "DSLWrapper_Tests", loadCtx: ctx)

        await #expect(throws: (any Error).self) {
            _ = try await wrapper.getValueOf(property: "unknown-property", with: pInfo)
        }
    }
}
