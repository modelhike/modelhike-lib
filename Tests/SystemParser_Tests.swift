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

    // MARK: - Virtual groups

    @Test func virtualGroupFenceDetection() {
        #expect(VirtualGroupParser.isOpeningFence("+--- Data Tier") == true)
        #expect(VirtualGroupParser.isOpeningFence("+--- A") == true)
        #expect(VirtualGroupParser.isOpeningFence("+---") == false)     // no name → closing
        #expect(VirtualGroupParser.isOpeningFence("+---   ") == false)  // whitespace only → closing
        #expect(VirtualGroupParser.isOpeningFence("+ Data Tier") == false) // container ref
        #expect(VirtualGroupParser.isClosingFence("+---") == true)
        #expect(VirtualGroupParser.isClosingFence("+---   ") == true)
        #expect(VirtualGroupParser.isClosingFence("+--- Data") == false)
        #expect(VirtualGroupParser.isClosingFence("---") == false)
    }

    @Test func virtualGroupNameIsParsed() async throws {
        let (_, space) = try await parseModel("""
            * * * * * * * * *
            Group System
            * * * * * * * * *
            +--- Infrastructure
            |
            +---
            * * * * * * * * *
            """)

        let system = try #require(await systemNamed("Group System", space: space))
        let groups = await system.groups
        #expect(groups.count == 1)
        let g0 = groups[0]
        #expect(g0.givenname == "Infrastructure")
        #expect(g0.name == "Infrastructure")
    }

    @Test func virtualGroupNameNormalisedCorrectly() async throws {
        let (_, space) = try await parseModel("""
            * * * * * * * * *
            Norm System
            * * * * * * * * *
            +--- Data Services Layer
            |
            +---
            * * * * * * * * *
            """)

        let system = try #require(await systemNamed("Norm System", space: space))
        let groups = await system.groups
        #expect(groups.count == 1)
        #expect(groups[0].givenname == "Data Services Layer")
        #expect(groups[0].name == "DataServicesLayer")
    }

    @Test func virtualGroupInlineDescriptionIsParsed() async throws {
        let (_, space) = try await parseModel("""
            * * * * * * * * *
            Desc System
            * * * * * * * * *
            +--- Infrastructure -- Core data layer
            |
            +---
            * * * * * * * * *
            """)

        let system = try #require(await systemNamed("Desc System", space: space))
        #expect((await system.groups)[0].description == "Core data layer")
    }

    @Test func virtualGroupTagsAreParsed() async throws {
        let (_, space) = try await parseModel("""
            * * * * * * * * *
            Tag System
            * * * * * * * * *
            +--- Backend #tier=data #critical
            |
            +---
            * * * * * * * * *
            """)

        let system = try #require(await systemNamed("Tag System", space: space))
        let tags = (await system.groups)[0].tags
        #expect(tags.count == 2)
    }

    @Test func virtualGroupContainerRefIsStored() async throws {
        let (_, space) = try await parseModel("""
            * * * * * * * * *
            Ref System
            * * * * * * * * *
            +--- Backend
            | + Orders Service
            +---
            * * * * * * * * *
            """)

        let system = try #require(await systemNamed("Ref System", space: space))
        let group = (await system.groups)[0]
        #expect(group.unresolvedContainerRefs == ["Orders Service"])
    }

    @Test func virtualGroupContainerRefIsResolved() async throws {
        let (_, space) = try await parseModel("""
            * * * * * * * * *
            Resolved System
            * * * * * * * * *
            +--- Backend
            | + Orders Service
            +---
            * * * * * * * * *

            ===
            Orders Service
            ===
            """)

        let system = try #require(await systemNamed("Resolved System", space: space))
        let group = (await system.groups)[0]
        #expect(group.unresolvedContainerRefs.isEmpty)
        #expect(group.containers.count == 1)
        let name = await group.containers[0].givenname
        #expect(name == "Orders Service")
    }

    @Test func virtualGroupInfraNodeIsParsed() async throws {
        let (_, space) = try await parseModel("""
            * * * * * * * * *
            Infra Group System
            * * * * * * * * *
            +--- Data
            | PostgreSQL [database]
            | +++++++++++++++++++++
            | host = db.internal
            +---
            * * * * * * * * *
            """)

        let system = try #require(await systemNamed("Infra Group System", space: space))
        let group = (await system.groups)[0]
        #expect(group.infraNodes.count == 1)
        #expect(group.infraNodes[0].givenname == "PostgreSQL")
        #expect(group.infraNodes[0].infraType == "database")
        #expect(group.infraNodes[0].properties == [InfraProperty(key: "host", value: "db.internal")])
    }

    @Test func virtualGroupEmptyBodyIsParsed() async throws {
        let (_, space) = try await parseModel("""
            * * * * * * * * *
            Empty Group System
            * * * * * * * * *
            +--- Placeholder
            |
            |
            +---
            * * * * * * * * *
            """)

        let system = try #require(await systemNamed("Empty Group System", space: space))
        let group = (await system.groups)[0]
        #expect(group.unresolvedContainerRefs.isEmpty)
        #expect(group.infraNodes.isEmpty)
        #expect(group.subGroups.isEmpty)
    }

    @Test func multipleVirtualGroupsAtTopLevel() async throws {
        let (_, space) = try await parseModel("""
            * * * * * * * * *
            Multi Group System
            * * * * * * * * *
            +--- Frontend
            | + Web App
            +---
            +--- Backend
            | + API Service
            +---
            * * * * * * * * *

            ===
            Web App
            ===

            ===
            API Service
            ===
            """)

        let system = try #require(await systemNamed("Multi Group System", space: space))
        let groups = await system.groups
        #expect(groups.count == 2)
        #expect(groups[0].givenname == "Frontend")
        #expect(groups[1].givenname == "Backend")
        #expect(groups[0].containers.count == 1)
        #expect(groups[1].containers.count == 1)
    }

    @Test func nestedVirtualGroupIsParsed() async throws {
        let (_, space) = try await parseModel("""
            * * * * * * * * *
            Nested System
            * * * * * * * * *
            +--- Outer
            | + Top Level Service
            | +--- Inner
            | | + Inner Service
            | +---
            +---
            * * * * * * * * *

            ===
            Top Level Service
            ===

            ===
            Inner Service
            ===
            """)

        let system = try #require(await systemNamed("Nested System", space: space))
        let groups = await system.groups
        #expect(groups.count == 1)
        let outer = groups[0]
        #expect(outer.givenname == "Outer")
        #expect(outer.subGroups.count == 1)

        let inner = outer.subGroups[0]
        #expect(inner.givenname == "Inner")
        #expect(inner.containers.count == 1)
        let innerContainerName = await inner.containers[0].givenname
        #expect(innerContainerName == "Inner Service")
    }

    @Test func deeplyNestedVirtualGroups() async throws {
        let (_, space) = try await parseModel("""
            * * * * * * * * *
            Deep Nest System
            * * * * * * * * *
            +--- L1
            | +--- L2
            | | +--- L3
            | | | + Deep Service
            | | +---
            | +---
            +---
            * * * * * * * * *

            ===
            Deep Service
            ===
            """)

        let system = try #require(await systemNamed("Deep Nest System", space: space))
        let allGroups = await system.groups
        let l1 = try #require(allGroups.first)
        let l2 = try #require(l1.subGroups.first)
        let l3 = try #require(l2.subGroups.first)
        #expect(l3.givenname == "L3")
        #expect(l3.containers.count == 1)
        let svc = await l3.containers[0].givenname
        #expect(svc == "Deep Service")
    }

    @Test func virtualGroupMixedContent() async throws {
        // A group can hold container refs, infra nodes, and sub-groups all at once.
        let (_, space) = try await parseModel("""
            * * * * * * * * *
            Mixed System
            * * * * * * * * *
            +--- Everything
            | + Order Service
            | Redis [cache]
            | ++++++++++++++
            | host = redis.internal
            | +--- Sub
            | | + Payment Service
            | +---
            +---
            * * * * * * * * *

            ===
            Order Service
            ===

            ===
            Payment Service
            ===
            """)

        let system = try #require(await systemNamed("Mixed System", space: space))
        let group = (await system.groups)[0]
        #expect(group.containers.count == 1)
        let c0name = await group.containers[0].givenname
        #expect(c0name == "Order Service")
        #expect(group.infraNodes.count == 1)
        #expect(group.infraNodes[0].givenname == "Redis")
        #expect(group.subGroups.count == 1)
        #expect(group.subGroups[0].givenname == "Sub")
        #expect(group.subGroups[0].containers.count == 1)
    }

    @Test func virtualGroupAndTopLevelContainerRefCoexist() async throws {
        let (_, space) = try await parseModel("""
            * * * * * * * * *
            Coexist System
            * * * * * * * * *
            + Direct Service
            +--- Grouped
            | + Grouped Service
            +---
            * * * * * * * * *

            ===
            Direct Service
            ===

            ===
            Grouped Service
            ===
            """)

        let system = try #require(await systemNamed("Coexist System", space: space))
        let topLevel = await system.containers.snapshot()
        #expect(topLevel.count == 1)
        let directName = await topLevel[0].givenname
        #expect(directName == "Direct Service")

        let groups = await system.groups
        #expect(groups.count == 1)
        #expect(groups[0].containers.count == 1)
    }

    @Test func virtualGroupWithoutClosingFenceParsesToEOF() async throws {
        // No closing `+---` — the body is consumed until EOF.
        let (_, space) = try await parseModel("""
            * * * * * * * * *
            Unclosed Group System
            * * * * * * * * *
            +--- Unclosed
            | + Some Service
            """)

        // System is parsed; group has the ref but no closing container definition.
        let system = try #require(await systemNamed("Unclosed Group System", space: space))
        let groups = await system.groups
        #expect(groups.count == 1)
        // No container was defined so the ref remains unresolved.
        #expect(groups[0].unresolvedContainerRefs.count == 1)
    }

    @Test func closingFenceWithTrailingWhitespaceIsRecognised() {
        #expect(VirtualGroupParser.isClosingFence("+---   ") == true)
        #expect(VirtualGroupParser.isClosingFence("   +---   ") == true)
    }

    @Test func virtualGroupDigitFirstNameFallback() async throws {
        // Group names starting with a digit bypass containerName_Capturing and hit
        // the ParserUtil.extractNameAndTagString fallback path.
        let (_, space) = try await parseModel("""
            * * * * * * * * *
            Fallback System
            * * * * * * * * *
            +--- 1st Infrastructure #tier=data -- Core layer
            |
            +---
            * * * * * * * * *
            """)

        let system = try #require(await systemNamed("Fallback System", space: space))
        let groups = await system.groups
        #expect(groups.count == 1)
        let g = groups[0]
        #expect(g.givenname == "1st Infrastructure")
        #expect(g.description == "Core layer")
        #expect(g.tags.count == 1)
    }

    @Test func extractNameAndTagStringUtil() {
        // Unit test for the ParserUtil helper directly.
        let (name1, tags1) = ParserUtil.extractNameAndTagString(from: "1st Layer #tier=data #critical")
        #expect(name1 == "1st Layer")
        #expect(tags1 == "#tier=data #critical")

        let (name2, tags2) = ParserUtil.extractNameAndTagString(from: "Plain Name")
        #expect(name2 == "Plain Name")
        #expect(tags2 == nil)

        let (name3, tags3) = ParserUtil.extractNameAndTagString(from: "  Trimmed  #tag  ")
        #expect(name3 == "Trimmed")
        // Trailing whitespace on the input is removed by the initial trim.
        #expect(tags3 == "#tag")
    }

    @Test func virtualGroupContainerRefResolvedByNormalisedName() async throws {
        // Ref uses the givenname with spaces; container name is normalised — resolution
        // must match on normalised form just like top-level system refs do.
        let (_, space) = try await parseModel("""
            * * * * * * * * *
            Norm Resolve System
            * * * * * * * * *
            +--- Services
            | + Order Service
            +---
            * * * * * * * * *

            ===
            Order Service
            ===
            """)

        let system = try #require(await systemNamed("Norm Resolve System", space: space))
        let group = (await system.groups)[0]
        #expect(group.unresolvedContainerRefs.isEmpty)
        #expect(group.containers.count == 1)
        let resolvedName = await group.containers[0].givenname
        #expect(resolvedName == "Order Service")
    }

    @Test func virtualGroupBodyTruncatesAtMalformedLine() async throws {
        // When a line that is neither `|`-prefixed nor the closing `+---` appears,
        // body collection stops there (W621 is emitted as a side-effect).
        // — Elements BEFORE the malformed line are captured.
        // — Elements AFTER the malformed line inside the group are NOT captured.
        let (_, space) = try await parseModel("""
            * * * * * * * * *
            Malformed Group System
            * * * * * * * * *
            +--- Broken
            | + Service A
            oops this line has no pipe prefix
            | + Service B
            +---
            * * * * * * * * *
            """)

        let system = try #require(await systemNamed("Malformed Group System", space: space))
        let group = (await system.groups)[0]
        // Only Service A (before the malformed line) is captured.
        #expect(group.unresolvedContainerRefs == ["Service A"])
        // Service B (after the malformed line) is NOT in the group's refs.
        #expect(!group.unresolvedContainerRefs.contains("Service B"))
    }

    @Test func commentLineInsideGroupBodyIsSkipped() async throws {
        let (_, space) = try await parseModel("""
            * * * * * * * * *
            Comment Group System
            * * * * * * * * *
            +--- Services
            | // This is a comment
            | + Inventory Service
            +---
            * * * * * * * * *

            ===
            Inventory Service
            ===
            """)

        let system = try #require(await systemNamed("Comment Group System", space: space))
        let group = (await system.groups)[0]
        // Comment should not be captured as a container ref or cause any issue.
        #expect(group.containers.count == 1)
        let name = await group.containers[0].givenname
        #expect(name == "Inventory Service")
    }

    @Test func virtualGroupCoexistsWithTopLevelInfraNode() async throws {
        let (_, space) = try await parseModel("""
            * * * * * * * * *
            Hybrid System
            * * * * * * * * *
            Kafka [broker]
            +++++++++++++++++
            bootstrap = kafka:9092
            +--- Services
            | + Alpha Service
            +---
            * * * * * * * * *

            ===
            Alpha Service
            ===
            """)

        let system = try #require(await systemNamed("Hybrid System", space: space))
        #expect((await system.infraNodes).count == 1)
        #expect((await system.infraNodes)[0].givenname == "Kafka")
        let groups = await system.groups
        #expect(groups.count == 1)
        #expect(groups[0].containers.count == 1)
    }

    @Test func barePlusLineInsideGroupBodyIsIgnored() async throws {
        // A bare `+ ` (no name after the +) should not add an empty ref.
        let (_, space) = try await parseModel("""
            * * * * * * * * *
            Bare Plus System
            * * * * * * * * *
            +--- Services
            | +
            +---
            * * * * * * * * *
            """)

        let system = try #require(await systemNamed("Bare Plus System", space: space))
        let group = (await system.groups)[0]
        #expect(group.unresolvedContainerRefs.isEmpty)
    }
}

// MARK: - Equatable for test assertions

extension InfraProperty: Equatable {
    public static func == (lhs: InfraProperty, rhs: InfraProperty) -> Bool {
        lhs.key == rhs.key && lhs.value == rhs.value
    }
}
