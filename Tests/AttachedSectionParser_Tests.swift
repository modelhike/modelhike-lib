import Testing
@testable import ModelHike

@Suite struct AttachedSectionParser_Tests {
    private func parseModel(_ dsl: String) async throws -> (LoadContext, ModelSpace) {
        let ctx = LoadContext(config: PipelineConfig())
        let modelSpace = try await ModelFileParser(with: ctx).parse(string: dsl, identifier: "AttachedSectionParser_Tests")
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

    private func domainObject(_ name: String, ctx: LoadContext) async throws -> DomainObject {
        let obj = try #require(await ctx.model.types.get(for: name))
        return try #require(obj as? DomainObject)
    }

    @Test func domainObjectGenericSectionCapturesBodyLinesAndAnnotations() async throws {
        let (ctx, _) = try await parseModel("""
            ===
            Svc
            ===
            + CRM

            === CRM ===

            Customer
            ========
            ** id: Id

            # Import
            @ format:: csv, xlsx
            "Customer Name" -> name
            "Email" -> email
            #
            """)

        let customer = try await domainObject("Customer", ctx: ctx)
        let importSection = try #require(await customer.attachedSections.get("Import"))

        #expect(await importSection.bodyLines.map(\.text) == ["\"Customer Name\" -> name", "\"Email\" -> email"])
        #expect(await customer.annotations["format"] != nil)
    }

    @Test func moduleGenericSectionCapturesJobsBodyLinesAndAnnotations() async throws {
        let (_, space) = try await parseModel("""
            ===
            Svc
            ===
            + Ops

            === Ops ===

            # Jobs
            @ schedule:: cron = "0 0 * * *"
            rebuild-search-index
            compact-events
            #

            Task
            ====
            ** id: Id
            """)

        let module = try #require(await moduleNamed("Ops", space: space))
        let jobs = try #require(await module.attachedSections.get("Jobs"))

        #expect(await jobs.bodyLines.map(\.text) == ["rebuild-search-index", "compact-events"])
        #expect(await module.annotations["schedule"] != nil)
    }

    @Test func allGenericSectionNamesCaptureBodyLines() async throws {
        let sectionNames = [
            "Import",
            "Export",
            "Cache",
            "Rate Limit",
            "Search",
            "Media",
            "Fixtures",
            "Analytics",
            "Error Policy",
            "Versioned",
            "Jobs"
        ]
        let sections = sectionNames.map { name in
            """
            # \(name)
            body for \(name)
            #
            """
        }.joined(separator: String.newLine)

        let (ctx, _) = try await parseModel("""
            ===
            Svc
            ===
            + CRM

            === CRM ===

            Customer
            ========
            ** id: Id

            \(sections)
            """)

        let customer = try await domainObject("Customer", ctx: ctx)
        for name in sectionNames {
            let section = try #require(await customer.attachedSections.get(name))
            #expect(await section.bodyLines.first?.text == "body for \(name)")
        }
    }

    @Test func attachedSectionWithMultipleBodyLinesPreservesAll() async throws {
        let (ctx, _) = try await parseModel("""
            ===
            Svc
            ===
            + CRM

            === CRM ===

            Customer
            ========
            ** id: Id

            # Cache
            @ ttl:: 3600
            @ strategy:: LRU
            @ eviction:: on-update
            | get-by-id
            | list-active
            | search-by-name
            #
            """)

        let customer = try await domainObject("Customer", ctx: ctx)
        let cache = try #require(await customer.attachedSections.get("Cache"))
        #expect(await cache.bodyLines.count == 3)
        #expect(await cache.bodyLines.map(\.text) == ["get-by-id", "list-active", "search-by-name"])
    }

    @Test func attachedSectionOnUIViewCapturesBodyLines() async throws {
        let (_, space) = try await parseModel("""
            ===
            Web
            ===
            + UI

            === UI ===

            Search View
            /;;;;;;/
            * query: String

            # Analytics
            @ events:: search.submitted, search.cleared
            | track search
            | track clear
            #
            """)

        let module = try #require(await moduleNamed("UI", space: space))
        let view = try #require(await module.uiViewObjects.first)
        let analytics = try #require(await view.attachedSections.get("Analytics"))
        #expect(await analytics.bodyLines.count == 2)
    }
}
