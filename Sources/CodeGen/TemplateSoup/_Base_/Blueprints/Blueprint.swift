//
//  Blueprint.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike-lib
//

import Foundation

public protocol Blueprint : InputFileRepository {
    var blueprintName: String {get}
    func exists() async throws -> Bool
    func loadTemplate(fileName: String, with pInfo: ParsedInfo) async throws -> Template
    func loadScriptFile(fileName: String, with pInfo: ParsedInfo) async throws -> Script
    func loadSymbols(to sandbox: any Sandbox) async throws
}

public protocol InputFileRepository: Actor {
    func copyFiles(foldername: String, to folder: OutputFolder, with pInfo: ParsedInfo) async throws
    func renderFiles(foldername: String, to folder: OutputFolder, using templateSoup: TemplateSoup, with pInfo: ParsedInfo) async throws

    func readTextContents(filename: String, with pInfo: ParsedInfo) async throws -> String
    func hasFolder(_ foldername: String) async -> Bool
    func hasFile(_ filename: String) -> Bool

    /// Returns the filenames (including extension) of all files directly inside `foldername`.
    /// Implementations that do not support filesystem enumeration (e.g. resource-bundle loaders)
    /// return an empty array via the default below.
    func listFiles(inFolder foldername: String) async -> [String]
}

public typealias RenderClosure = (@Sendable (String, ParsedInfo) async throws -> Void)

public extension Blueprint {
    /// Reads the `symbols-to-load` key from `main.ss` front matter and registers the
    /// declared language symbol libraries with the sandbox before script execution begins.
    ///
    /// Front matter example:
    /// ```
    /// -----
    /// symbols-to-load : typescript, mongodb_typescript
    /// -----
    /// ```
    ///
    /// Supported values: `typescript`, `mongodb_typescript`, `java`, `noMocking`.
    /// An empty or absent key is valid — no language-specific symbols are loaded.
    /// An unrecognised token throws `EvaluationError.invalidInput` with a "did you mean?" hint.
    func loadSymbols(to sandbox: any Sandbox) async throws {
        let pInfo = await ParsedInfo.dummyForMainFile(with: sandbox.context)
        // Load main.ss to access its front matter without executing the script body.
        let mainScript = try await loadScriptFile(fileName: TemplateConstants.MainScriptFile, with: pInfo)
        // simpleParse: synchronous, context-free, no validation — safe before the sandbox is configured.
        let frontMatter = FrontMatter.simpleParse(contents: mainScript.toString()).values
        // An absent key produces an empty set, which is a valid no-op for blueprints that rely solely on _modifiers_/.
        let symbols = try PreDefinedSymbols.parseList(frontMatter["symbols-to-load"] ?? "", pInfo: pInfo)
        try await sandbox.loadSymbols(symbols)
    }

    /// Returns all modifiers declared as `.teso` files inside this blueprint's `_modifiers_/` folder.
    func modifiers(templateSoup: TemplateSoup, with pInfo: ParsedInfo) async throws -> [Modifier] {
        try await BlueprintModifierLoader.loadModifiers(from: self, templateSoup: templateSoup, with: pInfo)
    }

    func modifiers(from sandbox: any Sandbox) async throws -> [Modifier] {
        let pInfo = await ParsedInfo.dummyForMainFile(with: sandbox.context)
        return try await modifiers(templateSoup: sandbox.templateSoup, with: pInfo)
    }
}
