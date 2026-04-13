//
//  DebugRecorder.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike-lib
//

import Foundation

public protocol DebugRecorder: Actor, Sendable {
    func record(_ envelope: DebugEventEnvelope) async
    /// Record a single event (convenience; builds envelope with sequenceNo, timestamp, containerName).
    func recordEvent(_ event: DebugEvent) async
    func recordGeneratedFile(
        outputPath: String, templateName: String?, objectName: String?, workingDir: String,
        source: SourceLocation) async
    func registerSourceFile(_ file: SourceFile) async
    func setContainerName(_ name: String?) async
    func captureModel(_ model: AppModel) async
    func captureBaseSnapshot(label: String, variables: [String: String]) async
    func captureDelta(eventIndex: Int, variable: String, oldValue: String?, newValue: String) async
    var currentEventCount: Int { get async }
    func captureError(
        category: String, code: DiagnosticErrorCode?, message: String, source: SourceLocation,
        callStack: [SourceLocation], memoryDump: MemoryDump?) async
    func addGeneratedFile(
        outputPath: String, templateName: String?, objectName: String?, workingDir: String) async
    /// Records phase lifecycle into the phase summary and event timeline.
    func recordPhaseStarted(name: String) async
    /// Records phase completion/failure into the phase summary and event timeline.
    func recordPhaseCompleted(name: String, success: Bool, errorMessage: String?) async
    func session(config: OutputConfig) async -> DebugSession
}

extension DebugRecorder {
    /// Captures an error with source, call stack, and memory for both session and timeline views.
    public func recordErrorWithStackAndMemory(
        _ error: ErrorWithMessageAndParsedInfo, category: String
    ) async {
        let ctx = error.pInfo.ctx
        let stackItems = await ctx.debugLog.stack.snapshot()
        let callStack = stackItems.map { item -> SourceLocation in
            if let pInfo = item.callStackItem.pInfo {
                return SourceLocation(
                    fileIdentifier: pInfo.identifier,
                    lineNo: pInfo.lineNo,
                    lineContent: pInfo.line,
                    level: pInfo.level
                )
            }
            return SourceLocation(
                fileIdentifier: "",
                lineNo: 0,
                lineContent: item.callStackItem.renderForDisplay(),
                level: 0
            )
        }
        let source = SourceLocation(
            fileIdentifier: error.pInfo.identifier,
            lineNo: error.pInfo.lineNo,
            lineContent: error.pInfo.line,
            level: error.pInfo.level
        )
        let memoryDump = await ctx.variablesForDebug()

        await captureError(
            category: category,
            code: error.diagnosticErrorCode,
            message: error.info,
            source: source,
            callStack: callStack,
            memoryDump: MemoryDump(variables: memoryDump)
        )
        await recordEvent(
            .error(
                category: category,
                code: error.diagnosticErrorCode,
                message: error.info,
                source: source,
                callStack: callStack
            ))
    }

    /// Records file generation with context-derived object name, working dir, and memory snapshot.
    public func recordFileGeneratedWithContext(
        _ context: Context,
        outputPath: String,
        templateName: String,
        pInfo: ParsedInfo
    ) async {
        let workingDir = await context.workingDirectoryString

        var objectName: String?
        if let entityWrap = await context.variables["entity"] as? CodeObject_Wrap {
            objectName = await entityWrap.item.name
        } else if let moduleWrap = await context.variables["module"] as? C4Component_Wrap {
            objectName = await moduleWrap.item.name
        }

        let vars = await context.variables.snapshot()
        await captureBaseSnapshot(label: "file-gen", variables: vars.mapValues(debugValueString))

        let source = SourceLocation(
            fileIdentifier: pInfo.identifier,
            lineNo: pInfo.lineNo,
            lineContent: pInfo.line,
            level: pInfo.level
        )
        await recordGeneratedFile(
            outputPath: outputPath,
            templateName: templateName,
            objectName: objectName,
            workingDir: workingDir,
            source: source
        )
    }
}

