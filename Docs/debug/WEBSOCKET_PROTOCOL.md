# WebSocket Debugging Protocol

This document provides a comprehensive reference for the WebSocket-based debugging protocol used in ModelHike's `--debug-stepping` mode.

## Overview

The debug server exposes a WebSocket endpoint at `/ws` that enables:

- **Real-time event streaming** — receive debug events as the pipeline executes
- **Breakpoint management** — add/remove breakpoints dynamically
- **Execution control** — pause and resume pipeline execution
- **State synchronization** — new clients receive current pause state on connect

## Connection

### Endpoint

```
ws://localhost:<port>/ws
```

Default port is `4800`. Any HTTP path with `Upgrade: websocket` header will trigger the upgrade.

### JavaScript Example

```javascript
const ws = new WebSocket('ws://localhost:4800/ws');

ws.onopen = () => console.log('Connected');
ws.onmessage = (e) => {
  const msg = JSON.parse(e.data);
  console.log('Received:', msg.type, msg);
};
ws.onclose = () => console.log('Disconnected');
```

### Connection Behavior

1. On connect, the server registers the client with `WebSocketClientManager`
2. If execution is currently paused at a breakpoint, the server immediately sends a `paused` message to the new client
3. All subsequent events are broadcast to all connected clients
4. On disconnect, the client is removed from the manager

---

## Server → Client Messages

All messages are JSON objects with a `type` field.

### `event` — Debug Event

Sent for every debug event recorded during pipeline execution.

```json
{
  "type": "event",
  "envelope": {
    "sequenceNo": 42,
    "timestamp": "2024-03-23T12:34:56.789Z",
    "containerName": "APIs",
    "event": { /* DebugEvent - varies by event type */ }
  }
}
```

**Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `envelope.sequenceNo` | `number` | Monotonically increasing sequence number |
| `envelope.timestamp` | `string` | ISO 8601 timestamp |
| `envelope.containerName` | `string?` | Current container being processed (may be null) |
| `envelope.event` | `object` | The actual debug event (see DebugEvent types below) |

### `paused` — Execution Paused

Sent when execution pauses at a breakpoint. Also sent to new clients that connect while already paused.

```json
{
  "type": "paused",
  "location": {
    "fileIdentifier": "main.ss",
    "lineNo": 10,
    "lineContent": "for module in @container.modules",
    "level": 0
  },
  "vars": {
    "@container": "APIs",
    "working_dir": "src/main/java",
    "entity": "User"
  }
}
```

**Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `location.fileIdentifier` | `string` | Source file name (e.g., `main.ss`, `{{entity.name}}.java`) |
| `location.lineNo` | `number` | 1-based line number |
| `location.lineContent` | `string` | The actual source line content |
| `location.level` | `number` | Nesting level in the call stack |
| `vars` | `object` | Variable state at the pause point (key-value pairs, all stringified) |

### `completed` — Pipeline Finished

Sent when the pipeline completes execution.

```json
{
  "type": "completed"
}
```

After receiving this message, clients can fetch the full session via REST endpoints (`/api/session`, etc.).

---

## Client → Server Messages

All messages are JSON objects with a `type` field.

### `resume` — Continue Execution

Resume pipeline execution after a pause.

```json
{
  "type": "resume",
  "mode": "run"
}
```

**Fields:**

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `mode` | `string` | `"run"` | One of: `run`, `stepOver`, `stepInto`, `stepOut` |

**Mode Semantics:**

| Mode | Description | Current Status |
|------|-------------|----------------|
| `run` | Continue until next breakpoint or completion | ✅ Implemented |
| `stepOver` | Execute current item, pause on next sibling | ⏳ In progress |
| `stepInto` | Step into current item (e.g., function call) | ⏳ In progress |
| `stepOut` | Run until current scope exits | ⏳ In progress |

> **Note:** Currently all modes behave like `run` (unconditional continuation). Differentiated stepping semantics are planned.

### `addBreakpoint` — Set Breakpoint

Add a breakpoint at a specific file and line.

```json
{
  "type": "addBreakpoint",
  "fileIdentifier": "main.ss",
  "lineNo": 10
}
```

**Fields:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `fileIdentifier` | `string` | Yes | Source file identifier (must match registered sources) |
| `lineNo` | `number` | Yes | 1-based line number |

### `removeBreakpoint` — Clear Breakpoint

Remove a previously set breakpoint.

```json
{
  "type": "removeBreakpoint",
  "fileIdentifier": "main.ss",
  "lineNo": 10
}
```

**Fields:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `fileIdentifier` | `string` | Yes | Source file identifier |
| `lineNo` | `number` | Yes | 1-based line number |

---

## Programmatic Breakpoints (Swift API)

Breakpoints can also be set programmatically in Swift before the pipeline starts.

### Types

```swift
/// Identifies a breakpoint by file and line
public struct BreakpointLocation: Hashable, Codable, Sendable {
    public let fileIdentifier: String
    public let lineNo: Int
}

/// Resume mode
public enum StepMode: String, Codable, Sendable {
    case run
    case stepOver
    case stepInto
    case stepOut
}

/// Snapshot of pause state (for new client sync)
public struct PauseState: Sendable {
    public let location: SourceLocation
    public let vars: [String: String]
}
```

### LiveDebugStepper API

```swift
public actor LiveDebugStepper: DebugStepper {
    /// Add a breakpoint
    public func addBreakpoint(_ bp: BreakpointLocation)
    
    /// Remove a breakpoint
    public func removeBreakpoint(_ bp: BreakpointLocation)
    
    /// Resume execution with specified mode
    public func resume(mode: StepMode = .run)
    
    /// Set callback invoked when pausing (before suspension)
    public func setOnPause(_ callback: StepperPauseCallback?)
    
    /// Get current pause state (nil if not paused)
    public func getPauseState() -> PauseState?
}
```

