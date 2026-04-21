import Testing
@testable import ModelHike

/// Module-level `=` expressions, `~` functions, named constraints, and `@name` references on properties.
@Suite struct ModuleLevelElements_Tests {

    private func parseModel(_ dsl: String) async throws -> (LoadContext, ModelSpace) {
        let ctx = LoadContext(config: PipelineConfig())
        let modelSpace = try await ModelFileParser(with: ctx).parse(string: dsl, identifier: "ModuleLevelElements_Tests")
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

    @Test func moduleLevelExpressionProperty() async throws {
        let (_, space) = try await parseModel("""
            ===
            Svc
            ===
            + Mod

            === Mod ===

            = MAX_RETRIES : Int = 5

            Thing
            =====
            ** id : Id
            """)

        let module = try #require(await moduleNamed("Mod", space: space))
        let exprs = await module.expressions
        #expect(exprs.count == 1)
        #expect(await exprs[0].name == "MAX_RETRIES")
        #expect(await exprs[0].defaultValue == "5")
    }

    @Test func moduleLevelFunctionMethod() async throws {
        let (_, space) = try await parseModel("""
            ===
            Svc
            ===
            + Mod

            === Mod ===

            ~ calculateTax(amount: Float) : Float

            Thing
            =====
            ** id : Id
            """)

        let module = try #require(await moduleNamed("Mod", space: space))
        let fns = await module.functions
        #expect(fns.count == 1)
        #expect(await fns[0].name == "calculateTax")
    }

    @Test func moduleLevelNamedConstraint() async throws {
        let (_, space) = try await parseModel("""
            ===
            Svc
            ===
            + Mod

            === Mod ===

            = positiveAmount : { amount > 0 }

            Thing
            =====
            ** id : Id
            """)

        let module = try #require(await moduleNamed("Mod", space: space))
        let named = await module.namedConstraints.snapshot()
        #expect(named.count == 1)
        #expect(named[0].name == "positiveAmount")
    }

    @Test func multiLineNamedConstraintBody() async throws {
        let (_, space) = try await parseModel("""
            ===
            Svc
            ===
            + Mod

            === Mod ===

            = rangeOk : {
            amount > 0
            && amount < 100
            }

            Thing
            =====
            ** id : Id
            """)

        let module = try #require(await moduleNamed("Mod", space: space))
        let named = await module.namedConstraints.snapshot()
        #expect(named.count == 1)
        #expect(named[0].name == "rangeOk")
    }

    @Test func atReferenceOnProperty_appliedConstraints() async throws {
        let (ctx, _) = try await parseModel("""
            ===
            Svc
            ===
            + Mod

            === Mod ===

            = positiveAmount : { amount > 0 }

            Thing
            =====
            * amount : Float { @positiveAmount }
            """)

        let thing = try await domainObject("Thing", ctx: ctx)
        let prop = try #require(await thing.getProp("amount"))
        let applied = await prop.appliedConstraints
        #expect(applied == ["positiveAmount"])
    }

    @Test func atReferenceOutsideBraces_throws() async {
        await #expect(throws: (any Error).self) {
            let ctx = LoadContext(config: PipelineConfig())
            _ = try await ModelFileParser(with: ctx).parse(
                string: """
                ===
                Svc
                ===
                + Mod

                === Mod ===

                = positiveAmount : { amount > 0 }

                Thing
                =====
                * amount : Float @positiveAmount
                """,
                identifier: "ModuleLevelElements_Tests_outsideAt"
            )
        }
    }

    @Test func appliedDefaultExpressionFromAt() async throws {
        let (ctx, _) = try await parseModel("""
            ===
            Svc
            ===
            + Mod

            === Mod ===

            = DEFAULT_CURRENCY : String = "USD"

            Thing
            =====
            * currency : String = @DEFAULT_CURRENCY
            """)

        let thing = try await domainObject("Thing", ctx: ctx)
        let prop = try #require(await thing.getProp("currency"))
        #expect(await prop.appliedDefaultExpression == "DEFAULT_CURRENCY")
    }

    // MARK: - Component-level # apis section

    @Test func componentLevelCustomLogicAPI() async throws {
        let (_, space) = try await parseModel("""
            ===
            Svc
            ===
            + Mod

            === Mod ===

            # apis
            ## notify(userId: Id) : Void
            #
            """)

        let module = try #require(await moduleNamed("Mod", space: space))
        let apis = await module.getAPIs().snapshot()
        #expect(apis.count == 1)
        let api = try #require(apis.first as? CustomLogicAPI)
        #expect(await api.method.name == "notify")
    }

    @Test func componentLevelAPIs_exposedViaWrap() async throws {
        let (ctx, space) = try await parseModel("""
            ===
            Svc
            ===
            + Mod

            === Mod ===

            # apis
            ## sendAlert(message: String) : Void
            ## fetchStatus() : String
            #
            """)

        let model = await ctx.model
        let module = try #require(await moduleNamed("Mod", space: space))
        let wrap = C4Component_Wrap(module, model: model)
        let apis = await wrap.apis
        #expect(apis.count == 2)
        #expect(apis.isNotEmpty)
    }

    @Test func componentLevelAPIs_mergedWithEntityAPIs() async throws {
        let (ctx, space) = try await parseModel("""
            ===
            Svc
            ===
            + Mod

            === Mod ===

            # apis
            ## ping() : Void
            #

            Order
            =====
            ** id : Id
            # apis
            ## cancel
            #
            """)

        let model = await ctx.model
        let module = try #require(await moduleNamed("Mod", space: space))
        let wrap = C4Component_Wrap(module, model: model)
        let apis = await wrap.apis
        // 1 component-level + 1 entity-level
        #expect(apis.count == 2)
    }

    @Test func classLevelNamedConstraint() async throws {
        let (ctx, _) = try await parseModel("""
            ===
            Svc
            ===
            + Mod

            === Mod ===

            Thing
            =====
            = saneDates : { start < end }

            ** id : Id
            """)

        let thing = try await domainObject("Thing", ctx: ctx)
        let named = await thing.namedConstraints.snapshot()
        #expect(named.count == 1)
        #expect(named[0].name == "saneDates")
    }
}
