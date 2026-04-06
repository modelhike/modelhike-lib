//
//  DebugUtils.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike
//

import Foundation

func debugValueString(_ value: any Sendable) -> String {
    if let string = value as? String { return string }
    if let int = value as? Int { return String(int) }
    if let bool = value as? Bool { return String(bool) }
    if let double = value as? Double { return String(double) }
    return String(describing: value)
}

public final class ContextDebugLog: @unchecked Sendable {
    public let stack = CallStack()
    public private(set) var flags: ContextDebugFlags
    private var recorder: (any DebugRecorder)?

    private var hasRecorder: Bool {
        recorder != nil
    }

    public init(flags: ContextDebugFlags, recorder: (any DebugRecorder)? = nil) {
        self.flags = flags
        self.recorder = recorder
    }

    public func configure(flags: ContextDebugFlags, recorder: (any DebugRecorder)? = nil) {
        self.flags = flags
        self.recorder = recorder
    }

    /// Best-effort drain for fire-and-forget recorder tasks before reading a session snapshot.
    public func drainRecorder(maxPolls: Int = 16) async {
        guard let recorder else { return }

        var lastCount = await recorder.currentEventCount
        var stableReads = 0

        for _ in 0..<maxPolls {
            await Task.yield()
            let currentCount = await recorder.currentEventCount
            if currentCount == lastCount {
                stableReads += 1
                if stableReads >= 2 {
                    return
                }
            } else {
                stableReads = 0
                lastCount = currentCount
            }
        }
    }

    /// Emit a debug event into the recorder (fire-and-forget; does nothing when no recorder is attached).
    public func recordEvent(_ event: DebugEvent) {
        guard let recorder else { return }
        Task { await recorder.recordEvent(event) }
    }

    /// Emit a non-fatal diagnostic (warning/info/hint) that is surfaced in the debug console
    /// without stopping the pipeline. Warnings are also printed to stdout.
    public func recordDiagnostic(
        _ severity: DiagnosticSeverity,
        code: String? = nil,
        _ message: String,
        source: SourceLocation,
        suggestions: [DiagnosticSuggestion] = []
    ) {
        let shouldPrint = flags.printDiagnosticsToStdout && (severity == .warning || severity == .error)
        guard hasRecorder || shouldPrint else { return }

        if hasRecorder {
            recordEvent(.diagnostic(severity: severity, code: code, message: message,
                                    source: source, suggestions: suggestions))
        }
        if shouldPrint {
            let codeStr = code.map { "[\($0)] " } ?? ""
            let suggStr = suggestions.isEmpty
                ? ""
                : "\n   = \(suggestions.map(\.displayText).joined(separator: "\n   = "))"
            print("\(severity.icon) \(codeStr)\(message)\(suggStr)")
        }
    }

    /// Convenience overload accepting ParsedInfo for location.
    public func recordDiagnostic(
        _ severity: DiagnosticSeverity,
        code: String? = nil,
        _ message: String,
        pInfo: ParsedInfo,
        suggestions: [DiagnosticSuggestion] = []
    ) {
        recordDiagnostic(severity, code: code, message, source: SourceLocation(from: pInfo), suggestions: suggestions)
    }

    /// Convenience overload for lookup-driven diagnostics that need "did you mean?"
    /// and optional "available options" suggestions.
    public func recordLookupDiagnostic(
        _ severity: DiagnosticSeverity,
        code: String? = nil,
        _ message: String,
        lookup query: String,
        in candidates: [String],
        availableOptionsLabel: String? = nil,
        source: SourceLocation
    ) {
        recordDiagnostic(
            severity,
            code: code,
            message,
            source: source,
            suggestions: Suggestions.lookupSuggestions(
                for: query,
                in: candidates,
                availableOptionsLabel: availableOptionsLabel
            )
        )
    }

    /// Convenience overload accepting ParsedInfo for location.
    public func recordLookupDiagnostic(
        _ severity: DiagnosticSeverity,
        code: String? = nil,
        _ message: String,
        lookup query: String,
        in candidates: [String],
        availableOptionsLabel: String? = nil,
        pInfo: ParsedInfo
    ) {
        recordLookupDiagnostic(
            severity,
            code: code,
            message,
            lookup: query,
            in: candidates,
            availableOptionsLabel: availableOptionsLabel,
            source: SourceLocation(from: pInfo)
        )
    }

    /// Records file generation and adds to session.files for traceability.
    public func recordFileGenerated(outputPath: String, templateName: String?, objectName: String?, workingDir: String, source: SourceLocation) async {
        guard let recorder else { return }
        await recorder.recordGeneratedFile(
            outputPath: outputPath,
            templateName: templateName,
            objectName: objectName,
            workingDir: workingDir,
            source: source
        )
    }