### Example: Adding Test Breakpoints

```swift
// In DevMain.swift runCodebaseGenerationWithStepping()
let stepper = LiveDebugStepper()

// Wire pause callback to broadcast over WebSocket
await stepper.setOnPause { location, vars in
    await streamingRecorder.broadcastPaused(location: location, vars: vars)
}

// Add programmatic breakpoints
await stepper.addBreakpoint(BreakpointLocation(fileIdentifier: "main.ss", lineNo: 10))
await stepper.addBreakpoint(BreakpointLocation(fileIdentifier: "{{entity.name}}.java", lineNo: 1))

// Pipeline will pause when it reaches these locations
```

---

## Debug Event Types

The `event` field in `WSEventMessage.envelope.event` varies by event type. Common types include:

| Event Type | Description |
|------------|-------------|
| `templateParseStarted` | Template parsing begins |
| `templateStarted` | Template execution begins |
| `scriptParseStarted` | Script parsing begins |
| `scriptStarted` | Script execution begins |
| `fileGenerated` | Output file was generated |
| `fileCopied` | Static file was copied |
| `fileSkipped` | File generation was skipped |
| `controlFlow` | If/else branch decision |
| `workingDirChanged` | `working_dir` variable changed |
| `statementDetected` | Script statement parsed |
| `textContent` | Template text content emitted |
| `functionCallEvaluated` | Template function call completed |

See `Sources/Debug/DebugEvent.swift` for the full event enum.

---

## Finding Valid File Identifiers

File identifiers must match how templates/scripts are registered with the debug recorder.

### Method 1: Query the Session

```bash
curl -s http://localhost:4800/api/session | \
  python3 -c "import sys,json; [print(s['identifier']) for s in json.load(sys.stdin).get('sourceFiles',[])]"
```

### Method 2: Check Browser Console

In the debug console, open DevTools and run:

```javascript
state.session.sourceFiles.map(s => s.identifier)
```

### Common Identifiers

| Identifier | Description |
|------------|-------------|
| `main.ss` | Blueprint entry-point script |
| `{{entity.name}}.java` | Entity template with placeholder |
| `docker-compose.yml` | Static config template |
| `README.md` | Documentation template |

---

## JavaScript Helper Functions

The debug console provides helper functions in `utils/api.js`:

```javascript
// Connect to WebSocket with handlers
const ws = connectWebSocket({
  onEvent: (envelope) => { /* handle event */ },
  onPaused: (msg) => { /* handle pause: msg.location, msg.vars */ },
  onCompleted: () => { /* handle completion */ },
  onOpen: () => { /* connected */ },
  onClose: () => { /* disconnected */ }
});

// Send commands
sendResume(ws, 'run');           // or 'stepOver', 'stepInto', 'stepOut'
sendAddBreakpoint(ws, 'main.ss', 10);
sendRemoveBreakpoint(ws, 'main.ss', 10);
```

---

## Implementation Notes

### New Client Synchronization

When a new WebSocket client connects while execution is paused, the server immediately sends the current `paused` message. This ensures late-joining clients can display the correct state.

Implementation in `WebSocketHandler.handlerAdded()`:

```swift
// If currently paused at a breakpoint, send the pause state to the new client
if let stepper = stepperRef, let pauseState = await stepper.getPauseState() {
    let msg = WSPausedMessage(location: pauseState.location, vars: pauseState.vars)
    if let data = try? JSONEncoder().encode(msg), let json = String(data: data, encoding: .utf8) {
        client.send(json)
    }
}
```

### Thread Safety

- `LiveDebugStepper` is an actor — all state access is serialized
- `WebSocketClientManager` is an actor — client list is thread-safe
- `StreamingDebugRecorder` is an actor — recording and broadcasting are serialized
- WebSocket frames are sent via NIO's event loop (`channel.eventLoop.execute`)

### Breakpoint Matching

Breakpoints match exactly on `(fileIdentifier, lineNo)`. The `fileIdentifier` must match the identifier used when the source was registered (usually the template/script filename without path).

---

## Sequence Diagram

```
Browser                    Server                     Pipeline
   |                          |                          |
   |------- connect /ws ----->|                          |
   |<-- paused (if paused) ---|                          |
   |                          |                          |
   |                          |<---- record event -------|
   |<------ event msg --------|                          |
   |                          |                          |
   |--- addBreakpoint msg --->|                          |
   |                          |---- add to set -------->|
   |                          |                          |
   |                          |<-- willExecute (match) --|
   |                          |---- onPause callback --->|
   |<------ paused msg -------|                          |
   |                          |      [suspended]         |
   |                          |                          |
   |---- resume msg --------->|                          |
   |                          |---- resume() ----------->|
   |                          |      [continues]         |
   |                          |                          |
   |                          |<---- pipeline done ------|
   |<----- completed msg -----|                          |
```

---

## Related Files

| File | Description |
|------|-------------|
| `DevTester/DebugServer/WebSocketHandler.swift` | NIO handler for WebSocket frames |
| `DevTester/DebugServer/WebSocketClientManager.swift` | Actor managing connected clients |
| `DevTester/DebugServer/StreamingDebugRecorder.swift` | Broadcasts events over WebSocket |
| `Sources/Debug/LiveDebugStepper.swift` | Breakpoint management and execution control |
| `DevTester/Assets/debug-console/utils/api.js` | JavaScript WebSocket helpers |
| `DevTester/Assets/debug-console/components/stepper-panel.js` | UI for stepping controls |
