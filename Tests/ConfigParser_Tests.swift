import Testing
@testable import ModelHike

@Suite struct ConfigParser_Tests {
    private func parseModel(_ dsl: String) async throws -> (LoadContext, ModelSpace) {
        let ctx = LoadContext(config: PipelineConfig())
        let modelSpace = try await ModelFileParser(with: ctx).parse(string: dsl, identifier: "ConfigParser_Tests")
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

    @Test func configParsesKindPropertiesAndGroups() async throws {
        let (_, space) = try await parseModel("""
            ===
            Svc
            ===
            + Billing

            === Billing ===

            Currency Settings (currency)
            ::::::::
            base = USD
            rounding: HALF_UP
            rates:
            | EUR -> 0.9
            | INR = 83
            """)

        let module = try #require(await moduleNamed("Billing", space: space))
        let config = try #require(await module.configObjects.first)

        #expect(await config.name == "CurrencySettings")
        #expect(await config.configKind == "currency")
        #expect(await config.properties.map(\.key) == ["base", "rounding"])
        #expect(await config.properties.map(\.value) == ["USD", "HALF_UP"])

        let group = try #require(await config.groups.first)
        #expect(group.name == "rates")
        var groupKeys: [String] = []
        var groupValues: [String] = []
        for property in group.properties {
            groupKeys.append(property.key)
            groupValues.append(property.value)
        }
        #expect(groupKeys == ["EUR", "INR"])
        #expect(groupValues == ["0.9", "83"])
    }

    @Test func configWithoutKindStillParsesAndStopsBeforeNextObject() async throws {
        let (ctx, space) = try await parseModel("""
            ===
            Svc
            ===
            + Billing

            === Billing ===

            Feature Flags
            ::::::::
            checkout = enabled

            Customer
            ========
            ** id: Id
            """)

        let module = try #require(await moduleNamed("Billing", space: space))
        let config = try #require(await module.configObjects.first)

        #expect(await config.configKind == nil)
        #expect(await config.properties.first?.key == "checkout")
        #expect(await config.properties.first?.value == "enabled")
        let customer = try #require(await ctx.model.types.get(for: "Customer") as? DomainObject)
        #expect(await customer.name == "Customer")
    }

    @Test func configParsesMultipleGroups() async throws {
        let (_, space) = try await parseModel("""
            ===
            Svc
            ===
            + Billing

            === Billing ===

            Payment Config (payment)
            ::::::::
            gateways:
            | stripe = enabled
            | paypal = enabled
            retries:
            | max = 3
            | delay = 1000
            """)

        let module = try #require(await moduleNamed("Billing", space: space))
        let config = try #require(await module.configObjects.first)

        #expect(await config.configKind == "payment")
        #expect(await config.properties.isEmpty)
        #expect(await config.groups.count == 2)
        #expect(await config.groups[0].name == "gateways")
        #expect(await config.groups[0].properties.count == 2)
        #expect(await config.groups[1].name == "retries")
        #expect(await config.groups[1].properties.count == 2)
        #expect(await config.groups[1].properties[0].key == "max")
    }

    @Test func configWithRootPropertiesBeforeGroup() async throws {
        let (_, space) = try await parseModel("""
            ===
            Svc
            ===
            + Billing

            === Billing ===

            App Config (app)
            ::::::::
            env = production
            debug = false
            cache:
            | ttl = 300
            | max_size = 1024
            """)

        let module = try #require(await moduleNamed("Billing", space: space))
        let config = try #require(await module.configObjects.first)

        #expect(await config.properties.count == 2)
        #expect(await config.properties[0].key == "env")
        #expect(await config.properties[1].key == "debug")
        #expect(await config.groups.count == 1)
        #expect(await config.groups[0].properties.count == 2)
    }

    @Test func configParsesColonEqualsAndArrowProperties() async throws {
        let (_, space) = try await parseModel("""
            ===
            Svc
            ===
            + Billing

            === Billing ===

            Sequence Config (sequence)
            ::::::::
            prefix: INV
            next = 1000
            format -> INV-{next}
            """)

        let module = try #require(await moduleNamed("Billing", space: space))
        let config = try #require(await module.configObjects.first)

        #expect(await config.properties.map(\.key) == ["prefix", "next", "format"])
        #expect(await config.properties.map(\.value) == ["INV", "1000", "INV-{next}"])
    }
}
