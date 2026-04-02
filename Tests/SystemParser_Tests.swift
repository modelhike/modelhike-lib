import Testing
@testable import ModelHike

@Suite struct SystemParser_Tests {

    // MARK: - Helpers

    private func parseModel(_ dsl: String) async throws -> (ctx: LoadContext, space: ModelSpace) {
        let ctx = LoadContext(config: PipelineConfig())
        let space = try await ModelFileParser(with: ctx).parse(string: dsl, identifier: "SystemParser_Tests")
        await ctx.model.append(contentsOf: space)
        try await ctx.model.resolveAndLinkItems(with: ctx)
        return (ctx, space)
    }

    private func systemNamed(_ givenname: String, space: ModelSpace) async -> C4System? {
        for s in await space.systems.snapshot() {
            if await s.givenname == givenname { return s }
        }
        return nil
    }

    // MARK: - Fence detection

    @Test func asterismLineDetection() {
        #expect(SystemParser.isAsterismLine("* * *") == true)
        #expect(SystemParser.isAsterismLine("* * * * * * * * *") == true)
        #expect(SystemParser.isAsterismLine("*") == false)       // only one star
        #expect(SystemParser.isAsterismLine("* *") == false)     // only two stars (below minimum)
        #expect(SystemParser.isAsterismLine("===") == false)
        #expect(SystemParser.isAsterismLine("") == false)
        #expect(SystemParser.isAsterismLine("* * - *") == false) // mixed chars
    }

    // MARK: - Basic system parsing

    @Test func systemNameIsParsed() async throws {
        let (_, space) = try await parseModel("""
            * * * * * * * * *
            E-Commerce Platform
            * * * * * * * * *
            * * * * * * * * *
            """)

        let system = try #require(await systemNamed("E-Commerce Platform", space: space))
        #expect(await system.givenname == "E-Commerce Platform")
        #expect(await system.name == "E_CommercePlatform")
    }

    // MARK: - Container references

    @Test func containerRefsAreStoredAsUnresolved() async throws {
        let (_, space) = try await parseModel("""
            * * * * * * * * *
            Logistics Platform
            * * * * * * * * *
            + Inventory Service
            + Shipping Service
            * * * * * * * * *

            ===
            Inventory Service
            ===

            ===
            Shipping Service
            ===
            """)

        let system = try #require(await systemNamed("Logistics Platform", space: space))
        #expect(await system.unresolvedContainerRefs.isEmpty)

        let resolved = await system.containers.snapshot()
        #expect(resolved.count == 2)
        #expect(await resolved[0].givenname == "Inventory Service")
        #expect(await resolved[1].givenname == "Shipping Service")
    }

    @Test func containerRefMatchesByGivenname() async throws {
        let (_, space) = try await parseModel("""
            * * * * * * * * *
            My System
            * * * * * * * * *
            + Order Service
            * * * * * * * * *

            ===
            Order Service #blueprint(api-nestjs-monorepo)
            ===
            """)

        let system = try #require(await systemNamed("My System", space: space))
        let resolved = await system.containers.snapshot()
        #expect(resolved.count == 1)
        #expect(await resolved[0].givenname == "Order Service")
    }

    // MARK: - Infra nodes

    @Test func infraNodeNameAndTypeAreParsed() async throws {
        let (_, space) = try await parseModel("""
            * * * * * * * * *
            Auth Platform
            * * * * * * * * *
            PostgreSQL [database]
            +++++++++++++++++++++
            * * * * * * * * *
            """)

        let system = try #require(await systemNamed("Auth Platform", space: space))
        let nodes = await system.infraNodes
        #expect(nodes.count == 1)
        #expect(nodes[0].givenname == "PostgreSQL")
        #expect(nodes[0].name == "PostgreSQL")
        #expect(nodes[0].infraType == "database")
    }

