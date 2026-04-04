import Foundation
import Testing
@testable import ModelHike

@Suite("Render cache") struct RenderCache_Tests {
    @Test func compiledTemplateCache_reusesParsedTemplate() async throws {
        let workspace = Workspace()
        let sandbox = await CodeGenerationSandbox(model: workspace.context.model, config: await workspace.config)
        let pInfo = await ParsedInfo.dummyForMainFile(with: sandbox.context)

        let first = try await sandbox.templateSoup.renderTemplate(
            string: "{{ value }}",
            identifier: "compiled-cache",
            data: ["value": "one"],
            with: pInfo,
            parseFrontMatter: false
        )
        let second = try await sandbox.templateSoup.renderTemplate(
            string: "{{ value }}",
            identifier: "compiled-cache",
            data: ["value": "two"],
            with: pInfo,
            parseFrontMatter: false
        )

        #expect(first?.trim() == "one")
        #expect(second?.trim() == "two")
        #expect(await sandbox.templateSoup.compiledTemplateCacheCount() == 1)
    }

    @Test func blueprintModifier_reusesCompiledModifierTemplate() async throws {
        let workspace = Workspace()
        let sandbox = await CodeGenerationSandbox(model: workspace.context.model, config: await workspace.config)
        let blueprint = InlineBlueprint(name: "test") {
            InlineModifier("shout", contents: "{{ value | uppercase }}")
        }
        let modifier = try #require(try await blueprint.modifiers(from: sandbox).first as? BlueprintModifierWithoutParams)
        let pInfo = await ParsedInfo.dummyForMainFile(with: sandbox.context)

        let first = try await modifier.applyTo(value: "hello", with: pInfo) as? String
        let second = try await modifier.applyTo(value: "swift", with: pInfo) as? String

        #expect(first?.trim() == "HELLO")
        #expect(second?.trim() == "SWIFT")
        #expect(await sandbox.templateSoup.compiledTemplateCacheCount() == 1)
    }

    @Test func localBlueprint_reusesCachedFilesetForRepeatedFolderRender() async throws {
        let workspace = Workspace()
        let sandbox = await CodeGenerationSandbox(model: workspace.context.model, config: await workspace.config)
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let blueprintRoot = tempRoot.appendingPathComponent("blueprint")
        let entityFiles = blueprintRoot.appendingPathComponent("entity-files")
        let outputRoot = tempRoot.appendingPathComponent("output")
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        try FileManager.default.createDirectory(at: entityFiles, withIntermediateDirectories: true)
        try "Hello".write(to: entityFiles.appendingPathComponent("Hello.teso"), atomically: true, encoding: .utf8)

        let sandboxContext = await sandbox.context
        let blueprint = LocalFileBlueprint(path: LocalPath(blueprintRoot.path), with: sandboxContext)
        let outputFolder = OutputFolder(LocalPath(outputRoot.path))
        let pInfo = await ParsedInfo.dummyForMainFile(with: sandboxContext)

        try await blueprint.renderFiles(foldername: "entity-files", to: outputFolder, using: sandbox.templateSoup, with: pInfo)
        #expect(await blueprint.cachedFilesetCount() == 1)

        try await blueprint.renderFiles(foldername: "entity-files", to: outputFolder, using: sandbox.templateSoup, with: pInfo)
        #expect(await blueprint.cachedFilesetCount() == 1)
    }

    @Test func localBlueprint_cachedFileset_stillHonorsIncludeIfExclusion() async throws {
        let workspace = Workspace()
        let sandbox = await CodeGenerationSandbox(model: workspace.context.model, config: await workspace.config)
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let blueprintRoot = tempRoot.appendingPathComponent("blueprint")
        let entityFiles = blueprintRoot.appendingPathComponent("entity-files")
        let outputRoot = tempRoot.appendingPathComponent("output")
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        try FileManager.default.createDirectory(at: entityFiles, withIntermediateDirectories: true)
        try """
        ---
        /include-if: 1 == 2
        ---
        Hello
        """.write(to: entityFiles.appendingPathComponent("Hello.teso"), atomically: true, encoding: .utf8)

        let sandboxContext = await sandbox.context
        let blueprint = LocalFileBlueprint(path: LocalPath(blueprintRoot.path), with: sandboxContext)
        let outputFolder = OutputFolder(LocalPath(outputRoot.path))
        let pInfo = await ParsedInfo.dummyForMainFile(with: sandboxContext)

        try await blueprint.renderFiles(foldername: "entity-files", to: outputFolder, using: sandbox.templateSoup, with: pInfo)

        #expect(await outputFolder.items.isEmpty)
    }
}
