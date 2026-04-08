//
//  Sandbox.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike-lib
//

import Foundation

public protocol GenerationSandbox : Sandbox, FileGeneratorProtocol {
    func generateFilesFor(container: String, usingBlueprint blueprint: Blueprint, outputFolderSuffix: String) async throws -> String?

    /// Runs generation for an arbitrary `C4Container` instance (including synthetic slices not registered on `AppModel`).
    func generateFilesFor(resolvedContainer: C4Container, usingBlueprint blueprint: Blueprint, outputFolderSuffix: String) async throws -> String?
}

public protocol Sandbox: Actor {
    var model: AppModel {get}
    var context: GenerationContext {get}
    var config: OutputConfig {get async}
    var templateSoup: TemplateSoup {get}
    
    var onLoadTemplate : LoadTemplateHandler {get async}
    func onLoadTemplate(_ newValue: @escaping LoadTemplateHandler) async
    
    func loadSymbols(_ sym : Set<PreDefinedSymbols>?) async throws
    
    func render(string templateString: String, data: [String: Sendable]) async throws -> String?
}
 
