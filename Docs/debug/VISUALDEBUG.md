# Visual Debugging System

This document explains how the current ModelHike visual debugging system works, how its pieces fit together, and what is implemented versus scaffolded.

It describes the system as it exists today, not just the original brainstorm in `.ai/brainstorm/debug-console-brainstorm.md`.

## Purpose

The visual debugger replaces most ad-hoc `print()`-driven debugging with a structured, browser-based inspection flow for a pipeline run.

At a high level it provides:

- a `--debug` execution mode in `DevTester` for post-mortem inspection
- a `--debug-stepping` execution mode for live event streaming and future breakpoint-driven stepping
- a structured in-memory debug session
- a local HTTP server that exposes the session and related derived views
- a WebSocket endpoint (`/ws`) for real-time event streaming in stepping mode
- a single-page browser UI for browsing phases, files, model snapshots, source, variables, and rendered outputs

**Post-mortem mode** (`--debug`):

- the pipeline runs to completion first
- debug data is captured during execution by `DefaultDebugRecorder`
- the browser UI is opened after the run

**Live stepping mode** (`--debug-stepping`):

- the HTTP server and WebSocket endpoint start *before* the pipeline runs
- a `StreamingDebugRecorder` wraps `DefaultDebugRecorder` and broadcasts every captured event over WebSocket as it is emitted
- the browser UI can be opened before the pipeline starts and receives events in real time
- a `LiveDebugStepper` is installed for future breakpoint-driven execution control (run, step over, step into, step out)

## Entry Point

The main entry point is `DevTester/DevMain.swift`.

When `DevTester` starts:

- if `--debug` is absent, it runs the normal code-generation flow
- if `--debug` is present, it runs `runCodebaseGenerationWithDebug()` (post-mortem mode)
- if `--debug-stepping` is present, it runs `runCodebaseGenerationWithStepping()` (live streaming mode)

### Post-mortem path (`--debug`)

1. Builds `Pipelines.codegen`
2. Creates a `DefaultDebugRecorder`
3. Stores it on `config.debugRecorder`
4. Stores `NoOpDebugStepper()` on `config.debugStepper`
5. Runs the pipeline
6. Serializes the recorder state into a `DebugSession`
7. Extracts in-memory rendered output content from pipeline sandboxes
8. Starts `DebugHTTPServer`
9. Optionally opens the browser
10. Keeps the process alive until Ctrl+C

### Live stepping path (`--debug-stepping`)

1. Creates a `WebSocketClientManager` actor
2. Creates a `StreamingDebugRecorder` wrapping `DefaultDebugRecorder`, wired to the `WebSocketClientManager`
3. Creates a `LiveDebugStepper`; installs a pause callback that broadcasts a `paused` WebSocket message to connected clients
4. Stores both on `config.debugRecorder` and `config.debugStepper`
5. **Starts `DebugHTTPServer` before the pipeline runs** — browser can connect and receive live events
6. Optionally opens the browser; sleeps 4 s to allow a connection before events begin
7. Runs the pipeline — every captured event is immediately broadcast over WebSocket
8. After pipeline completion, calls `server.updateSession(_:renderedOutputs:)` to make the full session available for post-mortem REST API calls
9. Broadcasts a `completed` WebSocket message
10. Keeps the process alive until Ctrl+C

Relevant flags:

- `--debug`: enable post-mortem debug mode
- `--debug-stepping`: enable live streaming mode (server starts before pipeline)
- `--perf`: print pipeline total, phase, and pass timings after the run completes
- `--debug-port=<port>`: choose the HTTP server port (default 4800)
- `--debug-dev`: serve debug console directly from `DevTester/Assets/debug-console/`
- `--no-open`: do not auto-open the browser

## Runtime Architecture

The runtime is split into four layers.

### 1. Instrumented execution

The generator already has many hook points through `ContextDebugLog` in `Sources/Workspace/Context/DebugUtils.swift`.

These hooks are called from:

- template parsing and execution
- script parsing and execution
- file generation and copy operations
- control-flow decisions
- variable capture points
- error pathways

The system does not attach one giant tracer around the pipeline. Instead, instrumentation is distributed across the existing execution code paths.

### 2. Recorder and session model

`DefaultDebugRecorder` in `Sources/Debug/DebugRecorder.swift` is the central capture store.

It collects:

- `events`
- `sourceFiles`
- `generatedFiles`
- `baseSnapshots`
- `deltaSnapshots`
- `errors`
- `phaseRecords`
- `modelSnapshot`

At the end of the run it produces a `DebugSession`, defined in `Sources/Debug/DebugSession.swift`.

### 3. Local HTTP server and WebSocket server

`DevTester/DebugServer/DebugHTTPServer.swift` serves the debug UI, JSON endpoints, and a WebSocket upgrade endpoint over **SwiftNIO** (`NIOPosix` + `NIOHTTP1` + `NIOWebSocket`).

It is built around a SwiftNIO `ServerBootstrap` that configures an HTTP/1.1 pipeline with `NIOWebSocketServerUpgrader`. Incoming connections are handled by:

- `HTTPChannelHandler` — assembles `HTTPServerRequestPart` frames into complete requests and dispatches them to `DebugRouter`
- `WebSocketHandler` — registers/deregisters with `WebSocketClientManager` and handles WebSocket frames; uses `handlerAdded(context:)` (not `channelActive`) because the handler is added to an already-active pipeline during the HTTP→WebSocket upgrade

The server accepts a `DebugRouter`, `WebSocketClientManager`, and `LiveDebugStepper` at construction. In post-mortem mode the session is passed at construction time. In stepping mode the session is initially empty and updated after the pipeline completes via `updateSession(_:renderedOutputs:)`.

**Key files:**

| File | Role |
|---|---|
| `DebugHTTPServer.swift` | `ServerBootstrap` setup, channel pipeline, start/stop, `updateSession` |
| `DebugRouter.swift` | Actor; all HTTP request routing and business logic |
| `HTTPChannelHandler.swift` | NIO `ChannelInboundHandler`; assembles HTTP requests, writes responses |
| `WebSocketClientManager.swift` | Actor; tracks connected WebSocket clients, provides `broadcast(json:)` |
| `WebSocketHandler.swift` | NIO `ChannelInboundHandler`; registers clients in `handlerAdded`, handles frames |
| `StreamingDebugRecorder.swift` | Actor implementing `DebugRecorder`; wraps `DefaultDebugRecorder`, broadcasts every event live via `WebSocketClientManager` |