    @Test func infraNodePropertiesAreParsed() async throws {
        let (_, space) = try await parseModel("""
            * * * * * * * * *
            Data Platform
            * * * * * * * * *
            PostgreSQL [database] #primary-db
            +++++++++++++++++++++++++++++++++
            host    = db.internal
            port    = 5432
            version = 14
            * * * * * * * * *
            """)

        let system = try #require(await systemNamed("Data Platform", space: space))
        let nodes = await system.infraNodes
        #expect(nodes.count == 1)
        let node = nodes[0]
        #expect(node.infraType == "database")
        #expect(node.tags.contains(where: { $0.name == "primary-db" }))
        #expect(node.properties.count == 3)
        #expect(node.properties[0] == InfraProperty(key: "host", value: "db.internal"))
        #expect(node.properties[1] == InfraProperty(key: "port", value: "5432"))
        #expect(node.properties[2] == InfraProperty(key: "version", value: "14"))
    }

    @Test func infraNodeInlineDescription() async throws {
        let (_, space) = try await parseModel("""
            * * * * * * * * *
            My System
            * * * * * * * * *
            Redis Cache [cache] -- Session store
            +++++++++++++++++++++++++++++++++++++
            * * * * * * * * *
            """)

        let system = try #require(await systemNamed("My System", space: space))
        let node = try #require(await system.infraNodes.first)
        #expect(node.description == "Session store")
    }

    @Test func multipleInfraNodes() async throws {
        let (_, space) = try await parseModel("""
            * * * * * * * * *
            E-Commerce Platform
            * * * * * * * * *
            PostgreSQL [database]
            +++++++++++++++++++++
            host = db.internal
            port = 5432

            Kafka Events [message-broker]
            +++++++++++++++++++++++++++++
            bootstrap.servers = kafka:9092

            Redis Cache [cache]
            +++++++++++++++++++
            host = redis.internal
            * * * * * * * * *
            """)

        let system = try #require(await systemNamed("E-Commerce Platform", space: space))
        let nodes = await system.infraNodes
        #expect(nodes.count == 3)
        #expect(nodes[0].infraType == "database")
        #expect(nodes[1].infraType == "message-broker")
        #expect(nodes[2].infraType == "cache")
    }

    // MARK: - Mixed body

    @Test func systemWithContainerRefsAndInfraNodes() async throws {
        let (_, space) = try await parseModel("""
            * * * * * * * * * * * * *
            Full Platform
            * * * * * * * * * * * * *
            + Payments Service
            PostgreSQL [database]
            +++++++++++++++++++++
            host = db.internal
            Kafka Events [message-broker]
            +++++++++++++++++++++++++++++
            * * * * * * * * * * * * *

            ===
            Payments Service
            ===
            """)

        let system = try #require(await systemNamed("Full Platform", space: space))
        let resolved = await system.containers.snapshot()
        #expect(resolved.count == 1)
        let nodes = await system.infraNodes
        #expect(nodes.count == 2)
    }

    // MARK: - System description

    @Test func systemInlineDescriptionIsParsed() async throws {
        let (_, space) = try await parseModel("""
            * * * * * * * * *
            Billing Platform -- Our payments backbone
            * * * * * * * * *
            * * * * * * * * *
            """)

        let system = try #require(await systemNamed("Billing Platform", space: space))
        #expect(await system.description == "Our payments backbone")
    }

    @Test func systemPendingDescriptionFromTripleBlock() async throws {
        let (_, space) = try await parseModel("""
            >>> Core commerce system
            * * * * * * * * *
            Commerce Platform
            * * * * * * * * *
            * * * * * * * * *
            """)

        let system = try #require(await systemNamed("Commerce Platform", space: space))
        #expect(await system.description == "Core commerce system")
    }

    // MARK: - Container reference edge cases

    @Test func barePlusLineIsIgnored() async throws {
        let (_, space) = try await parseModel("""
            * * * * * * * * *
            Edge Platform
            * * * * * * * * *
            +
            * * * * * * * * *
            """)

        let system = try #require(await systemNamed("Edge Platform", space: space))
        #expect(await system.unresolvedContainerRefs.isEmpty)
        #expect(await system.containers.snapshot().isEmpty)
    }