public actor DefaultDebugRecorder: DebugRecorder {
    private var events: [DebugEventEnvelope] = []
    private var sourceFileMap = SourceFileMap()
    private var containerName: String?
    private var modelSnapshot: ModelSnapshot?
    private var baseSnapshots: [MemorySnapshot] = []
    private var deltaSnapshots: [DeltaSnapshot] = []
    private var errors: [ErrorRecord] = []
    private var generatedFiles: [GeneratedFileRecord] = []
    private var phaseRecords: [PhaseRecord] = []
    private var currentPhaseStart: Date?
    private var sequenceNo = 0

    public init() {}

    public func record(_ envelope: DebugEventEnvelope) async {
        events.append(envelope)
    }

    public func recordEvent(_ event: DebugEvent) async {
        sequenceNo += 1
        let envelope = DebugEventEnvelope(
            sequenceNo: sequenceNo, timestamp: Date(), containerName: containerName, event: event)
        await record(envelope)
    }

    public func recordGeneratedFile(
        outputPath: String, templateName: String?, objectName: String?, workingDir: String,
        source: SourceLocation
    ) async {
        await recordEvent(
            .fileGenerated(
                outputPath: outputPath, templateName: templateName, objectName: objectName,
                source: source))
        let record = GeneratedFileRecord(
            outputPath: outputPath,
            templateName: templateName,
            objectName: objectName,
            workingDir: workingDir,
            eventIndex: max(0, events.count - 1)
        )
        generatedFiles.append(record)
    }

    public func registerSourceFile(_ file: SourceFile) async {
        await sourceFileMap.register(
            identifier: file.identifier, content: file.content, fullPath: file.fullPath,
            fileType: file.fileType)
    }

    /// Get a source file by identifier (for live source lookup during stepping mode).
    public func getSourceFile(identifier: String) async -> SourceFile? {
        await sourceFileMap.file(for: identifier)
    }

    /// Get all registered source files (for live source lookup during stepping mode).
    public func getAllSourceFiles() async -> [SourceFile] {
        await sourceFileMap.allFiles()
    }

    public func setContainerName(_ name: String?) async {
        containerName = name
    }

    public func captureModel(_ model: AppModel) async {
        let containers = await buildContainerSnapshots(from: model)
        modelSnapshot = ModelSnapshot(containers: containers)
    }

    public func captureBaseSnapshot(label: String, variables: [String: String]) async {
        let snapshot = MemorySnapshot(
            label: label, timestamp: Date(), eventIndex: events.count, variables: variables)
        baseSnapshots.append(snapshot)
    }

    public func captureDelta(eventIndex: Int, variable: String, oldValue: String?, newValue: String)
        async
    {
        let delta = DeltaSnapshot(
            eventIndex: eventIndex, variable: variable, oldValue: oldValue, newValue: newValue)
        deltaSnapshots.append(delta)
    }

    public var currentEventCount: Int { events.count }

    public func captureError(
        category: String, code: DiagnosticErrorCode?, message: String, source: SourceLocation,
        callStack: [SourceLocation], memoryDump: MemoryDump?
    ) async {
        let record = ErrorRecord(
            category: category, code: code, message: message, source: source, callStack: callStack,
            memoryDump: memoryDump)
        errors.append(record)
    }

    public func addGeneratedFile(
        outputPath: String, templateName: String?, objectName: String?, workingDir: String
    ) async {
        let record = GeneratedFileRecord(
            outputPath: outputPath, templateName: templateName, objectName: objectName,
            workingDir: workingDir, eventIndex: events.count)
        generatedFiles.append(record)
    }

    /// Reconstruct variable state at a given event index.
    public func reconstructState(atEventIndex eventIndex: Int) async -> [String: String] {
        var vars: [String: String] = [:]
        var bestBase: MemorySnapshot?
        for base in baseSnapshots where base.eventIndex <= eventIndex {
            if bestBase == nil || base.eventIndex > (bestBase?.eventIndex ?? -1) {
                bestBase = base
            }
        }
        if let base = bestBase {
            vars = base.variables
        }
        for delta in deltaSnapshots where delta.eventIndex <= eventIndex {
            vars[delta.variable] = delta.newValue
        }
        return vars
    }

    public func recordPhaseStarted(name: String) async {
        let now = Date()
        markPhaseStarted(name: name, timestamp: now)
        await recordEvent(.phaseStarted(name: name, timestamp: now))
    }

    public func recordPhaseCompleted(name: String, success: Bool, errorMessage: String?) async {
        let now = Date()
        let duration = markPhaseCompleted(
            name: name, success: success, errorMessage: errorMessage, completedAt: now)
        if success {
            await recordEvent(.phaseCompleted(name: name, duration: duration))
        } else {
            await recordEvent(
                .phaseFailed(name: name, error: errorMessage ?? "Unknown phase error"))
        }
    }

    /// Update phase summary state only (no event emission).
    public func markPhaseStarted(name: String, timestamp: Date) {
        currentPhaseStart = timestamp
        phaseRecords.append(
            PhaseRecord(
                name: name, startedAt: timestamp, completedAt: nil, duration: nil, success: false,
                errorMessage: nil))
    }

    /// Update phase summary state only (no event emission), returning computed duration.
    public func markPhaseCompleted(
        name: String, success: Bool, errorMessage: String?, completedAt: Date
    ) -> Double {
        let duration = currentPhaseStart.map { completedAt.timeIntervalSince($0) } ?? 0
        if let lastIndex = phaseRecords.indices.last {
            phaseRecords[lastIndex] = PhaseRecord(
                name: name,
                startedAt: phaseRecords[lastIndex].startedAt,
                completedAt: completedAt,
                duration: duration,
                success: success,
                errorMessage: errorMessage
            )
        }
        currentPhaseStart = nil
        return duration
    }

    public func session(config: OutputConfig) async -> DebugSession {
        let configSnapshot = ConfigSnapshot(
            basePath: config.basePath.string,
            outputPath: config.output.path.string,
            containersToOutput: config.containersToOutput
        )
        let outputRoot = config.output.path.string
        return DebugSession(
            timestamp: Date(),
            config: configSnapshot,
            phases: phaseRecords,
            model: modelSnapshot ?? ModelSnapshot(containers: []),
            events: events,
            sourceFiles: await sourceFileMap.allFiles(),
            files: generatedFiles.map { normalizeGeneratedFileRecord($0, outputRoot: outputRoot) },
            errors: errors,
            baseSnapshots: baseSnapshots,
            deltaSnapshots: deltaSnapshots
        )
    }

    func sourceLocation(from pInfo: ParsedInfo) -> SourceLocation {
        SourceLocation(
            fileIdentifier: pInfo.identifier, lineNo: pInfo.lineNo, lineContent: pInfo.line,
            level: pInfo.level)
    }

    private func normalizeGeneratedFileRecord(_ record: GeneratedFileRecord, outputRoot: String)
        -> GeneratedFileRecord
    {
        GeneratedFileRecord(
            outputPath: record.outputPath,
            relativeOutputPath: relativeOutputPath(for: record, outputRoot: outputRoot),
            templateName: record.templateName,
            objectName: record.objectName,
            workingDir: record.workingDir,
            eventIndex: record.eventIndex
        )
    }

    private func relativeOutputPath(for record: GeneratedFileRecord, outputRoot: String) -> String {
        let root = LocalPath(outputRoot)
        let candidates = [
            record.outputPath.hasPrefix("/") ? record.outputPath : nil,
            record.workingDir.hasPrefix("/") ? record.workingDir + "/" + record.outputPath : nil,
        ].compactMap { $0.map { LocalPath($0) } }

        for candidate in candidates {
            if let relative = candidate.relativePath(from: root) {
                return relative
            }
        }

        return [record.workingDir, record.outputPath]
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
            .filter { !$0.isEmpty }
            .joined(separator: "/")
    }

    private func buildContainerSnapshots(from model: AppModel) async -> [ContainerSnapshot] {
        var result: [ContainerSnapshot] = []
        let containers = await model.containers.snapshot()
        for container in containers {
            let name = await container.name
            let givenname = await container.givenname
            let containerType = String(describing: await container.containerType)
            let components = await container.components.snapshot()
            var modules: [ModuleSnapshot] = []
            for comp in components {
                modules.append(await buildModuleSnapshot(from: comp))
            }
            result.append(
                ContainerSnapshot(
                    name: name, givenname: givenname, containerType: containerType, modules: modules
                ))
        }
        return result
    }

    private func buildModuleSnapshot(from component: C4Component) async -> ModuleSnapshot {
        let name = await component.name
        let givenname = await component.givenname
        var objects: [ObjectSnapshot] = []
        var submodules: [ModuleSnapshot] = []
        for item in await component.items {
            if let submodule = item as? C4Component {
                submodules.append(await buildModuleSnapshot(from: submodule))
            } else if let codeObj = item as? CodeObject {
                objects.append(await buildObjectSnapshot(from: codeObj))
            }
        }
        return ModuleSnapshot(
            name: name, givenname: givenname, objects: objects, submodules: submodules)
    }

    private func buildObjectSnapshot(from obj: CodeObject) async -> ObjectSnapshot {
        let name = await obj.name
        let givenname = await obj.givenname
        let kind = String(describing: await obj.dataType)
        var properties: [PropertySnapshot] = []
        for prop in await obj.properties {
            properties.append(
                PropertySnapshot(
                    name: await prop.name,
                    givenname: await prop.givenname,
                    typeName: await prop.type.objectString(),
                    required: String(describing: await prop.required)
                ))
        }
        var methods: [MethodSnapshot] = []
        for method in await obj.methods {
            let params = await method.parameters.map { $0.name }
            methods.append(
                MethodSnapshot(
                    name: await method.name,
                    givenname: await method.givenname,
                    parameters: params,
                    returnType: await method.returnType.objectString()
                ))
        }
        let anns = await obj.annotations.annotationsList
        let annotations = anns.map { $0.name }
        var tags: [String] = []
        try? await obj.tags.processEach { tag in
            tags.append(tag.name)
            return tag
        }
        var apis: [APISnapshot] = []
        for artifact in await obj.attached {
            if let api = artifact as? GenericAPI {
                let state = await api.state
                let typeStr = String(describing: state.type)
                apis.append(APISnapshot(name: await api.name, type: typeStr))
            }
        }
        return ObjectSnapshot(
            name: name, givenname: givenname, kind: kind, properties: properties, methods: methods,
            annotations: annotations, tags: tags, apis: apis)
    }
}
