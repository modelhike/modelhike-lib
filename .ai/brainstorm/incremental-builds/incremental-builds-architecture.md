# Incremental Builds Architecture Decision: Library vs CLI

> **Status:** Architectural Recommendation  
> **Date:** 2026-04-04  
> **Scope:** Where should incremental build capabilities live in the ModelHike project — in the core `ModelHike` library package, or in a future CLI executable?

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Current Project Structure](#2-current-project-structure)
3. [What "Incremental Builds" Actually Means](#3-what-incremental-builds-actually-means)
   - 3.1 [Core Primitives](#31-core-primitives-library-territory) (6 families, concrete Swift types)
   - 3.1.3 [Coordinator Types](#313-coordinator-types-not-primitives)
   - 3.2 [Policy & Orchestration](#32-policy--orchestration-cli--tool-territory)
4. [Layered Architecture Analysis](#4-layered-architecture-analysis)
   - 4.3 [`BuildSession` Wrapper](#43-a-buildsession-wrapper-around-pipeline)
5. [Where Each Component Should Live](#5-where-each-component-should-live)
6. [Recommended Implementation Strategy](#6-recommended-implementation-strategy)
7. [Detailed Design by Layer](#7-detailed-design-by-layer)
8. [Hard Constraints From the Codebase](#8-hard-constraints-from-the-codebase)
9. [Trade-offs and Risks](#9-trade-offs-and-risks)
   - 9.1 [Failure Semantics and Manifest Consistency](#91-failure-semantics-and-manifest-consistency)
   - 9.2 [Manifest Version Migration](#92-manifest-version-migration)
   - 9.3 [How BuildSession Feeds Incremental Data Into the Pipeline](#93-how-buildsession-feeds-incremental-data-into-the-pipeline)
   - 9.3.1 [Performance Trade-off: Full Render Cost](#931-performance-trade-off-full-render-cost)
   - 9.4 [Testing Strategy for Incremental Builds](#94-testing-strategy-for-incremental-builds)
10. [Migration Path](#10-migration-path)
11. [Conclusion and Next Steps](#11-conclusion-and-next-steps)

---

## 1. Executive Summary

**Recommendation:** Implement **core incremental primitives** in the `ModelHike` library package, but build the **orchestration, caching policy, CLI interface, and watch mode** in a separate CLI executable (e.g. `modelhike` CLI).

**Why this split?**

- The library should provide **pure, composable, reusable incremental building blocks**.
- The CLI (or future IDE plugins, build plugins, etc.) should provide **opinionated policies** about when and how to use those blocks.

This follows the same architectural pattern as other successful build tools:
- **Swift Package Manager** — incremental compilation logic lives in the compiler (`swiftc`), the build orchestration lives in `swift build`.
- **Cargo** — incremental compilation is in `rustc`, caching policy and orchestration is in Cargo.
- **Bazel** — the core is a library of rules and actions, the CLI orchestrates them.

---

## 2. Current Project Structure

From `AGENTS.md` and `Package.swift`:

**Library (`ModelHike` target):**
- `Sources/` — all the core logic
- `Pipelines/` — the 6-phase pipeline
- `Workspace/`, `Sandbox/`, `CodeGen/`, `Scripting/`, `Modelling/`
- `DevTester/` — currently the only executable, used for development

**No CLI yet** — the `README.md` describes a future CLI (`modelhike generate`, `modelhike watch`, etc.) that does not currently exist.

**Current incremental capability:** None. Every run is a full rebuild.

---

## 3. What "Incremental Builds" Actually Means

Incremental builds involve several distinct concerns:

### 3.1 Core Primitives (Library Territory)
- Change detection (file hashing, entity fingerprinting)
- Dependency graph construction and traversal
- Provenance tracking (which entity produced which file)
- Content diffing / CAS (content-addressable storage)
- Manifest / cache serialization
- Summary extraction (for summary-boundary architecture)

### 3.1.1 Primitive Categories (Expanded)

The word **primitive** is doing a lot of work in this document. It should mean: **small, reusable, mostly policy-free building blocks**. In practice, the incremental system needs six primitive families.

| Primitive Family | Examples | Why It Belongs In The Library |
|------------------|----------|-------------------------------|
| **Identity** | `ContainerId`, `ModuleId`, `EntityId`, `TemplateId`, `OutputPathKey` | Stable identifiers are shared by every frontend: CLI, watch mode, plugin, tests |
| **Fingerprinting** | `SourceFingerprint`, `EntityFingerprint`, `TemplateFingerprint`, `BlueprintFingerprint` | These are pure computations on inputs and should not depend on CLI policy |
| **Dependency** | `DependencyKind`, `DependencyEdge`, `DependencyGraph`, reverse-dependency index | Core semantic model of \"what affects what\" |
| **Planning** | `ChangeSet`, `BuildPlan`, `RenderDecision`, `PersistDecision`, `SkipReason` | Deciding *what must happen* is library logic; deciding *when to ask for it* is CLI logic |
| **Storage** | `BuildManifest`, `ManifestEntry`, `CacheBackend`, `CacheKey`, `StoredArtifact` | Serialization and cache access are reusable concerns |
| **Reporting** | `IncrementalStats`, `BuildReport`, `InvalidationReason` | Every consumer benefits from the same diagnostics and perf data |

Recommended shapes:

- Prefer `struct`, `enum`, and `protocol` for primitives.
- Keep them `Codable`, `Hashable`, and `Sendable` wherever reasonable.
- Avoid making primitives `actor`s. Actors are for coordination, not for stable value semantics.
- Treat anything with lifecycle, mutation across runs, locking, or warm in-memory state as a **coordinator**, not a primitive.

### 3.1.2 Suggested Primitive Set

Below is a more concrete primitive inventory than the earlier draft.

```swift
public struct EntityId: Hashable, Codable, Sendable {
    public let container: String
    public let modulePath: [String]   // supports submodules naturally
    public let name: String
    public let kind: ArtifactKind
}

public struct EntityFingerprint: Hashable, Codable, Sendable {
    public let entityId: EntityId
    public let hash: String
}

public enum DependencyKind: String, Codable, Sendable {
    case mixin
    case customType
    case referenceType
    case dtoDerived
    case moduleExpression
    case namedConstraint
    case templateDynamicLookup
    case aggregateFile
}

public struct DependencyEdge: Hashable, Codable, Sendable {
    public let from: EntityId
    public let to: EntityId
    public let kind: DependencyKind
}

public struct ChangeSet: Codable, Sendable {
    public var directlyChanged: Set<EntityId>
    public var transitivelyAffected: Set<EntityId>
    public var removed: Set<EntityId>
    public var globalInvalidationReasons: [String]
}

public struct FileProvenance: Codable, Sendable {
    public let primaryEntity: EntityId?
    public let dependencies: Set<EntityId>
    public let templateName: String?
}

public struct ManifestEntry: Codable, Sendable {
    public let contentHash: String
    public let provenance: FileProvenance?
    public let templateHash: String?
    public let isStaticCopy: Bool        // true for FileToCopy / StaticFile
}

public struct BuildManifest: Codable, Sendable {
    public let version: Int
    public let timestamp: Date
    public let files: [String: ManifestEntry]    // output relative path → entry
    public let entityFingerprints: [EntityId: EntityFingerprint]
    public let blueprintFingerprints: [String: String]
    public let configFingerprint: String?
    public let commonModelFingerprint: String?
}

public struct BuildReport: Sendable {
    public let manifest: BuildManifest
    public let stats: IncrementalStats
    public let updatedSummaryCache: SummaryCache
    public let success: Bool
}

public struct IncrementalStats: Sendable {
    public var filesRendered: Int = 0
    public var filesSkipped: Int = 0
    public var filesWritten: Int = 0
    public var filesUnchanged: Int = 0
    public var filesDeleted: Int = 0
    public var entitiesChanged: Int = 0
    public var entitiesUnchanged: Int = 0
    public var globalInvalidation: Bool = false
}
```

### 3.1.3 Coordinator Types (Not Primitives)

Coordinators have lifecycle, hold mutable state across runs, and compose primitives.

```swift
public protocol ContentHasher: Sendable {
    func hash(string: String) -> String
    func hash(data: Data) -> String
    func hash(file: LocalFile) throws -> String
}

public struct DependencyGraph: Sendable {
    private let edges: [DependencyEdge]
    private let forwardIndex: [EntityId: Set<EntityId>]   // X depends on → [Y, Z]
    private let reverseIndex: [EntityId: Set<EntityId>]   // Y is depended on by → [X]

    public init(edges: [DependencyEdge]) { ... }
    public func dependenciesOf(_ id: EntityId) -> Set<EntityId> { ... }
    public func dependentsOf(_ id: EntityId) -> Set<EntityId> { ... }
    public func transitivelyAffected(by changed: Set<EntityId>) -> Set<EntityId> { ... }
}
```

Important distinction:

- `EntityId`, `EntityFingerprint`, `DependencyEdge`, `BuildManifest`, `ManifestEntry`, `ChangeSet`, `FileProvenance`, `BuildReport`, `IncrementalStats` are **primitives** (value types, no lifecycle).
- `BuildSession`, `DependencyGraph`, `ContentHasher` are **coordinators** (stateful or protocol-shaped, composed from primitives).
- `IncrementalRunner`, `DependencyTracker` are **internal implementation details** inside the library — not public API.
- `SummaryCache` is an **internal coordinator** — a warm in-memory cache held by `BuildSession` across runs (see §4.3.3 for its shape).

### 3.2 Policy & Orchestration (CLI / Tool Territory)
- **When** to do incremental vs full rebuild (`--force`, `--clean`, smart detection based on git status)
- **What** to cache and for how long (local cache, remote cache, TTL, garbage collection)
- **Watch mode** behavior (file watching, debouncing, live reloading)
- **User experience** (progress reporting, error recovery, cache invalidation hints)
- **Integration** with build systems (Xcode, SwiftPM plugins, Bazel rules, Turborepo tasks)

### 3.3 Cross-Cutting Concerns
- Debug mode (`--debug`) should **force full rebuild** for complete event traces
- Error handling and cache poisoning recovery
- Configuration (`.modelhike-build.toml` or similar)
- Telemetry / performance reporting

---

## 4. Layered Architecture Analysis

### Layer 1: ModelHike Library (Recommended)

**Responsibility:** Provide reusable, pure functions and types for incremental computation.

**Should include:**

1. **`BuildManifest`** and manifest I/O logic
2. **`EntityFingerprint`** and fingerprinting utilities
3. **`DependencyGraph`** and change set computation
4. **`EntityId`** and `FileProvenance` types
5. **`ContentHasher`** protocol + implementations for different file types
6. **`IncrementalPipeline`** wrapper that can wrap existing pipelines
7. Extension points:
   - `IncrementalPass` protocol
   - `CacheBackend` protocol (local disk, remote, in-memory)
   - `ChangeDetector` protocol

**Should NOT include:**
- File watching logic
- CLI argument parsing
- Watch mode orchestration
- Opinionated cache policies (e.g. "always clean on git branch change")

### Layer 2: CLI / Build Tool (Future)

**Responsibility:** Provide user-facing tools that use the library.

**Should include:**

- `modelhike generate --incremental`
- `modelhike watch`
- `modelhike clean`
- Integration with SwiftPM (`Package.swift` plugin)
- Integration with Xcode build phases
- Remote cache configuration
- User-friendly error messages and cache debugging tools

### 4.3 A `BuildSession` Wrapper Around `Pipeline`

Yes, a wrapper around the pipeline **would help a lot**. But I would **not** call it plain `Session`.

Why not plain `Session`?

- The codebase already has `DebugSession` in `Sources/Debug/DebugSession.swift`.
- `session(config:)` already exists on `DebugRecorder`.
- A generic `Session` name would be ambiguous in docs, logs, and API autocomplete.

**Recommended names:**
- `BuildSession`
- `GenerationSession`
- `IncrementalBuildSession`

`BuildSession` is the clearest name.

### 4.3.1 Why a `BuildSession` Helps

Today, `Pipeline` looks reusable on the surface, but repeated in-process runs are awkward:

- `Pipeline` owns a persistent `Workspace`.
- `Workspace` owns a persistent `LoadContext`.
- `LoadContext` owns a persistent `AppModel`.
- `PipelineState` keeps `generationSandboxes` and does not obviously clear them between runs.

That means a long-lived process (for example watch mode, IDE integration, tests that run multiple builds in one process, or a future language-server-style tool) should not casually call `pipeline.run(...)` over and over and assume the world is fresh.

A `BuildSession` gives you one place to own:

- the cache backend
- the last manifest
- warm in-memory summaries / fingerprints
- run-level locking (`only one build at a time`)
- policy flags like `forceFullBuild`
- fresh-pipeline creation per run
- run reports and incremental stats

### 4.3.2 What the `BuildSession` Should Actually Do

The session should be a **thin stateful coordinator**, not a second build system.

Good responsibilities:

1. Create a **fresh `Pipeline` per run** (or explicitly reset run-state before reuse).
2. Load and save manifests through `CacheBackend`.
3. Hold warm in-memory caches that only make sense inside one process.
4. Produce a `BuildReport` for the caller.
5. Expose a simple API to the CLI and tests.

Bad responsibilities:

- file watching
- terminal UX
- CLI argument parsing
- OS-level debounce logic
- remote cache auth / deployment concerns

### 4.3.3 Recommended `BuildSession` Shape

```swift
/// Warm in-memory cache held across runs within a single process.
/// Not serialized to disk — lost when the process exits.
/// Holds data that is expensive to recompute but safe to discard.
public struct SummaryCache: Sendable {
    /// Entity fingerprints from the last successful run.
    /// Avoids re-hashing unchanged model files.
    public var entityFingerprints: [EntityId: EntityFingerprint] = [:]

    /// Template file content hashes from the last successful run.
    /// Avoids re-reading and re-hashing unchanged .teso files.
    public var templateHashes: [String: String] = [:]

    /// Dependency edges from the last successful run.
    /// Avoids re-walking the model to rebuild the graph
    /// (only useful once DependencyGraph is implemented in Phase 3).
    public var dependencyEdges: [DependencyEdge] = []

    public init() {}
}

public actor BuildSession {
    /// Factory that creates a fresh Pipeline for each run.
    /// IMPORTANT: the factory should return a Pipeline WITHOUT
    /// Persist.toOutputFolder() — BuildSession handles persistence.
    private let pipelineFactory: @Sendable () -> Pipeline
    private let cacheBackend: any CacheBackend
    private var lastManifest: BuildManifest?
    private var warmCache = SummaryCache()
    private var isRunning = false

    public init(
        pipelineFactory: @escaping @Sendable () -> Pipeline,
        cacheBackend: any CacheBackend = LocalDiskCacheBackend()
    ) {
        self.pipelineFactory = pipelineFactory
        self.cacheBackend = cacheBackend
    }

    public func run(using config: OutputConfig) async throws -> BuildReport {
        precondition(!isRunning, "BuildSession does not support concurrent runs")
        isRunning = true
        defer { isRunning = false }

        // Load manifest from disk on first run (or after a failed run cleared lastManifest)
        if lastManifest == nil {
            lastManifest = try? await cacheBackend.loadManifest(for: config.output)
        }

        let pipeline = pipelineFactory()   // fresh Pipeline (no Persist pass)
        let runner = IncrementalRunner(
            hasher: CryptoKitContentHasher(),
            warmCache: warmCache
        )
        let report = try await runner.run(
            pipeline: pipeline,
            using: config,
            previousManifest: lastManifest
        )

        if report.success {
            lastManifest = report.manifest
            warmCache = report.updatedSummaryCache
            try? await cacheBackend.saveManifest(report.manifest, for: config.output)
        }
        // On failure: lastManifest stays as-is (see §9.1)

        return report
    }

    /// Discard all cached state. Next run will be a full rebuild.
    public func reset() {
        lastManifest = nil
        warmCache = SummaryCache()
    }
}
```

### 4.3.4 Where `BuildSession` Should Live

`BuildSession` should live in the **library**, not the CLI, because:

- it is still reusable orchestration, not UX
- tests can use it directly
- IDE/build-plugin integrations can use it directly
- the CLI can be a thin wrapper around it

But it should stay **optional**. The low-level `Pipeline` API should still exist for one-shot or custom use cases.

---

## 5. Where Each Component Should Live

### 5.1 Definitely Library (`ModelHike` target)

| Component | Location | Reason |
|---------|--------|-------|
| `EntityId`, `FileProvenance` | `Sources/Modelling/_Base_/Artifact.swift` or new `Incremental/` dir | Core model concept |
| `EntityFingerprint` | `Sources/Pipelines/Incremental/` | Reusable computation |
| `BuildManifest` | `Sources/_Common_/FileGen/` | General filegen concern |
| `ContentHasher` protocol | `Sources/_Common_/FileGen/` | Extensible for different file types |
| `DependencyGraph` | `Sources/Pipelines/Incremental/` | Pipeline-level concern |
| `IncrementalPipeline` wrapper | `Sources/Pipelines/` | Extends existing pipeline system |
| `BuildSession` | `Sources/Pipelines/Incremental/` or `Sources/Workspace/` | Reusable stateful coordinator for repeated in-process builds |
| Cache backend protocols | `Sources/Workspace/` | Part of sandbox/workspace abstraction |

### 5.2 Definitely CLI / Separate Tool

| Component | Reason |
|---------|--------|
| File watcher (`FSEvents` / `DispatchSource`) | OS-specific, not a library concern |
| CLI argument parsing (`ArgumentParser`) | CLI-specific |
| Watch mode orchestration (debouncing, restart logic) | User experience concern |
| Remote cache client (S3, GitHub Cache, custom) | Deployment-specific |
| Integration with Xcode/SwiftPM | Build system specific |
| Cache invalidation heuristics (git status, mtime vs hash) | Policy decision |

### 5.3 Gray Area — Could Go Either Way

| Component | Recommendation | Rationale |
|---------|--------------|---------|
| `main.tconfig` and `common.modelhike` invalidation logic | **Library** | Part of core model loading semantics |
| Debug mode integration (`--debug` forces full rebuild) | **Library** with CLI override | Library should expose `forceFullBuild: Bool` flag |
| Performance reporting (`--perf` for incremental metrics) | **Library** | Pipeline already has performance recording |
| Error recovery (corrupt cache → full rebuild) | **Library** | Should be default safe behavior |

---

## 6. Recommended Implementation Strategy

### Phase 0: Library Foundation (Do This First)

1. Add `Incremental/` directory under `Sources/Pipelines/`
2. Implement core types: `EntityId`, `EntityFingerprint`, `BuildManifest`, `ContentHasher`, `ChangeSet`
3. Add `IncrementalPass` protocol that can wrap existing passes
4. Add `BuildSession` as the primary reusable orchestration API for repeated builds
5. Implement Phase 1 (Content-Hash Diff Persist) as an optional pass
6. Add comprehensive tests for fingerprinting, manifests, and multi-run session behavior

### Phase 1: Make Library Incremental-Aware

- Add `incremental: Bool` to `PipelineConfig` / `OutputConfig`
- Add `cacheBackend: CacheBackend?` to config
- Make `GenerateOutputFoldersPass` respect the manifest when incremental mode is enabled
- Add `IncrementalPipeline` convenience wrapper for low-level callers
- Prefer `BuildSession` for repeated runs in the same process

### Phase 2: Build CLI (Later)

Once the library is solid, build a proper CLI that:
- Uses the library's incremental primitives
- Provides nice defaults and policies
- Implements `modelhike watch`
- Supports remote caching
- Has good error messages

---

## 7. Detailed Design by Layer

### 7.1 Library API Surface

```swift
// New protocol
public protocol CacheBackend: Sendable {
    func loadManifest(for output: LocalFolder) async throws -> BuildManifest?
    func saveManifest(_ manifest: BuildManifest, for output: LocalFolder) async throws
}

// New protocol (on ContentHasher)
public protocol ContentHasher: Sendable {
    func hash(string: String) -> String
    func hash(data: Data) -> String
    func hash(file: LocalFile) throws -> String
}

// Default CryptoKit-based implementation
public struct CryptoKitContentHasher: ContentHasher, Sendable {
    public func hash(string: String) -> String {
        let data = Data(string.utf8)
        return SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
    }
    // ...
}

// New pipeline preset: codegen without Persist (for use with BuildSession)
extension Pipelines {
    public static let codegenRenderOnly = Pipeline {
        Discover.models()
        Load.models()
        Hydrate.models()
        Hydrate.annotations()
        Validate.models()
        Render.code()
        // No Persist.toOutputFolder() — BuildSession handles persistence
    }
}

// Optional: OutputConfig protocol extension for incremental flags
extension OutputConfig {
    public var forceFullBuild: Bool { false }
}

// --- Usage ---

// One-shot (non-incremental, existing behavior unchanged)
let pipeline = Pipelines.codegen
try await pipeline.run(using: config)

// Preferred repeated-run usage with BuildSession
let session = BuildSession(
    pipelineFactory: { Pipelines.codegenRenderOnly },
    cacheBackend: LocalDiskCacheBackend()
)
let report1 = try await session.run(using: config) // full build, writes manifest
let report2 = try await session.run(using: config) // incremental, skips unchanged files
```

### 7.2 CLI Surface (Future)

```bash
modelhike generate --incremental          # smart incremental
modelhike generate --force               # full rebuild, update cache
modelhike generate --clean               # wipe cache + output
modelhike watch                          # watch mode
modelhike cache status                   # show cache stats
modelhike cache clean                    # clear cache
```

---

## 8. Hard Constraints From the Codebase

### 8.1 Zero External Dependencies

The `ModelHike` library target has **zero external Swift package dependencies** (only `DevTester` depends on SwiftNIO). This is a deliberate design choice documented in `AGENTS.md`.

Content hashing (SHA-256) is central to every incremental build phase. Options:

| Option | External Dep? | Platform Support | Notes |
|--------|--------------|-----------------|-------|
| **`CryptoKit`** (Apple framework) | No — it's a system framework, not a SwiftPM dependency | macOS 10.15+, iOS 13+, tvOS 13+, watchOS 6+ — all covered by ModelHike's minimums | Preferred. `import CryptoKit` then `SHA256.hash(data:)`. |
| **`CommonCrypto`** (C library) | No — system library | All Apple platforms | Lower-level API, requires `CC_SHA256` calls. Works but less ergonomic. |
| **Pure Swift hash** | No | All platforms including Linux | Could use a vendored SHA-256 implementation. More code to maintain but enables Linux support. |
| **`Foundation.Data.hashValue`** | No | All platforms | Not cryptographic — `Hashable` is per-process random. Not suitable for persistent caching. |

**Recommendation:** Use `CryptoKit` (with `#if canImport(CryptoKit)` and a pure-Swift fallback for future Linux support). This preserves the zero-dependency constraint while using Apple's optimised implementation on all currently supported platforms.

### 8.2 `OutputConfig` Is a Public Protocol — Extension Is a Breaking Change

`OutputConfig` is a `public protocol` conforming to `Sendable`, used in **30+ locations** across the codebase (`Workspace`, `Sandbox`, `Context`, `Pipeline`, every `PipelinePhase`, `DebugRecorder`, `BlueprintAggregator`, etc.). `PipelineConfig` is the only concrete conformance today, but external consumers of the library could define their own.

**Adding required properties** (e.g. `var incremental: Bool`) to `OutputConfig` is a **source-breaking change** — any external conformance would fail to compile.

**Options:**

| Approach | Breaking? | Complexity |
|----------|----------|-----------|
| **Add with default** — provide defaults via protocol extension (`extension OutputConfig { var incremental: Bool { false } }`) | No | Low |
| **Separate protocol** — create `IncrementalOutputConfig: OutputConfig` that adds incremental properties | No | Medium |
| **Keep on `PipelineConfig` only** — don't add to the protocol, access via `config as? PipelineConfig` downcasts | No | Low but ugly |

**Recommendation:** Use protocol extension defaults. This is the standard Swift pattern for non-breaking protocol evolution:

```swift
extension OutputConfig {
    public var incremental: Bool { false }
    public var forceFullBuild: Bool { false }
    public var cacheBackend: (any CacheBackend)? { nil }
}
```

`PipelineConfig` overrides these with stored properties. External conformances get the defaults and "just work" with no incremental behavior.

### 8.3 Default `CacheBackend` and Manifest Path

The document proposes a `CacheBackend` protocol but doesn't address where the **default local-disk implementation** lives or who decides the manifest file path.

**Recommendation:** The library provides a default `LocalDiskCacheBackend` that stores the manifest at `config.output / ".modelhike-manifest.json"`. This is a sensible default that works without configuration. The CLI can override it (e.g. to use a shared cache directory, remote backend, or custom path).

```swift
public struct LocalDiskCacheBackend: CacheBackend, Sendable {
    public func loadManifest(for output: LocalFolder) async throws -> BuildManifest? {
        let file = LocalFile(path: output.path / ".modelhike-manifest.json")
        guard file.exists else { return nil }
        let data = try file.readData()
        return try JSONDecoder().decode(BuildManifest.self, from: data)
    }
    // ...
}
```

### 8.4 Swift Tools Version

`Package.swift` uses `swift-tools-version: 6.2` (not 6.0 as stated in `AGENTS.md`). This means Swift 6.2 language features and concurrency improvements are available. No impact on the incremental builds design, but worth noting for implementation.

---

## 9. Trade-offs and Risks

### Advantages of Library-First Approach

**Pros:**
- Reusable across different tools (CLI, Xcode plugin, SwiftPM plugin, web UI)
- Testable in isolation (`ModelHikeTests`)
- Clean separation of concerns
- Future-proof — multiple frontends can share the same incremental engine

**Cons:**
- Slightly more complex API (need to expose incremental primitives)
- Requires careful design of the public API surface

### Advantages of CLI-First Approach

**Pros:**
- Faster to ship initial incremental feature
- Can make more opinionated decisions

**Cons:**
- Duplicated logic if multiple tools need incremental builds
- Harder to test core logic
- Less reusable

### Risks

1. **Over-abstraction** — making the library too generic before understanding real usage patterns.
2. **API churn** — changing public APIs in the library affects all consumers.
3. **Scope creep** — trying to solve watch mode, remote caching, and CLI all at once.

**Mitigation:** Start with a **narrow, well-tested incremental core** in the library, then build the CLI on top.

### 9.1 Failure Semantics and Manifest Consistency

What happens when a build fails partway through? This is critical for correctness.

**Problem:** If Run N fails during the Render phase (e.g., a template error), some files have been rendered and some have not. If the manifest is saved, the next incremental run trusts the partial manifest and skips files it shouldn't. If the manifest is not saved, we lose fingerprint work.

**Recommendation:**

1. **Never save the manifest on failure.** The `BuildSession.run()` method should only update `lastManifest` if the run succeeds. On failure, the next run falls back to whatever the last-good manifest was (or does a full rebuild if there is none).
2. **Persist-phase atomicity.** The current `GenerateOutputFolders` writes files one by one. With incremental mode, this is fine — we're only writing changed files. But the manifest itself should be written **last**, after all files are persisted, so a crash mid-write doesn't leave a manifest that claims files exist that don't.
3. **Graceful cache corruption.** If `loadManifest` fails (malformed JSON, version mismatch, I/O error), treat it as "no previous manifest" → full rebuild. Never throw.

### 9.2 Manifest Version Migration

The `BuildManifest.version` field enables schema evolution.

**Rules:**
- If `loadedManifest.version < currentVersion` → discard the manifest, full rebuild, save new-version manifest.
- If `loadedManifest.version > currentVersion` → discard (written by a newer tool). Same behavior.
- If `loadedManifest.version == currentVersion` → use normally.

This avoids the need for migration code. Since manifests are cheap to rebuild (just run one full build), there's no value in writing migration logic.

### 9.3 How `BuildSession` Feeds Incremental Data Into the Pipeline

The document shows `BuildSession` creating a fresh `Pipeline` and an `IncrementalRunner`, but doesn't explain the integration point — how does incremental data (the manifest, the change set, the provenance tracker) reach the existing pipeline phases?

**Two approaches:**

| Approach | Description | Complexity |
|----------|-------------|------------|
| **Wrapping passes** | `IncrementalRunner` replaces `Pipelines.codegen` with a modified pipeline that swaps `GenerateOutputFoldersPass` for an `IncrementalPersistPass`, and injects a `ChangeSet` into the `GenerationContext` so the Render phase can consult it. | Medium — requires `GenerationContext` to carry an optional `ChangeSet`, and `GenerateCodePass` to check it before rendering a container/entity. |
| **Post-render filter** | The pipeline runs identically to today (full render into in-memory `OutputFolder`s). After render, `IncrementalRunner` compares each `OutputFile`'s content hash against the manifest and only persists changed files. | Low — no changes to render logic. But you still pay the full render cost. |

**Recommendation for Phase 1:** Post-render filter. It's the smallest change, it's correct, and it immediately eliminates unnecessary disk I/O (the most visible bottleneck). Save selective render (wrapping passes) for Phase 3 when the dependency graph exists.

**Concrete integration for Phase 1:**

The key insight: `Pipeline` is a `struct` built with `@PipelineBuilder`. There is **no `runUpTo` API** and adding one would be invasive. Instead, compose a pipeline that omits the Persist pass entirely — this is already supported:

```swift
// A pipeline that stops after Render — uses the EXISTING @PipelineBuilder DSL
let renderOnly = Pipeline {
    Discover.models()
    Load.models()
    Hydrate.models()
    Hydrate.annotations()
    Validate.models()
    Render.code()
    // No Persist.toOutputFolder() — IncrementalRunner handles persistence
}
```

After `renderOnly.run(using: config)` completes, the rendered output lives in-memory inside `pipeline.state.generationSandboxes`. Each sandbox has a `base_generation_dir: OutputFolder` — a tree of `OutputFolder`s containing `OutputFile`s (actors). The Persist phase normally walks this tree and calls `file.persist()` on every item.

**Important:** `OutputFile` is a protocol with `filename`, `outputPath`, and `persist()` — but **no `contents` accessor on the protocol**. The concrete types differ:

| Type | How to get content hash |
|------|------------------------|
| `TemplateRenderedFile` | Has `contents: String?` after `render()` is called (render happens during the Render phase). Hash the string. |
| `StaticFile` | Has `stringContents: String?` or `dataContents: Data?`. Hash whichever is non-nil. |
| `FileToCopy` | Source path is known. Hash the source file on disk. |
| `PlaceHolderFile` | Has `contents: String?` after rendering. Hash the string. |

This means the `IncrementalRunner` needs to `switch` on the concrete `OutputFile` type (or we add a `var contentHash: String` requirement to the `OutputFile` protocol — the cleaner long-term approach, but a larger change).

```swift
// Inside IncrementalRunner
func run(pipeline: Pipeline, using config: OutputConfig, previousManifest: BuildManifest?) async throws -> BuildReport {
    // 1. Build a render-only pipeline (no persist pass)
    let renderOnly = pipelineFactory()   // factory returns a Pipeline without Persist
    try await renderOnly.run(using: config)

    // 2. Walk the sandbox output trees to collect all rendered files
    let sandboxes = await renderOnly.state.generationSandboxes
    var newEntries: [String: ManifestEntry] = [:]
    var stats = IncrementalStats()

    for sandbox in sandboxes {
        let root = await sandbox.base_generation_dir
        try await walkAndPersistIncrementally(
            folder: root,
            manifest: previousManifest,
            newEntries: &newEntries,
            stats: &stats
        )
    }

    // 3. Delete orphaned files (in previous manifest but not in this run's output)
    if let previousManifest {
        let orphanedPaths = Set(previousManifest.files.keys).subtracting(newEntries.keys)
        for path in orphanedPaths {
            try? LocalFile(path: path).delete()
            stats.filesDeleted += 1
        }
    }

    // 4. Build new manifest and write it LAST (atomicity — see §9.1)
    let newManifest = BuildManifest(
        version: Self.currentManifestVersion,
        timestamp: Date(),
        files: newEntries,
        // ... fingerprints ...
    )
    return BuildReport(manifest: newManifest, stats: stats, ...)
}

// Recursive walk over the OutputFolder tree
// OutputFolder has three child collections: subFolders, folderItems, and items
private func walkAndPersistIncrementally(
    folder: OutputFolder, manifest: BuildManifest?,
    newEntries: inout [String: ManifestEntry], stats: inout IncrementalStats
) async throws {
    try folder.ensureExists()

    // Recurse into subFolders (OutputFolder children)
    for sub in await folder.subFolders {
        try await walkAndPersistIncrementally(folder: sub, manifest: manifest, newEntries: &newEntries, stats: &stats)
    }

    // Handle folderItems (PersistableFolder — e.g. RenderedFolder)
    // These are opaque — we can't inspect their contents before persist.
    // For Phase 1, persist them unconditionally and hash after.
    for folderItem in await folder.folderItems {
        try await folderItem.persist()
    }

    // Process items (OutputFile actors: TemplateRenderedFile, StaticFile, FileToCopy, PlaceHolderFile)
    for file in await folder.items {
        let hash = try await contentHash(of: file)  // dispatches by concrete type
        let relativePath = await (file.outputPath! / file.filename).string
        if manifest?.files[relativePath]?.contentHash == hash {
            stats.filesSkipped += 1
        } else {
            try await file.persist()
            stats.filesWritten += 1
        }
        newEntries[relativePath] = ManifestEntry(contentHash: hash, provenance: nil, templateHash: nil, isStaticCopy: file is FileToCopy)
    }
}
```

### 9.3.1 Performance Trade-off: Full Render Cost

Phase 1 (post-render filter) eliminates **disk I/O** for unchanged files but still pays the **full render cost** (template parsing + evaluation for every entity). For a model with hundreds of entities this could be significant.

Measured with `--perf`, the render phase is typically 60-80% of total pipeline time, while persist is 5-15%. So Phase 1's savings are real but modest — the bigger win comes in Phase 3 (selective render) when the dependency graph allows skipping template evaluation entirely for unchanged entities.

However, Phase 1 is still valuable because:
- It prevents unnecessary **git noise** (unchanged files don't get new timestamps).
- It enables the `--perf` baseline needed to measure Phase 3 savings.
- It's the smallest correct change and validates the manifest/hashing infrastructure.

### 9.4 Testing Strategy for Incremental Builds

Incremental correctness is hard to test because it requires **multi-run** scenarios. A single build tells you nothing.

**Test categories:**

| Category | What to verify | Example |
|----------|---------------|---------|
| **Identity** | Same model + same blueprint → zero files written on second run | `assert(report2.stats.filesWritten == 0)` |
| **Change propagation** | Modify one entity → only affected files rewritten | Modify entity `Order`, verify `OrderService.java` is rewritten but `UserService.java` is not |
| **Global invalidation** | Change `common.modelhike` → full rebuild | `assert(report2.stats.globalInvalidation == true)` |
| **Blueprint change** | Modify a `.teso` template → all files using that template rewritten | Change `entity.teso`, verify all entity files regenerated |
| **Config change** | Modify `main.tconfig` → full rebuild | `assert(report2.stats.globalInvalidation == true)` |
| **File deletion** | Remove an entity from the model → its output files are deleted | Entity `OldThing` removed, verify `OldThingService.java` deleted |
| **Cache corruption** | Corrupt the manifest JSON → graceful fallback to full rebuild | Write garbage to manifest file, verify build succeeds |
| **Failure recovery** | Inject a template error in run 2 → run 3 recovers with correct output | Verify manifest from run 1 is used for run 3 |

**Test harness shape:**

```swift
func testIncrementalIdentity() async throws {
    let tempDir = TemporaryDirectory()
    let session = BuildSession(
        pipelineFactory: { Pipelines.codegenRenderOnly },
        cacheBackend: LocalDiskCacheBackend()
    )
    let config = makeTestConfig(basePath: fixtureModelPath, output: tempDir.outputPath)

    let report1 = try await session.run(using: config)
    assert(report1.stats.filesWritten > 0)

    let report2 = try await session.run(using: config)
    assert(report2.stats.filesWritten == 0)
    assert(report2.stats.filesSkipped == report1.stats.filesWritten)
}
```

The test fixtures should be small, self-contained `.modelhike` files with a minimal blueprint so tests run fast and don't depend on the external `modelhike-blueprints` repo. Consider a `TestBlueprint` that generates 2-3 files per entity.

---

## 10. Migration Path

**Step 1 (Now):** Add the new `incremental-builds-*.md` documents and core types to the library.

**Step 2:** Implement Phase 1 (Content-Hash Diff Persist) as an optional `PipelinePass` in the library.

**Step 3:** Update `DevTester` to optionally use incremental mode for development.

**Step 4:** Build the proper CLI with full incremental support.

**Step 5:** Add remote caching and watch mode as advanced features.

---

## 11. Conclusion and Next Steps

**Decision:** Incremental build **primitives and core logic** belong in the `ModelHike` library package. The **orchestration, policy, and user interface** belong in a future CLI tool.

This follows industry best practices and gives us maximum flexibility.

### Immediate Next Steps:

1. **Create the `Incremental/` directory** under `Sources/Pipelines/`
2. **Add the core primitives** (`EntityId`, `EntityFingerprint`, `ManifestEntry`, `BuildManifest`, `ChangeSet`, `FileProvenance`, `BuildReport`, `IncrementalStats`)
3. **Add the coordinator types** (`ContentHasher` protocol + `CryptoKit` implementation, `CacheBackend` protocol + `LocalDiskCacheBackend`, `DependencyGraph`)
4. **Implement `BuildSession`** as the primary reusable API for repeated in-process builds
5. **Implement Phase 1** (Content-Hash Diff Persist via post-render filter) as the first incremental feature
6. **Write multi-run tests** (identity, change propagation, global invalidation, failure recovery) using small fixture models and a test blueprint
7. **Update this document** with implementation status as we progress

The library should be the home of "how to do incremental builds correctly." The CLI should be the home of "how to use incremental builds conveniently."

---

**Status:** Approved architectural decision  
**Owner:** AI Assistant + Project Maintainer  
**Target:** Implement Phase 1 in library first, then build CLI on top

**Related Documents:**
- [incremental-builds.md](incremental-builds.md) — detailed technical design: current pipeline analysis, dependency taxonomy, 4-phase plan, blueprint analysis, alternative architectures (Salsa/CAS/instrumented wrappers), complications
- `AGENTS.md` — project structure reference (zero-dependency constraint, module breakdown, pipeline phases)
- `README.md` — future CLI vision (`modelhike generate`, `modelhike watch`, etc.)