### 4. Browser UI

`DevTester/Assets/debug-console/` is a modular browser app using Lit web components.

It fetches the captured session and derives most of its UI state client-side. See `DevTester/Assets/debug-console/README.md` for the full component architecture.

## Main Data Flow

### Post-mortem mode (`--debug`)

```text
Pipeline execution
  -> ContextDebugLog emits debug events
  -> DefaultDebugRecorder stores events, sources, snapshots, errors, files
  -> Pipeline completes
  -> recorder.session(config:) produces DebugSession
  -> pipeline.state.renderedOutputRecords() extracts in-memory generated contents
  -> DebugHTTPServer starts, serves both over HTTP
  -> debug-console/ UI fetches and renders them
```

### Live stepping mode (`--debug-stepping`)

```text
DebugHTTPServer starts (HTTP + WebSocket)
  -> Browser connects to /ws
DevMain runs the pipeline
  -> ContextDebugLog emits debug events
  -> StreamingDebugRecorder stores events AND broadcasts each over WebSocket
  -> debug-console/ receives live WSEventMessage frames; appends events in real time
Pipeline completes
  -> server.updateSession() makes full DebugSession available via REST endpoints
  -> StreamingDebugRecorder broadcasts "completed" message
  -> debug-console/ can now use REST endpoints for variable inspector, source, etc.
```

There is no persistent debug database. Everything is in-memory for the lifetime of the `DevTester` process.

## Exact Integration Inventory

This section is intentionally file-oriented. It answers the question: "Where, exactly, does the visual debugger hook into the runtime?"

### `DevTester` layer

- `DevTester/DevMain.swift`
  - `--debug` path: installs `DefaultDebugRecorder` + `NoOpDebugStepper`, runs pipeline, then starts server
  - `--debug-stepping` path: installs `StreamingDebugRecorder` + `LiveDebugStepper`, starts server first, runs pipeline, updates session after completion
  - converts recorder state into `DebugSession`
  - extracts in-memory rendered outputs from retained sandboxes

- `DevTester/DebugServer/DebugHTTPServer.swift`
  - SwiftNIO `ServerBootstrap` — configures HTTP + WebSocket upgrade pipeline
  - delegates all routing to `DebugRouter`
  - wires `WebSocketClientManager` and `LiveDebugStepper` into NIO handlers
  - exposes `updateSession(_:renderedOutputs:)` for stepping mode

- `DevTester/DebugServer/DebugRouter.swift`
  - actor; all HTTP business logic and endpoint handlers
  - serves HTML, all JSON APIs, static assets, expression evaluation
  - `updateSession(_:renderedOutputs:)` allows live session refresh after pipeline completion

- `DevTester/DebugServer/HTTPChannelHandler.swift`
  - NIO `ChannelInboundHandler` — assembles `HTTPServerRequestPart` frames into complete requests
  - dispatches to `DebugRouter` via `Task { await router.handle(request:) }`
  - writes `HTTPRouteResponse` back to the NIO channel

- `DevTester/DebugServer/WebSocketClientManager.swift`
  - actor — tracks all active WebSocket clients
  - each client is a `WebSocketClient` struct with a `@Sendable (String) -> Void` send closure
  - `broadcast(json:)` sends a JSON string to all connected clients

- `DevTester/DebugServer/WebSocketHandler.swift`
  - NIO `ChannelInboundHandler` — registers with `WebSocketClientManager` in `handlerAdded(context:)` (not `channelActive`) because the handler joins an already-active pipeline during WebSocket upgrade
  - deregisters on `handlerRemoved`
  - forwards text frames to `LiveDebugStepper` for stepping commands (resume, breakpoints)

- `DevTester/DebugServer/StreamingDebugRecorder.swift`
  - actor implementing `DebugRecorder`
  - wraps `DefaultDebugRecorder` for full session capture
  - after every `record(_:)` call, broadcasts the event as a `WSEventMessage` JSON string via `WebSocketClientManager`
  - `broadcastCompleted()` sends a final `{ "type": "completed" }` message
  - `broadcastPaused(location:vars:)` sends pause state for future stepping UI

- `DevTester/Assets/debug-console/`
  - modular Lit web components (no build step required)
  - derives UI state from `DebugSession` (post-mortem) or live WebSocket events (stepping mode)
  - `debug-app.js` checks `/api/mode`; in `stepping` mode it connects WebSocket and appends live events
  - `stepper-panel.js` shown when WebSocket sends a `paused` message; provides Run/Step Over/Step Into/Step Out buttons
  - builds file windows client-side
  - drives source/generated/variables/models panes
  - controls timeline/file-tree interaction

### Pipeline layer

- `Sources/Pipelines/Pipeline.swift`
  - records phase metadata through the recorder
  - retains generation sandboxes in `PipelineState`

- `Sources/Pipelines/PipelinePhase.swift`
  - `RenderPhase.runIn(pipeline:)` creates the sandbox that later becomes the source of in-memory rendered-output snapshots

- `Sources/Pipelines/PipelineConfig.swift`
  - carries `debugRecorder`
  - carries `debugStepper`

### Context and execution layer

- `Sources/Workspace/Context/Context.swift`
  - exposes `debugRecorder`
  - exposes `debugStepper`
  - exposes `variablesForDebug()`
  - carries `working_dir`

- `Sources/Workspace/Context/DebugUtils.swift`
  - central event emission adapter
  - records parser/runtime events
  - records file-generation metadata
  - captures base variable snapshots

- `Sources/Scripting/_Base_/TemplateStmtContainer.swift`
  - injects `debugStepper.willExecute(item:ctx:)` before every item executes

### Template/script parsing and execution layer

- `Sources/CodeGen/TemplateSoup/TemplateEvaluator.swift`
  - registers template source
  - emits template-parse and template-start events

- `Sources/Scripting/_Base_/ScriptFileExecutor.swift`
  - registers script source
  - emits script-parse and script-start events

- `Sources/Scripting/_Base_/Parsing/LineParser.swift`
  - emits line-level debug hooks such as line/skip/increment/end-of-block behavior

- `Sources/CodeGen/TemplateSoup/ContentLine/ContentHandler.swift`
  - emits `textContent`
  - emits inline-function-call events
  - emits inline-expression debug callbacks

