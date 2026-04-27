import Testing
@testable import ModelHike

@Suite struct AgentWrapper_Tests {
    private func parseModel(_ dsl: String) async throws -> (LoadContext, ModelSpace) {
        let ctx = LoadContext(config: PipelineConfig())
        let modelSpace = try await ModelFileParser(with: ctx).parse(string: dsl, identifier: "AgentWrapper_Tests")
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

    @Test func componentWrapperExposesAgentCollections() async throws {
        let (ctx, space) = try await parseModel("""
            ===
            Svc
            ===
            + Support

            === Support Agent (agent) ===
            ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

            ```system-prompt
            Base support prompt.
            ```

            Search Articles
            ===============
            ~ searchArticles(query: String) : Article[]
            | source @"Support Knowledge Base"

            # Guardrails
            | output-rules:
            | | max-response-length: 300 tokens
            #
            """)

        let module = try #require(await moduleNamed("SupportAgent", space: space))
        let pInfo = await ParsedInfo.dummy(line: "wrapper", identifier: "AgentWrapper_Tests", loadCtx: ctx)
        let component = C4Component_Wrap(module, model: await ctx.model)

        let agents = try #require(try await component.getValueOf(property: "agents", with: pInfo) as? [AgentObject_Wrap])
        let hasAgentsValue = try await component.getValueOf(property: "has-agents", with: pInfo)
        let hasAgents = try #require(hasAgentsValue as? Bool)
        let prompts = try #require(try await component.getValueOf(property: "agent-prompts", with: pInfo) as? [AgentPrompt])
        let tools = try #require(try await component.getValueOf(property: "agent-tools", with: pInfo) as? [AgentTool])
        let guardrails = try #require(try await component.getValueOf(property: "guardrails", with: pInfo) as? [AgentSection])

        #expect(hasAgents)
        #expect(agents.count == 1)
        #expect(prompts.count == 1)
        #expect(tools.count == 1)
        #expect(guardrails.count == 1)

        let agentKind = try #require(try await agents[0].getValueOf(property: "kind", with: pInfo) as? String)
        let agentTools = try #require(try await agents[0].getValueOf(property: "tools", with: pInfo) as? [AgentTool])
        #expect(agentKind == "agent")
        #expect(agentTools.first?.delegations.first?.target == "Support Knowledge Base")
    }

    @Test func agentWrapperExposesAllCollectionFlagsAndRejectsUnknownProperties() async throws {
        let (ctx, space) = try await parseModel("""
            ===
            Svc
            ===
            + Support

            === Support Agent (agent) ===
            ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

            ```system-prompt
            Base prompt.
            ```

            Search Articles
            ===============
            ~ searchArticles(query: String) : Article[]
            | source @"Support Knowledge Base"

            # Slash Commands
            /help:
            | routes-to: self
            #
            """)

        let module = try #require(await moduleNamed("SupportAgent", space: space))
        let agent = try #require(await module.agentObjects.first)
        let wrapper = AgentObject_Wrap(agent)
        let pInfo = await ParsedInfo.dummy(line: "wrapper", identifier: "AgentWrapper_Tests", loadCtx: ctx)

        let name = try #require(try await wrapper.getValueOf(property: "name", with: pInfo) as? String)
        let givenName = try #require(try await wrapper.getValueOf(property: "given-name", with: pInfo) as? String)
        let prompts = try #require(try await wrapper.getValueOf(property: "prompts", with: pInfo) as? [AgentPrompt])
        let hasPromptsValue = try await wrapper.getValueOf(property: "has-prompts", with: pInfo)
        let hasPrompts = try #require(hasPromptsValue as? Bool)
        let tools = try #require(try await wrapper.getValueOf(property: "tools", with: pInfo) as? [AgentTool])
        let hasToolsValue = try await wrapper.getValueOf(property: "has-tools", with: pInfo)
        let hasTools = try #require(hasToolsValue as? Bool)
        let sections = try #require(try await wrapper.getValueOf(property: "sections", with: pInfo) as? [AgentSection])
        let slashCommands = try #require(try await wrapper.getValueOf(property: "slash-commands", with: pInfo) as? [AgentSection])

        #expect(name == "SupportAgent")
        #expect(givenName == "Support Agent")
        #expect(prompts.count == 1)
        #expect(hasPrompts)
        #expect(tools.count == 1)
        #expect(hasTools)
        #expect(sections.count == 1)
        #expect(slashCommands.count == 1)

        await #expect(throws: (any Error).self) {
            _ = try await wrapper.getValueOf(property: "unknown-property", with: pInfo)
        }
    }
}