    @Test func containerRefMatchesByNormalizedName() async throws {
        let (_, space) = try await parseModel("""
            * * * * * * * * *
            My System
            * * * * * * * * *
            + OrderService
            * * * * * * * * *

            ===
            Order Service
            ===
            """)

        let system = try #require(await systemNamed("My System", space: space))
        let resolved = await system.containers.snapshot()
        #expect(resolved.count == 1)
        #expect(await resolved[0].givenname == "Order Service")
    }

    @Test func unresolvedRefRemainsWhenNoMatchingContainer() async throws {
        let (_, space) = try await parseModel("""
            * * * * * * * * *
            Isolated System
            * * * * * * * * *
            + Ghost Service
            * * * * * * * * *
            """)

        let system = try #require(await systemNamed("Isolated System", space: space))
        #expect(await system.containers.snapshot().isEmpty)
        #expect(await system.unresolvedContainerRefs == ["Ghost Service"])
    }

    // MARK: - Body boundary conditions

    @Test func bodyWithoutClosingAsterismParsesToEOF() async throws {
        // No closing asterism — body loop reads to EOF.
        // Any content after the system header is consumed as body lines,
        // so the refs are captured but remain unresolved (no containers defined).
        let (_, space) = try await parseModel("""
            * * * * * * * * *
            Open System
            * * * * * * * * *
            + Alpha Service
            + Beta Service
            """)

        let system = try #require(await systemNamed("Open System", space: space))
        #expect(await system.unresolvedContainerRefs.count == 2)
    }

    @Test func twoSystemsInSameFile() async throws {
        let (_, space) = try await parseModel("""
            * * * * * * * * *
            Platform Alpha
            * * * * * * * * *
            * * * * * * * * *

            * * * * * * * * *
            Platform Beta
            * * * * * * * * *
            * * * * * * * * *
            """)

        let systems = await space.systems.snapshot()
        #expect(systems.count == 2)
        #expect(await systems[0].givenname == "Platform Alpha")
        #expect(await systems[1].givenname == "Platform Beta")
    }

    @Test func unrecognizedLineInBodyIsSkipped() async throws {
        let (_, space) = try await parseModel("""
            * * * * * * * * *
            Silent System
            * * * * * * * * *
            some random unrecognised text here
            another weird line
            * * * * * * * * *
            """)

        let system = try #require(await systemNamed("Silent System", space: space))
        #expect(await system.infraNodes.isEmpty)
        #expect(await system.containers.snapshot().isEmpty)
    }

    // MARK: - canParse boundary conditions

    @Test func canParseReturnsFalseWhenNameCandidateIsAsterism() async throws {
        // Three consecutive asterisms: the name candidate for any opener is always
        // another asterism — canParse rejects all of them, so no system is parsed.
        let (_, space) = try await parseModel("""
            * * * * * * * * *
            * * * * * * * * *
            * * * * * * * * *
            """)

        #expect(await space.systems.snapshot().isEmpty)
    }

    // MARK: - System attributes and tags

    @Test func systemAttributesAndTagsAreParsed() async throws {
        let (_, space) = try await parseModel("""
            * * * * * * * * *
            My Platform (env=production) #flagship
            * * * * * * * * *
            * * * * * * * * *
            """)

        let system = try #require(await systemNamed("My Platform", space: space))
        #expect(await system.attribs.getString("env") == "production")
        #expect(await system.tags.has("flagship"))
    }

    // MARK: - Infra node edge cases

    @Test func infraNodeWithNoType() async throws {
        let (_, space) = try await parseModel("""
            * * * * * * * * *
            Thin Platform
            * * * * * * * * *
            Redis
            +++++
            host = redis.internal
            * * * * * * * * *
            """)

        let system = try #require(await systemNamed("Thin Platform", space: space))
        let node = try #require(await system.infraNodes.first)
        #expect(node.givenname == "Redis")
        #expect(node.infraType == nil)
        #expect(node.properties.count == 1)
    }