    /// Capture current variables as base snapshot for time-travel. Pass variables from context.
    public func captureVariablesForDebug(_ variables: [String: Sendable]) {
        guard let recorder else { return }
        let serialized: [String: String] = variables.mapValues(debugValueString)
        Task { await recorder.captureBaseSnapshot(label: "file-gen", variables: serialized) }
    }

    public func parseLines(startingFrom startKeyword : String?, till endKeyWord: String?, line: String?, lineNo : Int ) {
        if flags.lineByLineParsing || flags.blockByBlockParsing {
            if let startKeyword = startKeyword, let endKeyWord = endKeyWord, let line = line {
                print("[\(lineNo)] PARSE LINES START \"\(startKeyword)\" till>> \(endKeyWord)")
                print(line)
            } else {
                print("PARSE LINES till END-OF-FILE")
            }
        }
    }
    
    public func parseLines(ended endKeyWord: String, pInfo: ParsedInfo) {
        if recorder != nil {
            recordEvent(.parseBlockEnded(keyword: endKeyWord, source: SourceLocation(from: pInfo)))
        }
        if flags.lineByLineParsing || flags.blockByBlockParsing {
            print("[\(pInfo.lineNo)] PARSE LINES ENDED>> \(endKeyWord)")
        }
    }

    public func stmtDetected(keyWord: String, pInfo: ParsedInfo) {
        if recorder != nil {
            recordEvent(.statementDetected(keyword: keyWord, source: SourceLocation(from: pInfo)))
        }
        if flags.lineByLineParsing {
            print("[\(pInfo.lineNo)] STMT DETECT>> \(keyWord)")
        }
    }
    
    public func multiBlockDetected(keyWord: String, pInfo: ParsedInfo) {
        guard hasRecorder || flags.lineByLineParsing || flags.blockByBlockParsing else { return }
        if hasRecorder {
            recordEvent(.multiBlockDetected(keyword: keyWord, source: SourceLocation(from: pInfo)))
        }
        if flags.lineByLineParsing || flags.blockByBlockParsing {
            print("[\(pInfo.lineNo)] MULTIBLOCK DETECT>> \(keyWord)")
        }
    }
    
    public func multiBlockDetectFailed(pInfo: ParsedInfo) {
        guard hasRecorder || flags.lineByLineParsing || flags.blockByBlockParsing else { return }
        if hasRecorder {
            recordEvent(.multiBlockFailed(source: SourceLocation(from: pInfo)))
        }
        if flags.lineByLineParsing || flags.blockByBlockParsing {
            print("[\(pInfo.lineNo)] FAILED MULTIBLOCK PARSE>> \(pInfo.line) ")
        }
    }
    
    public func comment(line: String, lineNo: Int) {
        print("[\(lineNo)] \(line)")
    }
    
    public func content(_ line: String, pInfo: ParsedInfo) {
        guard recorder != nil || flags.lineByLineParsing else { return }
        if recorder != nil {
            recordEvent(.textContent(text: line, source: SourceLocation(from: pInfo)))
        }
        if flags.lineByLineParsing {
            print("[\(pInfo.lineNo)] --txt-- \(line)")
        }
    }

    public func inlineExpression(_ line: String, pInfo: ParsedInfo) {
        guard recorder != nil || flags.lineByLineParsing else { return }
        if flags.lineByLineParsing {
            print("[\(pInfo.lineNo)] -------{{ \(line) }}")
        }
    }

    public func inlineFunctionCall(_ line: String, pInfo: ParsedInfo) {
        guard hasRecorder || flags.lineByLineParsing else { return }
        if hasRecorder {
            recordEvent(.functionCallEvaluated(expression: line, source: SourceLocation(from: pInfo)))
        }
        if flags.lineByLineParsing {
            print("[\(pInfo.lineNo)] -------={{ \(line) }}=")
        }
    }
    
    public func line(_ line: String, pInfo: ParsedInfo) {
        if flags.lineByLineParsing {
            print("[\(pInfo.lineNo)]-- \(line)")
        }
    }
    
    public func skipEmptyLine(lineNo: Int) {
        if flags.onSkipLines {
            print("[\(lineNo)] skipping empty line...")
        }
    }
    
    public func skipLine(lineNo: Int) {
        if flags.onSkipLines {
            print("[\(lineNo)] skipping line...")
        }
    }
    
