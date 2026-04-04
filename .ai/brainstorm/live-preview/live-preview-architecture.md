# Live Preview Architecture — Library vs. CLI Split

> **Status:** Architecture Decision / Brainstorm  
> **Date:** 2026-04-04  
> **Goal:** Deeply analyze every component of the Live Preview system and determine whether it belongs in the pure `ModelHike` Swift library or in the future `ModelHike CLI` project.

---

## Table of Contents

1. [The Guiding Principle](#1-the-guiding-principle)
2. [Hard Constraints From the Codebase](#2-hard-constraints-from-the-codebase)
3. [Component Placement Matrix](#3-component-placement-matrix)
4. [Part 1: The `ModelHike` Library — What Goes In](#4-part-1-the-modelhike-library--what-goes-in)
    - 4.1 [Model Snapshotting](#41-model-snapshotting)
    - 4.2 [Model Diffing](#42-model-diffing)
    - 4.3 [Mock Data Generation (`MockResponseBuilder`)](#43-mock-data-generation-mockresponsebuilder)
    - 4.4 [Mock Route Derivation](#44-mock-route-derivation)
    - 4.5 [Mock Request Validation](#45-mock-request-validation)
    - 4.6 [Preview Protocol Definitions (Message Shapes)](#46-preview-protocol-definitions-message-shapes)
    - 4.7 [`FileWatcher` Protocol](#47-filewatcher-protocol)
    - 4.8 [Default UI Detection Logic](#48-default-ui-detection-logic)
    - 4.9 [Debounce Utility](#49-debounce-utility)
    - 4.10 [`PreviewCoreOptions`](#410-previewcoreoptions)
    - 4.11 [`BuildSession` (From Incremental Builds)](#411-buildsession-from-incremental-builds)
5. [Part 2: The `ModelHike CLI` Project — What Goes Out](#5-part-2-the-modelhike-cli-project--what-goes-out)
    - 5.1 [`PreviewSession` Orchestrator](#51-previewsession-orchestrator)
    - 5.2 [`FileWatcher` Implementation (FSEvents / DispatchSource)](#52-filewatcher-implementation-fsevents--dispatchsource)
    - 5.3 [Preview & Mock HTTP Server (SwiftNIO)](#53-preview--mock-http-server-swiftnio)
    - 5.4 [Process Manager (Framework Dev Servers)](#54-process-manager-framework-dev-servers)
    - 5.5 [Preview UI Assets (HTML/JS/CSS)](#55-preview-ui-assets-htmljscss)
    - 5.6 [`PreviewConfig` and CLI Argument Parsing](#56-previewconfig-and-cli-argument-parsing)
    - 5.7 [Blueprint Dev-Server Configuration Parsing](#57-blueprint-dev-server-configuration-parsing)
    - 5.8 [WebSocket Broadcast Infrastructure](#58-websocket-broadcast-infrastructure)
    - 5.9 [Browser Auto-Open](#59-browser-auto-open)
6. [Remaining Gray Areas](#6-remaining-gray-areas)
7. [Why `PreviewSession` Is CLI, Not Library](#7-why-previewsession-is-cli-not-library)
8. [Concrete API Boundary](#8-concrete-api-boundary)
    - 8.1 [What the CLI Imports From the Library](#81-what-the-cli-imports-from-the-library)
    - 8.2 [Loop 1 Integration Sketch](#82-loop-1-integration-sketch)
    - 8.3 [Loop 2 Integration Sketch](#83-loop-2-integration-sketch)
9. [Swift 6 Sendable Constraints](#9-swift-6-sendable-constraints)
10. [Relationship to `DevTester` and Migration Path](#10-relationship-to-devtester-and-migration-path)
11. [Testing Strategy for the Split](#11-testing-strategy-for-the-split)
12. [Cross-References](#12-cross-references)

---

## 1. The Guiding Principle

The `ModelHike` library has a strict architectural constraint: **Zero external SwiftPM dependencies**. It must remain a pure, deterministic, cross-platform data transformation engine (Text → AST → Code).

The `ModelHike CLI` (and any future IDE plugins, VS Code extensions, or build system integrations) will be **consumers** of this library. The CLI is allowed to have external dependencies (`SwiftNIO` for web servers, `ArgumentParser` for CLI flags, OS-specific file watchers, process management, etc.).

The split is defined by a simple test:

> **Does this component require I/O, networking, OS process management, or an external SwiftPM dependency?**
> - **Yes** → CLI
> - **No** → Library (pure computation on model data)

A secondary heuristic:

> **Could an IDE plugin, a SwiftPM build plugin, or a test suite use this without bringing in SwiftNIO?**
> - **Yes** → Library
> - **No** → CLI

---

## 2. Hard Constraints From the Codebase

### 2.1 Zero External Dependencies on `ModelHike` Target

`Package.swift` only adds `SwiftNIO` dependencies to the `DevTester` executable target. The `ModelHike` library target has zero external packages. This constraint is documented in `AGENTS.md` and must be preserved.

Anything that requires `import NIOCore`, `import NIOHTTP1`, `import NIOWebSocket`, or `import NIOPosix` **cannot** live in the library.

### 2.2 `OutputConfig` Is a Public Protocol

`OutputConfig` (in `Sources/Pipelines/PipelineConfig.swift`) is a `public protocol` used in 30+ locations. Adding required properties is a breaking change. The incremental builds architecture doc already recommends using **protocol extension defaults** for non-breaking evolution. The same approach applies to any preview-related config.

### 2.3 All Model Types Are Actors

`AppModel`, `C4Container`, `C4Component`, `DomainObject`, `Property`, `MethodObject`, etc. are all `actor`s. Serializing them to JSON requires `await` on every property access. A synchronous `Codable` conformance won't work. This drives the snapshot-struct design (§4.1).

### 2.4 `ParsedTypesCache` and `AppModel` Are Append-Only

As analyzed in the brainstorm, `ParsedTypesCache` and `AppModel` only support `append()`. There is no `remove()` or `replace()`. This means Loop 1 must do a full re-parse (creating a fresh `AppModel`), not a selective re-parse.

### 2.5 `SampleJson` Generates Incomplete Mock Data

`SampleJson.swift` only iterates required properties (`prop.required == .yes`), excludes `id` fields, and produces hand-crafted string templates rather than `JSONEncoder` output. The `MockResponseBuilder` (§4.3) wraps this with full-property support.

### 2.6 Swift 6 Strict Concurrency

The project uses `swift-tools-version: 6.2` with strict concurrency. All public types must be `Sendable`. `[String: Any]` is **not** `Sendable`. This impacts `MockResponseBuilder`'s public API shape (see §9).

---

## 3. Component Placement Matrix

| Component | Placement | Reason |
|-----------|-----------|--------|
| Model Snapshotting (`AppModelSnapshot`) | **Library** | Pure `async` data extraction from actors → `Codable` structs |
| Model Diffing (`ModelDiff`, `computeDiff`) | **Library** | Pure comparison of two snapshot structs |
| Mock Data Generation (`MockResponseBuilder`) | **Library** | Generates `MockValue` trees and response bytes from model data |
| Stateful Mock Store (`MockStateStore`) | **Library** | Optional in-memory CRUD engine keyed by entity; transport-neutral runtime logic |
| Mock Route Derivation (`MockRouteTable`) | **Library** | Maps `Entity → API → HTTP method + path`; pure model introspection |
| Mock Request Validation | **Library** | Validates request body against model schema; pure expression evaluation |
| Preview Protocol Types (message shapes) | **Library** | Defines the JSON contract for WebSocket/REST communication |
| `FileWatcher` protocol | **Library** | Reusable abstraction; implementations are CLI |
| `FileChangeEvent`, `FileChangeKind` | **Library** | Value types used by the protocol |
| Default UI detection logic | **Library** | Inspects `#blueprint(name)` tags + container metadata; pure model query |
| Debounce utility | **Library** | Generic `Sendable` timer-based coalescing; useful in tests and IDE plugins |
| `PreviewCoreOptions` | **Library** | Pure preview behavior knobs (`mockDataSeed`, route mode, list count, mock mode) reusable by IDE plugins and tests |
| `BuildSession` (from incremental builds) | **Library** | Already decided in `incremental-builds-architecture.md` §4.3.4 |
| `PreviewSession` orchestrator | **CLI** | Owns NIO server, file watcher impl, process manager — all I/O |
| `FileWatcher` implementation (FSEvents) | **CLI** | OS-specific API (`DispatchSource`, `FSEvents`, `inotify`) |
| Mock API HTTP Server | **CLI** | Requires `SwiftNIO` for HTTP routing + TCP |
| WebSocket broadcast infrastructure | **CLI** | Requires `NIOWebSocket` |
| Preview server routing / connection policy | **CLI** | `/preview/*` prefix handling and `Connection: keep-alive` live in NIO router/handler code |
| Process Manager | **CLI** | `Foundation.Process` execution, stdout piping |
| Infra provisioner (`docker compose`, in-memory DB profiles) | **CLI** | Starts/stops external services for real-server mode |
| Preview UI assets (HTML/JS/CSS) | **CLI** | Presentation layer, bundled with executable |
| `PreviewConfig` struct | **CLI** | Wrapper over `PreviewCoreOptions` plus port, browser, watch paths, real-server settings, and derived `PipelineConfig` |
| CLI argument parsing (`--preview`, `--real`) | **CLI** | `ArgumentParser` or manual parsing |
| Blueprint dev-server config parsing | **CLI** | Reads `dev-command`, `dev-ready-pattern` from `main.ss` front matter |
| Browser auto-open (`NSWorkspace.shared.open`) | **CLI** | OS-specific |

---

## 4. Part 1: The `ModelHike` Library — What Goes In

### 4.1 Model Snapshotting

**Location:** `Sources/Modelling/Preview/` (new directory)

The library needs a way to serialize the actor-based `AppModel` into plain `Codable`, `Sendable` structs. This is the foundation for diffing, JSON serialization to the preview UI, and WebSocket payloads.

```swift
public struct AppModelSnapshot: Codable, Sendable, Equatable {
    public let systems: [SystemSnapshot]
    public let containers: [ContainerSnapshot]
    public let commonTypes: [CodeObjectSnapshot]

    public init(from model: AppModel) async { ... }
}

public struct ContainerSnapshot: Codable, Sendable, Equatable {
    public let name: String
    public let givenname: String
    public let containerType: String
    public let modules: [ModuleSnapshot]
    public let tags: [String]
}

public struct ModuleSnapshot: Codable, Sendable, Equatable {
    public let name: String
    public let givenname: String
    public let entities: [EntitySnapshot]
    public let dtos: [EntitySnapshot]
    public let port: Int?
}

public struct EntitySnapshot: Codable, Sendable, Equatable {
    public let name: String
    public let givenname: String
    public let dataType: String                    // entity, dto, cache, apiInput, etc.
    public let properties: [PropertySnapshot]
    public let methods: [MethodSnapshot]
    public let apis: [APISnapshot]
    public let mixinNames: [String]
    public let tags: [String]
}

public struct PropertySnapshot: Codable, Sendable, Equatable {
    public let name: String
    public let givenname: String
    public let typeKind: String
    public let isArray: Bool
    public let required: String                    // yes, no, conditional
    public let isUnique: Bool
    public let defaultValue: String?
    public let validValueSet: [String]
    public let constraints: [String]
    public let tags: [String]
}

public struct MethodSnapshot: Codable, Sendable, Equatable {
    public let name: String
    public let parameters: [MethodParameterSnapshot]
    public let returnType: String?
    public let hasLogic: Bool
}

public struct MethodParameterSnapshot: Codable, Sendable, Equatable {
    public let name: String
    public let type: String
    public let required: String
    public let isOutput: Bool
    public let defaultValue: String?
}

public struct APISnapshot: Codable, Sendable, Equatable {
    public let type: String                        // "create", "list", "getById", etc.
    public let path: String?
    public let httpMethod: String                   // derived from APIType
    public let queryParams: [String]?
}

public struct SystemSnapshot: Codable, Sendable, Equatable {
    public let name: String
    public let givenname: String
    public let description: String?
    public let infraNodes: [InfraNodeSnapshot]
    public let groups: [VirtualGroupSnapshot]
    public let containerNames: [String]
}

public struct InfraNodeSnapshot: Codable, Sendable, Equatable {
    public let name: String
    public let type: String
    public let properties: [String: String]
}

public struct VirtualGroupSnapshot: Codable, Sendable, Equatable {
    public let name: String
    public let containerRefs: [String]
    public let subGroups: [VirtualGroupSnapshot]
}
```

**Why library:** These are pure data transformations. An IDE plugin could snapshot the model without any NIO dependency.

### 4.2 Model Diffing

**Location:** `Sources/Modelling/Preview/`

Given two `AppModelSnapshot`s, compute what changed.

```swift
public struct ModelDiff: Codable, Sendable {
    public let addedEntities: [String]
    public let removedEntities: [String]
    public let modifiedEntities: [String]
    public let addedContainers: [String]
    public let removedContainers: [String]
    public let addedAPIs: [String]
    public let removedAPIs: [String]

    public static func compute(old: AppModelSnapshot?, new: AppModelSnapshot) -> ModelDiff { ... }
}
```

**Implementation:** Compare entity names and `Equatable` snapshots. If an entity exists in both but `oldEntity != newEntity`, it's modified. If only in new, it's added. If only in old, it's removed. Similarly for containers and APIs.

**Why library:** Pure comparison of `Equatable` structs. No I/O.

### 4.3 Mock Data Generation (`MockResponseBuilder`)

**Location:** `Sources/CodeGen/MockData/`

Wraps the existing `SampleJson` infrastructure to produce complete, valid JSON for mock API responses.

```swift
public enum MockValue: Codable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
    case array([MockValue])
    case object([String: MockValue])
}

public struct MockResponseBuilder: Sendable {
    public let typesCache: ParsedTypesCache

    public init(typesCache: ParsedTypesCache) { ... }

    /// Full JSON dictionary for an entity, including ALL properties (not just required).
    public func objectValue(for entity: CodeObject, includeId: Bool = true, seed: Int? = nil) async -> [String: MockValue] { ... }

    /// Array of N JSON dictionaries for list APIs.
    public func arrayValue(for entity: CodeObject, count: Int = 5, seed: Int? = nil) async -> [[String: MockValue]] { ... }

    /// Serialized Data for an HTTP response body.
    public func responseData(for entity: CodeObject, apiType: APIType, seed: Int? = nil) async throws -> Data { ... }
}
```

**Key differences from `SampleJson`:**
- Iterates **all** properties (not just `required == .yes`)
- Includes `id` fields in response objects
- Uses `MockValue`, a `Codable` + `Sendable` JSON-safe value enum
- Wraps arrays for list APIs
- Uses a `seed` for deterministic output (testable)

**Why library:** Derives data from `PropertyKind`, `ParsedTypesCache`, and model constraints. Pure computation.

Stateful mode should also be owned by the library, not reimplemented inside the HTTP server:

```swift
public struct MockEntityKey: Hashable, Codable, Sendable {
    public let containerName: String
    public let modulePath: [String]
    public let entityName: String
}

public actor MockStateStore {
    public init() {}

    public func seed(entity: MockEntityKey, values: [[String: MockValue]]) async { ... }
    public func list(entity: MockEntityKey) async -> [[String: MockValue]] { ... }
    public func get(entity: MockEntityKey, id: String) async -> [String: MockValue]? { ... }
    public func create(entity: MockEntityKey, value: [String: MockValue]) async -> [String: MockValue] { ... }
    public func update(entity: MockEntityKey, id: String, value: [String: MockValue]) async -> [String: MockValue]? { ... }
    public func delete(entity: MockEntityKey, id: String) async -> Bool { ... }
    public func invalidate(entity: MockEntityKey) async { ... }
    public func resetAll() async { ... }
}
```

**Final decision:** the transport-neutral CRUD engine (`MockStateStore`) belongs in the library. The CLI decides:
- whether preview runs in `.stateless` or `.statefulInMemory` mode
- when to call `invalidate(entity:)` after a `ModelDiff`
- whether mock state should be discarded on restart or persisted externally

If a future tool wants persisted mock state across process restarts, the persistence layer is CLI/tool territory. The in-memory store itself stays in the library.

### 4.4 Mock Route Derivation

**Location:** `Sources/Modelling/Preview/`

The pure logic that maps the model's entity + API metadata to HTTP endpoints.

```swift
public struct MockRoute: Codable, Sendable {
    public let httpMethod: String              // GET, POST, PUT, DELETE, PATCH
    public let path: String                    // /mock/{module}/{entity}, /mock/{module}/{entity}/:id
    public let apiType: String                 // "create", "list", "getById", etc.
    public let entityName: String
    public let moduleName: String
    public let containerName: String
}

public struct MockRouteTable: Sendable {
    public let routes: [MockRoute]

    /// Derives all mock routes from the model snapshot.
    public static func derive(from snapshot: AppModelSnapshot) -> MockRouteTable { ... }

    /// Finds the matching route for a given HTTP method and path.
    public func match(method: String, path: String) -> MockRoute? { ... }
}
```

**Why library:** This is pure model introspection — iterating containers → modules → entities → APIs and mapping `APIType` to HTTP method. The CLI's NIO handler calls `routeTable.match(method:path:)` and then calls `MockResponseBuilder` to generate the body. No networking involved in the derivation itself.

### 4.5 Mock Request Validation

**Location:** `Sources/Modelling/Preview/`

Validates an incoming request body against the entity's schema using model metadata.

```swift
public struct ValidationResult: Codable, Sendable {
    public let isValid: Bool
    public let errors: [ValidationError]
}

public struct ValidationError: Codable, Sendable {
    public let field: String
    public let message: String
    public let code: String                    // "required", "type_mismatch", "invalid_value", "constraint_violated"
}

public struct MockRequestValidator: Sendable {
    public let typesCache: ParsedTypesCache

    /// Validates a JSON body against the entity's property schema.
    public func validate(body: [String: MockValue], for entity: CodeObject, apiType: APIType) async -> ValidationResult { ... }
}
```

**Validates:**
- `required` properties are present
- `validValueSet` constraints are respected
- Type checking (string for string fields, number for int fields, etc.)
- Property-level `constraints` (min, max, etc.) — uses the existing expression evaluator

**Why library:** All validation logic is already in the library (`Property.required`, `Property.validValueSet`, `Property.constraints`, `ExpressionEvaluator`). The mock server just calls this function and maps the result to an HTTP 400.

### 4.6 Preview Protocol Definitions (Message Shapes)

**Location:** `Sources/Modelling/Preview/`

Defines the WebSocket message contract so that CLI, IDE plugins, and the browser UI all agree on the format.

```swift
// Server → Client messages
public enum PreviewServerMessage: Codable, Sendable {
    case modelUpdated(diff: ModelDiff, snapshot: AppModelSnapshot)
    case codegenStarted(containersAffected: [String])
    case codegenCompleted(stats: IncrementalStats, filesChanged: [String])
    case buildError(phase: String?, message: String, diagnostics: [PreviewDiagnostic])
    case realServerStarting(framework: String, command: String)
    case realServerReady(port: Int, baseUrl: String)
    case realServerError(error: String, stdout: String, stderr: String)
    case fileChangeDetected(path: String, kind: String)
}

// Client → Server messages
public enum PreviewClientMessage: Codable, Sendable {
    case switchBackend(target: String)         // "mock" or "real"
    case forceRebuild
    case setMockSeed(seed: Int)
}

public struct PreviewDiagnostic: Codable, Sendable {
    public let severity: String
    public let code: String?
    public let message: String
    public let fileIdentifier: String?
    public let lineNo: Int?
}
```

**Why library:** These are just `Codable` structs/enums. No I/O. Defining them in the library ensures every consumer (CLI WebSocket, IDE plugin, test harness) encodes/decodes the exact same format.

### 4.7 `FileWatcher` Protocol

**Location:** `Sources/Modelling/Preview/` or `Sources/_Common_/`

The **protocol** lives in the library. The **implementation** lives in the CLI.

```swift
public protocol FileWatcher: Sendable {
    func watch(
        paths: [LocalPath],
        extensions: Set<String>,
        onChange: @escaping @Sendable (FileChangeEvent) async -> Void
    ) async throws

    func stop() async
}

public enum FileChangeKind: String, Codable, Sendable {
    case modified
    case created
    case deleted
    case renamed
}

public struct FileChangeEvent: Sendable {
    public let path: LocalPath
    public let kind: FileChangeKind
    public let timestamp: Date
}
```

**Why library:** The protocol is a reusable abstraction. A test suite can provide a `MockFileWatcher` that fires synthetic events. An IDE plugin can provide its own implementation using the editor's file-watching API. Only the concrete `FSEventsFileWatcher` / `DispatchSourceFileWatcher` belongs in the CLI.

### 4.8 Default UI Detection Logic

**Location:** `Sources/Modelling/Preview/`

Determines whether a container needs the default preview UI (no UI blueprint present).

```swift
public struct PreviewUIDecision: Sendable {
    public let containerName: String
    public let needsDefaultUI: Bool
    public let reason: String
}

public func detectDefaultUIContainers(from snapshot: AppModelSnapshot, blueprintMetadata: [String: BlueprintMeta]?) -> [PreviewUIDecision] { ... }

public struct BlueprintMeta: Codable, Sendable {
    public let name: String
    public let type: String?                   // "api", "ui", nil
}
```

**Detection priority (from `live-preview.md` §14.1):**
1. Explicit blueprint metadata (`type: ui` / `type: api`) if available.
2. Naming convention (`ui-*`, `web-*`, `mobile-*`).
3. Container type fallback (`.webApp` / `.mobileApp` → has UI).

**Why library:** Pure model inspection. No I/O.

### 4.9 Debounce Utility

**Location:** `Sources/_Common_/Utils/`

A generic, `Sendable` debounce helper that coalesces rapid calls.

```swift
public actor Debouncer {
    private let delayMs: Int
    private var pendingTask: Task<Void, Never>?

    public init(delayMs: Int) { ... }

    public func debounce(_ action: @escaping @Sendable () async -> Void) {
        pendingTask?.cancel()
        pendingTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
            guard !Task.isCancelled else { return }
            await action()
        }
    }
}
```

**Why library:** No external dependencies. Tests and IDE plugins benefit from the same debouncing logic. The CLI uses two instances: one for Loop 1 (150ms) and one for Loop 2 (500ms).

### 4.10 `PreviewCoreOptions`

**Location:** `Sources/Modelling/Preview/`

`PreviewCoreOptions` is the library-owned configuration for transport-neutral preview behavior.

```swift
public enum MockMode: String, Codable, Sendable {
    case stateless
    case statefulInMemory
}

public enum MockRouteMode: String, Codable, Sendable {
    case canonicalOnly
    case canonicalPlusBlueprintAliases
}

public struct PreviewCoreOptions: Sendable {
    public let mockDataSeed: Int?
    public let defaultListCount: Int
    public let mockMode: MockMode
    public let routeMode: MockRouteMode
}
```

**Why library:** none of these options require ports, browser behavior, watch paths, or OS integration. They are pure preview behavior knobs and therefore reusable by tests, IDE plugins, and any future non-CLI consumers.

### 4.11 `BuildSession` (From Incremental Builds)

Already decided in `incremental-builds-architecture.md` §4.3.4: `BuildSession` lives in the **library**. It is the stateful coordinator for repeated in-process builds (Loop 2). The `PreviewSession` in the CLI owns a `BuildSession` instance.

---

## 5. Part 2: The `ModelHike CLI` Project — What Goes Out

### 5.1 `PreviewSession` Orchestrator

The `PreviewSession` actor is the top-level coordinator. It owns I/O-heavy components that require external dependencies (NIO server, OS file watcher, OS process manager).

See §7 for the detailed reasoning on why this is CLI, not library.

```swift
// In CLI Project
import ModelHike
import NIOCore

public actor PreviewSession {
    private let config: PreviewConfig
    private let buildSession: BuildSession         // from ModelHike library
    private let fileWatcher: FSEventsFileWatcher    // CLI implementation
    private let processManager: ProcessManager      // CLI
    private let httpServer: PreviewHTTPServer       // CLI (NIO)

    private var currentSnapshot: AppModelSnapshot?  // from ModelHike library
    private var routeTable: MockRouteTable?         // from ModelHike library
    private var mockBuilder: MockResponseBuilder?   // from ModelHike library
    private var mockStore: MockStateStore?          // from ModelHike library
    private var loop1Debouncer: Debouncer           // from ModelHike library
    private var loop2Debouncer: Debouncer           // from ModelHike library

    public func start() async throws { ... }
    public func stop() async { ... }
}
```

### 5.2 `FileWatcher` Implementation (FSEvents / DispatchSource)

The concrete implementation of the `FileWatcher` protocol using OS-level APIs.

```swift
// In CLI Project
import ModelHike

public final class FSEventsFileWatcher: FileWatcher, @unchecked Sendable { ... }
public final class DispatchSourceFileWatcher: FileWatcher, @unchecked Sendable { ... }
```

### 5.3 Preview & Mock HTTP Server (SwiftNIO)

The HTTP server that serves the preview UI, handles WebSocket connections, and routes mock API requests. It uses `SwiftNIO`.

```swift
// In CLI Project
import NIOCore
import NIOHTTP1
import NIOWebSocket
import ModelHike

class MockAPIHandler: ChannelInboundHandler {
    let routeTable: MockRouteTable          // from library
    let mockBuilder: MockResponseBuilder    // from library
    let validator: MockRequestValidator     // from library

    // Routes incoming HTTP request → library's routeTable.match()
    // → library's mockBuilder.responseData()
    // → NIO HTTP response with Connection: keep-alive
}
```

The CLI wraps the library's pure functions in NIO channel handlers.

This subsection also owns **server-specific behavior** from the main brainstorm:
- `/mock/**` should opt into `Connection: keep-alive`
- preview routing/prefix policy (`/preview/*`, `/debug/*`, or separate ports) is a router concern
- static asset path handling for the preview UI is a server concern

These are all transport-layer decisions, so they belong in the CLI, not the library.

### 5.4 Process Manager (Framework Dev Servers)

Spawning `npm run start:dev` or `./mvnw spring-boot:run` requires `Foundation.Process`. It monitors `stdout` for regex patterns to detect readiness.

This same layer should also own **real-server infrastructure provisioning** when needed:
- starting/stopping `docker compose` services for databases, caches, or brokers
- selecting in-memory DB profiles when a blueprint supports them
- deciding whether preview mode runs mock-only or mock+real

```swift
// In CLI Project
public actor ProcessManager {
    func spawn(id: String, command: String, arguments: [String],
               workingDirectory: LocalPath, readyPattern: Regex<Substring>,
               onReady: @Sendable () async -> Void,
               onError: @Sendable (String) async -> Void) async throws
    func restart(id: String) async throws
    func stop(id: String) async
    func stopAll() async
}
```

### 5.5 Preview UI Assets (HTML/JS/CSS)

The Lit web components that make up the default preview UI. Same architecture as the debug console (loaded from CDN, no build step). Bundled as resources within the CLI executable.

### 5.6 `PreviewConfig` and CLI Argument Parsing

```swift
// In ModelHike library
public enum MockMode: String, Codable, Sendable {
    case stateless
    case statefulInMemory
}

public enum MockRouteMode: String, Codable, Sendable {
    case canonicalOnly
    case canonicalPlusBlueprintAliases
}

public struct PreviewCoreOptions: Sendable {
    public let mockDataSeed: Int?
    public let defaultListCount: Int
    public let mockMode: MockMode
    public let routeMode: MockRouteMode
}

// In CLI Project
public struct PreviewConfig: Sendable {
    public let core: PreviewCoreOptions
    public let basePath: LocalPath
    public let blueprintsPath: LocalPath
    public let outputPath: LocalPath
    public let port: Int                          // default 4800
    public let enableRealServer: Bool             // --real flag
    public let openBrowser: Bool                  // --no-open to disable
    public let allowShellCommands: Bool           // permit blueprint `run-shell-cmd`?
    public let loop1DebounceMs: Int               // default 150
    public let loop2DebounceMs: Int               // default 500

    public var watchPaths: [LocalPath] { [basePath, blueprintsPath] }
    public var watchExtensions: Set<String> { ["modelhike", "tconfig", "teso", "ss"] }
    public var pipelineConfig: PipelineConfig { ... }
}
```

**Final decision:** there is **no monolithic library `PreviewConfig`**.

Instead:
- the **library** exposes `PreviewCoreOptions` for transport-neutral preview behavior
- the **CLI** exposes `PreviewConfig` as the wrapper that adds ports, browser behavior, watch paths, real-server toggles, and a derived `PipelineConfig`

This avoids leaking CLI concerns into the library while still giving every consumer a shared set of pure preview options.

### 5.7 Blueprint Dev-Server Configuration Parsing

Reads `dev-command`, `dev-ready-pattern`, `dev-install-command`, `dev-port` from `main.ss` front matter or a `blueprint.tconfig` file. This is CLI-level because:
- It determines how to spawn OS processes (CLI concern)
- The library doesn't need to know about framework dev servers

### 5.8 WebSocket Broadcast Infrastructure

The `WebSocketClientManager` that manages connected browser clients and broadcasts JSON messages. Requires `NIOWebSocket`.

The library defines the *message shapes* (`PreviewServerMessage`, `PreviewClientMessage`). The CLI handles the *transport* (encoding them to JSON, sending over WebSocket frames).

### 5.9 Browser Auto-Open

`NSWorkspace.shared.open(url)` on macOS. Purely OS-specific.

---

## 6. Remaining Gray Areas

The two biggest ambiguities from earlier drafts are now resolved:
- **Stateful mock store** → library (`MockStateStore`)
- **Preview config boundary** → library `PreviewCoreOptions` + CLI `PreviewConfig`

Only the smaller design questions below remain open.

| Component | Recommendation | Rationale |
|-----------|---------------|-----------|
| `common.modelhike` detection (is this a common file?) | **Library** | Already handled by `LocalFileModelLoader.commonModelsFileName`. No change needed. |
| Loop 1 → Loop 2 model sharing optimization | **Library** | Would require a `Pipelines.renderFromModel(model:)` preset. Core pipeline concern. But defer to Phase 2. |
| `IncrementalStats` display formatting | **CLI** | The library provides the `IncrementalStats` struct; the CLI formats it for terminal or WebSocket. |
| Error recovery (parse error → keep last-good model) | **Split** | Library provides the "try parse, return error" API. CLI decides what to do with the error (keep old model, show banner). |

---

## 7. Why `PreviewSession` Is CLI, Not Library

This is the most debated component. An earlier draft of the brainstorm treated `PreviewSession` as library territory. After deeper analysis, **it belongs in the CLI.** Here's why:

### Direct Dependencies on CLI Components

`PreviewSession`'s pseudocode (from `live-preview.md` §11.2) calls:
- `startPreviewServer()` — requires `SwiftNIO`
- `broadcast(.modelUpdated(diff))` — requires `WebSocketClientManager` (NIO)
- `mockServer.configure(from: model)` — `MockAPIServer` is an HTTP server (NIO)
- `spawnFrameworkServer()` — requires `ProcessManager` (`Foundation.Process`)
- `openBrowser()` — requires `NSWorkspace` (macOS)

If `PreviewSession` lived in the library, it would pull in `SwiftNIO` → breaking the zero-dependency constraint.

### What About Protocol Abstraction?

One could define protocols for the server, WebSocket, and process manager, then put `PreviewSession` in the library operating only against protocols. But:
1. This adds protocol boilerplate for components that only have one real implementation each.
2. The orchestration logic (debounce timers, loop coordination) is tightly coupled to the I/O lifecycle.
3. The library already provides all the **reusable primitives** (`AppModelSnapshot`, `ModelDiff`, `MockRouteTable`, `MockResponseBuilder`, `BuildSession`, `Debouncer`). The CLI's job is to wire them together.

### The Right Split

- **Library provides the brains** — snapshotting, diffing, mock data, route derivation, validation, `BuildSession`, protocol definitions.
- **CLI provides the body** — `PreviewSession` wires the brains to the real world (NIO, FSEvents, Process).

This matches how `DevTester` already works: it imports `ModelHike` (the brain) and adds `SwiftNIO` (the body).

---

## 8. Concrete API Boundary

### 8.1 What the CLI Imports From the Library

```swift
// In CLI Project
import ModelHike

// --- Snapshotting & Diffing ---
// AppModelSnapshot, ContainerSnapshot, EntitySnapshot, PropertySnapshot, ...
// ModelDiff

// --- Mock Infrastructure ---
// MockValue, MockResponseBuilder, MockStateStore, MockRouteTable, MockRoute
// MockRequestValidator, ValidationResult, ValidationError

// --- Protocol Definitions ---
// PreviewServerMessage, PreviewClientMessage, PreviewDiagnostic

// --- File Watching Protocol ---
// FileWatcher, FileChangeEvent, FileChangeKind

// --- Detection ---
// detectDefaultUIContainers(), BlueprintMeta, PreviewUIDecision

// --- Utilities ---
// Debouncer, PreviewCoreOptions, MockMode, MockRouteMode

// --- Incremental Builds ---
// BuildSession, BuildReport, IncrementalStats

// --- Core Pipeline (existing) ---
// ModelFileParser, AppModel, Pipelines, Pipeline, PipelineConfig
// LocalFileModelLoader, LoadContext, ParsedTypesCache
// Hydrate.models(), Hydrate.annotations(), Validate.models()
```

### 8.2 Loop 1 Integration Sketch

```
CLI (PreviewSession)                         Library (ModelHike)
─────────────────────                        ────────────────────
FSEventsFileWatcher detects save
  │
  ├─► Debouncer.debounce(150ms)  ──────────► Debouncer (library)
  │     │
  │     ├─► ModelFileParser.parse()  ──────► ModelFileParser (library)
  │     │     → fresh AppModel
  │     │
  │     ├─► HydrateModels + Validate  ─────► Pipeline phases (library)
  │     │
  │     ├─► AppModelSnapshot(from:)  ──────► Snapshotting (library)
  │     │
  │     ├─► ModelDiff.compute(old:new:) ───► Diffing (library)
  │     │
  │     ├─► MockRouteTable.derive(from:) ──► Route derivation (library)
  │     │
  │     ├─► if config.core.mockMode == .statefulInMemory
  │     │      for entity in affectedEntities {
  │     │          mockStore.invalidate(entity)
  │     │      }                               ───────► MockStateStore (library)
  │     │
  │     ├─► mockServer.updateRoutes()  ────► CLI (NIO handler swaps route table)
  │     │
  │     └─► wsManager.broadcast(           ► CLI (NIO WebSocket)
  │           PreviewServerMessage           ► Library (message struct)
  │             .modelUpdated(diff,snap))
  │
Browser receives JSON, re-renders
  │
  ├─► GET /mock/users  ───────────────────► CLI (NIO handler)
  │     │
  │     ├─► routeTable.match("GET","/mock/users")  ► Library
  │     ├─► mockBuilder.responseData(entity, .list) ► Library
  │     └─► NIO HTTP response  ───────────────────► CLI
```

### 8.3 Loop 2 Integration Sketch

```
CLI (PreviewSession)                         Library (ModelHike)
─────────────────────                        ────────────────────
Debouncer.debounce(500ms)  ─────────────────► Debouncer (library)
  │
  ├─► buildSession.run(using: config)  ────► BuildSession (library)
  │     │
  │     ├─► Pipeline (Discover→Render)  ───► Pipeline (library)
  │     ├─► IncrementalRunner ─────────────► Library
  │     └─► BuildReport  ─────────────────► Library
  │
  ├─► wsManager.broadcast(
  │     PreviewServerMessage
  │       .codegenCompleted(stats))
  │
  ├─► (framework watcher detects files)
  │
  ├─► processManager monitors stdout  ────► CLI (Foundation.Process)
  │     readyPattern matches
  │
  └─► wsManager.broadcast(
        PreviewServerMessage
          .realServerReady(port:baseUrl:))
```

---

## 9. Swift 6 Sendable Constraints

`[String: Any]` is **not** `Sendable` in Swift 6. The `MockResponseBuilder` must expose a `Sendable`-safe public API.

**Options:**

| Approach | Sendable? | JSON-Encodable? | Ergonomic? |
|----------|-----------|-----------------|------------|
| `[String: Any]` | No | Yes via `JSONSerialization` | Low |
| `[String: Sendable]` | Yes | No direct JSON encoder path | Medium-Low |
| Custom `MockValue` enum | Yes | Yes | High |
| `Data` (pre-serialized JSON) | Yes | N/A — already JSON bytes | High |

**Recommendation:** expose **both**:
- a structured public API based on `MockValue` (`objectValue`, `arrayValue`) for tests, IDE consumers, and validation
- a convenience `responseData(...)` API for HTTP servers

That gives the library a type-safe, reusable representation while still making the CLI's NIO path trivial.

---

## 10. Relationship to `DevTester` and Migration Path

### 10.1 Current State

`DevTester` is an executable target in the `ModelHike` repository. It depends on `SwiftNIO` and implements:
- `DebugHTTPServer` (HTTP + WebSocket)
- `DebugRouter` (REST API for debug data)
- `StreamingDebugRecorder` (live event streaming)
- Debug console (Lit web components in `Assets/debug-console/`)

This makes `DevTester` a **prototype of the future CLI**. It blurs the library boundary because it lives in the same repo.

### 10.2 Migration Path

When the official `ModelHike CLI` is created:

1. **Phase 1: Library additions.** Add the new preview primitives (snapshot, diff, mock builder, route table, protocol types, `FileWatcher` protocol, debouncer) to `Sources/`. No changes to `DevTester`.

2. **Phase 2: `DevTester` as preview prototype.** Add `--preview` flag to `DevTester` that exercises the new library primitives. Mock server routes are added to `DebugRouter`. This validates the library API before building the CLI.

3. **Phase 3: CLI repo.** Create a separate `modelhike-cli` repo that depends on the `ModelHike` library. Port the NIO server, debug console, and preview UI to the CLI. `DevTester` is either retired or stripped down to a minimal test runner.

4. **Phase 4: Clean separation.** The `ModelHike` repo contains only the library (zero NIO). The CLI repo contains all executable and presentation code.

### 10.3 Intermediate State (Acceptable)

It's fine for `DevTester` to temporarily host preview server code during development. The important thing is that the **library primitives** are properly isolated in `Sources/` so they're available to any consumer, not just `DevTester`.

---

## 11. Testing Strategy for the Split

### 11.1 Library Tests (in `Tests/`)

These test the preview primitives in isolation, with no NIO or file system:

| Test | What It Verifies |
|------|-----------------|
| Snapshot round-trip | `AppModel` → `AppModelSnapshot` → JSON → decode → identical snapshot |
| Diff correctness | Add entity A, diff shows `addedEntities: ["A"]`. Remove B, diff shows `removedEntities: ["B"]`. Modify C's property, diff shows `modifiedEntities: ["C"]`. |
| MockResponseBuilder | Produces valid JSON for every `PropertyKind`. Includes all properties (not just required). Includes `id` field. Array mode returns N objects. Seed produces deterministic output. |
| MockStateStore | `create`/`update`/`delete`/`list` semantics are correct. `invalidate(entity:)` clears only the affected entity. |
| MockRouteTable derivation | Given a model with 3 entities and standard APIs, derive returns correct HTTP methods and paths. |
| MockRequestValidator | Missing required field → error. Invalid type → error. Value not in `validValueSet` → error. Valid body → no errors. |
| Default UI detection | Container with `#blueprint(api-nestjs-monorepo)` → needs default UI. Container with `#blueprint(ui-react)` → does not. |
| PreviewCoreOptions | Default values are sensible. `.stateless` and `.statefulInMemory` select the correct runtime behavior. |
| Debouncer | Rapid calls coalesce. Final action fires after delay. Cancelled tasks don't fire. |
| PreviewServerMessage encoding | Encode `modelUpdated`, decode, verify fields. |

### 11.2 CLI Tests (in CLI repo)

These require a running NIO server and file system:

| Test | What It Verifies |
|------|-----------------|
| Mock HTTP server | `GET /mock/module/entity` returns 200 with valid JSON body. `POST /mock/module/entity` with invalid body returns 400 with validation errors. |
| WebSocket broadcast | Connect client, trigger model update, receive `model-updated` message with correct diff. |
| File watcher integration | Write a `.modelhike` file to a temp directory, verify `FileChangeEvent` is emitted within 500ms. |
| End-to-end Loop 1 | Edit model file → file watcher → re-parse → snapshot → diff → mock server updated → WebSocket message sent — all within 200ms. |

---

## 12. Cross-References

- **[Live Preview — Comprehensive Brainstorm](./live-preview.md)** — the full system design (two-loop architecture, mock server, preview UI, process manager, edge cases)
- **[Incremental Builds — Architecture Decision](../incremental-builds/incremental-builds-architecture.md)** — `BuildSession`, incremental primitives, library vs CLI split for the build system
- **[Incremental Builds — Technical Design](../incremental-builds/incremental-builds.md)** — dependency analysis, 4-phase plan, complications
- **`AGENTS.md`** — project structure, zero-dependency constraint, pipeline phases
- **`Docs/debug/VISUALDEBUG.md`** — existing debug server architecture (the pattern the preview server extends)
