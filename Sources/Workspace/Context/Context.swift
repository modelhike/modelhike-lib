//
//  Context.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike
//

fileprivate let working_dir_var : String = "working_dir"

public protocol Context : AnyObject, Actor {
    var config : OutputConfig {get}
    var debugLog: ContextDebugLog {get}
    var events: CodeGenerationEvents {get}
    var currentState: ContextState {get set}
    var variables: WorkingMemory {get}
    var symbols: ContextSymbols {get}
    var templateFunctions: TemplateFunctionMap {get}
    var snapshotStack : SnapshotStack {get}
    var objManager: ObjectAttributeManager {get}
    var evaluator: ExpressionEvaluator {get}

    func config(_ value: OutputConfig)
    var blueprints: BlueprintAggregator { get }
    func blueprint(named name: String, with pInfo: ParsedInfo) async throws -> any Blueprint
    
    func evaluate(expression: String, with pInfo: ParsedInfo) async throws -> Sendable?
    func evaluateCondition(expression: String, with pInfo: ParsedInfo) async throws -> Bool

    /// Debug recorder for capturing events when `--debug` is active.
    var debugRecorder: (any DebugRecorder)? { get async }
    /// Debug stepper for breakpoint-based stepping when `--debug` is active.
    var debugStepper: (any DebugStepper)? { get async }

    /// Current variables as [String: String] for debug display (e.g. when paused at breakpoint).
    func variablesForDebug() async -> [String: String]
}

public extension Context {
    var variables: WorkingMemory {
        get { currentState.variables }
    }

    var debugRecorder: (any DebugRecorder)? {
        get async { config.debugRecorder }
    }

    var debugStepper: (any DebugStepper)? {
        get async { config.debugStepper }
    }
    
    var debugInfo: DebugDictionary {
        get { currentState.debugInfo }
    }
    
    var templateFunctions: TemplateFunctionMap  {
        get { currentState.templateFunctions }
    }
    
    var loopIsFirst: Bool { get async { await variables["@loop.first"] as? Bool ?? false }}
    var loopIsLast: Bool { get async { await variables["@loop.last"] as? Bool ?? false }}
    
    var workingDirectoryString: String { get async { await variables[working_dir_var] as? String ?? "" }}
    var workingDirectory: LocalPath { get async { await config.output.path / workingDirectoryString }}

    @discardableResult
    internal func setWorkingDirectory(_ foldername: String) async -> Bool {
        await variables.set(working_dir_var, value: foldername)
        return true
    }
    
    func isWorkingDirectoryVariable(_ name: String) -> Bool {
        return name == working_dir_var
    }
    
    func append(variables vars: StringDictionary) async {
        for (key, value) in vars {
            await self.variables.set(key, value: value)
        }
    }

    func append(variables vars: WorkingMemory) async {
        for (key, value) in await vars.snapshot() {
            await self.variables.set(key, value: value)
        }
    }
    
    func replace(variables: StringDictionary) async {
        await self.currentState.variables.replace(variables: variables)
    }
    
    func replace(variables: WorkingMemory) async {
        await self.currentState.variables.replace(variables: variables)
    }
    
    func pushSnapshot() {
        snapshotStack.append(currentState)
        // Capture a base memory snapshot so the debug console can reconstruct
        // variable state at any event index via captureDelta deltas.
        if let recorder = config.debugRecorder {
            let label = "snapshot-push"
            let vars = variables
            Task {
                let snapshot = await vars.snapshot().mapValues(debugValueString)
                await recorder.captureBaseSnapshot(label: label, variables: snapshot)
            }
        }
    }

    func popSnapshot() {
        if let last = snapshotStack.popLast() {
            self.currentState = last
        }
    }
    
    func pushCallStack(_ item: CallStackable) async {
        await debugLog.stack.push(item)
    }

    func popCallStack() async {
        await debugLog.stack.popLast()
    }
    
    func evaluate(value: String, with pInfo: ParsedInfo) async throws -> Sendable? {
        return try await evaluator.evaluate(value: value, pInfo: pInfo)
    }
    
    func evaluate(expression: String, with pInfo: ParsedInfo) async throws -> Sendable? {
        return try await evaluator.evaluate(expression: expression, pInfo: pInfo)
    }
    
    func evaluateCondition(expression: String, with pInfo: ParsedInfo) async throws -> Bool {
        return try await evaluator.evaluateCondition(expression: expression, pInfo: pInfo)
    }
    
    func evaluateCondition(value: Sendable, with pInfo: ParsedInfo) async -> Bool {
        return await evaluator.evaluateCondition(value: value, with: self)
    }