    public func skipLine(by times : Int, lineNo: Int) {
        if flags.onSkipLines {
            for i in 0..<times {
                print("[\(lineNo + i)] skipping line...")
            }
        }
    }
    
    public func incrementLineNo(lineNo: Int) {
        if flags.onIncrementLines {
            print("[\(lineNo)] next line...")
        }
    }
    
    public func printParsedTree(for containers: SoupyScriptStmtContainerList) async {
        guard hasRecorder || flags.printParsedTree else { return }
        let desc = await containers.debugDescription
        if hasRecorder {
            recordEvent(.parsedTreeDumped(treeName: "containers", treeDescription: desc))
        }
        if flags.printParsedTree {
            print(desc)
        }
    }
    
    public func ifConditionSatisfied(condition: String, pInfo: ParsedInfo) {
        guard hasRecorder || flags.lineByLineParsing || flags.blockByBlockParsing || flags.controlFlow else { return }
        if hasRecorder {
            recordEvent(.controlFlow(branch: .ifTrue, condition: condition, satisfied: true, source: SourceLocation(from: pInfo)))
        }
        if flags.lineByLineParsing || flags.blockByBlockParsing || flags.controlFlow {
            print("[\(pInfo.lineNo)] IF Condition Satisfied>> \(pInfo.line)")
        }
    }
    
    public func elseIfConditionSatisfied(condition: String, pInfo: ParsedInfo) {
        guard hasRecorder || flags.lineByLineParsing || flags.blockByBlockParsing || flags.controlFlow else { return }
        if hasRecorder {
            recordEvent(.controlFlow(branch: .elseIfTrue, condition: condition, satisfied: true, source: SourceLocation(from: pInfo)))
        }
        if flags.lineByLineParsing || flags.blockByBlockParsing || flags.controlFlow {
            print("[\(pInfo.lineNo)] ELSE IF Condition Satisfied>> \(pInfo.line)")
        }
    }
    
    public func elseBlockExecuting(_ pInfo: ParsedInfo) {
        guard hasRecorder || flags.lineByLineParsing || flags.blockByBlockParsing || flags.controlFlow else { return }
        if hasRecorder {
            recordEvent(.controlFlow(branch: .elseBlock, condition: "", satisfied: true, source: SourceLocation(from: pInfo)))
        }
        if flags.lineByLineParsing || flags.blockByBlockParsing || flags.controlFlow {
            print("[\(pInfo.lineNo)] ELSE Block executing>> \(pInfo.line)")
        }
    }
    
    public func templateParsingStarting(name: String = "") {
        guard hasRecorder || flags.lineByLineParsing || flags.blockByBlockParsing else { return }
        if hasRecorder, name.isNotEmpty { recordEvent(.templateParseStarted(name: name)) }
        if flags.lineByLineParsing || flags.blockByBlockParsing {
            print("TEMPLATE PARSING START -------------\n\n")
        }
    }
    
    public func templateExecutionStarting(name: String = "", pInfo: ParsedInfo? = nil) {
        guard hasRecorder || flags.lineByLineParsing || flags.blockByBlockParsing else { return }
        if hasRecorder, name.isNotEmpty, let pInfo {
            recordEvent(.templateStarted(name: name, source: SourceLocation(from: pInfo)))
        }
        if flags.lineByLineParsing || flags.blockByBlockParsing {
            print("\n\n\n\nTEMPLATE EXECUTION START -------------\n")
        }
    }
    
    public func scriptFileParsingStarting(name: String = "") {
        guard hasRecorder || flags.lineByLineParsing || flags.blockByBlockParsing else { return }
        if hasRecorder, name.isNotEmpty { recordEvent(.scriptParseStarted(name: name)) }
        if flags.lineByLineParsing || flags.blockByBlockParsing {
            print("SCRIPT PARSING START -------------\n\n")
        }
    }
    
    public func scriptFileExecutionStarting(name: String = "", pInfo: ParsedInfo? = nil) {
        guard hasRecorder || flags.lineByLineParsing || flags.blockByBlockParsing else { return }
        if hasRecorder, name.isNotEmpty, let pInfo {
            recordEvent(.scriptStarted(name: name, source: SourceLocation(from: pInfo)))
        }
        if flags.lineByLineParsing || flags.blockByBlockParsing {
            print("\n\n\n\nSCRIPT TEMPLATE EXECUTION START -------------\n")
        }
    }
    
