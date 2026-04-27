import Testing
@testable import ModelHike

@Suite struct AnnotationParser_Tests {
    private func parseModel(_ dsl: String) async throws -> (LoadContext, ModelSpace) {
        let ctx = LoadContext(config: PipelineConfig())
        let modelSpace = try await ModelFileParser(with: ctx).parse(string: dsl, identifier: "AnnotationParser_Tests")
        await ctx.model.append(contentsOf: modelSpace)
        try await ctx.model.resolveAndLinkItems(with: ctx)
        return (ctx, modelSpace)
    }

    @Test func recognizedValueAnnotationsAreAccepted() async throws {
        let (ctx, _) = try await parseModel("""
            ===
            Svc
            ===
            + CRM

            === CRM ===

            Customer
            ========
            @ roles:: admin, ops
            ** id: Id
            """)

        let customer = try #require(await ctx.model.types.get(for: "Customer") as? DomainObject)
        #expect(await customer.annotations["roles"] != nil)
    }

    private func moduleNamed(_ name: String, space: ModelSpace) async -> C4Component? {
        for module in await space.modules.snapshot() {
            if await module.name == name { return module }
        }
        return nil
    }

    @Test func flowAnnotationsAreRecognized() async throws {
        let (_, space) = try await parseModel("""
            ===
            Svc
            ===
            + CRM

            === CRM ===

            Approval Flow
            >>>>>>
            @ timeout:: 48h
            @ trigger:: on-submit
            @ sla:: 24h
            [User] as human
            """)

        let module = try #require(await moduleNamed("CRM", space: space))
        let flow = try #require(await module.flowObjects.first)
        #expect(await flow.directives.count == 3)
    }

    @Test func rulesAnnotationsAreRecognized() async throws {
        let (_, space) = try await parseModel("""
            ===
            Svc
            ===
            + CRM

            === CRM ===

            Pricing Rules
            ??????
            @ input:: order: Order
            @ output:: price: Float
            @ hit:: first
            @ source:: pricing-engine
            rule VIP
            | when: tier == "VIP"
            | then: price = 0
            """)

        let module = try #require(await moduleNamed("CRM", space: space))
        let rules = try #require(await module.rulesObjects.first)
        #expect(await rules.inputs.count == 1)
        #expect(await rules.hitPolicy == "first")
        #expect(await rules.source == "pricing-engine")
    }

    @Test func uiAnnotationsAreRecognized() async throws {
        let (_, space) = try await parseModel("""
            ===
            Web
            ===
            + UI

            === UI ===

            Admin Panel
            /;;;;;;/
            @ title:: Admin
            @ route:: /admin
            @ roles:: admin, superadmin
            * content: String
            """)

        let module = try #require(await moduleNamed("UI", space: space))
        let view = try #require(await module.uiViewObjects.first)
        #expect(await view.directives.count == 3)
    }

    @Test func unknownAnnotationThrowsParsingError() async {
        await #expect(throws: (any Error).self) {
            _ = try await parseModel("""
                ===
                Svc
                ===
                + CRM

                === CRM ===

                Customer
                ========
                @ made-up:: nope
                ** id: Id
                """)
        }
    }
}