- `Sources/Scripting/SoupyScript/ScriptParser.swift`
  - emits `statementDetected`

### Statement-level hook sites

- `Sources/Scripting/SoupyScript/Stmts/RenderFile.swift`
  - captures current variables
  - records `fileGenerated`
  - creates `GeneratedFileRecord`

- `Sources/Scripting/SoupyScript/Stmts/RenderFolder.swift`
  - emits rendered-folder events

- `Sources/Scripting/SoupyScript/Stmts/CopyFile.swift`
  - emits file-copy events

- `Sources/Scripting/SoupyScript/Stmts/CopyFolder.swift`
  - emits folder-copy events

- `Sources/Scripting/SoupyScript/Stmts/FillAndCopyFile.swift`
  - emits generated/skipped file events for placeholder-driven generation

- `Sources/Scripting/SoupyScript/Stmts/If.swift`
  - emits branch decisions

- `Sources/Scripting/SoupyScript/Stmts/SetVar.swift`
  - emits `workingDirChanged` when `working_dir` is updated

- `Sources/Scripting/SoupyScript/Stmts/SetStr.swift`
  - emits `workingDirChanged` when `working_dir` is updated

### Blueprint render/copy layer

- `Sources/CodeGen/TemplateSoup/_Base_/Blueprints/LocalFileBlueprint.swift`
  - emits generated/copied/skipped file events during local blueprint rendering

- `Sources/CodeGen/TemplateSoup/_Base_/Blueprints/ResourceBlueprint.swift`
  - emits generated/copied/skipped file events during resource blueprint rendering

### Snapshot and session layer

- `Sources/Debug/DebugRecorder.swift`
  - stores all recorder state
  - reconstructs variable state
  - serializes `DebugSession`

- `Sources/Debug/RenderedOutputSnapshot.swift`
  - walks retained `OutputFolder` trees and extracts in-memory rendered contents

## Core Data Types

### Debug events

`Sources/Debug/DebugEvent.swift`

`DebugEvent` is the main event enum. It includes:

- pipeline lifecycle events
- file generation and copy events
- working-directory changes
- control-flow decisions
- template and script lifecycle
- inline debugging output
- function/expression events
- variable mutation events
- parse-detail events
- error events

Each event is wrapped in `DebugEventEnvelope` from `Sources/Debug/DebugTypes.swift`, which adds:

- `sequenceNo`
- `timestamp`
- `containerName`

### Source mapping

`Sources/Debug/SourceFileMap.swift`

The visual debugger needs to show source files for templates and scripts. It therefore keeps a registry of source text in `SourceFileMap`.

Each `SourceFile` contains:

- `identifier`
- `fullPath`
- `content`
- `lineCount`
- `fileType`

Each event that can be source-linked may carry a `SourceLocation`:

- `fileIdentifier`
- `lineNo`
- `lineContent`
- `level`

### Debug session

`Sources/Debug/DebugSession.swift`

`DebugSession` is the JSON-serializable snapshot served to the browser. It contains:

- `timestamp`
- `config`
- `phases`
- `model`
- `events`
- `sourceFiles`
- `files`
- `errors`
- `baseSnapshots`
- `deltaSnapshots`

### Memory snapshots

`Sources/Debug/MemorySnapshot.swift`

The time-travel variable inspector is built from:

- `MemorySnapshot`
- `DeltaSnapshot`

`MemorySnapshot` stores:

- `label`
- `timestamp`
- `eventIndex`
- `variables`

`DeltaSnapshot` stores:

- `eventIndex`
- `variable`
- `oldValue`
- `newValue`

### Important structural note

The debug schema is larger than the currently emitted runtime behavior.

Some fields and event types are active in the implementation today; some exist as schema or scaffolding but are not yet wired through every runtime path.

## Event Index Semantics

`eventIndex` is currently stored as `Int`, and that is the correct type.

Why `Int` is correct:

- it is used as an index into Swift arrays
- the UI uses it directly against `session.events`
- the debug server exposes event-addressed APIs like `/api/memory/:eventIndex`

However, the semantics are subtle.

Current usage is not perfectly uniform:

- generated file records generally point at the actual event index of the generated-file event
- base snapshots are captured with `eventIndex: events.count`, which means "state valid after the first N events"

So today `eventIndex` should be read as a timeline coordinate, not always as "there is definitely an event stored exactly at this index with matching meaning".

This works, but it is a known conceptual sharp edge. If the system evolves further, it would be worth normalizing this so all `eventIndex` values follow one strict interpretation.

## Schema Versus Runtime Reality

The visual debugger has an important characteristic: the data model is ahead of the actual emitters.

That means `VISUALDEBUG.md` must distinguish between:

- schema that exists in types
- runtime behavior that is actually produced today

### Event cases currently defined but not fully or consistently emitted

Most high-value event cases are now actively emitted in the runtime. The remaining notable gaps are:

- `expressionEvaluated`
- `parseBlockStarted`

Important nuance:

- phase lifecycle is now represented in **both** `session.phases` and `session.events`
- runtime errors are captured in **both** `session.errors` and `session.events` (`error(...)`)
- diagnostics are emitted as `session.events[].event.diagnostic` and can also be queried via `/api/diagnostics`

### Recorder capabilities that exist but are only partially wired

The recorder exposes more than the runtime currently uses, but the core pathways are now wired:

- `captureDelta(...)` is wired for variable mutation and object-attribute mutation paths
- `captureError(...)` is wired in pipeline failure paths
- `setContainerName(...)` is set during container generation

The recorder still has room to grow:

- pause-time call stack serialization is not yet exposed in live stepping payloads
- expression-evaluation events are not yet captured consistently enough to support a full "watch expression history" UI

### Practical implication

A consumer of `DebugSession` should treat it as:

- reliable for template/script/file/window browsing
- reliable for variable reconstruction at event indices via base snapshots + deltas
- reliable for problem discovery via `error(...)` and `diagnostic(...)` events
- still partially scaffolded for full provenance and richer pause-time debugging

## Event Emission Matrix

This section records what the current system actually emits, and where.

### Actively emitted today

- `phaseStarted`
  - from `Pipeline.run`
- `phaseCompleted`
  - from `Pipeline.run`
- `phaseFailed`
  - from `Pipeline.run`
- `modelLoaded`
  - from `LoadModels`
- `templateParseStarted`
  - from `TemplateEvaluator`