    public func workingDirectoryChanged(_ path: String, pInfo: ParsedInfo? = nil) {
        guard hasRecorder || flags.changesInWorkingDirectory else { return }
        let src = pInfo.map { SourceLocation(from: $0) }
            ?? SourceLocation(fileIdentifier: "", lineNo: 0, lineContent: "", level: 0)
        if hasRecorder {
            recordEvent(.workingDirChanged(from: "", to: path, source: src))
        }
        if flags.changesInWorkingDirectory {
            print("Working Dir: \(path)")
        }
    }
    
    public func stopRenderingCurrentFile(_ filepath: String, pInfo: ParsedInfo) {
        guard hasRecorder || flags.renderingStoppedInFiles else { return }
        if hasRecorder {
            recordEvent(.fileRenderStopped(path: filepath, source: SourceLocation(from: pInfo)))
        }
        if flags.renderingStoppedInFiles {
            print("⚠️ Stop Rendering \(filepath) ...")
        }
    }
    
    public func throwErrorFromCurrentFile(_ filepath: String, err: String, pInfo: ParsedInfo) {
        guard hasRecorder || flags.errorThrownInFiles else { return }
        if hasRecorder {
            recordEvent(.fatalError(message: err, source: SourceLocation(from: pInfo)))
        }
        if flags.errorThrownInFiles {
            print("🚨 Error '\(err)' Thrown From \(filepath) ...")
        }
    }
    
    public func excludingFile(_ filepath: String, pInfo: ParsedInfo? = nil) {
        guard hasRecorder || flags.excludedFiles else { return }
        let src = pInfo.map { SourceLocation(from: $0) }
            ?? SourceLocation(fileIdentifier: "", lineNo: 0, lineContent: "", level: 0)
        if hasRecorder {
            recordEvent(.fileExcluded(path: filepath, reason: "include-if", source: src))
        }
        if flags.excludedFiles {
            print("⚠️ Excluding \(filepath) ...")
        }
    }
    
    public func generatingFile(_ filepath: String) {
        guard hasRecorder || flags.fileGeneration else { return }
        if hasRecorder {
            recordEvent(.fileGenerated(outputPath: filepath, templateName: nil, objectName: nil, source: SourceLocation(fileIdentifier: "", lineNo: 0, lineContent: "", level: 0)))
        }
        if flags.fileGeneration {
            print("Generating \(filepath) ...")
        }
    }
    
    public func copyingFile(_ filepath: String) {
        guard hasRecorder || flags.fileGeneration else { return }
        if hasRecorder {
            recordEvent(.fileCopied(sourcePath: filepath, outputPath: filepath, source: SourceLocation(fileIdentifier: "", lineNo: 0, lineContent: "", level: 0)))
        }
        if flags.fileGeneration {
            print("Copying \(filepath) ...")
        }
    }
    
    public func copyingFile(_ filepath: String, to newFilePath: String) {
        guard hasRecorder || flags.fileGeneration else { return }
        if hasRecorder {
            recordEvent(.fileCopied(sourcePath: filepath, outputPath: newFilePath, source: SourceLocation(fileIdentifier: "", lineNo: 0, lineContent: "", level: 0)))
        }
        if flags.fileGeneration {
            print("Copying \(filepath) to \(newFilePath)...")
        }
    }
    
    public func copyingFileInFolder(_ filepath: String, folder: LocalFolder) {
        guard hasRecorder || flags.fileGeneration else { return }
        if hasRecorder {
            recordEvent(.fileCopied(sourcePath: filepath, outputPath: folder.pathString + "/" + filepath, source: SourceLocation(fileIdentifier: "", lineNo: 0, lineContent: "", level: 0)))
        }
        if flags.fileGeneration {
            print("[ \(folder.pathString) ] Copying \(filepath) ...")
        }
    }
    
    public func copyingFileInFolder(_ filepath: String, to newFilePath: String, folder: LocalFolder) {
        guard hasRecorder || flags.fileGeneration else { return }
        if hasRecorder {
            recordEvent(.fileCopied(sourcePath: filepath, outputPath: newFilePath, source: SourceLocation(fileIdentifier: "", lineNo: 0, lineContent: "", level: 0)))
        }
        if flags.fileGeneration {
            print("[ \(folder.pathString) ] Copying \(filepath) to \(newFilePath)...")
        }
    }
    
    public func copyingFolder(_ path: String) {
        guard hasRecorder || flags.fileGeneration else { return }
        if hasRecorder {
            recordEvent(.folderCopied(path: path, outputPath: path, source: SourceLocation(fileIdentifier: "", lineNo: 0, lineContent: "", level: 0)))
        }
        if flags.fileGeneration {
            print("Copying folder \(path) ...")
        }
    }
    
