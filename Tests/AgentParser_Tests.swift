import Testing
@testable import ModelHike

@Suite struct AgentParser_Tests {
    private func parseModel(_ dsl: String) async throws -> (LoadContext, ModelSpace) {
        let ctx = LoadContext(config: PipelineConfig())
        let modelSpace = try await ModelFileParser(with: ctx).parse(string: dsl, identifier: "AgentParser_Tests")
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

    @Test func agentModuleConsumesTildeUnderlineAndParsesPromptAndTool() async throws {
        let (_, space) = try await parseModel("""
            ===
            Svc
            ===
            + Support

            === Support Agent (agent, model=claude-sonnet-4) ===
            ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

            ```system-prompt
            You help customers.
            ```

            Get Order
            =========
            -- Retrieve an order.
            ~ getOrder(orderId: Id) : Order
            | source @"Support Knowledge Base"
            """)

        let module = try #require(await moduleNamed("SupportAgent", space: space))
        let agent = try #require(await module.agentObjects.first)
        let prompts = await agent.prompts
        let tools = await agent.tools

        #expect(await module.types.isEmpty)
        #expect(prompts.count == 1)
        #expect(prompts[0].body == ["You help customers."])
        #expect(tools.count == 1)
        #expect(tools[0].name == "Get Order")
        #expect(tools[0].descriptionLines == ["Retrieve an order."])
        #expect(await tools[0].method?.name == "getOrder")
        #expect(tools[0].delegations.first?.keyword == "source")
        #expect(tools[0].delegations.first?.target == "Support Knowledge Base")
    }

    @Test func subAgentIsNestedUnderParentAgent() async throws {
        let (_, space) = try await parseModel("""
            ===
            Svc
            ===
            + Support

            === Support Agent (agent) ===
            ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

            ==== Order Investigator (sub-agent, model=claude-sonnet-4) ====
            ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

            ```system-prompt
            Investigate orders.
            ```
            """)

        let module = try #require(await moduleNamed("SupportAgent", space: space))
        let agents = await module.agentObjects

        #expect(agents.count == 2)
        #expect(await agents[0].componentKind == .agent)
        #expect(await agents[1].componentKind == .subAgent)
        #expect(await agents[1].prompts.first?.body == ["Investigate orders."])
    }

    @Test func slashCommandsAndGuardrailsAreParsedAsAgentSections() async throws {
        let (_, space) = try await parseModel("""
            ===
            Svc
            ===
            + Support

            === Support Agent (agent) ===
            ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

            # Slash Commands
            /help:
            | description: "Get help"
            | routes-to: self
            #

            # Guardrails
            @ max-turns:: 30
            | tool-constraints:
            | | Cancel Order: requires confirmation
            #
            """)

        let module = try #require(await moduleNamed("SupportAgent", space: space))
        let agent = try #require(await module.agentObjects.first)

        #expect(await agent.slashCommands.count == 1)
        #expect(await agent.guardrails.count == 1)
        #expect(await agent.slashCommands.first?.lines.first?.text == "/help:")
        #expect(await agent.guardrails.first?.lines.last?.depth == 2)
    }

    @Test func knowledgeConfigInsideAgentRemainsConfigObject() async throws {
        let (_, space) = try await parseModel("""
            ===
            Svc
            ===
            + Support

            === Support Agent (agent) ===
            ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

            Support Knowledge Base (knowledge, vector-store)
            ::::::::
            provider = pinecone
            """)

        let module = try #require(await moduleNamed("SupportAgent", space: space))
        #expect(await module.agentObjects.count == 1)
        #expect(await module.configObjects.count == 1)
        #expect(await module.configObjects.first?.configKind == "knowledge")
    }

    @Test func agentAttributeCanAppearAfterOtherAttributes() async throws {
        let (_, space) = try await parseModel("""
            ===
            Svc
            ===
            + Support

            === Support Agent (model=claude-sonnet-4, agent, memory=session) ===
            ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
            """)

        let module = try #require(await moduleNamed("SupportAgent", space: space))
        let agent = try #require(await module.agentObjects.first)

        #expect(await agent.componentKind == .agent)
        #expect(await agent.attribs["model"] as? String == "claude-sonnet-4")
        #expect(await agent.attribs.has("memory"))
    }

    @Test func conditionalSystemPromptsArePreservedInOrder() async throws {
        let (_, space) = try await parseModel("""
            ===
            Svc
            ===
            + Support

            === Support Agent (agent) ===
            ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

            ```system-prompt
            Base prompt.
            ```

            ```system-prompt customer.tier == "ENTERPRISE"
            Enterprise prompt.
            ```
            """)

        let module = try #require(await moduleNamed("SupportAgent", space: space))
        let agent = try #require(await module.agentObjects.first)
        let prompts = await agent.prompts

        #expect(prompts.count == 2)
        #expect(prompts[0].condition == nil)
        #expect(prompts[0].body == ["Base prompt."])
        #expect(prompts[1].condition == "customer.tier == \"ENTERPRISE\"")
        #expect(prompts[1].body == ["Enterprise prompt."])
    }

    @Test func toolsParseEveryDelegationKeywordWithArgumentsAndResults() async throws {
        let (_, space) = try await parseModel("""
            ===
            Svc
            ===
            + Support

            === Support Agent (agent) ===
            ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

            Decide Return
            =============
            ~ decideReturn(orderId: Id) : Decision
            | decide @"Return Rules" with (order) -> decision

            Run Return Flow
            ===============
            ~ runReturn(orderId: Id) : ReturnResult
            | run @"Return Flow" with (order, reason) -> result

            Search Articles
            ===============
            ~ searchArticles(query: String) : Article[]
            | source @"Support Knowledge Base"

            Stripe Lookup
            =============
            ~ stripeLookup(customerId: Id) : Customer
            | mcp @"Stripe" with (customerId) -> customer

            Investigate
            ===========
            ~ investigate(orderId: Id) : Investigation
            | invoke @"Order Investigator" with (orderId) -> findings
            """)

        let module = try #require(await moduleNamed("SupportAgent", space: space))
        let agent = try #require(await module.agentObjects.first)
        let tools = await agent.tools

        #expect(tools.count == 5)
        var delegations: [AgentDelegation] = []
        for tool in tools {
            if let delegation = tool.delegations.first {
                delegations.append(delegation)
            }
        }
        var keywords: [String] = []
        for delegation in delegations {
            keywords.append(delegation.keyword)
        }
        #expect(keywords == ["decide", "run", "source", "mcp", "invoke"])
        #expect(delegations[0].target == "Return Rules")
        #expect(delegations[0].arguments == "(order)")
        #expect(delegations[0].result == "decision")
        #expect(delegations[1].target == "Return Flow")
        #expect(delegations[1].arguments == "(order, reason)")
        #expect(delegations[1].result == "result")
        #expect(delegations[2].target == "Support Knowledge Base")
        #expect(delegations[3].target == "Stripe")
        #expect(delegations[3].arguments == "(customerId)")
        #expect(delegations[4].target == "Order Investigator")
        #expect(delegations[4].result == "findings")
    }

    @Test func skillAndMCPResourcesParseDirectivesAndInlinePrompts() async throws {
        let (_, space) = try await parseModel("""
            ===
            Svc
            ===
            + Support

            === Support Agent (agent) ===
            ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

            Email Drafter (skill)
            =====================
            -- Draft professional emails.
            @ capabilities:: draft-email, improve-tone
            @ requires:: conversation
            ```skill-prompt draft-email
            Draft an email from {context}.
            ```

            Stripe (mcp-server)
            ===================
            @ url:: https://mcp.stripe.com/sse
            @ auth:: api-key
            """)

        let module = try #require(await moduleNamed("SupportAgent", space: space))
        let agent = try #require(await module.agentObjects.first)
        let tools = await agent.tools

        #expect(tools.count == 2)
        #expect(tools[0].resourceKind == .skill)
        #expect(tools[0].descriptionLines == ["Draft professional emails."])
        var skillDirectiveNames: [String] = []
        for directive in tools[0].directives {
            skillDirectiveNames.append(directive.name)
        }
        #expect(skillDirectiveNames == ["capabilities", "requires"])
        #expect(tools[0].prompts.first?.kind == "skill-prompt")
        #expect(tools[0].prompts.first?.condition == "draft-email")
        #expect(tools[0].prompts.first?.body == ["Draft an email from {context}."])
        #expect(tools[1].resourceKind == .mcpServer)
        var mcpDirectiveNames: [String] = []
        for directive in tools[1].directives {
            mcpDirectiveNames.append(directive.name)
        }
        #expect(mcpDirectiveNames == ["url", "auth"])
    }

    @Test func agentToolStopsBeforeNextFlowAndKeepsFlowParseable() async throws {
        let (_, space) = try await parseModel("""
            ===
            Svc
            ===
            + Support

            === Support Agent (agent) ===
            ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

            Process Return
            ==============
            ~ processReturn(orderId: Id) : ReturnResult
            | run @"Return Flow" with (orderId)

            Return Flow
            >>>>>>
            [Customer] as human
            Customer --> API : requestReturn
            """)

        let module = try #require(await moduleNamed("SupportAgent", space: space))
        let agent = try #require(await module.agentObjects.first)

        #expect(await agent.tools.count == 1)
        #expect(await module.flowObjects.count == 1)
        #expect(await module.flowObjects.first?.givenname == "Return Flow")
    }

    @Test func nonAgentModuleWithTildeLineDoesNotBecomeAgent() async throws {
        let (_, space) = try await parseModel("""
            ===
            Svc
            ===
            + Support

            === Support Module ===
            ~~~~~~~~~~~~~~~~~~~~~~

            Ticket
            ======
            ** id: Id
            """)

        let module = try #require(await moduleNamed("SupportModule", space: space))
        #expect(await module.agentObjects.isEmpty)
        #expect(await module.types.count == 1)
    }

    @Test func unterminatedSystemPromptThrows() async throws {
        await #expect(throws: (any Error).self) {
            _ = try await parseModel("""
                ===
                Svc
                ===
                + Support

                === Support Agent (agent) ===
                ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

                ```system-prompt
                Missing close fence.
                """)
        }
    }

    @Test func unterminatedSkillPromptThrows() async throws {
        await #expect(throws: (any Error).self) {
            _ = try await parseModel("""
                ===
                Svc
                ===
                + Support

                === Support Agent (agent) ===
                ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

                Email Drafter (skill)
                =====================
                ```skill-prompt draft-email
                Missing close fence.
                """)
        }
    }
}
