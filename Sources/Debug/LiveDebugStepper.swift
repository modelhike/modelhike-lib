//
//  LiveDebugStepper.swift
//  ModelHike
//  https://www.github.com/modelhike/modelhike
//

import Foundation

/// Breakpoint location by file and line.
public struct BreakpointLocation: Hashable, Codable, Sendable {
    public let fileIdentifier: String
    public let lineNo: Int

    public init(fileIdentifier: String, lineNo: Int) {
        self.fileIdentifier = fileIdentifier
        self.lineNo = lineNo
    }
}

/// Step mode when resuming from a breakpoint.
public enum StepMode: String, Codable, Sendable {
    case run
    case stepOver
    case stepInto
    case stepOut
}

/// Callback when the stepper pauses at a breakpoint. Called before suspending.
public typealias StepperPauseCallback = @Sendable (SourceLocation, [String: String]) async -> Void

/// Current pause state, exposed so new WebSocket clients can receive it on connect.
public struct PauseState: Sendable {
    public let location: SourceLocation
    public let vars: [String: String]
}

/// Live stepping implementation. Suspends at breakpoints using CheckedContinuation.
/// Requires the pipeline to run while the debug server is already listening (--debug-stepping mode).
public actor LiveDebugStepper: DebugStepper {
    private var breakpoints: Set<BreakpointLocation> = []
    private var continuation: CheckedContinuation<Void, Never>?
    private var mode: StepMode = .run
    private var onPause: StepperPauseCallback?
    
    /// Current pause state (non-nil when paused at a breakpoint)
    private var currentPauseState: PauseState?
    
    /// Depth level when stepping started (for stepOver/stepOut)
    private var stepStartLevel: Int = 0
    
    /// File where stepping started (for stepOver)
    private var stepStartFile: String?

    public init() {}
    
    /// Returns the current pause state if execution is suspended, nil otherwise.
    public func getPauseState() -> PauseState? {
        return currentPauseState
    }

    public func setOnPause(_ callback: StepperPauseCallback?) {
        onPause = callback
    }

    public func addBreakpoint(_ bp: BreakpointLocation) {
        breakpoints.insert(bp)
    }

    public func removeBreakpoint(_ bp: BreakpointLocation) {
        breakpoints.remove(bp)
    }

    public func resume(mode: StepMode = .run) {
        self.mode = mode
        currentPauseState = nil
        continuation?.resume()
        continuation = nil
    }

    public func willExecute(item: TemplateItem, ctx: Context) async {
        guard let itemWithInfo = item as? TemplateItemWithParsedInfo else { return }
        let pInfo = itemWithInfo.pInfo
        let loc = BreakpointLocation(fileIdentifier: pInfo.identifier, lineNo: pInfo.lineNo)
        let isSameFile = pInfo.identifier == stepStartFile
        
        // Determine if we should pause
        let shouldPause: Bool
        switch mode {
        case .run:
            // Only pause at explicit breakpoints
            shouldPause = breakpoints.contains(loc)
        case .stepInto:
            // Pause at every line (goes into render-file calls)
            shouldPause = true
        case .stepOver:
            // Pause at the next line in the SAME file
            // This enters loop bodies but skips into render-file/function calls
            shouldPause = isSameFile
        case .stepOut:
            // Pause when we return to the calling file at shallower level
            // If we're in a nested file, don't pause until we return
            shouldPause = isSameFile && pInfo.level < stepStartLevel
        }
        
        guard shouldPause else { return }

        let sourceLoc = SourceLocation(
            fileIdentifier: pInfo.identifier,
            lineNo: pInfo.lineNo,
            lineContent: pInfo.line,
            level: pInfo.level
        )
        let vars = await ctx.variablesForDebug()
        
        // Store current pause state so new WebSocket clients can receive it
        currentPauseState = PauseState(location: sourceLoc, vars: vars)
        
        // Remember the level and file for next step operation
        stepStartLevel = pInfo.level
        stepStartFile = pInfo.identifier
        
        // Reset to run mode - next resume will set the new mode
        mode = .run
        
        if let cb = onPause {
            await cb(sourceLoc, vars)
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            continuation = cont
        }
    }
}
