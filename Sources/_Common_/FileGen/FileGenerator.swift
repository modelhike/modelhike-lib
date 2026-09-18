//
//  FileGenerator.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike-lib
//

import Foundation

public protocol FileGeneratorProtocol: Actor {
    var base_generation_dir: OutputFolder {get}
    func setRelativePath(_ path: String) async throws
    
    func generateFile(_ filename: String, template: String, with pInfo: ParsedInfo) async throws -> TemplateRenderedFile?
    func generateFileWithData(_ filename: String, template: String, data: [String: Sendable], with pInfo: ParsedInfo) async throws -> TemplateRenderedFile?

    /// Compiles and executes a template purely for its side effects (e.g. `func`/`end-func`
    /// definitions, which register into the shared `templateFunctions` map at parse time) —
    /// no output file is written and the rendered content is discarded. Use this for a
    /// template whose only purpose is to make its `func` definitions available to `call`,
    /// as opposed to `generateFile`, which persists real output.
    func importFile(_ templateName: String, with pInfo: ParsedInfo) async throws
    func copyFile(_ filename: String, with pInfo: ParsedInfo) async throws -> StaticFile
    func copyFile(_ filename: String, to newFilename: String, with pInfo: ParsedInfo) async throws -> StaticFile
    
    func copyFolder(_ path: String, with pInfo: ParsedInfo) async throws -> StaticFolder
    func copyFolder(_ path: String, to newPath: String, with pInfo: ParsedInfo) async throws -> StaticFolder
    func renderFolder(_ path: String, to newPath: String, with pInfo: ParsedInfo) async throws -> RenderedFolder

    func fillPlaceholdersAndCopyFile(_ filename: String, with pInfo: ParsedInfo) async throws -> PlaceHolderFile?
    func fillPlaceholdersAndCopyFile(_ filename: String, to newFilename: String, with pInfo: ParsedInfo) async throws -> PlaceHolderFile?
}