- `templateStarted`
  - from `TemplateEvaluator`
- `templateCompleted`
  - from `TemplateEvaluator`
- `scriptParseStarted`
  - from `ScriptFileExecutor`
- `scriptStarted`
  - from `ScriptFileExecutor`
- `scriptCompleted`
  - from `ScriptFileExecutor`
- `statementDetected`
  - from `ScriptParser`
- `multiBlockDetected`
  - from `MultiBlockTemplateStmt+Config`
- `multiBlockFailed`
  - from `MultiBlockTemplateStmt+Config`
- `textContent`
  - from `ContentHandler`
- `functionCallEvaluated`
  - from `ContentHandler`
- `parsedTreeDumped`
  - from `ContextDebugLog.printParsedTree`
- `controlFlow`
  - from `If` statement execution paths
- `consoleLog`
  - from `ConsoleLog`
- `announce`
  - from `AnnnounceStmt`
- `workingDirChanged`
  - from `SetVar` / `SetStr`
- `variableSet`
  - from `Context.setValueOf(...)`
  - from `ObjectAttributeManager`
- `fileGenerated`
  - from `RenderFile`
  - from blueprint render-folder code paths
- `fileCopied`
  - from copy statements and blueprint copy paths
- `fileExcluded`
  - from parser-directive exclusion paths
- `fileRenderStopped`
  - from parser-directive stop-rendering paths
- `fileSkipped`
  - from "not generated" pathways
- `folderCopied`
  - from copy-folder paths
- `folderRendered`
  - from render-folder paths
- `fatalError`
  - from directive-driven error paths
- `diagnostic`
  - from validation, nil-condition warnings, variable-clear warnings, blueprint preflight, and other non-fatal reporting paths
- `error`
  - from pipeline catch blocks after `captureError(...)`
- `passSkipped`
  - from pipeline phase/pass gating
- `phaseSkipped`
  - from pipeline phase gating

### Not emitted consistently today

- `expressionEvaluated`
- `parseBlockStarted`

## How Source Registration Works

Source registration happens at template and script load time.

### Templates

`Sources/CodeGen/TemplateSoup/TemplateEvaluator.swift`

Before a template is executed:

- its full contents are converted into a `SourceFile`
- that file is registered with the recorder
- the template is parsed with a `LineParserDuringGeneration`

The registered template identifier is `template.name`.

### Scripts

`Sources/Scripting/_Base_/ScriptFileExecutor.swift`

Before a script is executed:

- its full contents are converted into a `SourceFile`
- that file is registered with the recorder
- the script is parsed with a `LineParserDuringGeneration`

The registered script identifier is `scriptFile.name`.

### Source locations on events

Most event-producing helpers in `ContextDebugLog` derive source locations from `ParsedInfo` using:

```swift
SourceLocation(fileIdentifier: pInfo.identifier, lineNo: pInfo.lineNo, lineContent: pInfo.line, level: pInfo.level)
```

This is what makes line highlighting in the browser possible.

### Important limitations of source registration

The source registry is useful, but it is not perfect.

#### 1. Only templates and scripts are actively registered

Even though `SourceFileType` supports:

- `.soupyScript`
- `.template`
- `.model`
- `.config`

the current runtime actively registers only:

- template files
- script files

Model files and config files are not currently registered into the debug session by the active pipeline paths.

#### 2. `fullPath` is usually `nil`

Template and script source registration currently stores the source text, but not a stable filesystem path.

That means source lookup is keyed mostly by logical identifier, not physical path.

#### 3. Identifiers can collide

`SourceFileMap` is keyed by `identifier`.

If two distinct templates or scripts register with the same identifier, the later one overwrites the earlier one.

In practice this matters because many source lookups are name-driven, not path-driven.

## How File Generation is Tracked

File generation has two related but distinct representations.

### 1. Event stream

The event stream records things like:

- `fileGenerated`
- `fileCopied`
- `fileExcluded`
- `fileSkipped`

These are useful for timeline inspection.

### 2. Generated file records

`GeneratedFileRecord` stores file-centric metadata:

- `outputPath`
- `templateName`
- `objectName`
- `workingDir`
- `eventIndex`

This is what the browser uses to build the left file tree and per-file windows.

The important point is that the file tree is not inferred solely from raw events. It is driven by `session.files`.

### Rename caveat in blueprint-driven generation

There is an important edge case when a template file is rendered with an output filename different from the source filename.

In both blueprint implementations, the debug record can be emitted using the template-side `filename` while the actual output object uses a derived `outputFilename`.

That means a generated-file record can occasionally drift from the actual output filename for front-matter-driven rename flows.

This does not break all browsing behavior, but it is a real mismatch point to be aware of.

## How Variable Time-Travel Works

The visual variable inspector is reconstructed, not continuously streamed.

Mechanism:

1. A base snapshot is captured at specific points
2. Variable mutation deltas are recorded with their `eventIndex`
3. When the browser asks for `/api/memory/:eventIndex`, the recorder reconstructs state by:
   - choosing the latest base snapshot at or before the requested event index
   - applying all deltas up to that event index

This logic lives in `DefaultDebugRecorder.reconstructState(atEventIndex:)`.

Current trade-offs:

- compact and simple
- good enough for interactive inspection
- not a full replay engine
- depends on capture points being placed usefully

### Actual fidelity today

The current time-travel system is much weaker than the schema suggests.

What is true today:

- base snapshots are captured at selected points, especially around file generation
- many values are stringified before storage
- broad delta tracking is not currently wired through all variable writes

So the current variable inspector is best understood as:

- a useful, approximate time-sliced variable view
- not a full faithful replay of runtime object state

In particular, booleans, numbers, arrays, wrappers, and actor-backed objects are not preserved with full fidelity once they pass through the serialized debug snapshot path.

## Model Snapshot Capture

The UI does not traverse live actors directly.

Instead, after the pipeline has run, the recorder captures a flattened `ModelSnapshot` tree containing:

- containers
- modules
- objects
- properties
- methods
- annotations
- tags
- APIs

This is served as plain JSON and rendered in the `Models` tab.

## Rendered Output Internals

Originally, the bottom "Generated Output" pane tried to read files back from disk.

That was fragile because:

- path resolution varied between absolute and output-root-relative values
- some files were not easy to resolve from `workingDir`
- the debugger should really show what the pipeline rendered, not what the filesystem currently contains

