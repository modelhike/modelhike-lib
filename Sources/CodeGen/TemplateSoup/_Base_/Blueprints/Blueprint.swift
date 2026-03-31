//
//  Blueprint.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike
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
    /// Registers modifier libraries on `sandbox` from this blueprint's `main.ss` front matter.
    /// Reads the `symbols-to-load:` key (comma-separated); an empty or missing value loads the sandbox default set.
    func loadSymbols(to sandbox: any Sandbox) async throws {
        let pInfo = await ParsedInfo.dummyForMainFile(with: sandbox.context)
        let mainScript = try await loadScriptFile(fileName: TemplateConstants.MainScriptFile, with: pInfo)
        // Same delimiter-based front matter as other `.ss` files; keys become the `values` map.
        let frontMatter = FrontMatter.parse(contents: mainScript.toString()).values
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
