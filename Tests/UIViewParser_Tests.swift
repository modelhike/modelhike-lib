import Testing
@testable import ModelHike

@Suite struct UIViewParser_Tests {
    private func parseModel(_ dsl: String) async throws -> (LoadContext, ModelSpace) {
        let ctx = LoadContext(config: PipelineConfig())
        let modelSpace = try await ModelFileParser(with: ctx).parse(string: dsl, identifier: "UIViewParser_Tests")
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

    @Test func uiViewParsesNewSemicolonFenceSectionsSlotsBindingsAndActions() async throws {
        let (_, space) = try await parseModel("""
            ===
            Web
            ===
            + UI

            === UI ===

            Dashboard
            /;;;;;;;/
            @ title:: Main Dashboard
            Fields:
            * name: String
            - notes: String
            * details: @"DetailsView"
            | lazy true
            # Actions
            ## submit
            run saveDashboard
            #
            """)

        let module = try #require(await moduleNamed("UI", space: space))
        let view = try #require(await module.uiViewObjects.first)

        #expect(await view.name == "Dashboard")
        #expect(await view.dataType == .ui)
        #expect(await view.directives.map(\.name) == ["title"])

        let section = try #require(await view.sections.first)
        #expect(section.name == "Fields")
        var controlNames: [String] = []
        var controlTypes: [String?] = []
        var controlRequired: [RequiredKind] = []
        for control in section.controls {
            controlNames.append(control.name)
            controlTypes.append(control.typeName)
            controlRequired.append(control.required)
        }
        #expect(controlNames == ["name", "notes"])
        #expect(controlTypes == ["String", "String"])
        #expect(controlRequired == [.yes, .no])

        let slot = try #require(await view.slots.first)
        #expect(slot.name == "details")
        #expect(slot.reference == "DetailsView")
        #expect(slot.directives.first?.text == "lazy true")

        let action = try #require(await view.actions.first)
        #expect(action.trigger == "submit")
        #expect(action.lines.first?.text == "run saveDashboard")
    }

    @Test func uiViewParsesMultipleActionsAndMultipleSections() async throws {
        let (_, space) = try await parseModel("""
            ===
            Web
            ===
            + UI

            === UI ===

            Settings View
            /;;;;;;;/
            General:
            * email: String
            - theme: String
            Advanced:
            * apiKey: String
            - debug: Bool
            # Actions
            ## save
            | run saveSettings
            | run notify
            ## reset
            | run clearForm
            #
            """)

        let module = try #require(await moduleNamed("UI", space: space))
        let view = try #require(await module.uiViewObjects.first)

        #expect(await view.sections.count == 2)
        #expect(await view.sections[0].name == "General")
        #expect(await view.sections[0].controls.count == 2)
        #expect(await view.sections[1].name == "Advanced")
        #expect(await view.sections[1].controls.count == 2)
        #expect(await view.actions.count == 2)
        #expect(await view.actions[0].trigger == "save")
        #expect(await view.actions[0].lines.count == 2)
        #expect(await view.actions[1].trigger == "reset")
        #expect(await view.actions[1].lines.count == 1)
    }

    @Test func uiViewParsesAllBindingPrefixes() async throws {
        let (_, space) = try await parseModel("""
            ===
            Web
            ===
            + UI

            === UI ===

            Form
            /;;;;;;;;;/
            * required: String
            - optional: String
            . computed: Int
            + added: Bool
            = readonly: Float
            """)

        let module = try #require(await moduleNamed("UI", space: space))
        let view = try #require(await module.uiViewObjects.first)

        let names = await view.bindings.map(\.name)
        let types = await view.bindings.map(\.typeName)
        let reqs = await view.bindings.map(\.required)
        #expect(names == ["required", "optional", "computed", "added", "readonly"])
        #expect(types == ["String", "String", "Int", "Bool", "Float"])
        #expect(reqs == [.yes, .no, .no, .no, .no])
    }

    @Test func uiViewParsesMultipleSlotsWithDirectives() async throws {
        let (_, space) = try await parseModel("""
            ===
            Web
            ===
            + UI

            === UI ===

            Page
            /;;;;;;;/
            * header: @"HeaderView"
            | sticky true
            * sidebar: @"SidebarView"
            | collapsible true
            | width 250
            * content: @"ContentView"
            """)

        let module = try #require(await moduleNamed("UI", space: space))
        let view = try #require(await module.uiViewObjects.first)

        #expect(await view.slots.count == 3)
        #expect(await view.slots[0].name == "header")
        #expect(await view.slots[0].directives.count == 1)
        #expect(await view.slots[0].directives[0].text == "sticky true")
        #expect(await view.slots[1].name == "sidebar")
        #expect(await view.slots[1].directives.count == 2)
        #expect(await view.slots[2].name == "content")
        #expect(await view.slots[2].directives.isEmpty)
    }

    @Test func uiViewParsesDescriptionLine() async throws {
        let (_, space) = try await parseModel("""
            ===
            Web
            ===
            + UI

            === UI ===

            Profile
            /;;;;;;/
            -- User profile editor
            * name: String
            """)

        let module = try #require(await moduleNamed("UI", space: space))
        let view = try #require(await module.uiViewObjects.first)

        #expect(await view.description == "User profile editor")
        #expect(await view.bindings.count == 1)
    }

    @Test func uiViewParsesRootLevelBindingsAndAttachedSections() async throws {
        let (_, space) = try await parseModel("""
            ===
            Web
            ===
            + UI

            === UI ===

            Search View
            /;;;;;;;;;;/
            * query: String
            = resultCount: Int

            # Analytics
            @ events:: search.submitted
            | search.submitted
            #
            """)

        let module = try #require(await moduleNamed("UI", space: space))
        let view = try #require(await module.uiViewObjects.first)

        #expect(await view.bindings.map(\.name) == ["query", "resultCount"])
        #expect(await view.bindings.map(\.typeName) == ["String", "Int"])
        let analytics = try #require(await view.attachedSections.get("Analytics"))
        #expect(await analytics.bodyLines.first?.text == "search.submitted")
        #expect(await view.annotations["events"] != nil)
    }

    @Test func legacyTildeUnderlineDoesNotCreateNewUIView() async throws {
        let (_, space) = try await parseModel("""
            ===
            Web
            ===
            + UI

            === UI ===

            Legacy View
            ~~~~~~~~~
            """)

        let module = try #require(await moduleNamed("UI", space: space))
        #expect(await module.uiViewObjects.isEmpty)
    }

    @Test func uiViewStopsBeforeNextTopLevelObject() async throws {
        let (ctx, space) = try await parseModel("""
            ===
            Web
            ===
            + UI

            === UI ===

            Editor
            /;;;;;;/
            * content: String

            Product
            ========
            ** id: Id
            """)

        let module = try #require(await moduleNamed("UI", space: space))
        let view = try #require(await module.uiViewObjects.first)
        #expect(await view.bindings.count == 1)

        let product = try #require(await ctx.model.types.get(for: "Product") as? DomainObject)
        #expect(await product.name == "Product")
    }

    @Test func twoUIViewsInSameModuleAreIndependent() async throws {
        let (_, space) = try await parseModel("""
            ===
            Web
            ===
            + UI

            === UI ===

            List View
            /;;;;;;/
            * items: Array

            Detail View
            /;;;;;;/
            * item: Object
            - editable: Bool
            """)

        let module = try #require(await moduleNamed("UI", space: space))
        let views = await module.uiViewObjects
        #expect(views.count == 2)
        #expect(await views[0].bindings.count == 1)
        #expect(await views[1].bindings.count == 2)
    }
}