The current implementation uses in-memory rendered output snapshots instead.

### Snapshot generation

`Sources/Debug/RenderedOutputSnapshot.swift`

After `pipeline.run(using:)` completes, `DevMain` calls:

```swift
await pipeline.state.renderedOutputRecords()
```

That walks every retained generation sandbox and recursively traverses `base_generation_dir`.

It extracts rendered content from supported output file types:

- `TemplateRenderedFile`
- `StaticFile`
- `PlaceHolderFile`
- `OutputDocumentFile`

Each result is stored as `RenderedOutputRecord(path:content:)`.

### Why this is better

- it reflects the exact in-memory rendered content
- it is independent of later filesystem mutations
- it avoids path resolution bugs for many generated artifacts

### Supported output file types

The current snapshot extraction supports these output object types:

- `TemplateRenderedFile`
- `StaticFile`
- `PlaceHolderFile`
- `OutputDocumentFile`

If a future output file type stores content differently and is not added to `RenderedOutputSnapshot.swift`, it will not appear in the generated-output pane.

## Pipeline and Sandbox Relationship

The pipeline retains generation sandboxes in `PipelineState`.

Relevant pieces:

- `Pipeline.state.generationSandboxes`
- `RenderPhase.runIn(pipeline:)` creates a sandbox and appends it to pipeline state
- each `CodeGenerationSandbox` owns an `OutputFolder` tree rooted at `base_generation_dir`

This retained sandbox state is what enables the rendered-output snapshot extraction after the run.

### Why sandbox retention matters

Without retained generation sandboxes:

- the browser would have to reread the filesystem
- rendered output could diverge from what was actually rendered in memory
- generated-output debugging would become sensitive to persistence order and post-run mutations

The retained sandbox model is therefore not incidental. It is central to the current "rendered output from memory" design.

## Debug HTTP Server

`DevTester/DebugServer/DebugHTTPServer.swift`

The debug server is intentionally small and local-only.

### Transport

The server is built on **SwiftNIO** (not `Network.framework`):

- `ServerBootstrap` from `NIOPosix` binds the TCP port
- `NIOHTTPServerPipelineHandlerConfiguration` configures HTTP/1.1 parsing
- `NIOWebSocketServerUpgrader` handles `Upgrade: websocket` requests on any path, upgrading them to persistent WebSocket connections
- `HTTPChannelHandler` assembles full HTTP requests and dispatches to `DebugRouter`
- `WebSocketHandler` manages WebSocket lifecycle; registers clients in `handlerAdded(context:)` (not `channelActive`) because the handler is installed on an already-active pipeline after the HTTP→WebSocket upgrade

**Important implementation note — `handlerAdded` vs `channelActive`:**

In NIO, `channelActive` is not re-fired for handlers added to an already-active channel (which is the case for WebSocket upgrade handlers). Registration with `WebSocketClientManager` must happen in `handlerAdded(context:)`, which fires when a handler joins the pipeline regardless of channel state. Using `channelActive` for upgrade handlers causes silent client registration failures.

### WebSocket message protocol

Messages broadcast from the server to clients are JSON objects with a `type` field:

| Message type | When sent | Additional fields |
|---|---|---|
| `event` | After every `StreamingDebugRecorder.record(_:)` | `envelope` (contains `sequenceNo`, `timestamp`, `containerName`, `event`) |
| `completed` | When `StreamingDebugRecorder.broadcastCompleted()` is called | — |
| `paused` | When `LiveDebugStepper` hits a breakpoint, or when a new client connects while paused | `location`, `vars` |

Messages from client to server are JSON objects:

| Message type | Effect |
|---|---|
| `resume` | Calls `LiveDebugStepper.resume(mode:)` with the specified `mode` (`run`, `stepOver`, `stepInto`, `stepOut`) |
| `addBreakpoint` | Adds a location breakpoint (`fileIdentifier`, `lineNo` fields required) |
| `removeBreakpoint` | Removes a location breakpoint (`fileIdentifier`, `lineNo` fields required) |

**New client synchronization:** When a WebSocket client connects while execution is paused at a breakpoint, the server immediately sends the current `paused` message. This ensures late-joining clients display the correct state.

> **Full protocol reference:** See [`Docs/debug/WEBSOCKET_PROTOCOL.md`](WEBSOCKET_PROTOCOL.md) for comprehensive message formats, field definitions, sequence diagrams, and implementation details.

### Programmatic breakpoints (Swift)

Breakpoints can also be added programmatically in Swift code before or during pipeline execution. This is useful for:

- Setting up test breakpoints in `DevMain.swift`
- Creating automated debugging scenarios
- Pre-configuring breakpoints based on configuration

**API:**

```swift
// BreakpointLocation identifies a file and line
public struct BreakpointLocation: Hashable, Codable, Sendable {
    public let fileIdentifier: String  // e.g., "main.ss", "{{entity.name}}Controller.java"
    public let lineNo: Int
}

// LiveDebugStepper manages breakpoints and execution control
public actor LiveDebugStepper: DebugStepper {
    public func addBreakpoint(_ bp: BreakpointLocation)
    public func removeBreakpoint(_ bp: BreakpointLocation)
    public func resume(mode: StepMode = .run)
    public func setOnPause(_ callback: StepperPauseCallback?)
    public func getPauseState() -> PauseState?  // Returns current pause state if paused
}

// StepMode for resume behavior
public enum StepMode: String, Codable, Sendable {
    case run       // Continue until next breakpoint
    case stepOver  // Step over current item (semantics in progress)
    case stepInto  // Step into current item (semantics in progress)
    case stepOut   // Step out of current scope (semantics in progress)
}

// Snapshot of pause state (used for new client synchronization)
public struct PauseState: Sendable {
    public let location: SourceLocation
    public let vars: [String: String]
}
```

**Example — adding a test breakpoint in DevMain.swift:**

```swift
static func runCodebaseGenerationWithStepping() async throws {
    let wsManager = WebSocketClientManager()
    let streamingRecorder = StreamingDebugRecorder(wsManager: wsManager)
    let stepper = LiveDebugStepper()

    // Wire pause callback to broadcast over WebSocket
    await stepper.setOnPause { location, vars in
        await streamingRecorder.broadcastPaused(location: location, vars: vars)
    }

    // Add a programmatic breakpoint at main.ss line 10
    await stepper.addBreakpoint(BreakpointLocation(fileIdentifier: "main.ss", lineNo: 10))

    // ... continue with pipeline setup ...
}
```

