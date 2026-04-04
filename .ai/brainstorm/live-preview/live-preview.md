# Live Preview System — Comprehensive Brainstorm

> **Status:** Brainstorm / Architecture Exploration  
> **Date:** 2026-04-04  
> **Goal:** For every model change, seamlessly rebuild and update a live preview — at lightning speed. If the session generates only an API (no UI blueprint), a default UI is auto-generated to enable the preview loop.

---

## Table of Contents

1. [The Vision](#1-the-vision)
2. [Two-Loop Architecture](#2-two-loop-architecture)
3. [Loop 1: Model → Preview (Instant)](#3-loop-1-model--preview-instant)
    - 3.3 [Selective Re-Parse via Cached ModelSpaces](#33-selective-re-parse-via-cached-modelspaces)
    - 3.4 [Performance: Why Fresh AppModel Is Fast Enough](#34-performance-why-fresh-appmodel-is-fast-enough)
    - 3.5 [Computing the Entity-Level Diff](#35-computing-the-entity-level-diff)
4. [Loop 2: Model → Generated Code → Running Server (Background)](#4-loop-2-model--generated-code--running-server-background)
5. [File Watching](#5-file-watching)
6. [Model-Driven Mock API Server](#6-model-driven-mock-api-server)
7. [Default Preview UI](#7-default-preview-ui)
8. [Preview Server Architecture](#8-preview-server-architecture)
    - 8.1.1 [Connection Keep-Alive for Mock Server](#811-connection-close-and-keep-alive)
    - 8.1.2 [Debug and Preview Routing Prefixes](#812-debug-and-preview-routing-prefixes)
9. [Process Manager — Framework Dev Servers](#9-process-manager--framework-dev-servers)
10. [WebSocket Notification Protocol](#10-websocket-notification-protocol)
11. [Orchestrator — The `PreviewSession`](#11-orchestrator--the-previewsession)
12. [Performance Budget](#12-performance-budget)
13. [What Already Exists vs What's New](#13-what-already-exists-vs-whats-new)
14. [Blueprint Awareness](#14-blueprint-awareness)
    - 14.4 [Infrastructure Dependencies for Real Server](#144-infrastructure-dependencies-for-real-server-loop-2)
15. [Edge Cases and Complications](#15-edge-cases-and-complications)
    - 15.9 [Loop 1 → Loop 2 Model Sharing](#159-loop-1--loop-2-model-sharing)
    - 15.10 [Model JSON Serialization](#1510-model-json-serialization-for-preview-ui)
    - 15.11 [Mock State Invalidation](#1511-mock-state-invalidation-on-schema-change)
    - 15.12 [Mobile App Containers](#1512-mobile-app-containers)
    - 15.13 [Generated Code Preview](#1513-generated-code-preview)
    - 15.14 [`UIView` and UI Preview Limitations](#1514-uiview-and-ui-preview-limitations)
    - 15.15 [Out-of-Order Loop 1 Completion](#1515-out-of-order-loop-1-completion)
16. [Library vs CLI Placement](#16-library-vs-cli-placement)
17. [Phased Implementation](#17-phased-implementation)
18. [Testing Strategy](#18-testing-strategy)
19. [Open Questions](#19-open-questions)

---

## 1. The Vision

A developer edits a `.modelhike` file. Within milliseconds, a browser preview updates to reflect the change — new entities appear, modified properties reshape forms, API endpoints reconfigure, validation rules take effect. No manual rebuild. No refresh button. No waiting for a framework compiler.

If the model describes only an API (NestJS, Spring Boot, etc.) with no UI blueprint, a default preview UI is automatically generated — an interactive explorer that shows entities, schemas, endpoints, and lets the developer try requests against a mock or real server.

The experience should feel like editing a live document, not running a build tool.

---

## 2. Two-Loop Architecture

The key architectural insight: there are **two feedback loops** with fundamentally different latency profiles.

```
┌─────────────────────────────────────────────────────────────┐
│                     LOOP 1 — INSTANT                        │
│                                                             │
│   .modelhike edit                                           │
│       → File watcher detects (FSEvents)          ~10ms      │
│       → Re-parse changed file only               ~50ms      │
│       → Fresh AppModel + re-link                 ~30ms      │
│       → Mock API server reconfigures             ~10ms      │
│       → WebSocket push to preview UI             ~5ms       │
│       → Preview UI re-renders                    ~50ms      │
│                                                             │
│   Total: ~200ms  ← "lightning speed"                        │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                   LOOP 2 — BACKGROUND                       │
│                                                             │
│   .modelhike edit                                           │
│       → File watcher detects                     ~10ms      │
│       → Incremental codegen (BuildSession)       ~500ms     │
│       → Write changed files to disk              ~50ms      │
│       → Framework watcher detects (nodemon/etc)  ~200ms     │
│       → Framework recompiles                     2-10s      │
│       → Real server restarts                     1-3s       │
│       → WebSocket push "real server ready"       ~5ms       │
│       → Preview UI can switch to real backend    ~50ms      │
│                                                             │
│   Total: 3-15s (framework-dependent)                        │
└─────────────────────────────────────────────────────────────┘
```

**Loop 1** is the primary developer experience — instant feedback from model to visual preview. It doesn't generate code at all. It works directly from the parsed in-memory model.

**Loop 2** runs in the background, generating real production code and optionally running it. When it finishes, the preview can switch from mock to real. This validates that the generated code actually compiles and runs.

This two-loop architecture is analogous to how **Vite** works — instant HMR for the dev experience, background bundling for production validation. Or how **SwiftUI Previews** work — instant canvas refresh from the source, actual compilation happens separately.

---

## 3. Loop 1: Model → Preview (Instant)

### 3.1 What Happens on a Model Change

1. **File watcher** detects `.modelhike` file save.
2. **Selective re-parse**: only the changed file is re-parsed by `ModelFileParser`. Its cached `ModelSpace` is replaced in the `ModelSpaceCache`. All other files' cached `ModelSpace`s remain untouched.
3. **Fresh `AppModel`**: a new `AppModel` is built from all cached `ModelSpace`s, then `resolveAndLinkItems()` runs to resolve cross-file references, mixins, and type canonicalization — exactly as the full-build pipeline does.
4. **Re-hydrate + re-validate** via extracted library helpers (or a lightweight pipeline preset that stops after Validate) so Loop 1 reuses the existing `Hydrate`/`Validate` logic instead of duplicating it.
5. **Update the mock API server** — the new `AppModel` replaces the old one. Mock endpoints are derived from `C4Container` → `C4Component` → `DomainObject` → APIs. No file I/O needed.
6. **Push a WebSocket event** to all connected preview UIs with the model diff.
7. **Preview UI re-renders** — entity lists, API endpoints, schemas, forms update.

### 3.2 What Doesn't Happen in Loop 1

- No template rendering (no `.teso` evaluation)
- No file writing
- No code generation
- No framework compilation
- No server restart

This is what makes it instant. The preview reads directly from the model, not from generated code.

### 3.3 Selective Re-Parse via Cached ModelSpaces

The key insight: `AppModel` and `resolveAndLinkItems()` were designed to be constructed once, linked once, and discarded. **Don't fight that design.** Instead, cache the *inputs* to `AppModel`, not try to surgically mutate its internals.

`LocalFileModelLoader` already parses each `.modelhike` file into a `ModelSpace` (via `ModelFileParser`), then appends each `ModelSpace` to a fresh `AppModel`, then calls `resolveAndLinkItems()`. The selective re-parse strategy mirrors this exactly:

1. **Cache each file's `ModelSpace`** (the raw parse output, before linking).
2. On file change: **update only the affected cache entries** — re-parse modified/created files, remove deleted paths, treat rename as remove-old + parse-new.
3. **Build a fresh `AppModel`**, replay all cached `ModelSpace`s via the existing `append(contentsOf:)`, call `resolveAndLinkItems()` exactly as today.

```swift
actor ModelSpaceCache {
    private let commonFileName = "common.\(ModelConstants.ModelFile_Extension)"
    private var common: ModelSpace?                               // from common.modelhike
    private var files: [String: ModelSpace] = [:]                // normalized absolute path → parsed ModelSpace
    private var orderedPaths: [String] = []                      // deterministic replay order
    private var hashes: [String: String] = [:]                   // normalized absolute path → content hash

    /// Re-parse or insert a single file. Returns true if anything changed.
    func reparse(file: LocalFile, using config: OutputConfig) async throws -> Bool {
        let key = file.path.string
        let hash = file.contentHash()
        if hashes[key] == hash { return false }                  // unchanged — skip

        let parseCtx = LoadContext(config: config)
        let space = try await ModelFileParser(with: parseCtx).parse(file: file)

        if file.name == commonFileName {
            common = space
        } else {
            files[key] = space
            if !orderedPaths.contains(key) {
                orderedPaths.append(key)
                orderedPaths.sort()
            }
        }
        hashes[key] = hash
        return true
    }

    /// Remove a deleted file (or the old path of a rename). Returns true if anything changed.
    func remove(file: LocalFile) -> Bool {
        let key = file.path.string

        if file.name == commonFileName {
            let changed = common != nil || hashes[key] != nil
            common = nil
            hashes.removeValue(forKey: key)
            return changed
        }

        let removed = files.removeValue(forKey: key) != nil
        orderedPaths.removeAll { $0 == key }
        hashes.removeValue(forKey: key)
        return removed
    }

    /// Rebuild a complete, freshly-linked AppModel from all cached ModelSpaces.
    func buildModel(using config: OutputConfig) async throws -> AppModel {
        let model = AppModel()
        let ctx = LoadContext(model: model, config: config)

        if let common { await model.appendToCommonModel(contentsOf: common) }
        for key in orderedPaths {
            if let space = files[key] {
                await model.append(contentsOf: space)
            }
        }

        try await model.resolveAndLinkItems(with: ctx)
        return model
    }
}
```

**Why this works:**
- **Zero changes to `AppModel`, `ParsedTypesCache`, `resolveAndLinkItems`, collection lists, or `extractMixins`.** The existing code is used as-is.
- **Cross-file references are handled naturally** — `resolveAndLinkItems()` runs on the full model every time, resolving all types, mixins, container→module links, and reference targets from scratch. Type names from different files, one file overriding another — all handled by the existing linking logic.
- **`common.modelhike` changes just work** — its cached `ModelSpace` is replaced, the fresh `AppModel` is rebuilt from all caches, and `resolveAndLinkItems()` re-resolves everything.
- **Parse errors are safe** — if re-parse fails, keep the old cached `ModelSpace` and don't rebuild. The previous model stays valid.

**Two important implementation details:**
- **Cache keys must be full normalized paths, not basenames.** Two files in different folders can share the same filename; keying by `file.name` would collide.
- **Replay order must be deterministic.** If override precedence depends on load order, `ModelSpaceCache` replay must use the same stable order as full builds. The safest rule is lexicographic absolute-path order, and `LocalFileModelLoader` should use that same ordering too so preview builds and full builds agree.

**What we trade:** We create a fresh `AppModel` on every change instead of mutating the existing one. Since `AppModel` construction is just appending actors to lists (no file I/O, no parsing), this is negligible — the cost is in `resolveAndLinkItems()` which walks the in-memory model. For a typical project (10-20 files, <100 entities), this is ~20-30ms.

### 3.4 Performance: Why Fresh `AppModel` Is Fast Enough

| Step | Cost | Notes |
|------|------|-------|
| Re-parse changed file | 30-80ms | The only file I/O + regex work |
| Create fresh `AppModel` + replay cached `ModelSpace`s | <5ms | Appending actors to lists; no parsing |
| `resolveAndLinkItems()` | 20-30ms | In-memory traversal: type registration, module linking, mixin extraction, type canonicalization |
| **Total** | **~50-115ms** | Well within 200ms Loop 1 budget |

The savings vs a full re-parse: we skip parsing N-1 files (30-80ms each). For a 10-file project, that's 300-800ms saved.

### 3.5 Computing the Entity-Level Diff

The preview UI needs to know *what* changed so it can animate the UI (e.g., highlighting a new property).

Since we serialize the model to JSON for the preview UI anyway (see §15.10), we can compute the diff on snapshots:
1. Snapshot old `AppModel` → `oldSnapshot` (already cached from last update).
2. Build fresh `AppModel` from caches.
3. Snapshot new `AppModel` → `newSnapshot`.
4. Diff `oldSnapshot` vs `newSnapshot` to find added/removed/modified entities.
5. Send diff via WebSocket.

---

## 4. Loop 2: Model → Generated Code → Running Server (Background)

### 4.1 What Happens

1. Loop 1 completes (model is updated).
2. `BuildSession.run()` is triggered (from the incremental builds design).
3. The pipeline runs: Discover → Load → Hydrate → Validate → Render (using `Pipelines.codegenRenderOnly`).
4. `IncrementalRunner` compares output hashes to the manifest and writes only changed files.
5. The framework's dev server (if running) detects changed files and recompiles.
6. When the real server is ready, a WebSocket event is pushed: `{ type: "real-server-ready" }`.
7. The preview UI can now toggle from mock to real backend.

### 4.2 Why Both Loops Matter

| Aspect | Loop 1 (Mock) | Loop 2 (Real) |
|--------|--------------|---------------|
| Latency | ~200ms | 3-15s |
| Fidelity | Mock data, derived endpoints | Real generated code |
| Validation | Schema-level | Runtime-level (does it compile? does it run?) |
| Dependencies | None (just the model) | Framework runtime (Node.js, JVM, etc.) |
| When useful | Rapid iteration on model shape | Verifying generated code correctness |

A developer's typical workflow:
1. Edit model rapidly with instant Loop 1 feedback.
2. Glance at Loop 2 status ("compiling..." → "ready").
3. Switch to real backend when they want to test actual behavior.
4. Switch back to mock for fast iteration.

---

## 5. File Watching

### 5.1 What to Watch

| Source | What Changes | Impact |
|--------|-------------|--------|
| `*.modelhike` in `basePath` | Entity/API/UI definitions | Full Loop 1 + Loop 2 |
| `common.modelhike` | Shared types, mixins | Global invalidation — re-parse common file + fresh `AppModel` rebuild in Loop 1, full rebuild in Loop 2 |
| `main.tconfig` | Generation variables | Loop 2 only (doesn't affect model shape) |
| `*.teso` / `*.ss` in blueprint | Templates / scripts | Loop 2 only (model unchanged, but output changes) |
| `_modifiers_/*.teso` in blueprint | Blueprint modifiers | Loop 2 only |

### 5.2 Debouncing

Rapid saves (e.g., auto-save every keystroke) should not trigger N rebuilds. Strategy:

- **Loop 1**: debounce at **150ms**. Fast enough to feel instant, slow enough to batch rapid keystrokes.
- **Loop 2**: debounce at **500ms–1s**. Code generation is heavier; no point rebuilding while the user is still typing.
- **Coalescing**: if Loop 2 is still running when a new change arrives, either cancel the in-flight run if `BuildSession` becomes cancellation-aware, or mark a **pending rerun** so one fresh run starts immediately after the current one completes. Never let multiple Loop 2 runs pile up.

### 5.3 Implementation

**macOS**: `DispatchSource.makeFileSystemObjectSource` or `FSEvents` via `FileManager`. Since ModelHike targets macOS 13+, `DispatchSource` is the simplest. For directory-level watching (new files added/removed), `FSEvents` is better.

**Cross-platform consideration**: if the CLI ever targets Linux, use `inotify` via a Swift wrapper or `DispatchSource` (which works on Linux via `swift-corelibs-libdispatch`).

**Proposed type:**

```swift
public protocol FileWatcher: Sendable {
    func watch(
        paths: [LocalPath],
        extensions: Set<String>,
        onChange: @escaping @Sendable (FileChangeEvent) async -> Void
    ) async throws

    func stop() async
}

public enum FileChangeKind: String, Sendable {
    case modified
    case created
    case deleted
    case renamed
}

public struct FileChangeEvent: Sendable {
    public let path: LocalPath
    public let oldPath: LocalPath? // non-nil for .renamed
    public let kind: FileChangeKind  // .modified, .created, .deleted, .renamed
    public let timestamp: Date
}
```

**Important semantic note:** `watch(...)` should mean "register the watcher and return once it is active", not "block forever until watching stops." Otherwise `PreviewSession.start()` would never continue past the watch call. The `onChange` callback is `async` so implementations will typically bridge OS events into a `Task { await onChange(event) }`. If desired, rename it to `startWatching(...)` to make the registration semantics explicit.

**Filtering note:** extension filtering cannot look only at the new path. For `.renamed` events, the watcher must emit the event if **either** `oldPath` or `path` matches one of the watched extensions. Otherwise renaming `foo.modelhike` to `foo.bak` would never reach `PreviewSession`, and the stale cached `ModelSpace` would remain loaded.

### 5.4 Deletes, Creates, and Renames

Loop 1 cannot treat every event as "re-parse this path":

- **Created** → parse the new file, insert it into `ModelSpaceCache`, rebuild fresh `AppModel`.
- **Modified** → re-parse that file, replace its cached `ModelSpace`, rebuild fresh `AppModel`.
- **Deleted** → remove that file from `ModelSpaceCache`, rebuild fresh `AppModel`.
- **Renamed** → remove `oldPath` from `ModelSpaceCache`; if the new `path` still matches `.modelhike`, parse it as a new file, then rebuild fresh `AppModel`.

This is why `FileChangeEvent` needs `oldPath` for `.renamed`. Without it, rename handling is lossy and stale cached definitions remain in memory.

---

## 6. Model-Driven Mock API Server

This is the core of Loop 1's instant preview. A mock server that derives its behavior entirely from the parsed in-memory model — no code generation, no framework runtime.

### 6.1 What It Serves

For each entity with APIs in the model:

| API Type | Mock Behavior |
|----------|--------------|
| `create` | Accept JSON body, validate against schema, return mock object with generated ID |
| `update` | Accept JSON body, return merged mock object |
| `delete` | Accept ID param, return 204 |
| `getById` | Return mock object for any ID |
| `list` | Return array of N mock objects (configurable) |
| `listByCustomProperties` | Return filtered mock array based on query params |
| `getByCustomProperties` | Return single mock object |
| `customLogic` (get/list/mutation) | Return mock based on return type |
| `pushData` / `pushDataList` | Accept and acknowledge |
| `activate` / `deactivate` | Toggle and return |

### 6.2 How Mock Data Works

ModelHike already has `SampleJson`, `SampleQueryString`, and `MockData_Generator`. These generate type-aware mock data from entity schemas:

- String properties → `"propName 42"` (name + random int)
- Int/Double/Float → random 0–99
- Bool → `true`
- Date → ISO8601 now
- ObjectId/Any → random hex string (MongoDB-style)
- Reference types → `{ "ref": "hex", "display": "name N" }`
- CodedValue types → `{ "vsRef": "hex", "display": "name N", "code": "BEN" }`
- Custom types → recursive object via `ParsedTypesCache`
- Unknown → `"--UnKnown--"`

The mock server uses this infrastructure but **needs adaptations**:

**Gap 1 — Only required properties.** `SampleJson` filters to `required == .yes` and excludes `id` fields (line 23 of `SampleJson.swift`). A mock server should include **all** properties (including optional ones with null/default values, and the `id` field for responses). Either extend `SampleJson` with a `mode: .allProperties` option, or build a dedicated `MockJsonBuilder` that wraps the same per-property logic but iterates all properties.

**Gap 2 — Not valid JSON by default.** `SampleJson.string(openCloseBraces:)` defaults to `openCloseBraces: false`, producing content without `{}` wrappers. The mock server must call it with `openCloseBraces: true`. The output is a hand-crafted JSON string built via `StringTemplate`, not `JSONEncoder` — so special characters in property names (spaces, quotes) could produce malformed JSON. For production mock responses, switch to a proper `Codable` / `MockValue`-based representation and encode that to `Data`.

**Gap 3 — Single object, not arrays.** `SampleJson` produces one object. For `list` APIs, the mock server needs an array of N objects (e.g., 5–10). This is a simple wrapper: generate N calls to `SampleJson.string(openCloseBraces: true)` and wrap in `[...]`.

**Gap 4 — `SampleQueryString` returns `--UnKnown--` for complex types.** For reference, codedValue, and customType query params, the current implementation returns a placeholder string. The mock server should substitute reasonable defaults (random IDs for references, first value from `validValueSet` for coded values).

**Gap 5 — Async access.** `SampleJson.string()` is `async` because it accesses `actor` properties on `CodeObject` and `Property`. The mock server's route handler must be async-aware (the existing NIO handler already dispatches to `Task {}`, so this is fine).

**Recommendation:** Build a `MockResponseBuilder` that wraps `SampleJson` and addresses gaps 1–4. Keep `SampleJson` unchanged for template use (blueprints may depend on its current behavior). The builder would:

```swift
struct MockResponseBuilder {
    let typesCache: ParsedTypesCache

    func objectValue(for entity: CodeObject, includeId: Bool = true) async -> [String: MockValue] { ... }
    func arrayValue(for entity: CodeObject, count: Int = 5) async -> [[String: MockValue]] { ... }
    func responseBody(for api: API, entity: CodeObject) async throws -> Data { ... }
}
```

Where `MockValue` is a small `Codable` + `Sendable` JSON value enum (`string`, `int`, `double`, `bool`, `null`, `array`, `object`) so the library stays Swift 6-safe while still serializing cleanly to JSON.

### 6.3 URL Routing

The model provides:
- **Container → Modules → Entities → APIs**
- Each module gets a port (from `HydrateModels`, starting at 3001)
- Each entity has a `baseUrl` (slugified entity name)
- Each API has a `path` fragment and an `APIType` that maps to HTTP method

Derived routes:

```
GET    /api/v1/{entity-slug}           → list
GET    /api/v1/{entity-slug}/:id       → getById
POST   /api/v1/{entity-slug}           → create
PUT    /api/v1/{entity-slug}/:id       → update
DELETE /api/v1/{entity-slug}/:id       → delete
GET    /api/v1/{entity-slug}/by?...    → listByCustomProperties
POST   /api/v1/{entity-slug}/activate  → activate
...
```

**Important:** `/api/v1` and the exact route shapes above are **examples**, not universal truth from the model. The core model provides `APIType`, `path`, `baseUrl`, and query mappings, but the full REST prefix and final URL policy are blueprint/config conventions. For example, the Spring Boot blueprint has `api-base-path : /api/v1` in `main.ss` front matter, while other blueprints may differ.

That gives two choices for the mock server:

1. **Canonical preview routes** — the preview system defines its own stable mock URL scheme (e.g. `/mock/{module}/{entity}`), independent of blueprint output.
2. **Blueprint-aware routes** — when the active blueprint declares enough metadata, the mock server mirrors the generated app's route structure.

**Recommendation:** Use **canonical preview routes** for Phase 1 (predictable, no blueprint parsing dependency), and optionally expose blueprint-aware aliases later.

The mock server doesn't need a port per module — it can serve all modules on a single port with route prefixes (e.g., `/mock/module-name/api/v1/...` or `/mock/module-name/{entity}` depending on the chosen strategy).

### 6.4 Stateful Mock (Optional Enhancement)

A stateless mock server returns random data every time. A **stateful mock** maintains an in-memory store:
- `create` adds to the store
- `getById` returns from the store
- `update` modifies in the store
- `delete` removes from the store
- `list` returns all items in the store

This is more useful for testing UI flows (create → list → see the new item). Pre-seeded with `SampleJson` data on startup.

**Placement decision:** the transport-neutral CRUD engine should live in the `ModelHike` library as a `MockStateStore` actor, alongside `MockResponseBuilder`. The CLI `PreviewSession` owns one instance, chooses whether preview runs in stateless or stateful mode, and decides whether state is discarded on restart or later persisted externally.

### 6.5 Validation in Mock Server

The model carries property metadata that enables request validation:
- `required` → reject if missing
- `validValueSet` → reject if not in allowed values
- `constraints` → reject if violated (min, max, etc.)
- `type` → type-check (string for string fields, number for int fields, etc.)

The mock server can return 400 responses with structured error messages, giving the developer immediate feedback on validation rules.

---

## 7. Default Preview UI

When no UI blueprint is included in the container's tags, a default preview UI is automatically generated. This UI enables the preview loop for API-only projects.

### 7.1 Architecture: Built-In vs Generated

| Approach | How It Works | Latency | Maintenance |
|----------|-------------|---------|-------------|
| **Built-in web app** | Static HTML/JS/CSS served by the preview server, reads model metadata via REST/WS. No code generation step. | Instant | ModelHike team maintains it |
| **Generated from preview blueprint** | A bundled `preview-ui` blueprint generates a SPA (React/Vue/etc.) | Requires codegen + build | Blueprint template maintenance |
| **Model-driven rendering** | Lit/Web Components shell that renders entirely from model JSON | Instant | Component library maintenance |

**Recommendation: Built-in web app using the same pattern as the debug console** (Lit web components loaded from CDN, no build step). This is:
- Instant (no code generation needed)
- Already proven (the debug console works this way)
- Dynamic (reads model metadata via API, re-renders on WebSocket push)
- Zero external dependencies on the preview consumer's machine

### 7.2 What the Default Preview UI Shows

**Dashboard View:**
- System overview: containers, modules, entity counts
- Deployment topology (container types, ports)
- Validation diagnostics (W301-W307)

**Entity Explorer:**
- List of all entities per module
- Schema view: properties, types, required/optional, constraints, valid value sets
- Relationship graph: which entities reference which

**API Explorer (the core feature):**
- Grouped by module → entity
- For each API endpoint: HTTP method, path, request schema, response schema
- "Try It" panel:
  - Auto-filled request body from `SampleJson`
  - Editable request fields
  - Send button → hits mock server (or real server if available)
  - Response display with syntax highlighting
- Query parameter builder for list APIs
- Validation feedback on requests

**Live Model Diff:**
- When the model changes, highlight what changed (new entity, modified property, removed API)
- Animation to draw attention to the change

### 7.3 Relationship to Debug Console

The debug console (`DevTester/Assets/debug-console/`) is a **pipeline inspection tool** — it shows events, traces, generated files, variable state. The preview UI is a **model interaction tool** — it shows entities, APIs, and lets you interact with them.

They could share:
- The same NIO server infrastructure
- The same WebSocket broadcast pattern
- Some UI components (model hierarchy panel, problems panel)
- The same Lit + CDN architecture

But they are **different apps** that may be served on different paths or different ports, depending on how routing is implemented (see §8.1.2).

### 7.4 Current `UIView` Metadata Gap

If ModelHike eventually wants to preview **model-defined UIs** (not just the default preview UI), the current code has a real limitation:

- `UIViewParser` currently parses the view name, description, annotations, and attached sections, but **does not parse member/property lines into the `UIView`**.
- `UIObject_Wrap` exposes only `name`, `given-name`, `description`, and `has-description`.
- `C4Component.types` collects only `CodeObject`s, so `UIView`s in `C4Component.items` are **not visible** if preview code iterates `types`.

This means a live preview system can easily drive:
- entities
- DTOs
- APIs
- validation metadata

but **cannot yet build a rich preview from `UIView` definitions alone**.

**Recommendation:** The default preview UI should be entity/API-centric, not `UIView`-centric. If future work wants true model-defined UI preview, first enhance:
1. `UIViewParser` to parse members and actions
2. `UIObject_Wrap` to expose them
3. module/container snapshot builders to include `UIView`s from `C4Component.items`, not just `types`

---

## 8. Preview Server Architecture

### 8.1 Extending the Existing Debug Server

The `DebugHTTPServer` already provides:
- SwiftNIO HTTP + WebSocket on a configurable port
- Static file serving for the debug console
- REST API endpoints for model/session data
- WebSocket broadcast for real-time events

Conceptually, the preview server can be a **sibling router** on the same NIO server:

```
http://localhost:4800/debug/          → Debug console (existing)
http://localhost:4800/preview/        → Preview UI (new)
http://localhost:4800/mock/           → Mock API server (new)
http://localhost:4800/api/model       → Model metadata (existing, shared)
http://localhost:4800/ws              → WebSocket (extended with new message types)
```

### 8.1.1 `Connection: close` and Keep-Alive

The existing `HTTPChannelHandler` sets `Connection: close` on every response and explicitly closes the TCP channel after writing (line 82 and 98 of `HTTPChannelHandler.swift`). This means every HTTP request opens and tears down a new TCP connection.

For the debug console (infrequent REST pulls), this is fine. For the mock API server (the preview UI's "Try It" panel may fire rapid sequences of requests, and a generated frontend app could make dozens of concurrent API calls), this adds measurable latency.

**Fix:** For routes under `/mock/**`, use `Connection: keep-alive` and don't close the channel after the response. The simplest approach: the `HTTPRouteResponse` struct gains an optional `keepAlive: Bool` field. `HTTPChannelHandler.writeResponse` checks it:

```swift
if response.keepAlive {
    headers.add(name: "Connection", value: "keep-alive")
    // Don't close channel after write
} else {
    headers.add(name: "Connection", value: "close")
    // Close channel after write (existing behavior)
}
```

This is a one-location change in `HTTPChannelHandler`. All existing debug routes continue to use `close` (unchanged behavior). Mock routes opt into `keep-alive`.

### 8.1.2 Debug and Preview Routing Prefixes

The current debug console is served from `/`, with static files under `/styles/*`, `/components/*`, `/utils/*`, and `/lib/*`. The HTML uses **relative asset paths** like `styles/base.css` and `components/debug-app.js`, so if the debug console is moved under `/debug/`, the router must also serve `/debug/styles/*`, `/debug/components/*`, etc. The current `DebugRouter` does **not** do that.

This means the earlier sketch:

```
/debug/   → debug console
/preview/ → preview UI
```

is not achievable with routing alone unless the server becomes **prefix-aware** for both apps.

**Options:**

1. **Separate ports** — simplest. Keep debug console on `localhost:4800`, preview on `localhost:4801`.
2. **Prefix-aware router** — teach the server to serve `/debug/styles/*`, `/debug/components/*`, etc., and make the preview app similarly prefix-safe.
3. **Root + preview split** — keep debug console at `/` and serve preview at `/preview/`. This avoids changing the debug console but gives preview the subpath.

**Recommendation:** For Phase 1, use **separate ports** or **root + preview split**. Avoid rewriting the debug console routing until preview mode proves valuable.

### 8.2 New Endpoints Needed

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/preview/` | Preview UI entry point |
| GET | `/preview/**` | Preview UI static assets |
| GET | `/api/preview/schema` | Full model schema for preview UI (entities, APIs, types) |
| GET | `/api/preview/entity/:name` | Single entity detail (properties, APIs, relationships) |
| GET | `/api/preview/status` | Build status (loop 1/2 state, real server health) |
| ANY | `/mock/**` | Mock API server (see §6) |
| POST | `/api/preview/rebuild` | Manually trigger rebuild (for edge cases) |

### 8.3 Server Modes

The server could run in different modes:

| Mode | What It Does | When |
|------|-------------|------|
| **Preview** | File watching + mock server + preview UI | `modelhike preview` or `swift run DevTester --preview` |
| **Preview + Real** | Above + spawns framework dev server | `modelhike preview --real` |
| **Debug + Preview** | Debug console + preview side by side | `modelhike preview --debug` |

---

## 9. Process Manager — Framework Dev Servers

For Loop 2, after code generation, the generated project's dev server needs to run.

### 9.1 What Needs to Be Managed

| Blueprint | Runtime | Dev Command | Watch Built-in? |
|-----------|---------|-------------|-----------------|
| `api-nestjs-monorepo` | Node.js | `npm run start:dev` (uses `ts-node --watch` or `nest start --watch`) | Yes |
| `api-springboot-monorepo` | JVM | `./mvnw spring-boot:run` or `./gradlew bootRun` (DevTools) | Yes (with DevTools) |
| Future: React/Vue/etc | Node.js | `npm run dev` (Vite/Webpack) | Yes |

Both NestJS and Spring Boot have their own file-watching and hot-reload. ModelHike's Loop 2 writes files → framework watcher picks them up → framework rebuilds. This is the natural integration point.

### 9.2 Process Lifecycle

```
1. First run:
   - Generate all code (full build)
   - Run `npm install` / `mvn dependency:resolve` (one-time)
   - Start framework dev server in background
   - Monitor stdout/stderr for "ready" signal

2. Subsequent model changes:
   - Incremental codegen writes changed files
   - Framework watcher detects and rebuilds
   - Monitor for "ready" signal again
   - Push "real-server-ready" via WebSocket

3. Shutdown:
   - SIGTERM to framework process
   - Clean up
```

### 9.3 Proposed Process Manager Shape

```swift
public actor ProcessManager {
    private var processes: [String: ManagedProcess] = [:]

    func spawn(
        id: String,
        command: String,
        arguments: [String],
        workingDirectory: LocalPath,
        readyPattern: Regex<Substring>,    // e.g., /Listening on port \d+/
        onReady: @Sendable () async -> Void,
        onError: @Sendable (String) async -> Void
    ) async throws

    func restart(id: String) async throws
    func stop(id: String) async
    func stopAll() async
    func isRunning(id: String) -> Bool
}

struct ManagedProcess: Sendable {
    let id: String
    let process: Process
    let readyPattern: Regex<Substring>
    var isReady: Bool
    var lastOutput: String
}
```

### 9.4 Ready Detection

Each framework signals readiness differently:

| Framework | Ready Signal |
|-----------|-------------|
| NestJS | `Nest application successfully started` |
| Spring Boot | `Started \w+ in \d+\.\d+ seconds` |
| Vite | `Local:   http://localhost:\d+` |
| Generic | Configurable regex in blueprint metadata |

The `readyPattern` parameter lets blueprints define their own ready signal.

### 9.5 First-Run Bootstrap

The first time a project is generated, dependencies must be installed:

```
NestJS:    npm install
Spring:    ./mvnw dependency:resolve  (or just let bootRun do it)
```

This is a one-time cost. The process manager should:
1. Check if `node_modules/` (or `.mvn/`) exists in the output directory.
2. If not, run the install command before starting the dev server.
3. Show progress in the preview UI: "Installing dependencies... (first run)"

---

## 10. WebSocket Notification Protocol

Extending the existing debug WebSocket protocol with preview-specific messages.

### 10.1 Server → Client

| `type` | Payload | When |
|--------|---------|------|
| `model-updated` | `{ containers, changedEntities, addedEntities, removedEntities, diagnostics }` | Loop 1 completes |
| `codegen-started` | `{ containersAffected }` | Loop 2 starts |
| `codegen-completed` | `{ stats: IncrementalStats, filesChanged }` | Loop 2 (incremental persist) done |
| `real-server-starting` | `{ framework, command }` | Framework dev server spawning |
| `real-server-ready` | `{ port, baseUrl }` | Framework dev server ready |
| `real-server-error` | `{ error, stdout, stderr }` | Framework dev server crashed |
| `build-error` | `{ phase?, error, diagnostics? }` | Pipeline error |
| `file-change-detected` | `{ path, oldPath?, kind }` | Before debounce (for UI activity indicator) |

### 10.2 Client → Server

| `type` | Payload | Effect |
|--------|---------|--------|
| `switch-backend` | `{ target: "mock" \| "real" }` | Toggle preview API target |
| `force-rebuild` | `{}` | Trigger full rebuild (skip incremental) |
| `set-mock-seed` | `{ seed }` | Change mock data randomization seed |

### 10.3 Backward Compatibility

Existing debug console WebSocket messages (`event`, `paused`, `completed`, `resume`, `addBreakpoint`, `removeBreakpoint`) continue to work unchanged. Preview messages use new `type` values that the debug console ignores.

For `build-error`, `diagnostics` should be treated as **optional**. `BuildSession` currently returns `BuildReport` without a diagnostics collection, so the preview layer may only have an error string unless it separately captures diagnostics from Loop 1 or from a recorder attached to Loop 2.

---

## 11. Orchestrator — The `PreviewSession`

The top-level coordinator that owns the entire preview lifecycle.

### 11.1 Responsibilities

1. **Own the file watcher** — detect model, config, and blueprint changes.
2. **Own the `ModelSpaceCache`** — selective re-parse on change, fresh `AppModel` rebuild.
3. **Own the `BuildSession`** — trigger incremental codegen (Loop 2).
4. **Own the mock server** — update mock routes on model change (Loop 1).
5. **Own the process manager** — spawn/monitor framework dev servers.
6. **Own the preview server** — serve the preview UI + mock API + WebSocket.
7. **Coordinate loops** — Loop 1 runs immediately, Loop 2 is debounced.
8. **Track state** — what's the current model? Is Loop 2 in flight? Is the real server ready?

### 11.2 Proposed Shape

```swift
public struct PreviewDiagnostic: Codable, Sendable {
    public let severity: String
    public let code: String?
    public let message: String
    public let fileIdentifier: String?
    public let lineNo: Int?
}

public actor PreviewSession {
    // --- Dependencies ---
    private let config: PreviewConfig
    private let buildSession: BuildSession
    private let fileWatcher: FileWatcher
    private let processManager: ProcessManager

    // --- State ---
    private var currentModel: AppModel?
    private var currentSnapshot: AppModelSnapshot?
    private var modelCache: ModelSpaceCache
    private var mockServer: MockAPIServer
    private var mockStateStore: MockStateStore?
    private var loop1Generation: Int = 0
    private var loop2InFlight: Bool = false
    private var loop2PendingRerun: Bool = false
    private var realServerReady: Bool = false
    private var lastDiagnostics: [PreviewDiagnostic] = []

    // --- Lifecycle ---
    public func start() async throws {
        // 1. Full initial build (both loops).
        //    `fullBuild()` should also populate ModelSpaceCache with every current
        //    model file so later Loop 1 updates can be truly incremental.
        let model = try await fullBuild()
        currentModel = model
        currentSnapshot = await AppModelSnapshot(from: model)

        // 2. Start mock server with initial model
        await mockServer.configure(from: model)

        // 3. Start preview HTTP server (serves UI + mock + WS)
        try await startPreviewServer()

        // 4. Optionally spawn framework dev server
        if config.enableRealServer {
            try await spawnFrameworkServer()
        }

        // 5. Start file watcher
        try await fileWatcher.watch(
            paths: config.watchPaths,
            extensions: config.watchExtensions,
            onChange: { [weak self] event in
                await self?.onFileChanged(event)
            }
        )

        // 6. Open browser
        if config.openBrowser {
            openBrowser(url: "http://localhost:\(config.port)/preview/")
        }
    }

    private func onFileChanged(_ event: FileChangeEvent) async {
        // Broadcast activity indicator immediately
        await broadcast(.fileChangeDetected(event))

        if event.path.extension == "modelhike" || event.oldPath?.extension == "modelhike" {
            // LOOP 1: instant model update
            await runLoop1(event: event)
        }

        // LOOP 2: debounced codegen (all file types)
        debounceLoop2()
    }

    private func runLoop1(event: FileChangeEvent) async {
        loop1Generation += 1
        let generation = loop1Generation

        do {
            // Update ModelSpaceCache from the file event, then rebuild a fresh AppModel.
            guard let diff = try await applyModelChange(event, generation: generation) else {
                return // no-op change, stale work, or change that produced no observable preview update
            }
            guard generation == loop1Generation else { return } // newer change arrived

            // Update mock server
            if let model = currentModel {
                await mockServer.configure(from: model)
            }

            // Broadcast to preview UIs
            await broadcast(.modelUpdated(diff, diagnostics: lastDiagnostics))
        } catch {
            guard generation == loop1Generation else { return }
            await broadcast(.buildError(
                phase: "loop1",
                error: String(describing: error),
                diagnostics: nil
            ))
        }
    }

    private func applyModelChange(_ event: FileChangeEvent, generation: Int) async throws -> ModelDiff? {
        let oldSnapshot = currentSnapshot

        // 1. Update the cache according to the file-system event.
        let changed: Bool
        switch event.kind {
        case .created, .modified:
            changed = try await modelCache.reparse(
                file: LocalFile(path: event.path), using: config.pipelineConfig
            )
        case .deleted:
            changed = await modelCache.remove(file: LocalFile(path: event.path))
        case .renamed:
            let removed = await modelCache.remove(
                file: LocalFile(path: event.oldPath ?? event.path)
            )
            let inserted: Bool
            if event.path.extension == "modelhike" {
                inserted = try await modelCache.reparse(
                    file: LocalFile(path: event.path), using: config.pipelineConfig
                )
            } else {
                inserted = false
            }
            changed = removed || inserted
        }
        guard changed else { return nil }

        // 2. Build a fresh AppModel from all cached ModelSpaces + link.
        //    Cross-file refs, mixins, type canonicalization — all handled
        //    by the existing resolveAndLinkItems(), no mutations needed.
        let newModel = try await modelCache.buildModel(using: config.pipelineConfig)

        // 3. Reuse the existing Hydrate + Validate logic for Loop 1.
        let diagnostics = await hydrateAndValidate(newModel, using: config.pipelineConfig)
        let newSnapshot = await AppModelSnapshot(from: newModel)

        // Drop stale work before publishing it as current state.
        guard generation == loop1Generation else { return nil }

        lastDiagnostics = diagnostics
        currentModel = newModel
        currentSnapshot = newSnapshot

        // 4. Diff
        return computeDiff(old: oldSnapshot, new: newSnapshot)
    }

    private func runLoop2() async {
        guard !loop2InFlight else {
            loop2PendingRerun = true
            return
        }
        loop2InFlight = true
        loop2PendingRerun = false
        defer {
            loop2InFlight = false
            if loop2PendingRerun {
                loop2PendingRerun = false
                Task { await self.runLoop2() }
            }
        }

        await broadcast(.codegenStarted)

        do {
            let report = try await buildSession.run(using: config.pipelineConfig)
            if report.success {
                await broadcast(.codegenCompleted(report.stats))
                // Framework watcher will detect changed files automatically
            } else {
                await broadcast(.buildError(
                    phase: "loop2",
                    error: "Build failed without a thrown error",
                    diagnostics: nil
                ))
            }
        } catch {
            await broadcast(.buildError(
                phase: "loop2",
                error: String(describing: error),
                diagnostics: nil
            ))
        }
    }

    public func stop() async {
        await fileWatcher.stop()
        await processManager.stopAll()
    }
}
```

### 11.3 `PreviewConfig`

```swift
public enum MockMode: String, Sendable {
    case stateless
    case statefulInMemory
}

public enum MockRouteMode: String, Sendable {
    case canonicalOnly
    case canonicalPlusBlueprintAliases
}

public struct PreviewCoreOptions: Sendable {
    public let mockDataSeed: Int?
    public let defaultListCount: Int
    public let mockMode: MockMode
    public let routeMode: MockRouteMode
}

public struct PreviewConfig: Sendable {
    public let core: PreviewCoreOptions
    public let basePath: LocalPath                     // model folder
    public let blueprintsPath: LocalPath               // blueprint folder
    public let outputPath: LocalPath                   // generated code output
    public let port: Int                               // preview server port (default 4800)
    public let enableRealServer: Bool                  // spawn framework dev server?
    public let openBrowser: Bool                       // auto-open browser?
    public let allowShellCommands: Bool                // allow blueprint `run-shell-cmd`?
    public let loop1DebounceMs: Int                    // model re-parse debounce (default 150)
    public let loop2DebounceMs: Int                    // codegen debounce (default 500)

    // Derived
    public var watchPaths: [LocalPath] { [basePath, blueprintsPath] }
    public var watchExtensions: Set<String> { ["modelhike", "tconfig", "teso", "ss"] }
    public var pipelineConfig: PipelineConfig { ... }
}
```

**Split decision:** `PreviewCoreOptions` is the library-facing, transport-neutral part of preview configuration. `PreviewConfig` is the CLI wrapper that adds port, browser behavior, watch paths, real-server toggles, and the derived `PipelineConfig`.

---

## 12. Performance Budget

### 12.1 Loop 1 — Target: <200ms

| Step | Budget | Notes |
|------|--------|-------|
| FSEvents callback | 10ms | OS-level, essentially free |
| File read + hash check | 5ms | Single file, typically <50KB |
| Re-parse changed file | 30-80ms | `ModelFileParser` on one file; regex-heavy but bounded |
| Build fresh `AppModel` from cached `ModelSpace`s | <5ms | Appending actors to lists; no parsing |
| `resolveAndLinkItems()` | 20-30ms | In-memory traversal: type registration, module linking, mixin extraction, type canonicalization |
| Re-hydrate + re-validate | 10-20ms | Port assignment, dataType classification, W301–W307 checks |
| Snapshot & Diff | 5-10ms | Compare new JSON snapshot to old |
| Mock server reconfigure | 5-10ms | Swap in-memory route table |
| WebSocket broadcast | 1-5ms | JSON encode + send |
| **Total** | **~100-170ms** | Well within 200ms budget |

**Bottleneck**: `ModelFileParser` regex parsing dominates. If a single `.modelhike` file is very large (hundreds of entities), consider pre-splitting or parallel parsing.

**Worst case — `common.modelhike` change**: All cached `ModelSpace`s are still valid, but the common `ModelSpace` is replaced and the fresh `AppModel` re-links everything. No extra parsing needed — only the common file is re-parsed. Cost is the same as any single-file change.

### 12.2 Loop 2 — Target: <1s for Incremental

| Step | Budget | Notes |
|------|--------|-------|
| Full pipeline (Discover–Render) | 300-800ms | Already measured with `--perf` |
| Incremental persist (hash + write) | 50-200ms | Only changed files |
| **Total** | **~500ms–1s** | Framework rebuild time is additional |

**Bottleneck**: Template rendering is 60-80% of pipeline time. Phase 3 of the incremental builds plan (selective render) would cut this dramatically.

### 12.3 First Run — One-Time Cost

| Step | Time | Notes |
|------|------|-------|
| Full codegen | 1-5s | All files generated |
| `npm install` (NestJS) | 10-30s | One-time, cached after |
| Framework first start | 3-10s | One-time compilation |
| **Total** | **~15-45s** | Only once per session |

---

## 13. What Already Exists vs What's New

### 13.1 Already Exists in ModelHike

| Capability | Where | Reusable? |
|-----------|-------|-----------|
| SwiftNIO HTTP + WebSocket server | `DevTester/DebugServer/` | Yes — extend with new routes |
| WebSocket broadcast to connected clients | `WebSocketClientManager` | Yes — add new message types |
| Lit web component architecture (no build step) | `DevTester/Assets/debug-console/` | Yes — same pattern for preview UI |
| Model metadata REST API (`/api/model`, `/api/session`) | `DebugRouter` | Yes — add preview-specific endpoints |
| Mock data generation (`SampleJson`, `SampleQueryString`) | `Sources/CodeGen/MockData/` | Yes — use for mock server responses |
| Pipeline event hooks (`CodeGenerationEvents`) | `Sources/Workspace/Context/` | Yes — for tracing/debugging the preview |
| Debug session + event streaming | `StreamingDebugRecorder` | Partially — different event types for preview |
| Incremental build primitives | `.ai/brainstorm/incremental-builds/` | Not yet implemented, but designed |
| `C4Container_Wrap`, `API_Wrap`, `CodeObject_Wrap` | `Sources/Scripting/Wrappers/` | Yes — rich model metadata for preview UI |
| Expression evaluator | `Sources/Workspace/Evaluation/` | Possibly — for interactive "evaluate expression" in preview |
| `run-shell-cmd` statement | `Sources/Scripting/SoupyScript/Stmts/` | Possibly — for bootstrap commands |
| Performance recorder | `Sources/Pipelines/PipelinePerformance.swift` | Yes — measure loop latency |

### 13.2 New Components Needed

| Component | Complexity | Notes |
|-----------|-----------|-------|
| **File watcher** | Low | `DispatchSource` / `FSEvents` wrapper |
| **`ModelSpaceCache`** | Low | Cache per-file `ModelSpace` parse results; rebuild fresh `AppModel` on change — zero changes to existing model code |
| **Mock API server** | Medium | HTTP router that serves model-derived responses using `SampleJson` |
| **Stateful mock store** | Medium | Optional library actor that backs CRUD-style mock behavior |
| **Preview UI** (Lit web app) | Medium-Large | New browser app; entity explorer, API explorer, "Try It" panel |
| **Process manager** | Medium | Spawn/monitor framework dev servers |
| **`PreviewSession` orchestrator** | Medium | Coordinates file watcher, build session, mock server, process manager |
| **Preview-specific WebSocket messages** | Low | New message types on existing infrastructure |
| **Default UI detection** | Low | Check if container has a UI blueprint; if not, serve built-in preview |
| **Debounce/coalesce logic** | Low | Timer-based debounce for Loop 1 and Loop 2 |
| **Reusable hydrate/validate runner** | Low-Medium | Loop 1 needs the existing Hydrate + Validate logic without running Render/Persist |
| **`PreviewCoreOptions` + `PreviewConfig` split** | Low-Medium | Library behavior knobs + CLI wrapper config |

---

## 14. Blueprint Awareness

### 14.1 How to Detect "No UI Blueprint"

The default preview UI triggers when a container has **only** API-generating blueprints and no UI blueprint. Detection:

1. Parse all containers' `#blueprint(name)` tags.
2. Check if any blueprint is a "UI blueprint" (generates a web/mobile app).
3. If none → serve the default built-in preview UI.

**How to know if a blueprint is UI-typed?** Options:
- **Convention**: blueprint names starting with `ui-` or `web-` or `mobile-`.
- **Metadata**: a `blueprint.json` or front-matter in `main.ss` declaring `type: ui` vs `type: api`.
- **Container type**: `containerType == .webApp` or `.mobileApp` implies UI.
- **Heuristic**: if the blueprint generates `.html`, `.tsx`, `.vue` files → UI.

**Recommendation:** Use this priority order:

1. **Explicit blueprint metadata** (`type: ui` / `type: api`) if available.
2. **Naming convention** (`ui-*`, `web-*`, `mobile-*`) if no explicit metadata exists.
3. **Container type** only as a fallback when blueprint metadata is missing.

This matches the product rule more closely: the default preview UI appears when there is **no UI blueprint**, not merely when the container happens to be `.microservices`.

### 14.2 Blueprint-Specific Dev Server Configuration

Each blueprint should be able to declare:
- What dev command to run (`npm run start:dev`)
- What ready pattern to look for
- What port the dev server binds to
- What install command to run first (`npm install`)
- What working directory (relative to output) to run in

This could live in `main.ss` front matter:

```
-----
symbols-to-load : typescript, mongodb_typescript
dev-command : npm run start:dev
dev-ready-pattern : Nest application successfully started
dev-install-command : npm install
dev-port : 3000
-----
```

Or in a separate `blueprint.json` / `blueprint.tconfig` file in the blueprint root.

### 14.3 Multi-Container Preview

A model may define multiple containers (e.g., `APIs` + `WebApp` + `Gateway`). The preview system needs to handle:
- Multiple framework dev servers running in parallel (each on its own port).
- The mock server covering all containers.
- The preview UI showing all containers with navigation.

The `ProcessManager` is designed for this — it manages processes by ID, one per container.

---

### 14.4 Infrastructure Dependencies for Real Server (Loop 2)

The real generated server (NestJS, Spring Boot) typically needs **external infrastructure** — a database, message broker, cache, etc. These are described in the model as `InfraNode`s inside `C4System` bodies.

| Blueprint | Typical Dependencies | How to Provide |
|-----------|---------------------|----------------|
| `api-nestjs-monorepo` | MongoDB | `docker run mongo` or Docker Compose |
| `api-springboot-monorepo` | PostgreSQL, Redis | Docker Compose |
| Future blueprints | RabbitMQ, Kafka, etc. | Docker Compose |

**Strategies:**

1. **Auto-generate `docker-compose.yml` for infra only** — the blueprints already generate `docker-compose.yml`. The process manager could run `docker compose up -d` for just the database services before starting the framework dev server.
2. **Use the mock server instead** — Loop 1's mock server avoids all infra dependencies. Only Loop 2 needs real databases.
3. **In-memory databases** — some frameworks support in-memory alternatives (H2 for Spring Boot, `mongodb-memory-server` for NestJS). Blueprint dev-server config could specify an in-memory profile.
4. **Skip real server by default** — `enableRealServer` defaults to `false`. The developer opts in when they're ready to test against real infra.

**Recommendation:** Default to mock-only (Loop 1). When `--real` is enabled, check for Docker, start infra via `docker compose up -d`, wait for readiness, then start the framework server.

---

## 15. Edge Cases and Complications

### 15.1 Parse Errors

If a `.modelhike` edit introduces a syntax error:
- Loop 1: `ModelSpaceCache.reparse()` fails. Since the old cached `ModelSpace` is only replaced on success, the cache is untouched. The previous `AppModel` stays valid. Show the error in the preview UI with the exact line/column.
- Loop 2: the pipeline fails. `BuildSession` doesn't update the manifest (§9.1 of incremental builds doc). Real server keeps running on the last-good code.
- The preview UI should show a prominent error banner: "Parse error in `orders.modelhike` line 42: ..."

### 15.2 Template Errors in Loop 2

A model change may be valid but trigger a template error in the blueprint (e.g., a new property type the blueprint doesn't handle). Loop 2 fails, but Loop 1 still works — the mock server reflects the new model even if real codegen can't handle it yet.

### 15.3 Common Model Changes

`common.modelhike` changes are **global invalidation** — every entity potentially changes (mixins, shared types). In Loop 1, `ModelSpaceCache` replaces only the common `ModelSpace` and rebuilds a fresh `AppModel` — no extra parsing of other files needed since their cached `ModelSpace`s are still valid. Loop 2 must do a full rebuild. `common.modelhike` changes are infrequent during active development.

### 15.4 Port Conflicts

The preview server, mock server, and framework dev servers all need ports. Strategy:
- Preview server: user-configured (default 4800).
- Mock server: same port as preview server, different path prefix (`/mock/`).
- Framework dev servers: use the ports assigned during hydration (3001, 3002, ...).

### 15.5 Framework Server Crashes

If the framework dev server crashes (bad generated code, missing dependency, etc.):
- Detect via process exit code.
- Show error in preview UI with stdout/stderr.
- Don't restart automatically — wait for the next model change (which triggers codegen → new files → framework restarts).

### 15.6 Large Models

A model with hundreds of entities across many files is where `ModelSpaceCache` shines — only the changed file is re-parsed while all others stay cached as `ModelSpace` objects.

The remaining bottleneck for very large models is `resolveAndLinkItems()`, which walks the entire model after every rebuild. For very large models:
- Profile `resolveAndLinkItems()` with `--perf` to measure its contribution.
- If it dominates: consider an eviction-based approach where the existing `AppModel` is mutated in place (avoiding the full re-link). This is significantly more complex (requires making `resolveAndLinkItems` re-runnable — see git history of this document for a detailed analysis) and should only be pursued if profiling proves the fresh-rebuild approach is too slow.

### 15.7 Binary Files and Non-Template Content

Blueprints can `copy-file` and `copy-folder` binary content (images, fonts, etc.). These bypass template rendering and are handled by `FileToCopy`. The mock server doesn't need them, but Loop 2's incremental persist should hash and track them normally.

### 15.8 `run-shell-cmd` in Blueprints

Some blueprints use `run-shell-cmd` to execute shell commands during generation (though the current blueprints don't). In preview mode, these should either:
- Run normally (they're part of the generation).
- Be skippable via a config flag (`PreviewConfig.allowShellCommands`).
- Have their output captured and shown in the preview UI.

### 15.9 Loop 1 → Loop 2 Model Sharing

Loop 1 builds a fresh `AppModel` from cached `ModelSpace`s (via `ModelSpaceCache`). Loop 2 creates a fresh `Pipeline` (via `BuildSession`'s `pipelineFactory`), which creates a fresh `Workspace` → fresh `LoadContext` → fresh `AppModel`. The two loops parse the model **independently**.

This means:
- The model is parsed twice on every change (once for Loop 1 via `ModelSpaceCache`, once for Loop 2 via full pipeline).
- Loop 2 doesn't benefit from Loop 1's cached `ModelSpace`s.

**Optimization:** Pass Loop 1's already-parsed `AppModel` into Loop 2's pipeline, skipping Discover + Load + Hydrate. This requires:
1. A new pipeline preset that starts from a pre-loaded model: `Pipelines.renderFromModel(model:)`.
2. Or: inject the model into the `Pipeline`'s `Workspace` before running, then skip the early phases.

**Risk:** The model state must be immutable or safely cloned between loops. Since model objects are actors, concurrent access is safe, but mutation during Loop 2's render could cause inconsistency. The safest approach: Loop 1 produces a **snapshot** of the model that Loop 2 consumes.

**Recommendation for Phase 1:** Don't optimize — let both loops parse independently. The re-parse is fast (<200ms). Optimize this only if `--perf` shows Discover+Load+Hydrate is a bottleneck in Loop 2.

### 15.10 Model JSON Serialization for Preview UI

The preview UI needs model data as JSON. Today's `DebugRouter` serves `/api/model` from a captured `DebugSession.model`, but this is a debug-specific format.

For the preview UI, we need to serialize:
- `C4System` (name, description, containers, infraNodes, groups)
- `C4Container` (name, containerType, modules)
- `C4Component` (name, entities, DTOs, UIViews, submodules, port from attribs)
- `DomainObject` (name, properties, methods, APIs, mixins, dataType, annotations, tags)
- `Property` (name, type, required, constraints, defaultValue, validValueSet)
- `MethodObject` (name, parameters, returnType, logic summary)
- `DtoObject` (name, fields)
- `UIView` (name, members)
- API metadata (type, path, baseUrl, queryParams)

**Challenge:** All model types are `actor`s. Serializing them requires `await` on every property access. A synchronous `Codable` conformance won't work.

**Options:**
1. **Async serialization function:** `func toJSON() async -> [String: MockValue]` on each model type. Match the wrapper pattern (`C4Container_Wrap` etc.) but output dictionaries instead of template values.
2. **Snapshot structs:** Create lightweight `Codable` mirror structs (e.g., `EntitySnapshot`, `PropertySnapshot`) that capture the actor state into plain structs, then JSON-encode those.
3. **Reuse wrappers:** The existing `_Wrap` types already extract data from actors. Add `Codable` conformance to wrappers (or a `toJSON()` method).

**Recommendation:** Snapshot structs (option 2). They're clean, `Codable`, `Sendable`, and decouple the serialization format from the actor internals. The snapshot is built once per model update and served to all API requests and WebSocket broadcasts.

### 15.11 Mock State Invalidation on Schema Change

If the mock server is stateful (§6.4), a schema change invalidates stored data:
- **New required property added** → existing mock records are missing it.
- **Property removed** → existing records have stale fields.
- **Type changed** → existing values may be wrong type.

**Strategy:** On model update, diff the entity schema. If the schema changed:
1. Clear the in-memory store for that entity.
2. Re-seed with fresh `SampleJson` data matching the new schema.
3. Notify the preview UI that mock data was reset.

This is invisible to the developer — the mock store always matches the current model.

**Placement detail:** the library-owned `MockStateStore` should expose `invalidate(entity:)` / `resetAll()` operations. The CLI `PreviewSession` decides when to call them based on the `ModelDiff` produced during Loop 1.

### 15.12 Mobile App Containers

For containers with `containerType == .mobileApp`, the preview system behaves differently:

| Aspect | API Container | Web App Container | Mobile App Container |
|--------|--------------|-------------------|---------------------|
| Mock server | Yes — mock API endpoints | Yes — if it has APIs | Yes — if it has APIs |
| Default preview UI | Yes — always (API explorer) | No — the web app IS the UI | Yes — API explorer for its backend APIs |
| Real server (Loop 2) | Framework dev server | `npm run dev` (Vite/etc) | Xcode build / `flutter run` / etc. |
| Preview rendering | Browser | Browser | **Not browser-based** |

**Mobile-specific challenges:**

1. **No browser preview of the app itself.** A mobile app can't run in a browser. The preview system can show the model (entities, APIs, schemas) but not the actual mobile UI.
2. **Simulator integration** is possible but heavyweight — `xcrun simctl` for iOS, Android emulator CLI. This is a much larger scope than web preview.
3. **The mock API server is still valuable.** Mobile developers can point their app (running in a simulator or on a device) at the mock server URL. The mock server serves on `localhost`, which simulators can reach.
4. **Hot reload** depends on the mobile framework: SwiftUI Previews, Flutter hot reload, React Native fast refresh. These have their own file-watching — Loop 2 writes files, the mobile framework detects them.

**Recommendation for Phase 1:** Treat mobile containers the same as API containers in the preview system — show the default preview UI (entity/API explorer) and run the mock server. Defer simulator integration to a future phase. The mock server at `http://localhost:{port}/mock/` is immediately useful for mobile developers testing against the backend.

### 15.13 Generated Code Preview

Beyond the running API, developers may want to see the **generated source code** in the preview UI — like the debug console's source/output split view but driven by the preview workflow.

After Loop 2 completes, the incremental build report contains a list of changed files. The preview UI could show:
- A file tree of generated output (reuse the debug console's `file-tree-panel`).
- Source view of any generated file.
- Diff view highlighting what changed in this regeneration cycle.

This bridges the gap between "what my model describes" (preview UI) and "what code was generated" (generated code view).

### 15.14 `UIView` and UI Preview Limitations

The default preview UI is fine for API-first projects, but there is an important distinction:

- **Default preview UI**: built-in explorer/admin shell that ModelHike provides when there is no UI blueprint.
- **Model-defined UI preview**: a future feature where `.modelhike` `UIView` declarations themselves drive rendered UI.

The current codebase is only ready for the first one. It is **not yet ready** for the second one because `UIView` metadata is too sparse in both parsing and template wrappers (see §7.4).

So when the document says "live preview updates on every model change," the reliable interpretation today is:
- entity schema changes
- API changes
- validation changes
- container/module topology changes

not full WYSIWYG preview of `UIView`-declared screens.

### 15.15 Out-of-Order Loop 1 Completion

Debouncing reduces work, but it does **not** guarantee correctness when two Loop 1 runs overlap:

1. Save A starts Loop 1 run #10.
2. Save B arrives before #10 finishes and starts run #11.
3. Run #10 finishes last and incorrectly overwrites the newer model from #11.

The fix is simple: keep a monotonic `loop1Generation` counter in `PreviewSession`. Each Loop 1 run captures the current generation before starting async work. Before publishing `currentModel`, reconfiguring the mock server, or broadcasting `model-updated`, compare the captured generation to the latest one. If they differ, discard the stale result.

This matters for rapid typing, auto-save, and big model files where parse/link work can overlap across edits.

---

## 16. Library vs CLI Placement

Following the same principle as the incremental builds architecture doc:

### 16.1 Definitely Library

| Component | Reason |
|-----------|--------|
| `ModelSpaceCache` | Core re-parse concern — caches per-file `ModelSpace` results, rebuilds fresh `AppModel`; zero changes to `AppModel` or `resolveAndLinkItems` |
| Model snapshotting (`AppModelSnapshot`) | Pure data transformation of actor state → `Codable` structs |
| Model diffing (`ModelDiff`) | Pure comparison of two snapshot structs |
| Mock data generation (`MockResponseBuilder`) | Derives JSON from `PropertyKind` + model constraints |
| Stateful mock store (`MockStateStore`) | Optional in-memory CRUD engine keyed by entity; transport-neutral runtime logic |
| Mock route derivation (`MockRouteTable`) | Maps Entity → API → HTTP method + path; pure model introspection |
| Mock request validation (`MockRequestValidator`) | Validates request body against model schema; uses existing expression evaluator |
| Preview protocol definitions (message shapes) | Defines JSON contract for WebSocket/REST communication |
| `FileWatcher` protocol (not implementation) | Reusable abstraction; implementations are CLI |
| Default UI detection logic | Inspects `#blueprint(name)` tags + container metadata; pure model query |
| Debounce utility (`Debouncer`) | Generic timer-based coalescing; useful in tests and IDE plugins |
| `PreviewCoreOptions` | Pure preview behavior knobs (`mockDataSeed`, route mode, list count, mock mode) |
| `BuildSession` (from incremental builds) | Already decided in `incremental-builds-architecture.md` |

### 16.2 Definitely CLI / DevTester

| Component | Reason |
|-----------|--------|
| `PreviewSession` orchestrator | Owns NIO server, file watcher impl, process manager — all I/O. See [live-preview-architecture.md §7](./live-preview-architecture.md#7-why-previewsession-is-cli-not-library) for detailed reasoning. |
| Preview UI HTML/CSS/JS assets | Presentation layer |
| `ProcessManager` (spawning real dev servers) | OS-specific, deployment-specific |
| Preview & Mock HTTP server (SwiftNIO) | Requires `NIOCore`, `NIOHTTP1` |
| WebSocket broadcast infrastructure | Requires `NIOWebSocket` |
| `DispatchSource` / `FSEvents` implementation of `FileWatcher` | Platform-specific |
| `PreviewConfig` struct | Wrapper over `PreviewCoreOptions` plus port, watch paths, browser behavior, real-server toggles, and derived `PipelineConfig` |
| Blueprint dev-server configuration parsing | CLI-level config (reads `dev-command` etc. from front matter) |
| Browser auto-open | OS-specific (`NSWorkspace`) |
| CLI argument parsing (`--preview`, `--real`) | CLI-specific |

### 16.3 Relationship to `BuildSession`

`PreviewSession` (CLI) **owns** a `BuildSession` (library) for Loop 2. The library provides the brains; the CLI provides the body:

```
PreviewSession (CLI)
  ├── FSEventsFileWatcher (CLI impl of library FileWatcher protocol)
  ├── Debouncer × 2 (library)
  ├── PreviewCoreOptions (library)
  ├── ModelSpaceCache (library — Loop 1: cache per-file parse, rebuild fresh AppModel)
  ├── AppModelSnapshot + ModelDiff (library)
  ├── MockRouteTable + MockResponseBuilder + MockStateStore (library)
  ├── MockHTTPServer (CLI — NIO, uses library's route table + builder)
  ├── BuildSession (library — Loop 2)
  │   └── Pipeline (per run)
  ├── ProcessManager (CLI — optional)
  └── PreviewHTTPServer (CLI — NIO, serves UI + WebSocket)
```

---

## 17. Phased Implementation

### Phase 0: Foundations

1. Implement `BuildSession` and incremental persist (from the incremental builds doc).
2. Implement `FileWatcher` protocol + macOS implementation.
3. Add `Pipelines.codegenRenderOnly` preset.

### Phase 1: Minimal Live Rebuild

- File watcher detects `.modelhike` changes.
- Full pipeline re-runs (no selective parse yet).
- Incremental persist writes only changed files.
- Console output shows what changed.
- **No preview UI, no mock server** — just the rebuild loop.
- **CLI flag:** `swift run DevTester --watch` or `modelhike watch`.

### Phase 2: Mock API Server

- Implement model-driven mock API server on the existing NIO server.
- Derive canonical preview routes from `C4Container` → `C4Component` → entities → APIs.
- Serve mock JSON using `MockResponseBuilder` (wrapping `SampleJson` where useful).
- Basic request validation from model metadata.
- **CLI flag:** `swift run DevTester --preview`.

### Phase 3: Default Preview UI

- Build the preview UI as Lit web components (same architecture as debug console).
- Entity explorer, API explorer, "Try It" panel.
- WebSocket-driven live updates on model change.
- Detect API-only containers and auto-serve the preview UI.

### Phase 4: Loop 1 — Instant Model Preview

- Implement `ModelSpaceCache` (cache per-file `ModelSpace`, rebuild fresh `AppModel` on change).
- Zero changes to `AppModel` or `resolveAndLinkItems` — they work as-is.
- Implement model snapshotting and diffing.
- Loop 1 runs in ~100-180ms.
- Preview UI updates instantly on model change.
- Loop 2 runs in background.

### Phase 5: Process Manager

- Implement `ProcessManager` for spawning framework dev servers.
- Ready detection, crash handling, stdout/stderr capture.
- Blueprint dev-server metadata (front matter or blueprint.tconfig).
- Preview UI shows real server status and toggle (mock vs real).

### Phase 6: Polish

- Multi-container preview (parallel dev servers).
- Stateful mock server (`MockStateStore` in library, wired by `PreviewSession` in CLI).
- Model diff visualization in preview UI.
- Error overlay for parse/template errors.
- Performance monitoring and optimization.

---

## 18. Testing Strategy

### 18.1 Unit Tests

| Component | What to Test |
|-----------|-------------|
| `ModelSpaceCache` basic | Parse files A and B, modify A, call `reparse` — only A is re-parsed; `buildModel` produces correct model |
| Cross-file type reference | File A defines `Order`, file B has `order: Order`. Re-parse A with `Order` renamed to `Purchase`. Fresh `AppModel` from `buildModel` has B's property type updated (or W301 if not found) |
| Cross-file mixin | File A entity mixes in `Audit` from common. Re-parse file B (unrelated). Fresh `AppModel` has A's mixin intact |
| Hash-based skip | Same content hash → `reparse` returns false, no rebuild |
| Deterministic replay order | Two files define conflicting overrides; cache replay in sorted-path order matches full-build ordering every time |
| `common.modelhike` change | Re-parse common → `buildModel` rebuilds all with new shared types |
| File delete / rename | Delete removes old cached `ModelSpace`; rename behaves as remove old path + parse new path |
| Parse error recovery | Re-parse fails → keep old cached `ModelSpace`, don't rebuild; previous model stays valid |
| Model snapshot diffing | Modify entity A, diff snapshots, verify only A is marked changed |
| Stale Loop 1 suppression | Run two overlapping Loop 1 updates; older one completes last and is discarded via generation token |
| Mock route derivation | Given a model with entities + APIs, verify correct HTTP method + path mapping |
| Mock data generation | `MockResponseBuilder` produces valid JSON for each `PropertyKind`, including optional fields and arrays |
| Mock state store | `create` / `update` / `delete` / `list` semantics are correct; `invalidate(entity:)` only clears affected entity data |
| Debounce logic | Rapid events coalesce into single callback; timer resets on new event |
| Loop 2 coalescing | A change arriving during Loop 2 marks one pending rerun; only one fresh rerun starts after the current run completes |
| Schema snapshot | Actor model → snapshot struct → JSON round-trip |
| Mock state invalidation | Schema change clears and re-seeds affected entity data |
| Prefix-aware routing | `/preview/*` and, if enabled, `/debug/*` static assets resolve correctly |

### 18.2 Integration Tests

| Scenario | What to Verify |
|----------|---------------|
| Full Loop 1 | Edit `.modelhike` on disk → file watcher fires → model re-parsed → mock server has new route → WebSocket message sent |
| Full Loop 2 | Edit `.modelhike` → `BuildSession.run()` → correct files written → IncrementalStats show expected changed/skipped counts |
| Parse error recovery | Introduce syntax error → Loop 1 keeps last-good model → fix error → Loop 1 updates to new model |
| Mock server CRUD | POST to create → GET by ID returns it → PUT to update → GET shows updated → DELETE → GET returns 404 |
| WebSocket broadcast | Connect N clients → model change → all N receive `model-updated` |

### 18.3 End-to-End Tests

These require a test model, a test blueprint, and a running preview server:

1. Start `PreviewSession` with a fixture model.
2. Verify preview UI loads and shows entities.
3. Append a new entity to the `.modelhike` file.
4. Verify preview UI shows the new entity within 500ms.
5. Verify mock server responds to the new entity's endpoints.
6. Verify Loop 2 generates the expected files.

**Test infrastructure:** Use `TemporaryDirectory` for output, a minimal test blueprint (2-3 files per entity), and `URLSession` for HTTP assertions against the preview/mock server.

---

## 19. Open Questions

1. **Should the mock server support WebSocket/gRPC APIs?** The model supports `pushData`/`pushDataList` (which could be WebSocket) and gRPC (GraphQL modifier lib exists). Mock server for these is more complex.

2. **How deep should mock validation go?** Basic required/type checking is straightforward. Full constraint evaluation (`{ salary > 0 }`, `{ min = 0, max = 10 }`) requires running the expression evaluator against request data.

3. **Should the preview UI support editing the model?** A truly live experience could allow editing entity properties directly in the browser, which writes back to the `.modelhike` file. This is a much larger scope (bidirectional sync).

4. **How does this interact with the visual debugger?** Can debug and preview run simultaneously? They share the NIO server, but the debug console expects pipeline events while the preview expects model metadata.

5. **Should preview mode generate documentation?** The blueprints generate PlantUML class diagrams (`plantuml.classes`). The preview UI could render these as live diagrams (using a PlantUML renderer or Mermaid).

6. **How to handle cross-container references?** If entity A in container X references entity B in container Y, the mock server needs to serve consistent data across both.

7. **Should the `PreviewSession` persist its state across restarts?** If the developer restarts the preview, should it pick up where it left off (same mock data, same model state)? The `BuildManifest` already handles incremental codegen state; the mock server state could be persisted similarly.

8. **How will blueprint authors test their blueprints in preview mode?** A blueprint author editing `.teso` files needs Loop 2 to re-render. The file watcher already covers `.teso` and `.ss` extensions. But the preview UI would need to show "regenerating..." status clearly.

---

**Related Documents:**
- [Live Preview Architecture — Library vs CLI Split](./live-preview-architecture.md) — details which components belong in the pure Swift library vs the CLI project
- [Incremental Builds — Technical Design](../incremental-builds/incremental-builds.md) — dependency analysis, 4-phase plan, complications
- [Incremental Builds — Architecture Decision](../incremental-builds/incremental-builds-architecture.md) — library vs CLI split, `BuildSession`, primitives, testing
- `AGENTS.md` — project structure, pipeline phases, debug server architecture
- `Docs/debug/VISUALDEBUG.md` — existing debug server architecture and WebSocket protocol
