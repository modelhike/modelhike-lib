//
//  Workspace.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike-lib
//

import Foundation

public actor Workspace {
    public let context: LoadContext

    /// Same instance as ``LoadContext/debugLog`` on ``context``; nonisolated so call sites can log without `await`.
    public nonisolated let debugLog: ContextDebugLog

    public var config: OutputConfig { get async { await self.context.config }}
    
    public func config(_ value: OutputConfig) async {
        await self.context.config(value)
    }
    
    var model: AppModel { context.model }
    public var isModelsLoaded: Bool {
        get async { await model.isModelsLoaded }
    }
    
    public func isModelsLoaded(_ newValue: Bool) async {
        await model.isModelsLoaded(newValue)
    }
    
    public func newGenerationSandbox() async -> GenerationSandbox {
        let loadedVars = await context.variables
        let sandbox = await CodeGenerationSandbox(model: self.model, config: config)
        await sandbox.context.append(variables: loadedVars)
        
        return sandbox
    }
    
    public func newStringSandbox() async -> Sandbox {
        let sandbox = await CodeGenerationSandbox(model: self.model, config: config)
        return sandbox
    }
    
    public func render(string input: String, data: [String: Sendable], modifiers: [Modifier] = []) async throws -> String? {
        let sandbox = await newStringSandbox()

        if modifiers.isNotEmpty {
            await sandbox.context.symbols.addTemplate(modifiers: modifiers)
        }

        let rendering = try await sandbox.render(string: input, data: data)
        return rendering?.trim()
    }

    internal init() {
        let config = PipelineConfig()
        let log = ContextDebugLog(flags: config.flags, recorder: config.debugRecorder)
        self.debugLog = log
        self.context = LoadContext(config: config, debugLog: log)
    }
}

public enum PreDefinedSymbols: String, CaseIterable, Sendable {
    case typescript
    case mongodb_typescript
    case java
    case noMocking

    public static func parseList(_ value: String, pInfo: ParsedInfo) throws -> Set<PreDefinedSymbols> {
        let tokens = value
            .split(separator: ",")
            .map { String($0).trim() }
            .filter { $0.isNotEmpty }
        var symbols: Set<PreDefinedSymbols> = []

        for token in tokens {
            guard let symbol = PreDefinedSymbols(symbolName: token) else {
                let knownSymbols = Self.allCases.map(\.rawValue)
                throw EvaluationError.invalidInput(
                    Suggestions.lookupFailureMessage(
                        "Unknown blueprint symbol '\(token)' in main.ss front matter.",
                        for: token,
                        in: knownSymbols,
                        availableOptionsLabel: "available blueprint symbols"
                    ),
                    pInfo
                )
            }

            symbols.insert(symbol)
        }

        return symbols
    }

    public init?(symbolName: String) {
        switch symbolName.trim().lowercased().replacingOccurrences(of: "-", with: "_") {
        case "typescript":
            self = .typescript
        case "mongodb_typescript":
            self = .mongodb_typescript
        case "java":
            self = .java
        case "nomocking", "no_mocking":
            self = .noMocking
        default:
            return nil
        }
    }
}
