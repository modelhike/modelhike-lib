import Testing
@testable import ModelHike

@Suite struct HierarchyParser_Tests {
    private func parseModel(_ dsl: String) async throws -> (LoadContext, ModelSpace) {
        let ctx = LoadContext(config: PipelineConfig())
        let modelSpace = try await ModelFileParser(with: ctx).parse(string: dsl, identifier: "HierarchyParser_Tests")
        await ctx.model.append(contentsOf: modelSpace)
        try await ctx.model.resolveAndLinkItems(with: ctx)
        return (ctx, modelSpace)
    }

    private func domainObject(_ name: String, ctx: LoadContext) async throws -> DomainObject {
        let obj = try #require(await ctx.model.types.get(for: name))
        return try #require(obj as? DomainObject)
    }

    @Test func hierarchySectionParsesOperationsAndDirectives() async throws {
        let (ctx, _) = try await parseModel("""
            ===
            Svc
            ===
            + Catalog

            === Catalog ===

            Category
            ========
            ** id: Id
            - parent: Reference@Category
            * children: Category[]

            # Hierarchy
            @ parent:: parent
            @ children:: children
            breadcrumb:
            | -- Full path from root
            | direction: up
            | include-self: true
            | returns: String
            | format: "{name}" joined by " > "
            subtree-count:
            | direction: down
            | aggregate: count
            | returns: Int
            #
            """)

        let category = try await domainObject("Category", ctx: ctx)
        let hierarchy = try #require(await category.attached.compactMap { $0 as? HierarchyObject }.first)
        let operations = await hierarchy.operations

        #expect(operations.count == 2)
        #expect(operations[0].name == "breadcrumb")
        #expect(operations[0].descriptionLines == ["Full path from root"])
        #expect(operations[0].direction == "up")
        #expect(operations[0].includeSelf == "true")
        #expect(operations[0].returns == "String")
        #expect(operations[0].format == "\"{name}\" joined by \" > \"")
        #expect(operations[1].aggregate == "count")
    }

    @Test func hierarchyWrapperIsExposedOnCodeObject() async throws {
        let (ctx, _) = try await parseModel("""
            ===
            Svc
            ===
            + Catalog

            === Catalog ===

            Category
            ========
            ** id: Id

            # Hierarchy
            descendants:
            | direction: down
            | returns: Category[]
            #
            """)

        let category = try await domainObject("Category", ctx: ctx)
        let wrapper = CodeObject_Wrap(category)
        let pInfo = await ParsedInfo.dummy(line: "wrapper", identifier: "HierarchyParser_Tests", loadCtx: ctx)

        let hasHierarchyValue = try await wrapper.getValueOf(property: "has-hierarchy", with: pInfo)
        let hasHierarchy = try #require(hasHierarchyValue as? Bool)
        let hierarchies = try #require(try await wrapper.getValueOf(property: "hierarchies", with: pInfo) as? [HierarchyObject_Wrap])
        let hierarchy = try #require(try await wrapper.getValueOf(property: "hierarchy", with: pInfo) as? HierarchyObject_Wrap)
        let operations = try #require(try await hierarchy.getValueOf(property: "operations", with: pInfo) as? [HierarchyOperation])

        #expect(hasHierarchy)
        #expect(hierarchies.count == 1)
        #expect(operations.first?.name == "descendants")
    }

