//
//  DebugEvent.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike-lib
//

import Foundation

public enum DebugEvent: Codable, Sendable {
    // Pipeline lifecycle
    case phaseStarted(name: String, timestamp: Date)
    case phaseCompleted(name: String, duration: Double)
    case phaseFailed(name: String, error: String)
    case phaseSkipped(name: String, reason: String)
    case passSkipped(name: String, reason: String?)

    // Model loading
    case modelLoaded(containerCount: Int, typeCount: Int, commonTypeCount: Int)

    // File generation
    case fileGenerated(
        outputPath: String, templateName: String?, objectName: String?, source: SourceLocation)
    case fileCopied(sourcePath: String, outputPath: String, source: SourceLocation)
    case fileExcluded(path: String, reason: String, source: SourceLocation)
    case fileRenderStopped(path: String, source: SourceLocation)
    case fileSkipped(path: String, templateName: String?, reason: String, source: SourceLocation)
    case folderCopied(path: String, outputPath: String, source: SourceLocation)
    case folderRendered(path: String, outputPath: String, source: SourceLocation)

    // Working directory
    case workingDirChanged(from: String, to: String, source: SourceLocation)

    // Control flow
    case controlFlow(branch: BranchKind, condition: String, satisfied: Bool, source: SourceLocation)

    // Script/template lifecycle
    case scriptParseStarted(name: String)
    case scriptStarted(name: String, source: SourceLocation)
    case scriptCompleted(name: String)
    case templateParseStarted(name: String)
    case templateStarted(name: String, source: SourceLocation)
    case templateCompleted(name: String)

    // In-template debugging
    case consoleLog(value: String, source: SourceLocation)
    case announce(value: String)
    case fatalError(message: String, source: SourceLocation)

    // Expression and function evaluation
    case expressionEvaluated(expression: String, result: String, source: SourceLocation)
    case functionCallEvaluated(expression: String, source: SourceLocation)

    // Variable mutations
    case variableSet(name: String, oldValue: String?, newValue: String, source: SourceLocation)

    // Parsing detail (fine-grained — filterable in UI)
    case parseBlockStarted(keyword: String, source: SourceLocation)
    case parseBlockEnded(keyword: String, source: SourceLocation)
    case statementDetected(keyword: String, source: SourceLocation)
    case multiBlockDetected(keyword: String, source: SourceLocation)
    case multiBlockFailed(source: SourceLocation)
    case textContent(text: String, source: SourceLocation)
    case parsedTreeDumped(treeName: String, treeDescription: String)

    // Errors
    case error(
        category: String, code: DiagnosticErrorCode?, message: String, source: SourceLocation,
        callStack: [SourceLocation])

    // Non-fatal diagnostics (warnings, hints, info)
    case diagnostic(
        severity: DiagnosticSeverity, code: DiagnosticErrorCode?, message: String, source: SourceLocation,
        suggestions: [DiagnosticSuggestion])
}

/// Severity level for non-fatal diagnostics emitted during pipeline execution.
public enum DiagnosticSeverity: String, Codable, Sendable, CaseIterable {
    case error
    case warning
    case info
    case hint

    public var icon: String {
        switch self {
        case .error: return "❌"
        case .warning: return "⚠️"
        case .info: return "ℹ️"
        case .hint: return "💡"
        }
    }
}

/// Semantic structure for a user-facing diagnostic suggestion.
public enum DiagnosticSuggestionKind: String, Codable, Sendable, CaseIterable {
    case didYouMean
    case availableOptions
    case note
}

/// A structured suggestion attached to a diagnostic.
public struct DiagnosticSuggestion: Codable, Sendable, Equatable {
    public let kind: DiagnosticSuggestionKind
    public let message: String
    public let replacement: String?
    public let options: [String]

    public init(
        kind: DiagnosticSuggestionKind,
        message: String,
        replacement: String? = nil,
        options: [String] = []
    ) {
        self.kind = kind
        self.message = message
        self.replacement = replacement
        self.options = options
    }

    public var displayText: String { message }
}