When the pipeline reaches `main.ss:10`, execution will pause and a `paused` WebSocket message will be broadcast to all connected clients. The browser's stepper-panel will appear, allowing the user to resume.

**Finding valid file identifiers:**

File identifiers are the names used when templates/scripts are registered with the debug recorder. To find valid identifiers:

1. Run the pipeline once in `--debug` mode
2. Query `/api/session` and inspect `sourceFiles[].identifier`
3. Or check the session in the browser's debug console

Common identifiers include:
- `main.ss` — the blueprint entry-point script
- Template filenames like `{{entity.name}}Controller.java`
- Other `.teso` and `.ss` files in the blueprint

### HTTP caching policy

Responses include:

- `Cache-Control: no-store, no-cache, must-revalidate, max-age=0`
- `Pragma: no-cache`
- `Expires: 0`

This was added specifically because stale browser caches were causing the user to see old HTML and old API payloads after rapid debug-console iterations.

### Implemented endpoints

- `GET /`
  - serves `debug-console/index.html`
- `GET /api/session`
  - serves full `DebugSession`
- `GET /api/model`
  - serves `session.model`
- `GET /api/events`
  - serves `session.events`
- `GET /api/files`
  - serves `session.files`
- `GET /api/diagnostics`
  - serves a filtered problem-oriented view of `diagnostic(...)` and `error(...)` events; used by the Problems panel
- `GET /api/memory/:eventIndex`
  - reconstructs variable state
- `GET /api/source/:identifier`
  - serves registered source file contents
- `GET /api/generated-file/:index`
  - serves rendered generated-file content from in-memory snapshots
- `POST /api/evaluate`
  - evaluates an expression against reconstructed variables using `pipeline.render`
- `GET /api/mode`
  - returns `{ "mode": "postMortem" }` or `{ "mode": "stepping" }` depending on how the server was started
- `GET /ws` (or any path with `Upgrade: websocket`)
  - upgrades to a persistent WebSocket connection for live event streaming

### Exposed versus actively consumed endpoints

The server exposes more routes than the browser currently consumes.

Exposed:

- `/api/session`
- `/api/mode`
- `/api/model`
- `/api/events`
- `/api/files`
- `/api/diagnostics`
- `/api/memory/:eventIndex`
- `/api/source/:identifier`
- `/api/generated-file/:index`
- `/api/evaluate`
- `/ws`

Actively consumed by the debug console:

- `/api/session`
- `/api/mode`
- `/api/diagnostics`
- `/api/memory/:eventIndex`
- `/api/source/:identifier`
- `/api/generated-file/:index`
- `/api/evaluate`
- `/ws` (in stepping mode)

Currently unused by the debug console:

- `/api/model`
- `/api/events`
- `/api/files`

### Security and scope note

This server is a development utility, not a hardened debug service.

Current properties:

- no authentication
- permissive `Access-Control-Allow-Origin: *`
- simple local dev transport
- intended for short-lived local inspection

It should be treated as a developer-only local tool.

### Source lookup behavior

The source lookup path currently tries multiple strategies:

- exact identifier match
- slash-normalized match
- suffix/prefix match for nested identifiers
- extension-aware fallback for `.teso` and `.ss`

This exists because generated file records may refer to template names like:

- `graphql-schema-module`
- `plantuml.classes`
- `List{{entity.name | plural}}Query.java`

while registered source identifiers may include different suffixes or path forms.

### Source lookup heuristics are deliberate

The current source lookup logic is heuristic because identifier capture is not normalized everywhere.

The heuristics are compensating for real mismatches in:

- suffixes
- relative versus nested identifiers
- extensionless template references
- template names that themselves contain render expressions

## Browser UI Internals

`DevTester/Assets/debug-console/`

The UI is a modular browser app using Lit web components loaded from CDN. No build step is required.

### Architecture

The console is organized into:
- `index.html` - Entry point
- `components/` - 14 Lit web components (including `problems-panel.js` and `stepper-panel.js`)
- `utils/` - Pure utility functions (api, state, formatters)
- `styles/` - CSS split by concern (base, layout, themes)

See `DevTester/Assets/debug-console/README.md` for the full component hierarchy.

### Initial load

On load the root `<debug-app>` component:

1. fetches `/api/mode`
2. in post-mortem mode, fetches `/api/session`
3. stores state in centralized `state` (utils/state.js)
4. derives `state.fileWindows` from `session.files`
5. refreshes the Problems panel from `/api/diagnostics`
6. renders child components with reactive property binding

The UI is intentionally thin:

- it keeps most heavy data shaping client-side
- it uses the full session payload as its primary state source
- it lazily refetches only dynamic panes such as variables, source text, and rendered output

### Main client-side state

Important fields:

- `session`
- `selectedIndex`
- `fileWindows`
- `activeSidebarTab`
- `renderToken`
- `fileTreeFilterIndex`
- `lastVisibleFileCount`

`renderToken` is especially important:

- source-pane and generated-output requests use it to ignore stale async responses after rapid selection changes

The variable inspector does not currently use this same guard.

### File windows

The UI groups events by generated file using `session.files`.

For each generated file record, it computes:

- `startIndex`
- `endIndex`
- `eventCount`
- `controlFlowCount`
- `templateCount`

This lets the UI show a per-file event window instead of dumping all session events at once.

### Window attribution caveat

File windows are contiguous timeline slices bounded by generated-file records.

This is pragmatic, but it means:

- any event between file A's generation point and file B's generation point is attributed to file A's window
- this is timeline grouping, not perfect semantic ownership

### Left sidebar behavior

The left sidebar is the generated-files tree.

Current behavior:

- the visible tree is filtered by `fileTreeFilterIndex`
- `fileTreeFilterIndex` changes only when the timeline slider is dragged
- clicking a file changes `selectedIndex`, but does not re-filter the tree

This was introduced so file clicks do not cause later files to disappear from the tree.

Additional behavior:

- folder rows toggle collapse/expand
- file rows force the right sidebar back to `Trace`
- the tree is reconstructed on each render
- when the visible file count shrinks, the files sidebar scroll is reset to the top

### Left sidebar caveats

- folder expansion state is not preserved across rerenders
- the filter boundary can differ from the current selected event because only slider movement updates `fileTreeFilterIndex`
- the tree is derived from `session.files`, not from the raw event stream