    @Test func infraNodePropertyValueWithEquals() async throws {
        let (_, space) = try await parseModel("""
            * * * * * * * * *
            Data Platform
            * * * * * * * * *
            PostgreSQL [database]
            +++++++++++++++++++++
            url = jdbc:postgresql://host:5432/mydb
            * * * * * * * * *
            """)

        let system = try #require(await systemNamed("Data Platform", space: space))
        let node = try #require(await system.infraNodes.first)
        #expect(node.properties.count == 1)
        #expect(node.properties[0] == InfraProperty(key: "url", value: "jdbc:postgresql://host:5432/mydb"))
    }

    @Test func commentLineInsidePropertyBlockIsSkipped() async throws {
        let (_, space) = try await parseModel("""
            * * * * * * * * *
            DB Platform
            * * * * * * * * *
            PostgreSQL [database]
            +++++++++++++++++++++
            host = db.internal
            // this comment should be skipped
            port = 5432
            * * * * * * * * *
            """)

        let system = try #require(await systemNamed("DB Platform", space: space))
        let node = try #require(await system.infraNodes.first)
        #expect(node.properties.count == 2)
        #expect(node.properties[0] == InfraProperty(key: "host", value: "db.internal"))
        #expect(node.properties[1] == InfraProperty(key: "port", value: "5432"))
    }

    @Test func plusLineInsidePropertyBlockStopsInfraNode() async throws {
        let (_, space) = try await parseModel("""
            * * * * * * * * *
            Mixed Platform
            * * * * * * * * *
            PostgreSQL [database]
            +++++++++++++++++++++
            host = db.internal
            + Order Service
            * * * * * * * * *

            ===
            Order Service
            ===
            """)

        let system = try #require(await systemNamed("Mixed Platform", space: space))
        let node = try #require(await system.infraNodes.first)
        // property reading stops at the `+ Order Service` line
        #expect(node.properties.count == 1)
        #expect(node.properties[0] == InfraProperty(key: "host", value: "db.internal"))
        // container ref after the infra node is still resolved
        #expect(await system.containers.snapshot().count == 1)
    }

    @Test func infraNodeWithAllFourFields() async throws {
        let (_, space) = try await parseModel("""
            * * * * * * * * *
            Full Platform
            * * * * * * * * *
            Kafka Events [message-broker] #async -- Event streaming backbone
            +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
            bootstrap.servers = kafka:9092
            group.id          = platform
            * * * * * * * * *
            """)

        let system = try #require(await systemNamed("Full Platform", space: space))
        let node = try #require(await system.infraNodes.first)
        #expect(node.givenname == "Kafka Events")
        #expect(node.infraType == "message-broker")
        #expect(node.tags.contains(where: { $0.name == "async" }))
        #expect(node.description == "Event streaming backbone")
        #expect(node.properties.count == 2)
    }

    @Test func annotationLineAboveUnderlineIsNotInfraNode() async throws {
        let (_, space) = try await parseModel("""
            * * * * * * * * *
            Guard Platform
            * * * * * * * * *
            @SomeAnnotation
            +++++++++++++++
            * * * * * * * * *
            """)

        let system = try #require(await systemNamed("Guard Platform", space: space))
        #expect(await system.infraNodes.isEmpty)
    }

    @Test func tagLineAboveUnderlineIsNotInfraNode() async throws {
        let (_, space) = try await parseModel("""
            * * * * * * * * *
            Guard Platform Two
            * * * * * * * * *
            #standalone-tag
            +++++++++++++++
            * * * * * * * * *
            """)

        let system = try #require(await systemNamed("Guard Platform Two", space: space))
        #expect(await system.infraNodes.isEmpty)
    }

    @Test func bracketPrefixedLineIsNotParsedAsInfraNode() async throws {
        // `[database]` starts with `[`, so canParse returns false — silently skipped.
        let (_, space) = try await parseModel("""
            * * * * * * * * *
            Bracket Platform
            * * * * * * * * *
            [database]
            ++++++++++
            * * * * * * * * *
            """)

        let system = try #require(await systemNamed("Bracket Platform", space: space))
        #expect(await system.infraNodes.isEmpty)
    }
}

// MARK: - Equatable for test assertions

extension InfraProperty: Equatable {
    public static func == (lhs: InfraProperty, rhs: InfraProperty) -> Bool {
        lhs.key == rhs.key && lhs.value == rhs.value
    }
}