    @Test func invalidHierarchyBodyLineThrows() async throws {
        await #expect(throws: (any Error).self) {
            _ = try await parseModel("""
                ===
                Svc
                ===
                + Catalog

                === Catalog ===

                Category
                ========
                ** id: Id

                # Hierarchy
                not a valid hierarchy operation
                #
                """)
        }
    }

    @Test func hierarchyParsesEverySupportedDirective() async throws {
        let (ctx, _) = try await parseModel("""
            ===
            Svc
            ===
            + Manufacturing

            === Manufacturing ===

            BOM Item
            ========
            ** id: Id

            # Hierarchy
            explode:
            | direction: down
            | include-self: true
            | max-depth: 25
            | aggregate: sum(unitCost * quantity)
            | multiply: quantity
            | filter: components.count == 0
            | order-by: sortOrder asc
            | as: name
            | format: "{name}" joined by " > "
            | group-by: accountType
            | action: reassign parent
            | validate: no-cycle, max-depth
            | returns: BOM Explosion[]
            #
            """)

        let item = try await domainObject("BOM Item", ctx: ctx)
        let hierarchy = try #require(await item.attached.compactMap { $0 as? HierarchyObject }.first)
        let operation = try #require(await hierarchy.operations.first)

        #expect(operation.direction == "down")
        #expect(operation.includeSelf == "true")
        var maxDepth: String?
        for directive in operation.directives {
            if directive.name == "max-depth" {
                maxDepth = directive.value
            }
        }
        #expect(maxDepth == "25")
        #expect(operation.aggregate == "sum(unitCost * quantity)")
        #expect(operation.multiply == "quantity")
        #expect(operation.filter == "components.count == 0")
        #expect(operation.orderBy == "sortOrder asc")
        #expect(operation.projectedAs == "name")
        #expect(operation.format == "\"{name}\" joined by \" > \"")
        #expect(operation.groupBy == "accountType")
        #expect(operation.action == "reassign parent")
        #expect(operation.validate == "no-cycle, max-depth")
        #expect(operation.returns == "BOM Explosion[]")
    }

    @Test func repeatedHierarchySectionsAppendToSameHierarchyObjectAndPreserveRawSections() async throws {
        let (ctx, _) = try await parseModel("""
            ===
            Svc
            ===
            + Catalog

            === Catalog ===

            Category
            ========
            ** id: Id

            # Hierarchy
            ancestors:
            | direction: up
            | returns: Category[]
            #

            # Hierarchy
            descendants:
            | direction: down
            | returns: Category[]
            #
            """)

        let category = try await domainObject("Category", ctx: ctx)
        let hierarchyArtifacts = await category.attached.compactMap { $0 as? HierarchyObject }
        let hierarchy = try #require(hierarchyArtifacts.first)
        let section = try #require(await category.attachedSections.get("Hierarchy"))

        #expect(hierarchyArtifacts.count == 1)
        #expect(await hierarchy.operations.map(\.name) == ["ancestors", "descendants"])
        #expect(await section.bodyLines.map(\.text) == ["descendants:", "direction: down", "returns: Category[]"])
    }

    @Test func invalidHierarchyDirectiveNameThrows() async throws {
        await #expect(throws: (any Error).self) {
            _ = try await parseModel("""
                ===
                Svc
                ===
                + Catalog

                === Catalog ===

                Category
                ========
                ** id: Id

                # Hierarchy
                descendants:
                | unsupported: value
                #
                """)
        }
    }

    @Test func emptyHierarchyDirectiveValueThrows() async throws {
        await #expect(throws: (any Error).self) {
            _ = try await parseModel("""
                ===
                Svc
                ===
                + Catalog

                === Catalog ===

                Category
                ========
                ** id: Id

                # Hierarchy
                descendants:
                | direction:
                #
                """)
        }
    }

    @Test func hierarchyWrapperRejectsUnknownProperty() async throws {
        let (ctx, _) = try await parseModel("""
            ===
            Svc
            ===
            + Catalog

            === Catalog ===

            Category
            ========
            ** id: Id

            # Hierarchy
            descendants:
            | direction: down
            | returns: Category[]
            #
            """)

        let category = try await domainObject("Category", ctx: ctx)
        let wrapper = CodeObject_Wrap(category)
        let pInfo = await ParsedInfo.dummy(line: "wrapper", identifier: "HierarchyParser_Tests", loadCtx: ctx)
        let hierarchy = try #require(try await wrapper.getValueOf(property: "hierarchy", with: pInfo) as? HierarchyObject_Wrap)
        let hasOperationsValue = try await hierarchy.getValueOf(property: "has-operations", with: pInfo)
        let hasOperations = try #require(hasOperationsValue as? Bool)

        #expect(hasOperations)
        await #expect(throws: (any Error).self) {
            _ = try await hierarchy.getValueOf(property: "unknown-property", with: pInfo)
        }
    }
}