### Source pane behavior

The top center pane shows template or script source.

Source resolution prefers:

1. `currentWindow.templateName`
2. event-derived `SourceLocation.fileIdentifier`

If a usable location is found, the UI requests `/api/source/:identifier` and highlights the relevant line when possible.

Important nuance:

- the source pane may prefer the current file window's template name over the currently selected event's actual source file
- this is useful for file-centric browsing, but it means the pane is not always a literal event-source viewer

### Generated output pane behavior

The bottom center pane requests `/api/generated-file/:index`.

It no longer depends on reading files from disk.

The server-side payload currently includes:

- original path from `GeneratedFileRecord`
- resolved in-memory rendered path
- full content
- line count

### Trace tab

The Trace tab renders the event stream for the currently selected file window.

Current capabilities:

- search by event label / source text
- filter by event type
- keyboard navigation
- automatic scroll-to-selection
- virtual scrolling so large sessions do not render thousands of DOM rows at once

The virtualized list uses a fixed row height plus buffered windowing, which keeps the browser responsive even for long sessions with dense event output.

### Variables tab

The variables inspector fetches `/api/memory/:eventIndex` and renders the reconstructed variable map in a simple table.

Current capabilities:

- search/filter by variable name or value
- optional display of `@system` variables
- paused-state variable view during live stepping
- reconstructed state from base snapshots + delta snapshots

Current limitations:

- values are flattened to strings in many cases
- there is no nested object viewer
- there is no diff view against prior events
- there is still no dedicated diff view against a previous selected event

### Problems tab

The Problems tab is the diagnostics-focused view of the debugger.

It prefers `GET /api/diagnostics` when available and falls back to scanning `session.events` for:

- `event.error`
- `event.diagnostic`

Current capabilities:

- severity badges (`error`, `warning`, `info`, `hint`)
- error/diagnostic code display
- source file + line display
- suggestion rendering
- keyboard-accessible rows
- click-through from a problem row to the corresponding trace event / source line

The Problems -> Trace/Source click-through behavior has been browser-verified against a real debug session by injecting a synthetic problem row tied to a real event index.

### Models tab

The models tab renders the flattened `ModelSnapshot` hierarchy from the session payload.

Backend snapshot data includes more than the UI currently shows:

- annotations
- tags
- APIs

The current browser tree focuses on:

- containers
- modules
- objects
- properties
- methods

## Live Stepping Status

Live stepping is enabled in `DevTester` behind `--debug-stepping`, but it is still only partially complete as a full interactive debugger.

### What exists

- `DebugStepper` protocol
- `LiveDebugStepper`
- breakpoint representation
- pause callback
- continuation-based suspension logic
- execution-loop integration in `GenericStmtsContainer.execute(with:)`
- `paused` WebSocket messages with source location and visible variables
- live event streaming through `StreamingDebugRecorder`
- browser keyboard shortcuts for continue / stepping actions
- pause-state sync for late-joining clients

That means the execution loop already calls:

```swift
if let stepper = await ctx.debugStepper {
    await stepper.willExecute(item: item, ctx: ctx)
}
```

### What is still incomplete

- `stepOver`, `stepInto`, and `stepOut` are wired end-to-end in the UI/protocol, but differentiated server-side stepping semantics are still incomplete
- there is no breakpoint gutter/list UI in the browser
- pause payloads do not yet include live stack frames
- conditional breakpoints are not implemented
- WebSocket ack/error protocol remains minimal

### WebSocket Protocol Reference

See [`Docs/debug/WEBSOCKET_PROTOCOL.md`](WEBSOCKET_PROTOCOL.md) for the full message format specification, including:

- Server → Client messages: `event`, `paused`, `completed`
- Client → Server messages: `resume`, `addBreakpoint`, `removeBreakpoint`
- Programmatic breakpoint API in Swift
- New-client synchronization behavior
- Sequence diagram

### What the `--debug` mode installs

`DevMain --debug` sets:

```swift
config.debugStepper = NoOpDebugStepper()
```

So the `--debug` experience is post-mortem only; the stepper is a no-op.

### What `--debug-stepping` mode installs

`DevMain --debug-stepping` sets:

```swift
config.debugRecorder = StreamingDebugRecorder(wsManager: wsManager)
config.debugStepper = stepper   // LiveDebugStepper
await stepper.setOnPause { location, vars in
    await streamingRecorder.broadcastPaused(location: location, vars: vars)
}
```

This makes live event streaming fully active. Clients that connect to `/ws` receive all events in real time and are notified on pause/completion.

### Additional implementation caveats

`LiveDebugStepper` stepping semantics are partially implemented:

Current state:

- stores `mode`
- supports breakpoint sets
- exposes `setOnPause` (wired to `broadcastPaused` in stepping mode)
- suspends on exact file+line breakpoint matches

Still incomplete:

- `mode` is not yet used to implement true `stepOver`/`stepInto`/`stepOut` semantics
- the browser has a `stepper-panel` UI with buttons, but the server currently treats all resume commands identically (unconditional `resume()`)

## Tests

There is test coverage for the core data model and recorder behavior:

- `Tests/Debug/DebugRecorder_Tests.swift`
- `Tests/Debug/DebugSession_Tests.swift`
- `Tests/Debug/ModelSnapshot_Tests.swift`

Current test coverage verifies:

- event recording and state reconstruction
- debug session Codable behavior
- model snapshot structure and JSON encoding

Current notable gap:

- there are no tests for the HTTP server
- there are no tests for the debug console components
- there are no end-to-end tests for source lookup or generated-output panes
- there are no tests for rendered-output snapshot extraction
- there are no tests for source-identifier heuristic matching
- there are no tests for live stepping behavior or WebSocket broadcasting

## Current Limitations

### Post-mortem by default

The system is not yet a fully live debugger. It is a run-capture-browse debugger.

### Session is process-local

There is no session persistence across runs. Restarting `DevTester` creates a new in-memory session.

### Event-index semantics are slightly mixed

As described earlier, `eventIndex` is correct as `Int`, but its meaning is not perfectly normalized across all snapshot-producing paths.

### Source matching is heuristic in places

Source lookup currently uses normalization and extension-aware fallback. This is practical, but it means file-template naming conventions still matter.

### Source registration is incomplete

