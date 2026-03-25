//
//  StreamingDebugRecorder.swift
//  DevTester
//

import Foundation
import ModelHike

// MARK: - WS message shapes

/// Broadcast to browser for every new event during a live run.
private struct WSEventMessage: Encodable {
    let type: String = "event"
    let envelope: DebugEventEnvelope
}

/// Broadcast to browser when the pipeline completes.
struct WSCompletedMessage: Encodable, Sendable {
    let type: String = "completed"
}

/// Broadcast to browser when execution pauses at a breakpoint.
struct WSPausedMessage: Encodable, Sendable {
    let type: String = "paused"
    let location: SourceLocation
    let vars: [String: String]
}

// MARK: - StreamingDebugRecorder

/// `DebugRecorder` for `--debug-stepping` mode.
///
/// Stores all data into an inner `DefaultDebugRecorder` for later REST access, and
/// simultaneously broadcasts each event to all connected WebSocket clients in real time.
///
/// To avoid double-appending inside `DefaultDebugRecorder`, we track the sequence
/// number and container name ourselves, build the `DebugEventEnvelope` here, and call
/// the lower-level `inner.record(_:)` directly — bypassing `inner.recordEvent(_:)`.
public actor StreamingDebugRecorder: DebugRecorder {

    public let inner: DefaultDebugRecorder
    private let wsManager: WebSocketClientManager

    private var sequenceNo = 0
    private var containerName: String?

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    init(wsManager: WebSocketClientManager) {
        self.inner = DefaultDebugRecorder()
        self.wsManager = wsManager
    }

    // MARK: - DebugRecorder protocol

    /// Store the pre-built envelope and broadcast it to all connected WebSocket clients.
    public func record(_ envelope: DebugEventEnvelope) async {
        await inner.record(envelope)
        let msg = WSEventMessage(envelope: envelope)
        await wsManager.broadcast(msg)
    }

    /// Build the envelope here (mirrors `DefaultDebugRecorder.recordEvent`), call the
    /// lower-level `record(_:)` so the broadcast also fires, and avoid going through
    /// `inner.recordEvent` which would call `inner.record` directly and skip broadcast.
    public func recordEvent(_ event: DebugEvent) async {
        sequenceNo += 1
        let envelope = DebugEventEnvelope(
            sequenceNo: sequenceNo,
            timestamp: Date(),
            containerName: containerName,
            event: event
        )
        await record(envelope)
    }

    public func recordGeneratedFile(
        outputPath: String,
        templateName: String?,
        objectName: String?,
        workingDir: String,
        source: SourceLocation
    ) async {
        await recordEvent(.fileGenerated(outputPath: outputPath, templateName: templateName, objectName: objectName, source: source))
        await inner.addGeneratedFile(outputPath: outputPath, templateName: templateName, objectName: objectName, workingDir: workingDir)
    }

    public func registerSourceFile(_ file: SourceFile) async {
        await inner.registerSourceFile(file)
    }

    public func setContainerName(_ name: String?) async {
        containerName = name
        await inner.setContainerName(name)
    }

    public func captureModel(_ model: AppModel) async {
        await inner.captureModel(model)
    }

    public func captureBaseSnapshot(label: String, variables: [String: String]) async {
        await inner.captureBaseSnapshot(label: label, variables: variables)
    }

    public func captureDelta(eventIndex: Int, variable: String, oldValue: String?, newValue: String) async {
        await inner.captureDelta(eventIndex: eventIndex, variable: variable, oldValue: oldValue, newValue: newValue)
    }

    public var currentEventCount: Int { sequenceNo }

    public func captureError(
        category: String,
        message: String,
        source: SourceLocation,
        callStack: [SourceLocation],
        memoryDump: [String: String]?
    ) async {
        await inner.captureError(category: category, message: message, source: source, callStack: callStack, memoryDump: memoryDump)
    }

    public func addGeneratedFile(
        outputPath: String,
        templateName: String?,
        objectName: String?,
        workingDir: String
    ) async {
        await inner.addGeneratedFile(outputPath: outputPath, templateName: templateName, objectName: objectName, workingDir: workingDir)
    }

    public func recordPhaseStarted(name: String) async {
        let now = Date()
        await inner.markPhaseStarted(name: name, timestamp: now)
        await recordEvent(.phaseStarted(name: name, timestamp: now))
    }

    public func recordPhaseCompleted(name: String, success: Bool, errorMessage: String?) async {
        let now = Date()
        let duration = await inner.markPhaseCompleted(name: name, success: success, errorMessage: errorMessage, completedAt: now)
        if success {
            await recordEvent(.phaseCompleted(name: name, duration: duration))
        } else {
            await recordEvent(.phaseFailed(name: name, error: errorMessage ?? "Unknown phase error"))
        }
    }

    public func session(config: any OutputConfig) async -> DebugSession {
        await inner.session(config: config)
    }

    public func reconstructState(atEventIndex eventIndex: Int) async -> [String: String] {
        await inner.reconstructState(atEventIndex: eventIndex)
    }

    // MARK: - Live helpers

    /// Broadcast the pipeline-completed signal to all WebSocket clients.
    func broadcastCompleted() async {
        await wsManager.broadcast(WSCompletedMessage())
    }

    /// Broadcast a breakpoint-paused event to all WebSocket clients.
    func broadcastPaused(location: SourceLocation, vars: [String: String]) async {
        await wsManager.broadcast(WSPausedMessage(location: location, vars: vars))
    }
}
