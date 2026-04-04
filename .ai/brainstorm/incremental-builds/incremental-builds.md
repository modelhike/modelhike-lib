# Incremental Builds for ModelHike

> **Status:** Brainstorm / Design Analysis  
> **Date:** 2026-04-04  
> **Scope:** Analyse the current full-rebuild pipeline and design an incremental build system where only files affected by model changes are regenerated.

---

## Table of Contents

1. [Problem Statement](#1-problem-statement)
2. [Current Pipeline Behaviour — Why Every File Is Regenerated](#2-current-pipeline-behaviour--why-every-file-is-regenerated)
3. [What Determines a Generated File?](#3-what-determines-a-generated-file)
4. [Dependency Graph Analysis](#4-dependency-graph-analysis)
5. [Change Detection Strategies](#5-change-detection-strategies)
6. [Incremental Build Architectures](#6-incremental-build-architectures)
7. [Recommended Phased Approach](#7-recommended-phased-approach)
8. [Detailed Design — Phase 1: Content-Hash Diff Persist](#8-detailed-design--phase-1-content-hash-diff-persist)
9. [Detailed Design — Phase 2: Entity-Level Provenance Tracking](#9-detailed-design--phase-2-entity-level-provenance-tracking)
10. [Detailed Design — Phase 3: Model-Aware Selective Render](#10-detailed-design--phase-3-model-aware-selective-render)
11. [Detailed Design — Phase 4: Full Dependency-Graph Incremental Pipeline](#11-detailed-design--phase-4-full-dependency-graph-incremental-pipeline)
12. [Blueprint/Template Change Handling](#12-blueprinttemplate-change-handling)
13. [Cross-Cutting Concerns](#13-cross-cutting-concerns)
14. [Real-World Blueprint Analysis](#14-real-world-blueprint-analysis-from-modelhike-blueprints)
15. [Gaps and Complications Discovered During Audit](#15-gaps-and-complications-discovered-during-audit)
16. [Risk Analysis](#16-risk-analysis)
17. [Appendix: Key Code Locations](#17-appendix-key-code-locations)
18. [Alternative Approaches From Other Build Systems](#18-alternative-approaches-from-other-build-systems)

---

## 1. Problem Statement

Today, every `swift run DevTester` (or future CLI `modelhike generate`) execution:

1. **Parses all `.modelhike` files** — even unchanged ones.
2. **Renders every template for every entity** — even when the entity hasn't changed.
3. **Wipes the entire output directory** (`config.output.deleteAllFilesAndFolders()`) before writing.
4. **Writes every file to disk** — even when the content is identical to what was already there.

For small models this is fine. As models grow (dozens of entities, hundreds of generated files, multiple blueprints), full rebuilds become a bottleneck — especially in a dev loop where only one entity changed.

**Goal:** When a single entity (e.g. `Order`) changes in a `.modelhike` file, only the files directly or transitively dependent on `Order` should be regenerated and written to disk.

---

## 2. Current Pipeline Behaviour — Why Every File Is Regenerated

### 2.1 The Pipeline Is Stateless

The 6-phase pipeline (`Discover → Load → Hydrate → Validate → Transform → Render → Persist`) starts from scratch on every run. There is no build cache, no manifest file, no previous-run state preserved between invocations.

```
Pipeline.run(using: config)
  → ws.config(config)         // fresh Workspace
  → for phase in phases:
      phase.runIn(pipeline:)   // each phase sees only current-run state
```

### 2.2 Persist Phase Wipes the Output Directory

`GenerateOutputFoldersPass` calls `pipeline.config.output.deleteAllFilesAndFolders()` as its first action, then writes all queued `OutputFile`s.

```swift
// GenerateOutputFolders.swift
try await pipeline.config.output.deleteAllFilesAndFolders()
// ... then persist all sandboxes
```

This means even unchanged files are destroyed and rewritten.

### 2.3 Render Phase Has No Entity-Level Granularity

`GenerateCodePass` iterates containers and creates a new `CodeGenerationSandbox` per container. Inside the sandbox, `main.ss` (the blueprint's entry-point script) drives everything — it loops over modules, entities, DTOs, and calls `render-file` for each.

The render phase has **no knowledge** of which entities changed. It processes the entire container model every time.

### 2.4 Output Files Have No Provenance Metadata

`TemplateRenderedFile`, `FileToCopy`, `StaticFile`, etc. do not store which model entity (or entities) contributed to their content. The only trace is an optional `objectName` captured by the debug recorder — not available in production runs.

### 2.5 No Content Hashing or Diffing

Files are written unconditionally. `LocalFile.write(_:)` calls `String.write(to:atomically:encoding:)` without comparing against the existing file on disk.

---

## 3. What Determines a Generated File?

A generated file's content is a function of:

| Input | Description | Change Frequency |
|-------|-------------|-----------------|
| **Primary entity** | The `DomainObject` / `DtoObject` / `UIView` being rendered | High — this is what the user edits |
| **Template** | The `.teso` file from the blueprint | Low — changes mean blueprint update |
| **Blueprint script** | `main.ss` + sub-scripts determine *which* files to render | Low |
| **Context variables** | `@container`, `@mock`, `@loop`, `working_dir`, etc. | Per-run (stable unless config changes) |
| **`main.tconfig`** | Config variables like `API_StartingPort` | Rare |
| **Mixins** | Other entities mixed into the primary entity | Medium — transitive dependency |
| **DTO parent types** | For DTOs, the entity whose fields are derived | Medium — transitive dependency |
| **Custom type references** | Properties referencing other entities (e.g. `customType`, `Ref@Target.field`) | Medium |
| **Annotations** | Container-level annotations cascade to entities | Low |
| **`common.modelhike`** | Shared types available as mixins/parents everywhere | Low — but affects everything |
| **Blueprint modifiers** | `_modifiers_/*.teso` files | Low |
| **Symbol libraries** | `TypescriptLib`, `JavaLib`, etc. (code, not config) | Very low |

### Key Insight

Most generated files depend on **exactly one primary entity** + some **shared context** (container metadata, config variables) + possibly **a few transitive type references** (mixins, referenced custom types). A small number of files are **entity-independent** (root config files, Dockerfiles, `package.json`).

---

## 4. Dependency Graph Analysis

### 4.1 Entity-Level Dependencies

```
common.modelhike types
       │
       ▼
┌─────────────────────────────┐
│  ParsedTypesCache (global)  │
└──────────┬──────────────────┘
           │
    ┌──────┼──────────────┐
    ▼      ▼              ▼
 Entity A  Entity B    Entity C
    │         │            │
    │    mixins from A     │
    │         │       Ref@B.field
    │         ▼            │
    │    DTO-derived       │
    │    from A+B          │
    ▼         ▼            ▼
 [files]   [files]      [files]
```

**Dependency types that exist today:**

| Dependency | Direction | How Resolved | Where in Code |
|-----------|-----------|--------------|---------------|
| **Mixin** | Child → Parent | `ParserUtil.extractMixins` matches attribute names against `ParsedTypesCache` | `AppModel.resolveAndLinkItems` |
| **DTO derived fields** | DTO → Mixin entity | `DtoObject.populateDerivedProperties()` binds fields by name from mixin | `AppModel.resolveAndLinkItems` |
| **Custom type property** | Entity → Referenced entity | `Property.type.kind == .customType` | Property parser |
| **Reference type** | Entity → Target entity.field | `Ref@Target.field` resolved in `resolveReferenceTargets` | `AppModel.resolveAndLinkItems` |
| **Container annotations** | Container → All entities | Copied to every entity in container | `PassDownAndProcessAnnotations` |
| **Common model** | Global → All entities | Contributes to `ParsedTypesCache` + mixin pool | `LocalFileModelLoader` |
| **Config variables** | Global → All renders | `main.tconfig` → `ctx.variables` | `LoadModels` / `ConfigFileParser` |
| **Cross-container type ref** | Entity in Container A → Entity in Container B | `ParsedTypesCache` is global (all containers share one index) | `AppModel.resolveAndLinkItems` |
| **Dynamic `get-object`** | Template → Any type by name | `ModelLib.getObjectWithName` looks up `ParsedTypesCache` at render time | `ModelLib.swift` |
| **`get-last-recursive-prop`** | Template → Chain of types | Follows `prop.sub.prop` across types in `ParsedTypesCache` | `ModelLib.swift` |
| **Module `expressions` / `namedConstraints`** | Entity `@name` ref → Module-level construct | Global `@name` namespace pooled from common + all modules | `ValidateModels.swift` (W302) |
| **Submodule → Parent module** | Structural | Parent `types` recursively includes submodule entities | `C4Component.types` |
| **`include-for` front matter** | Template → Entity collection | Blueprint folder rendering iterates entity list via `TemplateSoup.forEach` | `LocalFileBlueprint.renderTemplateFile` |

### 4.2 File-Level Dependencies

A single `.modelhike` file can contain:
- Multiple containers (each with `===...===` fences)
- Multiple modules within a container
- Multiple entities within a module
- System definitions

There is **no stored mapping** from "this entity came from file X line Y" on the domain model objects. `ParsedInfo` carries an `identifier` (the file name) but it's on individual parse events, not on the `DomainObject` actor itself.

### 4.3 Template-Level Dependencies

A blueprint template may:
- Access `@container` properties (container-wide)
- Access the current `entity` properties (entity-specific)
- Access `entity.mixins` (transitive)
- Access `entity.apis` (entity-specific, but influenced by annotations)
- Call other templates via sub-scripts
- Use blueprint modifiers that introspect model properties

---

## 5. Change Detection Strategies

### 5.1 File-Level Hashing (Coarse)

**Approach:** SHA-256 hash of each `.modelhike` file's content. If the file hash hasn't changed since last build, skip all entities from that file.

**Pros:** Simple to implement; no parsing needed for unchanged files.  
**Cons:** A whitespace-only change forces full rebuild of all entities in the file. A single-property change on one entity rebuilds all entities in the same file. Cannot handle cross-file dependencies (mixin from file A used in file B).

### 5.2 Entity-Level Fingerprinting (Fine)

**Approach:** After parsing, compute a hash of each entity's normalized representation (name, properties, methods, annotations, tags, attributes, mixins). Compare against cached fingerprints.

**Pros:** Precise change detection at entity granularity.  
**Cons:** Requires full parse of all files (can't skip parsing); needs a canonical serialization for hashing; mixins create transitive invalidation chains.

### 5.3 Hybrid: File Hash + Entity Fingerprint

**Approach:** 
1. Hash `.modelhike` files. Skip parsing unchanged files entirely (use cached parse results).
2. For changed files, re-parse and compare entity fingerprints.
3. Walk the dependency graph to find transitively affected entities.

**Pros:** Best of both worlds — skips parsing when possible, precise when needed.  
**Cons:** Most complex to implement; requires a persistent cache of both file hashes and parsed entity state.

### 5.4 Output Content Hashing (Post-Render)

**Approach:** After rendering, hash the generated content and compare against the existing file on disk (or a manifest). Only write files whose content actually changed.

**Pros:** Zero false positives — perfectly accurate at the I/O level; doesn't require understanding the dependency graph; trivially correct.  
**Cons:** Still does all the parsing and rendering work; only saves disk I/O and downstream tool churn (e.g. IDE file watchers, `git status` noise, `tsc --watch` re-compiles).

**This is the highest-value, lowest-effort first step.** See Phase 1 design.

---

## 6. Incremental Build Architectures

### Architecture A: "Smart Persist" (Output-Side Only)

```
Parse ALL → Hydrate ALL → Render ALL → [Diff against disk] → Write only changed
```

- Full pipeline runs every time
- Only the Persist phase is smart
- Easiest to implement
- Saves disk I/O + downstream churn
- **Does not save CPU time on large models**

### Architecture B: "Selective Render" (Entity-Granular)

```
Parse ALL → Hydrate ALL → [Identify changed entities] → Render CHANGED → Smart Persist
```

- Still parses everything (needed for dependency resolution)
- Only renders templates for changed entities + their dependents
- Saves the expensive template rendering phase
- Requires entity-level provenance tracking

### Architecture C: "Cached Parse + Selective Render"

```
[Hash files] → Parse CHANGED files only → Merge with cached parse → Hydrate → [Identify changed entities] → Render CHANGED → Smart Persist
```

- Skips parsing of unchanged `.modelhike` files
- Uses a persistent parsed-model cache
- Requires careful invalidation of cross-file dependencies
- Maximum performance gain, highest complexity

### Architecture D: "Watch Mode" (Reactive)

```
[File watcher] → Detect changed .modelhike → Incremental re-parse → Re-render affected → Smart Persist
```

- Long-running process watching the model folder
- Keeps the full parsed model in memory
- Applies targeted re-parses when files change
- Near-instant regeneration for single-entity edits
- Most complex; requires careful memory management

### Comparison Matrix

| Architecture | Parse Savings | Render Savings | Persist Savings | Complexity | Correctness Risk |
|---|---|---|---|---|---|
| A: Smart Persist | None | None | High | Low | None |
| B: Selective Render | None | High | High | Medium | Low |
| C: Cached Parse | High | High | High | High | Medium |
| D: Watch Mode | High | High | High | Very High | Medium |

---

## 7. Recommended Phased Approach

### Phase 1: Content-Hash Diff Persist ← START HERE
**Effort:** Small (days)  
**Impact:** Eliminates unnecessary disk writes, reduces downstream tool churn  
**Risk:** Zero — pure additive, no semantic changes  

### Phase 2: Entity-Level Provenance Tracking
**Effort:** Medium (1-2 weeks)  
**Impact:** Foundation for all future incremental work  
**Risk:** Low — additive metadata, no behavior change  

### Phase 3: Model-Aware Selective Render
**Effort:** Medium-Large (2-3 weeks)  
**Impact:** Skips rendering for unchanged entities — big speedup on large models  
**Risk:** Low-Medium — must correctly identify all dependencies  

### Phase 4: Full Dependency-Graph Incremental Pipeline
**Effort:** Large (4-6 weeks)  
**Impact:** Skips parsing unchanged files, full incremental from source to output  
**Risk:** Medium — persistent cache correctness is critical  

---

## 8. Detailed Design — Phase 1: Content-Hash Diff Persist

### 8.1 Concept

Instead of wiping the output directory and writing all files, compare each rendered file's content against what's already on disk. Only write files that actually changed. Remove files that are no longer generated.

### 8.2 Implementation

**New type: `BuildManifest`**

```swift
public struct BuildManifest: Codable, Sendable {
    public var version: Int = 1
    public var timestamp: Date
    public var files: [String: FileEntry]  // relative path → entry

    public struct FileEntry: Codable, Sendable {
        public var contentHash: String      // SHA-256 of file contents
        public var templateName: String?    // which template produced it
        public var lastModified: Date
    }
}
```

**Location:** Stored at `config.output / ".modelhike-manifest.json"`.

**Modified `GenerateOutputFoldersPass`:**

```swift
public func runIn(phase: PersistPhase, pipeline: Pipeline) async throws -> Bool {
    let manifest = loadManifest(from: config.output)
    var newManifest = BuildManifest(timestamp: .now, files: [:])
    var stats = PersistStats()

    for sandbox in sandboxes {
        let output = await sandbox.base_generation_dir
        try await output.diffPersist(
            previousManifest: manifest,
            newManifest: &newManifest,
            stats: &stats,
            context: sandbox.context
        )
    }

    // Remove files in old manifest but not in new (orphaned files)
    let orphaned = Set(manifest.files.keys).subtracting(newManifest.files.keys)
    for path in orphaned {
        try? LocalFile(path: config.output.path / path).delete()
        stats.deleted += 1
    }

    saveManifest(newManifest, to: config.output)
    print("✅ \(stats.written) written, \(stats.skipped) unchanged, \(stats.deleted) deleted")
    return true
}
```

**Modified `OutputFolder.diffPersist`:**

For each `OutputFile`:
1. Render/prepare contents as usual.
2. Compute SHA-256 of the content.
3. Look up the relative path in the previous manifest.
4. If hash matches → skip the write, carry the entry forward.
5. If hash differs or path is new → write to disk, record new entry.

### 8.3 Benefits

- **Downstream tools don't re-trigger.** IDEs, TypeScript compiler watchers, hot-reload servers only see actually-changed files.
- **`git status` stays clean.** Only genuinely modified generated files appear as changed.
- **Zero risk.** If the manifest is missing or corrupt, fall back to full write.
- **Disk I/O reduction.** On a typical single-entity edit, maybe 5-10 files out of hundreds actually change content.

### 8.4 Implementation Gotchas (Verified Against Code)

**Content availability timing:** `TemplateRenderedFile` and `PlaceHolderFile` have their `contents` filled during the Render phase (Phase 5) — `CodeGenerationSandbox.generateFile` calls `file.render()` immediately after adding to the queue. By persist time, `contents` is already a `String?` in memory. Hashing can happen at any point after render, not only at persist.

**Binary files cannot be hashed as strings.** `StaticFile` has both `contents: String?` and `data: Data?` — the `Data` path is used for binary resources (e.g. `ResourceBlueprint.copyResourceFiles` loads non-template resources as `Data`). `FileToCopy` uses `FileManager.copyItem` and never loads bytes into memory at all. The diff-persist implementation must:
- For `TemplateRenderedFile` / `PlaceHolderFile`: hash the `contents` string.
- For `StaticFile` with `data`: hash the `Data` bytes.
- For `FileToCopy`: hash the **source file** on disk (read `outFile` data for hashing), or compare mtime + size as a fast proxy.

**`deleteAllFilesAndFolders` removes and recreates.** The current implementation deletes the entire directory at `config.output` via `FileManager.removeItem`, then recreates an empty directory at the same path. Phase 1 must **not** call this — it must preserve the existing output tree and selectively update.

**Concurrent manifest writing.** `GenerateOutputFoldersPass` uses `withThrowingTaskGroup` to persist sandboxes in parallel. Each sandbox's `OutputFolder.persist` further parallelises with inner task groups for subfolders and items. A global `BuildManifest` updated from parallel tasks would race. Safe patterns:
- Each sandbox builds its own partial manifest; merge after `waitForAll`.
- Or: collect manifest entries into a thread-safe actor during persist, write once after all sandboxes complete.

**Empty folders.** `OutputFolder.persist` returns early if it has no items, folderItems, or subFolders — it won't create empty directories. However, `setRelativePath` calls `ensureExists()` on the generation directory during the **render** phase, so some directories may be created before persist. Phase 1 should track directories in the manifest too, or accept that empty dirs may linger after orphan cleanup.

**`autoGeneratedFileNumber` on `OutputFolder`.** Inert — the only uses are commented out. Does not affect incremental builds.

### 8.5 General Considerations

- Must handle the "first run" case (no manifest → write everything).
- Must handle `--clean` / `--force` flag to bypass diff persist.
- Orphan detection requires a complete manifest from the previous run.
- The output directory is no longer wiped, so stale files from a previous run must be explicitly cleaned via orphan detection.
- Multiple sandboxes target disjoint subtrees (via `outputFolderSuffix`), but suffix collision (two containers with the same normalized name or `#output-folder`) would cause overlapping writes — document this as a known limitation.

---

## 9. Detailed Design — Phase 2: Entity-Level Provenance Tracking

### 9.1 Concept

Track which model entities contributed to each generated file. This creates a reverse mapping: `Entity → [generated files]`.

### 9.2 What Needs to Change

**A. Add `sourceEntityId` to model objects.**

Every `DomainObject`, `DtoObject`, `UIView` gets a stable identifier:

```swift
// On Artifact protocol or CodeObject
public var entityId: EntityId { get }

public struct EntityId: Hashable, Codable, Sendable {
    public let container: String     // container name
    public let module: String        // module name
    public let name: String          // entity name
    public let kind: ArtifactKind    // entity/dto/ui/etc.
}
```

**B. Add source-file tracking to parsed objects.**

During `ModelFileParser.parse(file:)`, tag each container/entity with the source `.modelhike` file path:

```swift
// On DomainObject / DtoObject / UIView
public private(set) var sourceFile: String?  // "models.modelhike"
```

**C. Extend `OutputFile` with provenance.**

```swift
// On TemplateRenderedFile / FileToCopy / etc.
public var provenance: FileProvenance?

public struct FileProvenance: Codable, Sendable {
    public var primaryEntityId: EntityId?
    public var templateName: String?
    public var dependencies: Set<EntityId>  // mixins, referenced types
}
```

**D. Record provenance during render-file execution.**

In `RenderTemplateFileStmt.execute`, after the file is generated, capture the current entity from context:

```swift
if let entityWrap = await context.variables["entity"] as? CodeObject_Wrap {
    let entityId = await entityWrap.item.entityId
    await file.setProvenance(FileProvenance(
        primaryEntityId: entityId,
        templateName: fromTemplate,
        dependencies: await collectDependencies(for: entityWrap.item)
    ))
}
```

**E. Persist provenance in the manifest.**

Extend `BuildManifest.FileEntry` with `provenance: FileProvenance?`.

### 9.3 Dependency Collection

For a given entity, collect its dependency set:

```swift
func collectDependencies(for entity: CodeObject) async -> Set<EntityId> {
    var deps: Set<EntityId> = []
    // Mixins
    for mixin in await entity.mixins {
        deps.insert(await mixin.entityId)
    }
    // Custom type references
    for prop in await entity.properties {
        if await prop.type.isCustomType {
            if let referenced = await types.get(for: prop.type.kind.customTypeName) {
                deps.insert(await referenced.entityId)
            }
        }
    }
    // Reference types (Ref@Target.field)
    for prop in await entity.properties {
        if await prop.type.isReference() {
            // resolve target entity
        }
    }
    return deps
}
```

### 9.4 Benefits

- Creates the data structure needed for selective rendering in Phase 3.
- Enables "what generated this file?" queries (useful for debugging and CI).
- The manifest becomes a rich build artifact.

---

## 10. Detailed Design — Phase 3: Model-Aware Selective Render

### 10.1 Concept

After parsing and hydrating the full model, compare entity fingerprints against the cached versions from the last build. Only render files for entities that changed or whose dependencies changed.

### 10.2 Entity Fingerprinting

Compute a deterministic hash of an entity's normalized shape:

```swift
public struct EntityFingerprint: Codable, Sendable {
    public let entityId: EntityId
    public let hash: String  // SHA-256
}

extension DomainObject {
    func fingerprint() async -> EntityFingerprint {
        var hasher = SHA256()
        // Include all semantically meaningful state:
        hasher.update(name)
        hasher.update(givenname)
        hasher.update(dataType.rawValue)
        for prop in await properties.sorted(by: \.name) {
            hasher.update(prop.name)
            hasher.update(prop.type.description)
            hasher.update(prop.required.rawValue)
            // ... attributes, tags, constraints, defaultValue, validValueSet
        }
        for method in await methods.sorted(by: \.name) {
            hasher.update(method.name)
            // ... parameters, return type, logic hash
        }
        for annotation in await annotations.sorted() {
            hasher.update(annotation.description)
        }
        // tags, attributes
        return EntityFingerprint(entityId: entityId, hash: hasher.hex())
    }
}
```

### 10.3 Change Set Computation

```swift
struct ChangeSet {
    var directlyChanged: Set<EntityId>     // fingerprint differs
    var transitivelyAffected: Set<EntityId> // depends on something that changed
    var newEntities: Set<EntityId>          // not in previous build
    var removedEntities: Set<EntityId>      // in previous build but not current
}

func computeChangeSet(current: [EntityFingerprint], previous: [EntityFingerprint], graph: DependencyGraph) -> ChangeSet {
    let currentMap = Dictionary(current.map { ($0.entityId, $0.hash) })
    let previousMap = Dictionary(previous.map { ($0.entityId, $0.hash) })

    var changed = Set<EntityId>()
    for (id, hash) in currentMap {
        if previousMap[id] != hash {
            changed.insert(id)
        }
    }

    // Walk reverse dependency graph to find transitive dependents
    var affected = changed
    var queue = Array(changed)
    while let id = queue.popFirst() {
        for dependent in graph.reverseDependencies(of: id) {
            if affected.insert(dependent).inserted {
                queue.append(dependent)
            }
        }
    }

    return ChangeSet(
        directlyChanged: changed,
        transitivelyAffected: affected.subtracting(changed),
        newEntities: Set(currentMap.keys).subtracting(previousMap.keys),
        removedEntities: Set(previousMap.keys).subtracting(currentMap.keys)
    )
}
```

### 10.4 Selective Rendering

Modify `main.ss` execution to skip entities not in the change set. Two approaches:

**Approach A: Script-side filtering (non-invasive)**

Inject a `@changed-entities` set into context. Blueprint scripts can opt into checking:

```
for entity in @container.entities
  if entity.id not-in @changed-entities
    :skip
  end-if
  render-file entity-controller.teso as ...
end-for
```

**Approach B: Engine-side filtering (transparent)**

The `render-file` statement checks provenance: if the primary entity hasn't changed and no dependencies changed, skip rendering. The previous output is preserved on disk (from the manifest).

```swift
// In RenderTemplateFileStmt.execute
if let entityId = currentEntityId(from: context),
   !context.changeSet.isAffected(entityId) {
    // Carry forward from previous manifest — don't render
    await context.carryForward(outputPath: filename)
    return nil
}
```

**Approach B is preferred** — it's transparent to blueprint authors and automatically correct.

### 10.5 Container-Independent Files

Files generated outside entity loops (root config, Dockerfiles, `package.json`) depend on container-level state. These should be re-rendered if:
- Any entity in the container changed (conservative)
- Container-level metadata (annotations, tags) changed
- Config variables changed

A simpler heuristic: always re-render non-entity files (they're few and fast).

### 10.6 Benefits

- On a single-entity edit with no transitive dependents, only ~3-8 template renders instead of hundreds.
- Template rendering is the most expensive phase — this provides the largest speedup.
- Blueprint authors don't need to change anything (Approach B).

---

## 11. Detailed Design — Phase 4: Full Dependency-Graph Incremental Pipeline

### 11.1 Concept

Skip parsing unchanged `.modelhike` files entirely. Use a persistent model cache. Only re-parse changed files, merge results, re-hydrate, re-validate, and selectively render.

### 11.2 Persistent Model Cache

```swift
public struct ModelCache: Codable {
    public var version: Int
    public var files: [String: CachedFileState]

    public struct CachedFileState: Codable {
        public var fileHash: String          // SHA-256 of .modelhike file content
        public var parsedEntities: [CachedEntity]  // serialized parse results
        public var containers: [CachedContainer]
        public var systems: [CachedSystem]
    }
}
```

**Location:** `.modelhike-cache/model-cache.json` alongside the model files.

### 11.3 Modified Load Phase

```
1. Hash all .modelhike files
2. Compare against model cache
3. For unchanged files → deserialize cached parse results into ModelSpace
4. For changed files → parse fresh, update cache
5. Merge all ModelSpaces
6. Run resolveAndLinkItems (must re-run — cross-file references may have changed)
7. Hydrate + Validate
8. Compare entity fingerprints → compute change set
9. Selective render + diff persist
```

### 11.4 The `common.modelhike` Problem

`common.modelhike` contributes types to `ParsedTypesCache` and the mixin pool. If it changes, **every entity in every container** is potentially affected (any entity might mix in a common type).

**Strategy:** Treat `common.modelhike` as a "global invalidation trigger." If its hash changes, fall back to full rebuild. This is acceptable because `common.modelhike` changes rarely.

### 11.5 The `main.tconfig` Problem

Config variables from `main.tconfig` feed into template rendering. If config changes, all renders are affected.

**Strategy:** Same as `common.modelhike` — hash `main.tconfig` and treat changes as global invalidation.

### 11.6 Serialization Challenge

Cached parse results must be serializable. Current model objects are `actor`s with rich behavior and cross-references (e.g. `mixins: [CodeObject]` are live object references). Serializing and deserializing the full model graph is non-trivial.

**Options:**
1. **Serialize a "flat" representation** (DTOs) of each entity and reconstruct actors on load. Requires a second "build from cache" code path.
2. **Cache at the `.modelhike` text level** — store the raw lines per entity, re-parse only entities from changed files. Simpler but still requires full `resolveAndLinkItems`.
3. **Cache the ModelSpace per file** — serialize the container/module/entity structure per source file. On reload, merge cached + fresh. Still need the link phase.

Option 3 is the most practical balance.

### 11.7 Benefits

- For a 20-file model with 1 file changed: parse 1 file instead of 20.
- Combined with Phase 3, the entire pipeline from source change to disk write is O(changed entities) not O(total entities).

---

## 12. Blueprint/Template Change Handling

Templates change less often than models, but when they do, the impact is broad.

### Detection

| Change | Impact | Detection |
|--------|--------|-----------|
| Single `.teso` file modified | All files rendered from that template | Hash the template content |
| `main.ss` modified | Potentially all files (script controls iteration) | Hash the script |
| `_modifiers_/*.teso` modified | All files using that modifier | Hash modifier files |
| Blueprint added/removed | Full rebuild | Blueprint list comparison |
| Symbol library code changed | Full rebuild | Code change = binary change |

### Strategy

Store blueprint file hashes in the manifest:

```swift
public struct BuildManifest {
    // ...
    public var blueprintHashes: [String: String]  // relative path → SHA-256
    public var configHash: String                  // main.tconfig hash
    public var commonModelHash: String             // common.modelhike hash
}
```

If any blueprint file hash changes, invalidate all files produced by that blueprint. If `common.modelhike` or `main.tconfig` hash changes, full rebuild.

For per-template invalidation: each manifest `FileEntry` records `templateName`. If that template's hash changed, the file must be re-rendered.

---

## 13. Cross-Cutting Concerns

### 13.1 Correctness Guarantee

The fundamental invariant: **incremental build output must be byte-identical to full rebuild output.** 

To enforce this:
- Add a `--verify` flag that runs both full and incremental builds and diffs the output.
- Run `--verify` in CI on every commit.
- If they ever diverge, fall back to full rebuild and emit a warning.

### 13.2 Cache Invalidation Safety

Apply a **"when in doubt, rebuild"** policy:
- Missing manifest → full rebuild
- Corrupt manifest → full rebuild  
- `common.modelhike` changed → full rebuild
- `main.tconfig` changed → full rebuild
- Blueprint structure changed → full rebuild
- Cache version mismatch → full rebuild

### 13.3 `--clean` / `--force` Flag

Always provide a way to bypass the cache:

```bash
modelhike generate --clean   # wipe cache + output, full rebuild
modelhike generate --force   # ignore cache, full rebuild, update cache
```

### 13.4 Performance Reporting

Extend `--perf` to report incremental build metrics:

```
📊 Incremental Build Report
   Model files: 12 total, 1 changed, 11 cached
   Entities: 45 total, 3 affected (1 direct + 2 transitive)
   Files rendered: 12 / 312 (96% skipped)
   Files written: 8 / 312 (97% unchanged)
   Time: 0.4s (full build: 3.2s — 8x faster)
```

### 13.5 Debug Mode Interaction

The visual debugger (`--debug`, `--debug-stepping`) should **always run full builds** — the debug session needs complete event traces. Incremental mode is for production/dev-loop runs.

### 13.6 Watch Mode (Future)

Phase 4 naturally extends to a watch mode:
1. Keep the parsed model in memory.
2. Use `DispatchSource` / `FSEvents` to watch the model folder.
3. On file change → re-parse that file → re-link → fingerprint → selective render → diff persist.
4. Print which files were updated.

This would give sub-second feedback on model edits.

---

## 14. Real-World Blueprint Analysis (from `modelhike-blueprints`)

This section is based on analysis of the actual blueprint code in the sibling `modelhike-blueprints` repository. Two blueprints exist: `api-springboot-monorepo` (Java, 31 templates) and `api-nestjs-monorepo` (TypeScript, 24 templates).

### 14.1 File Generation Granularity in Practice

Both blueprints follow a **container → module → entity** iteration pattern in `main.ss`. The actual file output falls into four granularity levels:

| Granularity | Spring Boot Examples | NestJS Examples | Count (approx) |
|-------------|---------------------|-----------------|-----------------|
| **Per-container** | `_root_/` configs (Dockerfile, docker-compose, settings.gradle, README) | `typescript.domain.classes.ts`, `yup.domain.classes.schema.ts`, `docker-compose.yml`, `package.json`, `nest-cli.json`, root configs, `_root_/` | 4-6 Spring, 8-10 NestJS |
| **Per-module** | `base-service-files/` (build.gradle, application.yml), `base-service-files-src/` (App.java), graphql-schema, plantuml | `app.module.ts`, `main.ts`, `tsconfig.app.json`, `jest.config.js`, plantuml | 5-7 per module |
| **Per-entity** | `entity-files/model/` (Entity.java, EntityInput.java, Repository.java), `entity-graphql-api/` (Controller, Apis.http) | `controller.ts`, `controller.test.ts`, `module.ts`, `validator.ts`, `requests.http` | 5-8 per entity |
| **Per-API** | `entity-files/crud/` via `include-for` (Create, Update, Delete, Get, List commands — 1 file per matching API) | Per-API CRUD files via `main.ss` if-branches (`create.*.ts`, `update.*.ts`, etc.) | 1-5 per entity |

**Key observation:** Per-entity and per-API files are the majority of output. A typical entity with full CRUD generates ~10-13 files. With 20 entities across 4 modules, that's ~200-260 entity-scoped files plus ~30-40 module/container/root files. **The entity-scoped files are the incremental build sweet spot.**

### 14.2 "Wide Fan-In" Templates (Hardest to Incrementalise)

These templates iterate **all** entities in the container and must be re-rendered if **any** entity changes:

| Template | Blueprint | What It Iterates |
|----------|-----------|------------------|
| `typescript.domain.classes.teso` | NestJS | `@container.commons` + every `module.types` |
| `typescript.common.classes.teso` | NestJS | `@container.commons` (common types only) |
| `yup.domain.classes.teso` | NestJS | `@container.commons` + every `module.types` |
| `yup.common.classes.teso` | NestJS | `@container.commons` |
| `docker-compose.yml.teso` | NestJS | `@container.modules` (ports, names) |
| `package.json.teso` | NestJS | `@container.modules` |
| `nest-cli.json.teso` | NestJS | `@container.modules` |
| `_root_/settings.gradle.teso` | Spring | `@container.modules` |
| `_root_/docker-compose-*.yml.teso` | Spring | `@container.modules` |
| `graphql-schema-module.teso` | Spring | All module entities, APIs, embedded types |
| `plantuml.classes.teso` | Both | All `module.types` |
| `app.module.teso` | NestJS | All `module.entities` (imports all entity modules) |

**Incremental strategy for wide fan-in files:** Always re-render these (~10-15 files). They're few and relatively fast. The output content hash (Phase 1) will skip the disk write if the rendered content didn't actually change.

### 14.3 Dynamic Modifier Usage (Quantified)

| Modifier | Occurrences | Where | Incremental Impact |
|----------|-------------|-------|--------------------|
| `get-object` | **1 template** | Spring `entity-graphql-api/Apis.http.teso` — resolves `property.obj-type` to print nested GraphQL query fields | Low — only affects HTTP test files; can be treated as "depends on referenced type" |
| `get-last-recursive-prop` | **2 templates** | NestJS `entity.controller.teso` and `entity.get.all.query.teso` — resolves `@list-api` mapping annotations | Low — only affects list-query controller/query files |

**Conclusion:** Dynamic cross-entity modifiers are rare in current blueprints. Static dependency analysis (mixins, custom types, refs) covers ~98% of real dependency edges. The remaining 2% can be handled conservatively (re-render files using these modifiers whenever any entity changes, or extract the literal type name argument).

### 14.4 `run-shell-cmd` Usage

**Zero occurrences** in any blueprint. The side-channel risk identified in section 15.5 is theoretical — no current blueprint uses it. Document the limitation but deprioritise handling it.

### 14.5 `include-for` Usage (Spring Boot Only)

Used exclusively in Spring Boot's `entity-files/crud/` folder — 8 CRUD `.teso` files use front matter:

```
-----
/include-for : api in apis
/include-if : api.is-create
-----
```

This emits one Java file per matching API type. The NestJS blueprint achieves the same effect via explicit `if/else-if` branches in `main.ss`.

**Incremental impact:** These files are per-API but their provenance is still tied to the parent entity (since `apis` comes from `entity | apis`). Track provenance as `(entity, api-type)` pairs.

### 14.6 Template Dependency Summary

| Template accesses... | Frequency | Static analysable? |
|----------------------|-----------|--------------------|
| `entity.*` (properties, methods, name, apis) | All per-entity templates | Yes |
| `module.*` (name, port, entities, apis) | All per-module templates | Yes |
| `@container.*` (modules, commons) | Per-container templates | Yes |
| `property \| typename` (type name → other entity) | Very common in entity templates | Yes (resolve type name) |
| `@mock.object-id` | 3 templates (HTTP test files) | Yes (static, no entity dep) |
| `get-object(name)` | 1 template | Partially (arg is often a variable) |
| `get-last-recursive-prop(entity.name)` | 2 templates | Partially (arg is entity name) |
| `entity.mixins` (direct access) | **0 templates** | N/A — not used |

### 14.7 `entity.mixins` Not Used in Templates

No blueprint template directly accesses `entity.mixins`. Mixins affect **hydration** (properties are inherited) and **DTO derived fields**, but templates only see the **resolved** entity — they iterate `entity.properties` which already includes mixin-inherited properties. This means mixin changes propagate through entity fingerprinting (the properties change), not through explicit template dependency edges.

### 14.8 Revised Incremental Build Impact Estimate

For a model with 20 entities across 4 modules, changing **1 entity** with no transitive dependents:

| Phase | Full Build | Incremental | Savings |
|-------|-----------|-------------|---------|
| **Parse** | 20 entities | 20 entities (Phase 1-3) / 1 file (Phase 4) | 0% / 95% |
| **Render** | ~300 files | ~25 files (1 entity × ~13 files + ~12 wide-fan-in) | ~92% |
| **Write** | ~300 files | ~13 files (wide-fan-in content usually unchanged) | ~96% |

---

## 15. Gaps and Complications Discovered During Audit

Items below were identified by a second-pass audit of the codebase and were missing or underspecified in the initial analysis.

### 14.1 `ParsedTypesCache` Is Global, Not Per-Container

All entities from all containers and `common.modelhike` are registered in a single `ParsedTypesCache` on `AppModel`. Cross-container type references are valid — an entity in Container A can have a `customType` property referencing an entity in Container B. `resolveReferenceTargets` uses `ctx.model.types.get(for:)` with no container filter.

**Incremental impact:** Invalidating "only this container" is insufficient. A type rename or removal in Container A can break resolution for Container B. The dependency graph must be **cross-container**.

### 14.2 Dynamic Template Modifiers Create Unpredictable Dependency Edges

`ModelLib` registers modifiers that perform **runtime type lookups**:
- `get-object` — takes a string name and looks up any type in the global `ParsedTypesCache`
- `get-last-recursive-prop` — follows `prop.sub.prop` chains across types

A template can call `{{ "SomeEntity" | get-object }}` and access **any** type in the model, creating a dependency edge that **cannot be statically predicted** from the entity being rendered.

**Incremental impact:** Phase 3 (Selective Render) cannot rely purely on static dependency analysis. Options:
- **Conservative:** If any entity changes, re-render all files that use `get-object` / `get-last-recursive-prop` modifiers. (Requires tracking modifier usage per template.)
- **Heuristic:** Treat `get-object` calls as "depends on the named type" and extract the argument statically where it's a literal string.
- **Accept over-invalidation:** If the dependency graph is uncertain, re-render.

### 14.3 `include-for` Front Matter — A Separate File Generation Path

Blueprint `.teso` files can have front matter like `include-for: @container.entities`, which causes the blueprint folder renderer (`LocalFileBlueprint.renderTemplateFile`) to call `TemplateSoup.forEach` and emit **one output file per iteration item**. This is a **separate code path** from `main.ss` for-loops + `render-file` statements.

**Incremental impact:** Provenance tracking (Phase 2) must handle both paths:
1. Files created by `render-file` statements in `main.ss` (via `RenderTemplateFileStmt`)
2. Files created by `include-for` front matter (via `LocalFileBlueprint.renderTemplateFile` → `TemplateSoup.forEach`)

Both paths must capture the current entity and record it in provenance.

### 14.4 Submodule Types Are Not Isolated

Submodules (`C4Component` nested inside a parent `C4Component`) are **not** separate in the type graph. Parent module `types` **recursively** includes all entities from child submodules. APIs aggregated at the module level (`C4Component_Wrap.apis`) also flatten across submodules.

**Incremental impact:** An entity change in a submodule affects:
- The submodule's own rendered files
- Any parent module iteration that accesses `types` or `apis` (per-module aggregate files)
- Other entities in the same submodule that might share module-level constructs

### 14.5 `run-shell-cmd` Is a Side Channel

The `run-shell-cmd` SoupyScript statement executes arbitrary shell commands in the output directory. These can create, modify, or delete files **outside** the tracked `OutputFile` list.

**Incremental impact:** Files created by shell commands are invisible to the manifest. Options:
- **Ignore:** Accept that shell-created files are always stale/recreated (they're rare).
- **Track:** Snapshot the output directory before/after shell commands to detect side effects.
- **Document limitation:** Shell-created files are outside incremental tracking.

### 14.6 Module-Level `expressions`, `namedConstraints`, and the Global `@Name` Namespace

The `@name` reference namespace (used in property defaults and constraints) is **global**: it pools together names from `common.modelhike`, every module's `expressions`, and every module's `namedConstraints`. Validation (W302) resolves against this combined pool.

**Incremental impact:** A module-level expression change doesn't just affect entities in that module — it affects the global `@name` namespace. Any entity referencing `@thatName` (even in another module) is transitively affected. The dependency graph needs a "named expression" node type, not just entity nodes.

### 14.7 Per-Module Files Complicate Provenance

`main.ss` can generate files at **three granularity levels**:
1. **Per-entity** — inside a `for entity in module.entities` loop
2. **Per-module** — inside a `for module in @container.modules` loop but outside entity iteration (e.g. module index files, barrel exports)
3. **Per-container** — outside all loops (root configs, Dockerfiles)

Per-module files depend on **all entities in the module** (since the module wrapper exposes `types`, `entities`, `apis`, etc.). Provenance tracking must distinguish these granularities — a per-module file's `primaryEntityId` would be `nil` but its `dependencies` would be all entities in the module.

### 14.8 `CodeGenerationEvents` Hooks Can Suppress Files Without Tracking

`onBeforeRenderFile` and `onBeforeRenderTemplateFile` return `Bool` — `false` skips the file. These are user-supplied hooks (set on `PipelineConfig.events`). The skipped file is **not recorded** in any manifest or provenance system.

**Incremental impact:** If a hook implementation changes its decision (e.g. starts returning `true` for a previously skipped file), the incremental system won't know to generate the now-wanted file. Either:
- Treat hook changes as global invalidation triggers.
- Record skip decisions in the manifest so they can be compared.

### 14.9 `copyFile` / `copyFolder` Bypass `canRender` Hooks

Unlike `generateFile` and `fillPlaceholdersAndCopyFile`, the `copyFile` and `copyFolder` methods on `CodeGenerationSandbox` do **not** call `context.events.canRender`. Static files are always copied.

**Incremental impact:** Static files need separate handling — they depend on the blueprint, not the model. If the blueprint hasn't changed, static files haven't changed. Hash the source file content for diff-persist.

### 14.10 `@container.commons` Exposes Common Model to Templates

`C4Container_Wrap` exposes `commons`, which returns the common-model modules. Templates can iterate common types and generate files from them.

**Incremental impact:** Reinforces that `common.modelhike` changes are global invalidation triggers.

### 14.11 Systems, InfraNodes, VirtualGroups Are Not Rendered (Currently)

`GenerateCodePass` only renders when `outputItemType == .container`. The `PipelineConfig` defines `.systemView` and `.containerGroup` as output types, but **nothing in the codebase implements rendering for them**. Systems are loaded and linked (container refs inside systems/groups are resolved) but produce no output files.

**Incremental impact:** Currently irrelevant for codegen incremental builds. If system-view rendering is added in the future, systems become another invalidation scope.

### 15.9 Visual Debugger and Event Hook "Starvation"

If Phase 3 (Selective Render) skips rendering an entity, the statements inside its template are never executed. This means:
1. **Debug Events are skipped:** `DebugRecorder.recordFileGeneratedWithContext` is never called. The Visual Debugger's file tree will be missing all skipped files, making the output look incomplete.
2. **Event Hooks are skipped:** `CodeGenerationEvents.onBeforeRenderFile` and `onBeforeRenderTemplateFile` are never fired. If a user relies on these hooks for side-effects (e.g., logging, custom metrics), those side-effects won't happen.

**Incremental impact:** 
- For the Visual Debugger: As noted in 13.5, `--debug` and `--debug-stepping` must **force a full rebuild** to ensure the event trace is complete. Alternatively, the incremental engine must "replay" the manifest into the `DebugRecorder` so the UI file tree populates correctly.
- For Event Hooks: Document that hooks are only fired for *actively rendered* files, not cached ones.

### 15.10 Template Functions (Cross-Template Dependencies)

SoupyScript allows defining functions (`func ... end-func`). If `main.ss` defines a function (like `render-graphQl-schema()`), it's available in the context. If a `.teso` file defines a function and another `.teso` file calls it, this creates a **cross-template dependency**.

**Incremental impact:** If the template containing the function definition changes, all templates that *call* that function must be invalidated. 
- **Mitigation:** Hash the entire blueprint (all `.teso` and `.ss` files) as a single versioned unit. If any blueprint file changes, invalidate all generated files (as proposed in Section 12). Trying to track function-call graphs across templates is too complex and yields minimal value since blueprints change rarely compared to models.

---

## 16. Risk Analysis

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| **Stale cache produces wrong output** | Medium | High | `--verify` flag; "when in doubt, rebuild"; version the manifest |
| **Transitive dependency missed** | Medium | High | Conservative dependency walker; include all mixins + custom types + refs |
| **Blueprint change not detected** | Low | Medium | Hash all blueprint files in manifest |
| **Performance regression from hashing overhead** | Low | Low | SHA-256 is fast; hashing overhead << rendering time |
| **Serialization bugs in model cache** | Medium | Medium | Phase 4 only; extensive tests; fallback to full rebuild |
| **Annotation cascade invalidation too broad** | Low | Low | Container annotations rarely change; accept full-container rebuild when they do |

---

## 17. Appendix: Key Code Locations

### Files That Need Modification (by Phase)

**Phase 1 — Content-Hash Diff Persist:**

| File | Change |
|------|--------|
| `Sources/Pipelines/6. Persist/GenerateOutputFolders.swift` | Replace wipe-and-write with diff-persist logic |
| `Sources/_Common_/FileGen/InputOutput/OutputFolder.swift` | Add `diffPersist` method |
| `Sources/_Common_/FileGen/InputOutput/OutputFile.swift` | Add content hash computation |
| New: `Sources/_Common_/FileGen/BuildManifest.swift` | `BuildManifest` type + load/save |
| `Sources/Pipelines/PipelineConfig.swift` | Add `incrementalBuild: Bool` flag |

**Phase 2 — Entity-Level Provenance:**

| File | Change |
|------|--------|
| `Sources/Modelling/_Base_/Artifact.swift` | Add `entityId` to `Artifact` protocol |
| `Sources/Modelling/Domain/DomainObject.swift` | Implement `entityId` |
| `Sources/Modelling/Domain/DtoObject.swift` | Implement `entityId` |
| `Sources/Modelling/UI/UIView.swift` | Implement `entityId` |
| `Sources/_Common_/FileGen/FileTypes/TemplateRenderedFile.swift` | Add `provenance: FileProvenance?` |
| `Sources/Scripting/SoupyScript/Stmts/RenderFile.swift` | Capture provenance during render |
| `Sources/_Common_/FileGen/BuildManifest.swift` | Extend with provenance data |

**Phase 3 — Selective Render:**

| File | Change |
|------|--------|
| New: `Sources/Pipelines/ChangeDetection/EntityFingerprint.swift` | Fingerprint computation |
| New: `Sources/Pipelines/ChangeDetection/DependencyGraph.swift` | Dependency graph + reverse lookup |
| New: `Sources/Pipelines/ChangeDetection/ChangeSet.swift` | Change set computation |
| `Sources/Pipelines/5. Render/GenerateCodePass.swift` | Inject change set into context |
| `Sources/Scripting/SoupyScript/Stmts/RenderFile.swift` | Skip rendering for unaffected entities |
| `Sources/Workspace/Context/GenerationContext.swift` | Add change set + carry-forward logic |
| `Sources/_Common_/FileGen/BuildManifest.swift` | Store entity fingerprints |

**Phase 4 — Full Incremental Pipeline:**

| File | Change |
|------|--------|
| New: `Sources/Modelling/_Base_/Loader/ModelCache.swift` | Persistent model cache |
| `Sources/Modelling/_Base_/Loader/LocalFileModelLoader.swift` | Conditional parse with cache |
| `Sources/Pipelines/2. Load/LoadModels.swift` | Cache-aware loading |
| `Sources/Workspace/Sandbox/AppModel.swift` | Merge cached + fresh parse results |

### Current Code That Proves Full-Rebuild Behavior

1. **Output wipe:** `GenerateOutputFolders.swift:12` — `try await pipeline.config.output.deleteAllFilesAndFolders()`
2. **No entity tracking on output:** `TemplateRenderedFile.swift` — no `entityId` or `provenance` field
3. **No manifest:** No `.modelhike-manifest.json` or similar build artifact
4. **No file hashing:** `LocalFile.write` writes unconditionally
5. **No model cache:** `LocalFileModelLoader.loadModel` parses all files every time
6. **Debug-only provenance:** `DebugRecorder.recordFileGeneratedWithContext` captures `objectName` but only when a debug recorder is attached

---

## 18. Alternative Approaches From Other Build Systems

The phased approach in sections 7–11 is a pragmatic, pipeline-centric strategy. This section documents fundamentally different architectures used by other tools, assesses their applicability, and identifies ideas worth borrowing.

### 18.1 Demand-Driven / Query-Based Computation (Salsa / rust-analyzer)

**How it works:** The entire computation is modeled as a graph of pure function calls (queries). Each query's result is memoized. When an input changes, the system lazily re-evaluates only the queries demanded by the output, using a "red-green" algorithm. Two key optimizations: *early cutoff* (if a dependency changed but the result didn't, stop propagation) and *durability* (inputs that rarely change, like `common.modelhike`, can be verified in O(1)).

**Applicability:** This would solve the dynamic modifier problem (section 15.2) for free — `get-object("Order")` would automatically record a dependency on the `Order` entity query. It also gives you Phase 3 and Phase 4 benefits without hand-built fingerprinting or caching.

**Trade-off:** Requires restructuring the pipeline from imperative phases to a query graph. High conceptual cost, significant refactor. Best suited if ModelHike eventually needs sub-second watch-mode feedback (like an IDE language server). The phased approach in this document is more pragmatic for the near term.

**Verdict:** Worth acknowledging as a long-term architectural target. Not the right first step, but if watch mode (section 13.6) becomes a priority, query-based is the natural end-state.

### 18.2 Summary-Boundary Architecture (Zig / matklad's "Three Architectures")

**How it works:** Instead of fine-grained query tracking, design the computation as coarse independent phases separated by narrow "summary" boundaries:

1. Parse all files independently, in parallel
2. Extract a *summary* per entity (name, property signatures, method signatures, annotations, tags — not bodies)
3. Run a global resolution phase on summaries only
4. Render each entity in parallel, depending only on resolved summaries

Body changes that don't alter the summary don't propagate at all — by construction, not by cache lookup.

**Applicability:** Maps remarkably well to ModelHike. The document's Phase 4 proposes serializing `ModelSpace` per file (actors with cross-references), which is complex (section 11.6). A summary-boundary approach sidesteps this — you don't cache parse results, you cache *summaries* (simple, flat, `Codable` structs). If a file changes but its entity summaries don't, nothing downstream re-renders.

**Borrowable idea:** Replace Phase 4's "serialize actors" approach with summary extraction. An `EntitySummary` struct is trivially `Codable`:

```swift
struct EntitySummary: Codable, Hashable, Sendable {
    let name: String
    let givenname: String
    let kind: ArtifactKind
    let properties: [PropertySummary]  // name + type + required + tags
    let methods: [MethodSummary]       // name + params + returnType
    let annotations: [String]
    let tags: [String]
    let attributes: [String: String]
}
```

### 18.3 Content-Addressable Storage (Bazel / Buck / Nix)

**How it works:** Every build artifact is stored at a path determined by the hash of its *inputs* (not its content). Before executing a step, compute the input hash and check the store. No manifest, no versioning, no staleness — the cache is self-validating.

```
renderKey = hash(entityFingerprint + templateHash + configHash)
if cas.exists(renderKey) → read from CAS
else → render, store in CAS under renderKey
```

**Advantages over the manifest approach:**
- No "corrupt manifest → full rebuild" failure mode.
- Shared across git branches — switching and switching back hits the CAS.
- Enables **remote caching** — one developer renders, the whole team benefits (like Turborepo/Nx).

**Trade-off:** Adds storage overhead (multiple versions of outputs). For text-file code generation, storage is minimal.

**Borrowable idea:** The `BuildManifest` in Phase 1 could be replaced with (or augmented by) a CAS. For Phase 1 alone, the manifest is simpler. For Phase 3+, CAS is more robust.

### 18.4 Automatic Dependency Recording via Instrumentation

**How it works (inspired by Swift's `.swiftdeps`):** Instead of manually computing entity provenance (Phase 2), instrument the wrapper types' `DynamicMemberLookup` to automatically record which entities are accessed during rendering. Dependencies become a *side-effect of rendering*, not a pre-computed analysis.

**This is the single most actionable alternative idea.** It solves:
- Phase 2's provenance tracking — automatically, with zero blueprint changes.
- Phase 3's dynamic dependency problem (`get-object`, `get-last-recursive-prop`) — access is recorded at runtime.
- Cross-entity template dependencies (`property | typename` resolving to another type) — the type lookup would be recorded.

**Implementation sketch:**

```swift
// Add to GenerationContext
actor DependencyTracker {
    private var currentFile: String?
    private var accessedEntities: [String: Set<EntityId>] = [:]

    func startFile(_ path: String) { currentFile = path }
    func recordAccess(_ entityId: EntityId) {
        guard let file = currentFile else { return }
        accessedEntities[file, default: []].insert(entityId)
    }
    func finishFile() -> Set<EntityId> {
        guard let file = currentFile else { return [] }
        currentFile = nil
        return accessedEntities[file] ?? []
    }
}

// In CodeObject_Wrap's getValueOf(property:with:):
await context.dependencyTracker.recordAccess(item.entityId)

// In ModelLib's get-object modifier:
await sandbox.context.dependencyTracker.recordAccess(resolved.entityId)
```

**Trade-off:** Small runtime overhead per property access during rendering. Negligible compared to template parsing and I/O.

**Verdict:** Could replace Phase 2 entirely and make Phase 3 significantly simpler. Strongly recommended as an alternative to manual provenance tracking.

### 18.5 Remote / Shared Caching (Turborepo / Nx)

Not mentioned in the main design. For teams using ModelHike:
- CI can share a build cache — if the model hasn't changed, code gen is a cache hit.
- Developers pulling the same branch get pre-built outputs.
- Different blueprints against the same model share the parse/hydrate cache.

**Borrowable idea:** Add a remote CAS backend to the `BuildManifest` (or a standalone CAS) as a Phase 1.5 extension. Implementation is straightforward once content hashing exists.

### 18.6 Comparison of Approaches

| Approach | Complexity | Dependency Tracking | Handles Dynamic Deps | Persistent Cache | Remote Cache |
|----------|-----------|--------------------|-----------------------|------------------|-------------|
| **Document's Phased (current)** | Low → High | Manual fingerprint | Partially (conservative) | Manifest file | No |
| **Query-Based (Salsa)** | Very High | Automatic | Yes | In-memory + serializable | Possible |
| **Summary-Boundary** | Medium | Summary hash | Yes (at summary level) | Flat struct cache | Easy |
| **CAS (Bazel-style)** | Medium | Input hash | Yes (input-keyed) | Self-validating | Native |
| **Instrumented Wrappers** | Low | Automatic runtime | Yes | Pairs with any cache | Yes |

---

## Summary

The path from "full rebuild every time" to "true incremental builds" is a 4-phase journey. Each phase builds on the previous one and delivers independent value:

| Phase | What Changes | Speedup Source | Effort |
|-------|-------------|---------------|--------|
| 1. Diff Persist | Only Persist phase | Disk I/O + downstream tools | Small |
| 2. Provenance | Metadata on output files | Enables future phases | Medium |
| 3. Selective Render | Render phase skips unchanged | Template rendering (biggest cost) | Medium-Large |
| 4. Cached Parse | Load phase skips unchanged | Parsing (meaningful for large models) | Large |

**Phase 1 alone** solves the most visible user pain (unnecessary file churn, noisy `git status`, IDE re-indexing). **Phase 3** delivers the biggest raw performance gain. **Phase 4** is the endgame for very large models.

**Key alternative insight:** The **instrumented `DynamicMemberLookup`** approach (section 18.4) could replace Phase 2 and simplify Phase 3 significantly — it gives automatic, runtime-accurate dependency tracking without manual provenance code and solves the dynamic modifier problem for free. Consider this as the implementation strategy for Phases 2+3 rather than the manual approach described in sections 9–10.

Start with Phase 1. It's safe, simple, and immediately valuable.

---

**Related Documents:**
- [Incremental Builds Architecture Decision](incremental-builds-architecture.md) — where each component should live (library vs CLI), concrete type definitions, `BuildSession` wrapper design, hard constraints, testing strategy, and Phase 1 integration sketch grounded in the actual `Pipeline` and `OutputFolder` APIs.