Model and config source files are not currently part of the active source-registration path, even though the schema supports them.

### Error capture is only partially structured

The schema supports structured errors, but many actual runtime failures are still surfaced primarily through pipeline error printing rather than `session.errors`.

### Event ordering is not fully synchronized

Some debug recorder writes are intentionally fire-and-forget `Task` calls. That keeps instrumentation lightweight, but it means strict ordering and flush guarantees are weaker than they would be with fully awaited recording.

### Stepping semantics are partially implemented

The WebSocket infrastructure is complete and events stream live in `--debug-stepping` mode. However `stepOver`/`stepInto`/`stepOut` are not yet semantically differentiated from `resume` — all resume commands cause unconditional continuation.

### Source-file identity can collide

Because `SourceFileMap` is keyed by identifier and source files are often registered with `fullPath: nil`, same-named files can overwrite one another.

## Troubleshooting

### The UI looks stale after changes

Possible causes:

- an older debug server is still running on the same port
- the browser cached old HTML or old API responses

Mitigations already in place:

- `--debug-dev` serves the HTML directly from `DevTester/Assets`
- HTTP responses now use `no-store` cache headers

Recommended workflow during development:

1. stop stale `DevTester` processes
2. run a fresh `swift run DevTester --debug --debug-dev --no-open`
3. reopen the URL

### "Source not found"

Check these first:

- is the file coming from a template or script that was registered as a source file
- does the generated file record have a meaningful `templateName`
- does the source identifier require `.teso` or `.ss` extension-aware fallback
- are multiple same-named templates/scripts colliding in the source registry

### Generated output missing

Today the generated output endpoint serves from in-memory rendered snapshots, not disk. If this fails, the likely issue is that the relevant output file type was not included in `RenderedOutputSnapshot.swift`.

## Extension Points

If this system is extended further, the most natural next steps are:

- normalize `eventIndex` semantics
- add HTTP/API tests
- differentiate `stepOver`/`stepInto`/`stepOut` semantics in `LiveDebugStepper`
- normalize source-file identity around stable full paths instead of name heuristics
- wire model/config source registration into the active debug session
- wire structured error capture into failure paths
- wire variable deltas into actual mutation sites
- preserve UI pane sizes and active tabs in local storage
- expose event filtering controls in the UI
- add explicit source-path metadata instead of relying heavily on matching heuristics

## File Map

Important current files:

**Documentation:**
- `Docs/debug/VISUALDEBUG.md` — this file; architecture and troubleshooting
- `Docs/debug/WEBSOCKET_PROTOCOL.md` — comprehensive WebSocket debugging protocol reference
- `DevTester/Assets/debug-console/README.md` — browser UI component documentation

**DevTester:**
- `DevTester/DevMain.swift`
- `DevTester/DebugServer/DebugHTTPServer.swift`
- `DevTester/DebugServer/DebugRouter.swift`
- `DevTester/DebugServer/HTTPChannelHandler.swift`
- `DevTester/DebugServer/WebSocketClientManager.swift`
- `DevTester/DebugServer/WebSocketHandler.swift`
- `DevTester/DebugServer/StreamingDebugRecorder.swift`
- `DevTester/Assets/debug-console/` (modular Lit web components)
- `Sources/Debug/DebugRecorder.swift`
- `Sources/Debug/DebugSession.swift`
- `Sources/Debug/DebugEvent.swift`
- `Sources/Debug/MemorySnapshot.swift`
- `Sources/Debug/SourceFileMap.swift`
- `Sources/Debug/RenderedOutputSnapshot.swift`
- `Sources/Debug/DebugStepper.swift`
- `Sources/Debug/LiveDebugStepper.swift`
- `Sources/Debug/NoOpDebugStepper.swift`
- `Sources/Workspace/Context/DebugUtils.swift`
- `Sources/CodeGen/TemplateSoup/TemplateEvaluator.swift`
- `Sources/Scripting/_Base_/ScriptFileExecutor.swift`
- `Sources/Scripting/_Base_/TemplateStmtContainer.swift`
- `Sources/Pipelines/Pipeline.swift`
- `Sources/Pipelines/PipelinePhase.swift`
- `Sources/Pipelines/PipelineConfig.swift`
- `Sources/Workspace/Context/Context.swift`
- `Sources/Workspace/Sandbox/CodeGenerationSandbox.swift`
- `Sources/CodeGen/TemplateSoup/_Base_/Blueprints/LocalFileBlueprint.swift`
- `Sources/CodeGen/TemplateSoup/_Base_/Blueprints/ResourceBlueprint.swift`
- `Sources/Scripting/SoupyScript/Stmts/RenderFile.swift`
- `Sources/Scripting/SoupyScript/Stmts/RenderFolder.swift`
- `Sources/Scripting/SoupyScript/Stmts/CopyFile.swift`
- `Sources/Scripting/SoupyScript/Stmts/CopyFolder.swift`
- `Sources/Scripting/SoupyScript/Stmts/FillAndCopyFile.swift`
- `Sources/Scripting/SoupyScript/Stmts/If.swift`
- `Sources/Scripting/SoupyScript/Stmts/SetVar.swift`
- `Sources/Scripting/SoupyScript/Stmts/SetStr.swift`
- `Sources/Scripting/_Base_/Parsing/LineParser.swift`
- `Sources/CodeGen/TemplateSoup/ContentLine/ContentHandler.swift`
- `Sources/Scripting/SoupyScript/ScriptParser.swift`

## Summary

The current visual debugging system is a structured post-run debugger layered onto the existing ModelHike execution model.

Its most important design choices are:

- capture debug data as structured events instead of relying on stdout
- snapshot source text so template/script source can be shown in the browser
- reconstruct variable state from base snapshots, with delta support scaffolded but not yet broadly wired
- derive file-centric browsing views from `GeneratedFileRecord`
- serve rendered outputs from the in-memory output tree instead of disk
- provide `--debug-stepping` mode with live WebSocket event streaming and a `stepper-panel` UI; full `stepOver`/`stepInto`/`stepOut` semantics still in progress
- expose a schema that is slightly ahead of the currently emitted runtime behavior

That makes it useful as a practical debugging console. The `--debug-stepping` mode adds live event streaming over WebSocket, and the `stepper-panel` UI is ready to drive stepping once the full `stepOver`/`stepInto`/`stepOut` semantics are wired into `LiveDebugStepper`.
