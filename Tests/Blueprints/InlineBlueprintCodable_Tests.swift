import Foundation
import Testing
@testable import ModelHike

@Suite("InlineBlueprint Codable") struct InlineBlueprintCodable_Tests {
    @Test func snapshotRoundTrip_preservesFiles() async throws {
        let blueprint = InlineBlueprint(name: "json-blueprint") {
            InlineScript("main", contents: ":render file \"Entity.teso\"")
            InlineTemplate("Entity", contents: "class {{ entity.name }} {}")
            InlineStaticFile("package.json", in: SpecialFolderNames.root, contents: "{\"name\":\"demo\"}")
            InlineModifier("javaType", contents: "String")
            InlineFolder("helpers") {
                InlineTemplate("Util", contents: "// util")
            }
        }

        let snapshot = await blueprint.toSnapshot()
        let json = try await blueprint.toJSON()
        let decoded = try InlineBlueprintSnapshot.fromJSON(json)
        let rebuilt = decoded.toInlineBlueprint()
        let rebuiltSnapshot = await rebuilt.toSnapshot()

        #expect(decoded == snapshot)
        #expect(rebuiltSnapshot == snapshot)
    }

    @Test func ergonomicSnapshotInit_addsExpectedExtensions() async throws {
        let snapshot = InlineBlueprintSnapshot(
            name: "ergonomic",
            scripts: ["main": ":render file \"Entity.teso\""],
            templates: ["Entity": "class Test {}"],
            folders: [SpecialFolderNames.root: ["Readme": "# Hello"], "helpers": ["Util": "// util"]],
            modifiers: ["javaType": "String"]
        )

        #expect(snapshot.files[""]?["main.ss"] == ":render file \"Entity.teso\"")
        #expect(snapshot.files[""]?["Entity.teso"] == "class Test {}")
        #expect(snapshot.files[SpecialFolderNames.root]?["Readme.teso"] == "# Hello")
        #expect(snapshot.files["helpers"]?["Util.teso"] == "// util")
        #expect(snapshot.files[SpecialFolderNames.modifiers]?["javaType.teso"] == "String")

        let rebuilt = snapshot.toInlineBlueprint()
        let rebuiltSnapshot = await rebuilt.toSnapshot()
        #expect(rebuiltSnapshot == snapshot)
    }
}

@Suite("InlineModel Codable") struct InlineModelCodable_Tests {
    @Test func inlineModelSnapshotRoundTrip_preservesIdentifiersAndContent() throws {
        let model = InlineModel(identifier: "stdin.modelhike") {
            """
            ===
            APIs
            ===
            + Billing
            """
        }
        let commonTypes = InlineCommonTypes(identifier: "common.modelhike") {
            """
            Audit
            =====
            - createdAt: Date
            """
        }
        let config = InlineConfig(identifier: "main.tconfig") {
            "API_StartingPort = 3001"
        }

        let snapshot = model.toSnapshot(commonTypes: commonTypes, config: config)
        let json = try snapshot.toJSON()
        let decoded = try InlineModelSnapshot.fromJSON(json)

        #expect(decoded == snapshot)
        #expect(decoded.model.identifier == "stdin.modelhike")
        #expect(decoded.model.string.contains("APIs"))
        #expect(decoded.commonTypes?.identifier == "common.modelhike")
        #expect(decoded.commonTypes?.string.contains("createdAt") == true)
        #expect(decoded.config?.identifier == "main.tconfig")
        #expect(decoded.config?.string == "API_StartingPort = 3001")
    }
}
