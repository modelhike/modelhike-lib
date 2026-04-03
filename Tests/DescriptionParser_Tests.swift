import Testing
@testable import ModelHike

/// Tests for `>>>` prose blocks, `--` inline / following-line descriptions on containers, modules, classes, and methods.
@Suite struct DescriptionParser_Tests {

    private func parseModel(_ dsl: String) async throws -> (LoadContext, ModelSpace) {
        let ctx = LoadContext(config: PipelineConfig())
        let modelSpace = try await ModelFileParser(with: ctx).parse(string: dsl, identifier: "DescriptionParser_Tests")
        await ctx.model.append(contentsOf: modelSpace)
        try await ctx.model.resolveAndLinkItems(with: ctx)
        return (ctx, modelSpace)
    }

    private func domainObject(_ name: String, ctx: LoadContext) async throws -> DomainObject {
        let obj = try #require(await ctx.model.types.get(for: name))
        return try #require(obj as? DomainObject)
    }

    private func moduleNamed(_ name: String, space: ModelSpace) async -> C4Component? {
        for m in await space.modules.snapshot() {
            if await m.name == name { return m }
        }
        return nil
    }

    @Test func tripleBareLinesBeforeClass_setClassDescription() async throws {
        let (ctx, _) = try await parseModel("""
            ===
            Svc
            ===
            + Mod

            === Mod ===

            >>> Class summary line one
            >>> Class summary line two
            Thing
            =====
            ** id : Id
            """)

        let thing = try await domainObject("Thing", ctx: ctx)
        #expect(await thing.description == "Class summary line one Class summary line two")
    }

    @Test func tripleBareLinesBeforeModule_setModuleDescription() async throws {
        let (_, space) = try await parseModel("""
            ===
            Svc
            ===

            >>> Module overview
            === HR ===

            Thing
            =====
            ** id : Id
            """)

        let module = try #require(await moduleNamed("HR", space: space))
        #expect(await module.description == "Module overview")
    }

    @Test func tripleBareLinesBeforeContainer_setContainerDescription() async throws {
        let (_, space) = try await parseModel("""
            >>> Top-level container blurb
            ===
            APIs
            ===
            + Core

            === Core ===

            Thing
            =====
            ** id : Id
            """)

        let container = try #require(await space.containers.first)
        #expect(await container.description == "Top-level container blurb")
    }

    @Test func tripleMixedWithParamMetadataBeforeMethod_setsDescriptionAndMetadata() async throws {
        let (ctx, _) = try await parseModel("""
            ===
            Svc
            ===
            + Mod

            === Mod ===

            Thing
            =====
            ** id : Id

            >>> Explains the next method
            >>> * tax: Float
            ~ compute(tax: Float) : Float
            """)

        let thing = try await domainObject("Thing", ctx: ctx)
        let method = try #require(await thing.methods.first(where: { await $0.name == "compute" }))
        #expect(await method.description == "Explains the next method")
        let params = await method.parameters
        #expect(params.count == 1)
        #expect(params[0].name == "tax")
        #expect(params[0].metadata.required == .yes)
    }

    @Test func tripleOnlyDescriptionBeforeMethod_setsDescriptionOnly() async throws {
        let (ctx, _) = try await parseModel("""
            ===
            Svc
            ===
            + Mod

            === Mod ===

            Thing
            =====
            ** id : Id

            >>> Only prose, no param lines
            ~ ping() : Void
            """)

        let thing = try await domainObject("Thing", ctx: ctx)
        let method = try #require(await thing.methods.first(where: { await $0.name == "ping" }))
        #expect(await method.description == "Only prose, no param lines")
    }

    @Test func inlineDescriptionOnContainerNameLine() async throws {
        let (_, space) = try await parseModel("""
            ===
            APIs -- Public HTTP surface
            ===
            + Core

            === Core ===

            Thing
            =====
            ** id : Id
            """)

        let container = try #require(await space.containers.first)
        #expect(await container.description == "Public HTTP surface")
    }

    @Test func inlineDescriptionOnModuleFence() async throws {
        let (_, space) = try await parseModel("""
            ===
            Svc
            ===
            + HR

            === HR -- Payroll boundary ===

            Thing
            =====
            ** id : Id
            """)

        let module = try #require(await moduleNamed("HR", space: space))
        #expect(await module.description == "Payroll boundary")
    }

    @Test func inlineDescriptionOnSubModuleFence() async throws {
        let (_, space) = try await parseModel("""
            ===
            Svc
            ===
            + Billing

            === Billing ===

            ==== Invoices -- Invoice handling ==== 

            Thing
            =====
            ** id : Id
            """)

        let billing = try #require(await moduleNamed("Billing", space: space))
        var invoices: C4Component?
        for item in await billing.items {
            if let sub = item as? C4Component, await sub.name == "Invoices" {
                invoices = sub
            }
        }
        let inv = try #require(invoices)
        #expect(await inv.description == "Invoice handling")
    }

    @Test func descriptionLinesOnDto_setDtoDescription() async throws {
        let (_, space) = try await parseModel("""
            ===
            Svc
            ===
            + Mod

            === Mod ===

            OrderView
            /======/
            -- Summary of the DTO
            -- with extra detail
            """)

        let module = try #require(await moduleNamed("Mod", space: space))
        var found: DtoObject?
        for item in await module.items {
            if let d = item as? DtoObject, await d.name == "OrderView" {
                found = d
            }
        }
        let dto = try #require(found)
        #expect(await dto.description == "Summary of the DTO with extra detail")
    }

    @Test func descriptionLinesOnUIView_setViewDescription() async throws {
        let (_, space) = try await parseModel("""
            ===
            App
            ===
            + UI

            === UI ===

            Dashboard
            ~~~~~~~~~
            -- Main dashboard view
            -- with multiple panels
            """)

        let module = try #require(await moduleNamed("UI", space: space))
        var dashboard: UIView?
        for item in await module.items {
            if let v = item as? UIView, await v.name == "Dashboard" {
                dashboard = v
            }
        }
        let view = try #require(dashboard)
        #expect(await view.description == "Main dashboard view with multiple panels")
    }

    @Test func discardedTripleBlockAtEndOfFile_doesNotCrash() async throws {
        let (_, space) = try await parseModel("""
            ===
            Svc
            ===
            + Mod

            === Mod ===

            >>> orphaned block with no following element
            """)
        _ = space
    }
}