    func variablesForDebug() async -> [String: String] {
        let snapshot = await variables.snapshot()
        return snapshot.mapValues(debugValueString)
    }

    func recordVariableSetDiagnosticIfNeeded(variableName: String, newValue: Sendable?) async {
        guard let recorder = config.debugRecorder else { return }

        let oldRaw = await variables[variableName]
        let oldStr = oldRaw.map(debugValueString)
        let newStr = newValue.map(debugValueString) ?? ""

        guard oldStr != newStr else { return }

        let eventIndex = await recorder.currentEventCount
        await recorder.captureDelta(eventIndex: eventIndex, variable: variableName,
                                    oldValue: oldStr, newValue: newStr)
        debugLog.recordEvent(.variableSet(name: variableName, oldValue: oldStr, newValue: newStr,
            source: SourceLocation(fileIdentifier: "", lineNo: 0, lineContent: "", level: 0)))
    }
    
    //manage obj attributes in the context variables
    func valueOf(variableOrObjProp name: String, with pInfo: ParsedInfo) async throws -> Sendable? {
        
        if let dotIndex = name.firstIndex(of: ".") { //object attribute
            let beforeDot = String(name[..<dotIndex])
            let afterDot = String(name[name.index(after: dotIndex)...])

            let variableName = beforeDot
            let attributeName = afterDot

            return try await self.objManager.getObjAttributeValue(objName: variableName, propName: attributeName, with: pInfo)
            
        } else { // object only
            let variableName = name

            if let obj = await self.variables[variableName]  {
                return obj
            } else {
                let candidates = await self.variables.keySnapshot
                throw Suggestions.variableOrPropertyNotFound(
                    variableName,
                    candidates: candidates,
                    pInfo: pInfo
                )
            }
        }
    }
    
    func setValueOf(variableOrObjProp name: String, valueExpression: String, modifiers: [ModifierInstance] = [], with pInfo: ParsedInfo) async throws {
        
        if let dotIndex = name.firstIndex(of: ".") { //object attribute
            let beforeDot = String(name[..<dotIndex])
            let afterDot = String(name[name.index(after: dotIndex)...])

            let variableName = beforeDot
            let attributeName = afterDot

            try await objManager.setObjAttribute(objName: variableName, propName: attributeName, valueExpression: valueExpression, modifiers: modifiers, with: pInfo)
            
        } else { // object only
            let variableName = name

            let evaluatedValue = try await self.evaluate(expression: valueExpression, with: pInfo)
            await recordVariableSetDiagnosticIfNeeded(variableName: variableName, newValue: evaluatedValue)

            if let body = evaluatedValue {
                await self.variables.set(variableName, value: body)
            } else {
                await self.variables.removeValue(forKey: variableName)
            }
        }
    }
    
    func setValueOf(variableOrObjProp name: String, value: Sendable?, with pInfo: ParsedInfo) async throws {
        
        if let dotIndex = name.firstIndex(of: ".") { //object attribute
            let beforeDot = String(name[..<dotIndex])
            let afterDot = String(name[name.index(after: dotIndex)...])

            let variableName = beforeDot
            let attributeName = afterDot

            try await objManager.setObjAttribute(objName: variableName, propName: attributeName, value: value, with: pInfo)
            
        } else { // object only
            let variableName = name
            await recordVariableSetDiagnosticIfNeeded(variableName: variableName, newValue: value)
            if let body = value {
                await self.variables.set(variableName, value: body)
            } else {
                await self.variables.removeValue(forKey: variableName)
            }
        }
    }
    
    func setValueOf(variableOrObjProp name: String, body: String?, modifiers: [ModifierInstance] = [], with pInfo: ParsedInfo) async throws {
        
        if let dotIndex = name.firstIndex(of: ".") { //object attribute
            let beforeDot = String(name[..<dotIndex])
            let afterDot = String(name[name.index(after: dotIndex)...])

            let variableName = beforeDot
            let attributeName = afterDot

            try await objManager.setObjAttribute(objName: variableName, propName: attributeName, body: body, modifiers: modifiers, with: pInfo)
            
        } else { // object only
            let variableName = name

            let modifiedValue: Sendable?
            if let body = body {
                modifiedValue = try await Modifiers.apply(to: body, modifiers: modifiers, with: pInfo)
            } else {
                modifiedValue = nil
            }

            await recordVariableSetDiagnosticIfNeeded(variableName: variableName, newValue: modifiedValue)

            if let modifiedValue {
                await self.variables.set(variableName, value: modifiedValue)
            } else {
                await self.variables.removeValue(forKey: variableName)
            }
        }
    }
}