    public func copyingFolder(_ path: String, to newPath: String) {
        guard hasRecorder || flags.fileGeneration else { return }
        if hasRecorder {
            recordEvent(.folderCopied(path: path, outputPath: newPath, source: SourceLocation(fileIdentifier: "", lineNo: 0, lineContent: "", level: 0)))
        }
        if flags.fileGeneration {
            print("Copying folder \(path) to \(newPath)...")
        }
    }
    
    public func renderingFolder(_ path: String, to newPath: String) {
        guard hasRecorder || flags.fileGeneration else { return }
        if hasRecorder {
            recordEvent(.folderRendered(path: path, outputPath: newPath, source: SourceLocation(fileIdentifier: "", lineNo: 0, lineContent: "", level: 0)))
        }
        if flags.fileGeneration {
            print("Rendering folder \(path) to \(newPath)...")
        }
    }
    
    public func generatingFile(_ filepath: String, with template: String) {
        guard hasRecorder || flags.fileGeneration else { return }
        if hasRecorder {
            recordEvent(.fileGenerated(outputPath: filepath, templateName: template, objectName: nil, source: SourceLocation(fileIdentifier: "", lineNo: 0, lineContent: "", level: 0)))
        }
        if flags.fileGeneration {
            print("Generating \(filepath) [template \(template)] ...")
        }
    }
    
    public func fileNotGenerated(_ filepath: String, with template: String, pInfo: ParsedInfo? = nil) {
        guard hasRecorder || flags.fileGeneration else { return }
        let src = pInfo.map { SourceLocation(from: $0) }
            ?? SourceLocation(fileIdentifier: "", lineNo: 0, lineContent: "", level: 0)
        if hasRecorder {
            recordEvent(.fileSkipped(path: filepath, templateName: template, reason: "not generated", source: src))
        }
        if flags.fileGeneration {
            print("⚠️ File \(filepath) [template \(template)] was not generated.")
        }
    }
    
    public func generatingFileInFolder(_ filepath: String, with template: String, folder: LocalFolder, pInfo: ParsedInfo) async {
        let outputPath = folder.pathString + "/" + filepath
        await recordFileGenerated(
            outputPath: outputPath,
            templateName: template,
            objectName: nil,
            workingDir: folder.pathString,
            source: SourceLocation(from: pInfo)
        )
        if flags.fileGeneration {
            print("[ \(folder.pathString) ] Generating \(filepath) [template \(template)] ...")
        }
    }
    
    public func fileNotGeneratedInFolder(_ filepath: String, with template: String, folder: LocalFolder) {
        guard hasRecorder || flags.fileGeneration else { return }
        if hasRecorder {
            recordEvent(.fileSkipped(path: filepath, templateName: template, reason: "not generated", source: SourceLocation(fileIdentifier: "", lineNo: 0, lineContent: "", level: 0)))
        }
        if flags.fileGeneration {
            print("⚠️ [ \(folder.pathString) ] File \(filepath) [template \(template)] was not generated.")
        }
    }
    
    public func fileNotGenerated(_ filepath: String) {
        guard hasRecorder || flags.fileGeneration else { return }
        if hasRecorder {
            recordEvent(.fileSkipped(path: filepath, templateName: nil, reason: "not generated", source: SourceLocation(fileIdentifier: "", lineNo: 0, lineContent: "", level: 0)))
        }
        if flags.fileGeneration {
            print("⚠️ File \(filepath) was not generated.")
        }
    }
    
    public func pipelinePhaseCannotRun(_ phase: any PipelinePhase, msg: String) {
        recordEvent(.phaseSkipped(name: runtimeTypeName(of: phase), reason: msg))
        print("⦻ Phase \(phase) cannot run.")
        print("⦻ \(msg)")
    }
    
    public func pipelinePassCannotRun(_ pass: any PipelinePass, msg: String? = nil) {
        recordEvent(.passSkipped(name: runtimeTypeName(of: pass), reason: msg))
        print("⦻ Pass \(pass) cannot run.")
        if let msg {
            print("⦻ \(msg)")
        }
    }
}

public struct ContextDebugFlags: Sendable {
    public var printParsedTree = false
    public var printDiagnosticsToStdout = true
    
    public var lineByLineParsing = false
    public var blockByBlockParsing = false
    public var controlFlow = false
    
    public var excludedFiles = false
    public var renderingStoppedInFiles = false
    public var errorThrownInFiles = false
    
    public var changesInWorkingDirectory = false
    public var fileGeneration = false
    
    public var onSkipLines = false
    public var onIncrementLines = false
    public var onCommentedLines = false
    
    public init() {}
}
