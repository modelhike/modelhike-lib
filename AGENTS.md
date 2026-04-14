# ModelHike — Comprehensive Project Analysis

> **Purpose of this file:** A thorough, durable reference for any agent, engineer, or tool that needs to understand the project's current state without having to re-read every source file. Keep this file updated when making structural changes.

---

## Table of Contents

1. [What ModelHike Is](#1-what-modelhike-is)
2. [Repository Layout](#2-repository-layout)
3. [Swift Package](#3-swift-package)
4. [The ModelHike DSL](#4-the-modelhike-dsl)
5. [Source Module Breakdown](#5-source-module-breakdown)
6. [The 6-Phase Pipeline](#6-the-6-phase-pipeline)
7. [Domain Model Objects](#7-domain-model-objects)
8. [Template Engine — TemplateSoup + SoupyScript](#8-template-engine--templatesoup--soupyscript)
9. [Blueprint System](#9-blueprint-system)
10. [Workspace, Context, and Sandbox](#10-workspace-context-and-sandbox)
11. [DevTester Executable](#11-devtester-executable)
12. [Visual Debugging](#12-visual-debugging)
13. [Tests](#13-tests)
14. [Playground](#14-playground)
15. [Current Project State & Known Gaps](#15-current-project-state--known-gaps)
16. [Key Conventions & Patterns](#16-key-conventions--patterns)
17. [Glossary](#17-glossary)

---

## 1. What ModelHike Is

ModelHike is an open-source **code-generation toolchain** written in Swift 6. It takes plain-text, Markdown-flavoured **software models** (`.modelhike` or `.dsl.md` files) and generates production-grade, framework-specific source code, documentation, and architecture diagrams.

The core philosophy:

- **Single source of truth** — `.modelhike` files describing architecture (C4 model), data schemas, validation rules, and API surface.
- **Deterministic builds** — same model + same templates = identical output, every time. CI-safe.
- **AI optional** — AI can bootstrap or suggest models, but the generation pipeline is template-driven and fully controllable.
- **Zero external Swift dependencies** — the library is self-contained.

The value proposition is the elimination of hand-written boilerplate: entities, repositories, controllers, services, DTOs, tests, and API docs are all generated from the model.

---

## 2. Repository Layout

```
modelhike/
├── Package.swift               # Swift Package definition
├── README.md                   # Public-facing docs (aspirational; some features not yet implemented)
├── AGENTS.md                   # This file — living project analysis
├── .ai/
│   └── brainstorm/
│       └── debug-console-brainstorm.md  # Archived design/brainstorm notes for AI-assisted doc work
├── CREDITS.md
├── LICENSE                     # MIT
├── SECURITY.md
│
├── Sources/                    # Main Swift library (target: ModelHike)
│   ├── _Common_/               # Foundation utilities, file I/O, extensions
│   ├── Debug/                  # DebugRecorder, DebugSession, DebugEvent, RenderedOutputSnapshot, etc.
│   ├── Modelling/              # DSL parser + in-memory domain model
│   ├── Scripting/              # SoupyScript template scripting engine
│   ├── CodeGen/                # TemplateSoup renderer + Blueprint loading
│   ├── Workspace/              # Context, Sandbox, expression evaluator
│   └── Pipelines/              # 6-phase pipeline orchestrator
│
├── DSL/                        # Canonical DSL markdown specs — own SPM target (ModelHikeDSL); bundled as package resources
│   ├── modelHike.dsl.md        # Full DSL specification (Beginner → Pro guide)
│   ├── codelogic.dsl.md        # Fenced method-body logic block syntax reference
│   └── templatesoup.dsl.md     # TemplateSoup + SoupyScript syntax reference
│
├── DevTester/                  # Executable target for development runs
│   ├── DevMain.swift           # Entry point; runs codegen pipeline (or debug mode with --debug / --debug-stepping)
│   ├── Environment.swift       # Hardcoded dev/prod path configs
│   ├── DebugServer/            # SwiftNIO server: DebugHTTPServer, DebugRouter, HTTPChannelHandler, WebSocket*, StreamingDebugRecorder
│   └── Assets/
│       └── debug-console/      # Modular browser UI (Lit web components)
│
├── Tests/                      # Test suites
│
├── Docs/
│   ├── documentation.md        # Product documentation outline (partially written)
│   ├── ADRs.md                 # Architecture Decision Records (minimal)
│   ├── debug/
│   │   ├── DEBUGGING.md        # Developer debugging guide: flags, hooks, in-template debugging
│   │   └── VISUALDEBUG.md      # Visual debugging system: architecture, data flow, troubleshooting
│   ├── modelHike.brand.md      # Brand guide
│   ├── quickstart.md           # Quickstart guide
│   └── old-detailed-readme.md  # Archived old README
│
└── _Playground/                # gitignored — local dev testing only, never committed
```

---

## 3. Swift Package

**File:** `Package.swift` (swift-tools-version: 6.0)

| Property | Value |
|---|---|
| Package name | `ModelHike` |
| Swift tools version | 6.0 (strict concurrency enabled) |
| Platforms | macOS 13+, iOS 16+, tvOS 13+, watchOS 6+ |
| Products | `ModelHike` (library), `DevTester` (executable) |
| External dependencies | **ModelHike library: None** — zero-dependency design. **DevTester executable: SwiftNIO** (`NIOCore`, `NIOHTTP1`, `NIOPosix`, `NIOWebSocket`) for the debug server. |

**Targets:**

| Target | Type | Path |
|---|---|---|
| `ModelHike` | Library | `Sources/` |
| `DevTester` | Executable | `DevTester/` |
| `ModelHikeTests` | Test | `Tests/` |

The entire `Sources/` tree is compiled as a single `ModelHike` library target. There is no source-level separation between sub-modules from the Swift compiler's perspective; the sub-directories are organizational only.

---

## 4. The ModelHike DSL

**Spec files:** `DSL/modelHike.dsl.md` (full DSL), `DSL/codelogic.dsl.md` (method logic fence syntax)

The DSL is a Markdown-flavoured text format.

**Canonical file extension: `.modelhike`** — this is what `ModelConstants.ModelFile_Extension` defines and what `LocalFileModelLoader` exclusively scans for. Any file in `basePath` with extension `.modelhike` (except `common.modelhike`) is loaded as a model file.

**Special file: `common.modelhike`** — if present in `basePath`, it is loaded first and its types are stored in `model.commonModel` (shared across all containers, used for mixins like `Audit`, `CodedValue`, `Reference`, etc.).

**Generation config: `main.tconfig`** — if present in `basePath` (the model folder), loaded during **Phase 2 (Load)** by `LocalFileModelLoader.loadGenerationConfigIfAny()` via `ConfigFileParser`. Parses key-value pairs (e.g., `API_StartingPort = 3000`) into `LoadContext.variables`. These variables are available when `main.ss` executes in Phase 5. This is the pre-configuration step that runs before the blueprint entry point.

### 4.1 Structural Hierarchy

```
System  (* * * ... * * * asterism fence)
  ├─ VirtualGroup  (+--- Name … +--- fence; body lines prefixed with |; nests)
  │     ├─ + Container reference
  │     ├─ InfraNode  (setext ++++ header with [type])
  │     └─ VirtualGroup  (nested; body lines prefixed with | |)
  ├─ InfraNode  (setext ++++ header with [type]; top-level in system body)
  └─ Container  (===...===)
        └─ Module  (=== Name === or === Name ====)
             └─ SubModule  (extra = closing fence)
                  ├─ Class / Entity  (Name \n underline of =)
                  ├─ DTO             (Name \n /===/  underline)
                  ├─ UIView          (Name \n ~~~~ underline)
                  └─ Method          (~ prefix inside a class)
```

> **Syntax reference:** All DSL syntax — property prefixes, type names, array notation, attribute/annotation/tag grammar, UIView syntax, method syntax, API protocol options, and the `(backend)` attribute convention — is documented in [`DSL/modelHike.dsl.md`](DSL/modelHike.dsl.md). Fenced method-body logic block syntax (fence styles, depth rules, all statement keywords) is documented in [`DSL/codelogic.dsl.md`](DSL/codelogic.dsl.md). Those files are the single source of truth. **Update them when any syntax changes; do not duplicate syntax here.**

**Technical implications** — `[ … ]` segments after `(attributes)` and before `#` tags on the same line; parsed into `TechnicalImplication` / `TechnicalImplications` / `HasTechnicalImplicationsValues`. On `# APIs` lines, bracket text starting with `/` contributes to the REST route prefix. See **§6.5** in `DSL/modelHike.dsl.md`.

---

## 5. Source Module Breakdown

### `Sources/_Common_/`

Foundation-level utilities shared across all other modules.

| Sub-folder | Contents |
|---|---|
| `Document/` | `Document`, `Node`, `Tag`, `Attribute`, `Event`, `Renderable` — generic document-tree types |
| `Errors/` | `ParsingError`, `EvaluationError`, `ErrorWithInfo` — public error hierarchy |
| `Extensions/` | Swift extensions on `String`, `Array`, `Dictionary`, `Date`, `Data`, `Regex`, `Any+Optional`, `Defaultable`, `StringConvertible`, `Misc` |
| `FileGen/` | `FileGenerator`, `InputFile/Folder`, `OutputFile/Folder`, `LocalFolder+File`, `Path`, `SystemFolders`; file type protocols: `FileToCopy`, `StaticFile`, `StaticFolder`, `RenderedFolder`, `TemplateRenderedFile`, `PlaceHolderFile`, `OutputDocumentFile` |
| `RegEx/` | `CommonRegEx` — shared regex patterns |
| `Sendable/` | `AsyncSequence`, `CheckSendable`, `SendableDebug` — Swift 6 concurrency helpers |
| `ThirdParty/` | `Codextended` (embedded, MIT), `StringWrapper`, `pluralized` |
| `Utils/` | `ResultBuilder`, `RuntimeReflection`, `ShellExecute` |

### `Sources/Debug/`

Debugging infrastructure. Includes `Suggestions.swift` — a pure utility (Levenshtein-distance "did you mean?" helper) plus all debug recorder, event, and session types. `Suggestions` is used by expression evaluation warnings and validation diagnostics to offer actionable hints in error messages. `GeneratedFileRecord` now carries both the raw `outputPath` emitted during render and a normalized `relativeOutputPath` computed against the pipeline output root when the `DebugSession` is assembled; use `relativeOutputPath` when a consumer needs the canonical persisted file location.

### `Sources/Modelling/`

DSL parsing and the in-memory domain model.

```
Modelling/
├── ModelFileParser.swift       # Top-level DSL file parser (dispatches to sub-parsers)
├── _Base_/
│   ├── Annotation/             # Annotation parsing, processing, constants, types
│   ├── AttachedSections/       # Sections attached to model elements
│   ├── C4Component/            # C4Component + C4ComponentList (actors)
│   ├── C4Container/            # C4Container + C4ContainerList (actors)
│   ├── CodeElement/            # CodeMember, CodeObject, MethodObject, Property, TypeInfo
│   ├── Loader/                 # InlineModelLoader (supports per-item identifiers), LocalFileModelLoader, ModelRepository
│   ├── RegEx/                  # ModelRegEX — DSL-specific regex patterns
│   ├── System/                 # C4System, C4SystemList, SystemParser, InfraNode, InfraNodeParser, VirtualGroup, VirtualGroupParser
│   ├── Artifact.swift          # Artifact protocol + ArtifactKind enum
│   ├── Imports.swift
│   ├── ModelConfigConstants.swift
│   ├── ModelConstants.swift    # `*`, `-`, `.` prefix constants
│   ├── ModelErrors.swift
│   ├── ModelSpace.swift        # Root model object: containers + modules
│   ├── ParserUtil.swift        # Shared parsing helpers
│   └── TagConstants.swift
├── API/
│   ├── API+Extension.swift     # APIState, GenericAPI, API protocol, APIType enum, QueryParam types
│   ├── APIList.swift           # Collection of APIs
│   ├── APISectionParser.swift  # Parses `# APIs ... #` blocks
│   ├── CustomAPIs.swift        # Custom API operation parsing
│   └── WebService.swift        # WebService_MonoRepo wrapper
├── Container+Module/
│   ├── ContainerMember.swift
│   ├── ContainerParser.swift   # Parses `=== Name ===` fences
│   ├── ModuleParser.swift      # Parses `=== Module ===`
│   └── SubModuleParser.swift   # Parses `=== SubModule ====`
├── Domain/
│   ├── DerivedProperty.swift
│   ├── DomainObject.swift      # Class/Entity actor
│   ├── DomainObjectParser.swift
│   ├── DtoObject.swift         # DTO actor
│   └── DtoObjectParser.swift
└── UI/
    ├── UIView.swift            # UIView actor + UIObject protocol
    └── UIViewParser.swift
```

**Key types:**

- `ModelFileParser` (actor) — main entry point; dispatches to `ContainerParser`, `ModuleParser`, `SubModuleParser`, `DomainObjectParser`, `DtoObjectParser`, `UIViewParser`.
- `ModelSpace` (actor) — root model: holds `C4SystemList` + `C4ContainerList` + `C4ComponentList`.
- `C4Container` (actor) — `name`, `givenname`, `containerType` (unknown/microservices/webApp/mobileApp), `C4ComponentList`, `unresolvedMembers`.
- `C4Component` (actor) — module; holds `CodeObject`s (domain objects, DTOs, UIViews) + submodules.
- `DomainObject` (actor) — class with `[CodeMember]` (properties + methods), `mixins`, `attachedSections`, `Annotations`, `Attributes`, `Tags`. `properties` returns members that are `Property`; `methods` returns members that are `MethodObject`.
- `MethodObject` (actor) — `name`, `givenname`, `parameters: [MethodParameter]`, `returnType: TypeInfo`, `logic: CodeLogic?`, `tags`. Parsed from `~ methodName(param: Type) : ReturnType` or paramless `~ methodName` (tilde-prefix), and from `methodName(...)\n------` or paramless `methodName\n------` (setext) lines. An optional fenced logic block (` ``` `, `'''`, or `"""` — 3+ chars, opening and closing must match) may follow a tilde-prefix method; setext methods use `---` as the closing fence. Optionally preceded by one or more `>>>` parameter metadata lines (see DSL §12.1) — `canParse` uses `lookAheadLine(skippingPrefix:)` to verify a valid signature follows the block before committing.
- `MethodParameter` (struct, `Sendable`) — `name: String`, `type: TypeInfo`, `metadata: ParameterMetadata`. The `metadata` field carries all rich parameter decoration.
- `ParameterMetadata` (struct, public, `Sendable`) — `required: RequiredKind`, `isOutput: Bool`, `defaultValue: String?`, `validValueSet: [String]`, `constraints: [Constraint]`, `attribs: [Attribute]`, `tags: [Tag]`. Static factory methods: `parse(from: String) -> (name: String, metadata: ParameterMetadata)?` (parses one `>>>` line) and `parseMetadataBlockIfAny(from: LineParser) async -> [String: ParameterMetadata]` (consumes all consecutive `>>>` lines from a parser).
- `DtoObject` (actor) — read-model; fields reference parent types.
- `UIView` (actor) — UI component; `dataType = .ui`.
- `Property` (actor) — `name`, `givenname`, `type: TypeInfo`, `required: RequiredKind`, `arrayMultiplicity: MultiplicityKind`, `isUnique`, `isObjectID`, `isSearchable`, regular `attribs`, separate `constraints`, `defaultValue`, `validValueSet: [String]`, `tags`.
- `ParserUtil` (class, static helpers) — shared parsing utilities. Value-returning sync helpers: `parseAttributes(from: String) -> [Attribute]`, `parseTags(from: String) -> [Tag]`, `parseValidValueSet(from: String?) -> [String]`, `parseConstraints(from: String?) -> [Constraint]`. Actor-populating async helpers: `populateAttributes(for:from:)`, `populateTags(for:from:)`, `populateConstraints(for:from:)` — the async variants delegate to their sync counterparts.
- `PropertyKind` (enum) — full type system (see §4.3).
- `TypeInfo` — `kind: PropertyKind`, `isArray: Bool`; helpers `isObject()`, `isNumeric`, `isDate`, `isReference()`, etc.
- `APIType` (enum) — create, update, delete, getById, list, listByCustomProperties, getByCustomProperties, associate, deassosiate, activate, deactivate, pushData, pushDataList, getByUsingCustomLogic, listByUsingCustomLogic, mutationUsingCustomLogic.
- `ArtifactKind` (enum) — container, component, entity, dto, cache, apiInput, embeddedType, valueType, api, ui, unKnown.

### `Sources/Pipelines/`

The 6-phase pipeline orchestrator.

```
Pipelines/
├── Pipeline.swift          # Pipeline struct; runs phases sequentially; PipelineState actor
├── Pipelines.swift         # Pre-built pipeline presets: .codegen, .content, .empty
├── PipelineConfig.swift    # OutputConfig protocol + PipelineConfig struct
├── PipelinePerformance.swift # Optional pipeline/phase/pass timing recorder + report types
├── PipelinePass.swift      # Protocol hierarchy for passes
├── PipelinePhase.swift     # Phase protocol
├── PipelineErrorPrinter.swift
├── 1. Discover/
│   ├── Discover.swift      # Factory: Discover.models()
│   └── DiscoverModels.swift
├── 2. Load/
│   ├── Load.swift          # Factory: Load.models(), Load.contentsFrom()
│   ├── LoadModels.swift
│   ├── LoadPages.swift
│   ├── LoadTemplates.swift
│   └── ContentFromFolder.swift
├── 3. Hydrate/
│   ├── Hydrate.swift       # Factory: Hydrate.models(), Hydrate.annotations()
│   ├── HydrateModels.swift # Port assignment, dataType classification
│   └── PassDownAndProcessAnnotations.swift
├── 3.5. Validate/          # Semantic validation after hydration; emits diagnostics, does not throw
│   ├── Validate.swift      # Factory: Validate.models()
│   └── ValidateModels.swift # Checks: unresolved custom types (W301), unresolved `@name` refs (W302), unresolved modules (W303), duplicate type names (W304), duplicate members (W305/W306)
├── 4. Transform/
│   ├── Transform.swift
│   └── Plugins.swift
├── 5. Render/
│   ├── Render.swift        # Factory: Render.code()
│   ├── GenerateCodePass.swift  # Resolves blueprint per container via `#blueprint(name)` tag
│   └── DebugRenderer.swift
└── 6. Persist/
    ├── Persist.swift       # Factory: Persist.toOutputFolder()
    └── GenerateOutputFolders.swift
```

**Pre-built pipelines** (`Pipelines.swift`):

```swift
Pipelines.codegen  // Discover → Load → Hydrate (models + annotations) → Validate → Render → Persist
Pipelines.content  // Load (contents + pages + templates)
Pipelines.empty    // No passes — useful for string-rendering tests
```

### `Sources/CodeGen/`

The template rendering engine.

```
CodeGen/
├── TemplateSoup/
│   ├── TemplateSoup.swift          # Main renderer actor; TemplateRenderer protocol
│   ├── TemplateSoupParser.swift
│   ├── TemplateEvaluator.swift     # Evaluates a Template object against Context
│   ├── _Base_/
│   │   ├── Blueprints/             # Blueprint protocol; LocalFile/Resource/Inline blueprints; finders & loaders; BlueprintAggregator
│   │   ├── Templates/              # Template protocol; LocalFileTemplate, LocalFilesetTemplate, StringTemplate
│   │   └── SpecialFolderNames.swift / TemplateConstants.swift
│   └── ContentLine/
│       ├── ContentLine.swift       # Line protocol; multiline print indent propagation
│       ├── ContentHandler.swift
│       ├── TextContent.swift       # Plain text
│       ├── WhitespaceContent.swift # Leading spaces/tabs on a line (indent preservation)
│       ├── PrintExpressionContent.swift  # {{ expression }}
│       ├── InlineFunctionCallContent.swift
│       └── EmptyLine.swift
└── MockData/
    ├── MockData_Generator.swift
    ├── SampleJson.swift
    └── SampleQueryString.swift
```

`TemplateSoup` is the central actor for rendering. It:
- Loads templates and scripts via a `Blueprint` (pluggable source)
- Executes scripts via `ScriptFileExecutor`
- Evaluates templates via `TemplateEvaluator`
- Manages `GenerationContext` snapshots (push/pop) for scoped variable isolation
- Provides `forEach(forInExpression:)` for programmatic loop driving

The special entry-point file in a blueprint is **`main.ss`** — `TemplateConstants.MainScriptFile = "main"` + `TemplateConstants.ScriptExtension = "ss"`. Before `main.ss` is invoked, `main.tconfig` from the model folder is loaded during Phase 2 (Load), injecting variables into the context that `main.ss` can reference. Blueprint symbol libraries are also loaded from `main.ss` front matter via `symbols-to-load: ...` before script execution begins.

### `Sources/Scripting/`

The SoupyScript DSL interpreter.

```
Scripting/
├── SoupyScript/
│   ├── ScriptParser.swift
│   ├── SoupyScriptParser.swift
│   ├── Containers/
│   │   └── TemplateFunction.swift  # User-defined template functions
│   ├── Libs/
│   │   ├── DefaultModifiersLibrary.swift   # String, math, array, dict, date modifiers
│   │   ├── DefaultOperatorsLibrary.swift   # and, or, comparisons, arithmetic, membership (in/not-in)
│   │   ├── StatementsLibrary.swift         # Registry of all statement types
│   │   └── ModifierLibs/
│   │       ├── GenerationLib.swift
│   │       ├── MockDataLib.swift
│   │       ├── ModelLib.swift              # Model introspection: type checking, property access
│   │       └── Modifiers-LangSpecific/
│   │           ├── TypescriptLib.swift     # typename, default-value
│   │           ├── JavaLib.swift
│   │           ├── GraphQLLib.swift
│   │           └── MongoDB_TypescriptLib.swift
│   ├── Stmts/                              # All statement implementations
│   │   ├── For.swift       AnnnounceStmt.swift   ConsoleLog.swift
│   │   ├── If.swift        CopyFile.swift         CopyFolder.swift
│   │   ├── FunctionCall.swift   FillAndCopyFile.swift
│   │   ├── RenderFile.swift     RenderFolder.swift
│   │   ├── RunShellCmd.swift    SetStr.swift       SetVar.swift
│   │   ├── Spaceless.swift      Stop.swift         ThrowError.swift
│   │   └── UnIdentifiedStmt.swift
│   └── Symbols/
│       ├── Modifiers/  # Modifier, ModifierInstance, Modifiers collection, CreateModifierHelper
│       └── Operators/  # Operator, CreateOperatorHelper
├── Wrappers/                               # Script-accessible wrappers around model objects
│   ├── APIWrap.swift
│   ├── C4ComponentWrap.swift
│   ├── C4ContainerWrap.swift
│   ├── CodeObjectWrap.swift                # methods, has-methods, …
│   ├── DataMockWrap.swift
│   ├── FlatLogicLineWrap.swift             # FlatLogicLineData + MethodObject.logic-lines flattening
│   ├── Loop.swift                          # @loop variable in for loops
│   ├── MethodObjectWrap.swift              # Method + parameter wrappers for templates
│   └── UIObjectWrap.swift
└── _Base_/
    ├── LocalScriptFile.swift
    ├── ScriptFile.swift
    ├── ScriptFileExecutor.swift            # Executes a parsed script
    ├── SoupyScriptStmtContainerList.swift
    ├── TemplateStmtContainer.swift
    ├── Wrapper+DynamicMemberLookup.swift
    ├── Parsing/
    │   ├── FrontMatter.swift
    │   ├── LineParser.swift          # LineParser protocol + GenericLineParser actor; includes lookAheadLine(by:) and lookAheadLine(skippingPrefix:) utilities
    │   ├── ParsedInfo.swift
    │   └── ParserDirective.swift   TemplateSoup_ParsingError.swift
    └── Stmts+Config/
        ├── BlockOrLineTemplateStmt+Config.swift
        ├── BlockTemplateStmt+Config.swift
        ├── LineTemplateStmt+Config.swift
        └── MultiBlockTemplateStmt+Config.swift
```

### `Sources/Workspace/`

The execution context and sandbox.

```
Workspace/
├── Workspace.swift             # Public facade (actor): config, model, sandboxes, render
├── InlineGenerationHarness.swift # End-to-end codegen with InlineModel + InlineBlueprint (tests / no on-disk model or blueprint repo)
├── Config/
│   └── ConfigFileParser.swift  # Parses .tconfig files (key=value pairs)
├── Context/
│   ├── CallStack.swift
│   ├── CodeGenerationEvents.swift  # Event hooks: onBeforeRenderTemplateFile, onBeforeRenderFile, etc.
│   ├── Context.swift
│   ├── ContextState + Symbol.swift
│   ├── DebugUtils.swift
│   ├── GenerationContext.swift     # Extends LoadContext for render phase
│   ├── LoadContext.swift           # Context during load phase
│   ├── ModelSymbols.swift
│   ├── ObjectAttributeManager.swift
│   ├── SnapshotStack.swift
│   ├── TemplateFunctionMap.swift
│   ├── TemplateSoupSymbols.swift   # Registry: modifiers + operators + statements
│   └── WorkingMemory.swift
├── Evaluation/
│   ├── ExpressionEvaluator.swift              # Single-value + full-expression evaluator; delegates compound expressions to RegularExpressionEvaluator; includes parseStringArrayLiteral
│   ├── RegularExpressionEvaluator.swift       # Tokenizer (ExpressionToken) + parenthesised-group parser + operator overload dispatch; handles quoted strings, bracket arrays, infix operators
│   └── TemplateSoup_EvaluationError.swift
└── Sandbox/
    ├── AppModel.swift                    # Holds ModelSpace + commonModel
    ├── CodeGenerationSandbox.swift       # Main generation actor (GenerationSandbox protocol)
    ├── ParsedTypesCache.swift
    └── Sandbox.swift                     # Sandbox protocol
```

---

## 6. The 6-Phase Pipeline

```
Discover ──► Load ──► Hydrate ──► Validate ──► Transform ──► Render ──► Persist
```

Each phase is a `PipelinePhase` that holds a list of `PipelinePass` implementations. Passes are composable — you can build custom pipelines using the `@PipelineBuilder` DSL.

### Phase 1 — Discover

- `DiscoverModels` — walks `basePath` looking for `.modelhike` files and registers them in `LoadContext`.

### Phase 2 — Load

- `LoadModels` — for each discovered file, runs `ModelFileParser` which dispatches to sub-parsers. Populates `ModelSpace` with `C4Container`s, `C4Component`s, `DomainObject`s, `DtoObject`s, `UIView`s.
- `LoadPages`, `LoadTemplates`, `ContentFromFolder` — optional passes for non-codegen content pipelines.

### Phase 3 — Hydrate

- `HydrateModels` — post-load refinements:
  - Assigns sequential port numbers (starting at 3001) to each microservice.
  - Classifies `DomainObject` data types: `entity` (has `id`/`_id`), `cache` (name ends with `Cache`), `apiInput` (name ends with `Input`), `embeddedType` (otherwise).
  - Classifies `DtoObject` data types: `dto` or `apiInput`.
- `PassDownAndProcessAnnotations` — resolves annotation inheritance and cascades annotations down the model hierarchy.

### Phase 3.5 — Validate

- `ValidateModelsPass` — semantic validation pass run after hydration, before rendering. Emits structured `diagnostic` debug events (never throws) so warnings appear in the Problems panel without halting the pipeline. `W301`-`W306` now point at the parsed model line that triggered the warning when source metadata is available.
  - **W301** — Unresolved custom type reference (property refers to a type not found in `ParsedTypesCache`).
  - **W302** — Unresolved `@identifier` on a property line (constraint/expression reference not found in module/class `namedConstraints`/`expressions` or `common.modelhike`).
  - **W303** — Unresolved module reference on a container (references a `+module` that was never defined).
  - **W304** — Duplicate type name within the same container.
  - **W305** — Duplicate property name within the same class/entity.
  - **W306** — Duplicate method name within the same class/entity.
  - **W307** — Container missing `#blueprint(name)` tag — skipped during render.

### Phase 4 — Transform

- Currently a no-op placeholder. Intended for plugins/transformation passes.

### Phase 5 — Render

- `GenerateCodePass` — the main code generation pass:
  1. Resolves a blueprint per target container from either `config.blueprintName` (override) or that container's `#blueprint(name)` tag (for example `#blueprint(api-springboot-monorepo)` or `#blueprint(api-nestjs-monorepo)`).
  2. Loads language-specific modifier symbols (Java for Spring Boot; TypeScript + MongoDB for NestJS).
  3. Creates a `CodeGenerationSandbox`.
  4. Calls `sandbox.generateFilesFor(container:)` which:
     - Sets `@container` and `@mock` template variables.
     - Scopes output under a per-container subfolder. Default suffix: normalized container name. Override with `#output-folder(name)` on the container.
     - Renders the blueprint's `Root/` special folder.
     - Executes `main.ss` (the blueprint's entry-point SoupyScript file).

### Phase 6 — Persist

- `GenerateOutputFolders` — iterates all `OutputFolder`s and `OutputFile`s queued during Render, writes them to disk at `config.output` path.

---

## 7. Domain Model Objects

### Object Hierarchy

```
Artifact (protocol)
├── ArtifactHolder (protocol) → C4System, C4Container, C4Component
├── CodeObject (protocol) → DomainObject, DtoObject
│   └── CodeMember (protocol) → Property, MethodObject
└── UIObject (protocol) → UIView
```

### `C4System` (actor)

| Field | Type | Description |
|---|---|---|
| `name` | String | Normalised (variable-name safe) |
| `givenname` | String | Original human-readable name |
| `description` | String? | Inline or prose description |
| `containers` | `C4ContainerList` | Resolved containers (populated during hydration) |
| `unresolvedContainerRefs` | `[String]` | Container names from `+` lines — resolved during load (in `AppModel.resolveAndLinkItems`) |
| `infraNodes` | `[InfraNode]` | Inline infra elements (databases, brokers, caches, etc.) |
| `groups` | `[VirtualGroup]` | Named visual clusters (`+--- Name … +---`) declared inside the system body |
| `attribs` | `Attributes` | |
| `tags` | `Tags` | |
| `annotations` | `Annotations` | |

**DSL syntax:**
```text
* * * * * * * * * * * * * * * * * * *     ← opening title fence
System Name (attributes) #tags
* * * * * * * * * * * * * * * * * * *     ← closing title fence / body begins
+ Container A                             ← container reference (resolved at load)
+ Container B
PostgreSQL [database] #primary-db         ← infra node
+++++++++++++++++++++++++++++++++
host = db.internal
port = 5432
* * * * * * * * * * * * * * * * * * *     ← end of system body
```

### `C4Container` (actor)

| Field | Type | Description |
|---|---|---|
| `name` | String | Normalised (variable-name safe) |
| `givenname` | String | Original human-readable name |
| `containerType` | `ContainerKind` | unknown / microservices / webApp / mobileApp |
| `components` | `C4ComponentList` | Modules contained |
| `unresolvedMembers` | `[ContainerModuleMember]` | Pending module references |
| `attribs` | `Attributes` | |
| `tags` | `Tags` | |
| `annotations` | `Annotations` | |

### `C4Component` (actor) — Module

Holds `DomainObject`s, `DtoObject`s, `UIView`s. Has `submodules`. Inherits from parent modules via `mixins`.

### `DomainObject` (actor) — Class/Entity

| Field | Type |
|---|---|
| `name` / `givenname` | String |
| `members` | `[CodeMember]` (Property + MethodObject) |
| `mixins` | `[CodeObject]` (resolved parent classes) |
| `attachedSections` | `AttachedSections` |
| `attached` | `[Artifact]` (APIs attached to this object) |
| `dataType` | `ArtifactKind` |
| `attribs` / `tags` / `annotations` | Metadata |

### `Property` (actor)

| Field | Type | Notes |
|---|---|---|
| `name` / `givenname` | String | |
| `type` | `TypeInfo` | kind + isArray |
| `required` | `RequiredKind` | `yes` (`*`) / `no` (`-` or `_`) / `conditional` (`*?`) |
| `arrayMultiplicity` | `MultiplicityKind` | noBounds / lowerBound / bounded |
| `isUnique` | Bool | |
| `isObjectID` | Bool | |
| `isSearchable` | Bool | |
| `attribs` | `Attributes` | Regular property attributes such as `(backend)` |
| `constraints` | `Constraints` | Property-only constraints such as `{ min = 0, max = 10 }` or `{ salary > 0 }`, stored as structured expressions |
| `defaultValue` | `String?` | Scalar property default parsed from `= value` |
| `validValueSet` | `[String]` | Valid value set parsed from bare `<...>` after any default; split via `ParserUtil.parseValidValueSet` |
| `tags` | `Tags` | Free-form property tags |

### `APIType` enum

```
create, update, delete, getById, list,
listByCustomProperties, getByCustomProperties,
associate, deassosiate, activate, deactivate,
pushData, pushDataList,
getByUsingCustomLogic, listByUsingCustomLogic, mutationUsingCustomLogic
```

---

## 8. Template Engine — TemplateSoup + SoupyScript

### 8.1 TemplateSoup (template renderer)

`TemplateSoup` is the core rendering actor. It accepts a `Blueprint` (template source) and a `GenerationContext` and exposes:

- `renderTemplate(fileName:data:with:)` — render a named template file
- `renderTemplate(string:data:with:)` — render an inline template string
- `runScript(fileName:data:with:)` — run a SoupyScript file
- `startMainScript(with:)` — run the blueprint's `main.ss` entry-point script
- `forEach(forInExpression:renderClosure:)` — programmatic loop

> **Template + scripting syntax reference:** All TemplateSoup and SoupyScript syntax — `{{ }}` print expressions, file-type prefix rules (`.ss` vs `.teso`), statement reference, front matter, built-in template variables, modifiers, and operators — is documented in [`DSL/templatesoup.dsl.md`](DSL/templatesoup.dsl.md). That file is the single source of truth. **Update `DSL/templatesoup.dsl.md` when any syntax changes; do not duplicate syntax here.**

### 8.2 Content lines & method logic in templates

- **Indentation** — `WhitespaceContent` records leading spaces/tabs on a template line. When a `{{ … }}` print spans multiple lines, the first line’s leading whitespace is applied to continuation lines (use `String.newLine` / `String.newLine2` in Swift, not ad-hoc `\n` literals — see Key Conventions).
- **`MethodObject` in scripts** — `MethodObject_Wrap` / `MethodParameter_Wrap` expose signatures and metadata. For each method with logic, `logic-lines` is built from `FlatLogicLineData.flatten`, producing rows with `kind`, `depth`, `is-open` / `is-leaf` / `is-close`, and structured fields (`condition`, `for-item`, …). Language-specific emission belongs in blueprint `_modifiers_` (e.g. Spring Boot `java-method-body.teso`, `java-method-params.teso`, `java-return-type.teso`).

---

## 9. Blueprint System

A **Blueprint** is a named folder inside `localBlueprintsPath` containing `.teso` template files, static files, subfolder groups, and a `main.ss` entry-point SoupyScript. The engine renders it against a loaded model to produce the output codebase.

### Blueprint Sources

| Type | Class | Description |
|---|---|---|
| Local filesystem | `LocalFileBlueprint` | Loads from an absolute path (the external `modelhike-blueprints` repo) |
| Swift resources | `ResourceBlueprint` | Loads from embedded Swift package resources |
| In-memory (Swift) | `InlineBlueprint` | Builds the same virtual tree as a disk blueprint (`main.ss`, `.teso`, static files, nested folders); resolved via `InlineBlueprintFinder` |
| Aggregated | `BlueprintAggregator` | Merges multiple blueprint sources |

### Current Blueprints

Two blueprints live in `modelhike-blueprints/Sources/Resources/blueprints/`. `GenerateCodePass` resolves the active one from either `config.blueprintName` or each container's `#blueprint(name)` tag, and can optionally override the container's output subfolder via `#output-folder(name)`, for example:

```text
===
APIs #blueprint(api-springboot-monorepo) #output-folder(base-services)
===
```

---

### Special Blueprint Folders

- **`_root_/`** — static files (and `.teso` templates) that are copied/rendered into the output root. Contains Dockerfile, env files, config files, etc.
- There is **no** `Root/` folder in the actual blueprints; `_root_/` is the convention used.
- **`_modifiers_/`** — blueprint-local modifier definitions. Each `.teso` file in this folder is registered as a named `Modifier`. See §9.1 below for the front-matter schema.

### 9.1 Blueprint-Defined Modifiers (`_modifiers_/`)

Any `.teso` file placed in the blueprint's `_modifiers_/` folder is automatically loaded and registered as a modifier before `main.ss` runs. The modifier name is the filename without the `.teso` extension.

**Front-matter schema** (YAML key:value pairs between `---` fences):

```
---
input: value          # variable name the piped value is bound to in the template
type: String          # expected input type: String | Double | Bool | Array | Object | Any
params: from, to      # (optional) positional argument names, comma-separated
---
```

- All three keys are optional. Defaults: `input = "value"`, `type = Any`, no params.
- If `params` is absent, the modifier is registered as a **no-arg** modifier: `{{ value | myModifier }}`.
- If `params` is present, the modifier is registered as a **with-args** modifier: `{{ value | myModifier(arg1, arg2) }}`.
- The template body renders to a `String`. Normal TemplateSoup syntax (`:if`, `:for`, `{{ expr }}`, etc.) is fully available.
- Type mismatch at call time throws `modifierCalledOnwrongType`.

**Example — no-arg modifier (`_modifiers_/javaType.teso`):**

```teso
---
input: prop
type: Object
---
:if prop.type == "String"
String
:end-if
:if prop.type == "Int"
Integer
:end-if
```

Used as: `{{ prop | javaType }}`

**Example — with-args modifier (`_modifiers_/wrap.teso`):**

```teso
---
input: value
type: String
params: prefix, suffix
---
{{ prefix }}{{ value }}{{ suffix }}
```

Used as: `{{ value | wrap("(", ")") }}`

**Implementation details:**
- `BlueprintModifierWithoutParams` / `BlueprintModifierWithParams` — the `Modifier` definition types (in `Symbols/Modifiers/BlueprintModifier.swift`).
- `BlueprintModifierLoader` — scans `_modifiers_/`, parses front matter, builds instances (in `Libs/BlueprintModifierLoader.swift`).
- `InputFileRepository.listFiles(inFolder:)` — added to the blueprint protocol with a default empty implementation; `LocalFileBlueprint` provides a real filesystem-backed implementation.
- Loading happens in `CodeGenerationSandbox.generateFilesFor(container:usingBlueprintsFrom:)`, after the blueprint is set and before the root folder + `main.ss` are rendered.

### `working_dir` Variable

Scripts control where output files land by setting `working_dir`. It is read by the sandbox's `setRelativePath()` to route generated files into the correct output subdirectory. Full variable reference in [`DSL/templatesoup.dsl.md`](DSL/templatesoup.dsl.md) §5.7.

---

## 10. Workspace, Context, and Sandbox

### `Workspace` (actor)

The public API facade. Entry point for:
- `config(_:)` — set configuration
- `newGenerationSandbox()` — create a `CodeGenerationSandbox` for code gen
- `newStringSandbox()` — create a sandbox for string-only rendering
- `render(string:data:)` — render a template string directly

### `InlineGenerationHarness`

`InlineGenerationHarness` (`Sources/Workspace/InlineGenerationHarness.swift`) runs the **standard codegen pipeline** against an in-memory model and blueprint—no `.modelhike` files on disk and no `modelhike-blueprints` checkout. It wires `PipelineConfig.modelSource` to `InlineModelLoader` (from `InlineModel`, optional `InlineCommonTypes`, optional `InlineConfig`) and `PipelineConfig.blueprints` to a single `InlineBlueprintFinder` for the supplied `InlineBlueprint`. The active blueprint name comes from `blueprint.blueprintName` and is set on `pipelineConfig.blueprintName`.

The inline APIs now also support JSON round-trips:
- `InlineBlueprintSnapshot` (`Sources/CodeGen/TemplateSoup/_Base_/Blueprints/InlineBlueprint+Codable.swift`) is the Codable bridge for `InlineBlueprint`
- `InlineModelSnapshot` (`Sources/Modelling/_Base_/Loader/InlineModelLoader+Codable.swift`) is the Codable bridge for `InlineModel`, `InlineCommonTypes`, and `InlineConfig`
- `InlineBlueprint.toJSON()` / `InlineBlueprint.fromJSON(...)` and `InlineModelSnapshot.toJSON()` / `.fromJSON(...)` support serialization for test harnesses and higher-level tooling

| API | Pipeline | Result |
|---|---|---|
| `generate(...)` | Discover → Load → Hydrate → Validate → Render (**no Persist**) | `[String: String]` — merged `OutputFolder.snapshot()` from every `CodeGenerationSandbox` (logical paths → file body text; includes rendered templates, static copy outputs, and placeholders where applicable) |
| `generateToTempFolder(...)` | Same phases **plus** Persist | `(path: LocalPath, files: [String: String])` — files written under a unique temp directory **and** the same in-memory map as `generate` |

Optional `containersToOutput` limits which containers are generated (same semantics as `PipelineConfig.containersToOutput`). For ad-hoc checks and tests, prefer `generate` to avoid disk I/O; use `generateToTempFolder` when you need real files (e.g. shelling out to a compiler).

### `LoadContext` (actor)

Holds state during the Load phase:
- `AppModel` — the growing in-memory model
- `OutputConfig` — pipeline configuration (output roots, target selection, optional `blueprintName` override)
- `variables` — config variables from `.tconfig` files

### `GenerationContext` (actor)

Extends `LoadContext` with rendering state:
- `symbols: TemplateSoupSymbols` — registered modifiers, operators, and statements
- `fileGenerator` — reference to the `CodeGenerationSandbox`
- `callStack: CallStack` — for error reporting
- `debugLog` — debug/trace utilities
- `pushSnapshot()` / `popSnapshot()` — scoped variable isolation via `SnapshotStack`

### `CodeGenerationSandbox` (actor)

The workhorse for code generation:

```
CodeGenerationSandbox
├── context: GenerationContext
├── templateSoup: TemplateSoup
├── base_generation_dir: OutputFolder    (config.output)
├── generation_dir: OutputFolder         (current relative subdirectory)
└── Methods:
    ├── generateFilesFor(container:usingBlueprintsFrom:)
    ├── generateFile(_:template:with:)
    ├── generateFileWithData(_:template:data:with:)
    ├── copyFile(_:with:) / copyFile(_:to:with:)
    ├── copyFolder(_:with:) / copyFolder(_:to:with:)
    ├── renderFolder(_:to:with:)
    └── fillPlaceholdersAndCopyFile(_:with:)
```

**Symbol loading** (via `Blueprint.loadSymbols(to:)` reading `main.ss` front matter `symbols-to-load: ...`):
- `.typescript` → loads `TypescriptLib`
- `.mongodb_typescript` → additionally loads `MongoDB_TypescriptLib`
- `.java` → loads `JavaLib`
- `.noMocking` → skips `MockDataLib`
- Always loaded: `DefaultModifiersLibrary`, `DefaultOperatorsLibrary`, `StatementsLibrary`, `ModelLib`, `GenerationLib`, `GraphQLLib`

### `CodeGenerationEvents`

Optional event hooks on `PipelineConfig`:

| Hook | When called |
|---|---|
| `onBeforeRenderTemplateFile` | Before rendering a template file |
| `onBeforeRenderFile` | Before rendering any output file |
| `onBeforeParseTemplate` | Before parsing a template |
| `onBeforeExecuteTemplate` | Before executing a template |
| `onStartParseObject` | When the parser begins parsing a model object |

Return `false` from `onBeforeRenderFile` to skip generating that file.

---

## 11. DevTester Executable

**Path:** `DevTester/`

The `DevTester` target is the **development harness** — an executable that imports `ModelHike` and exercises the full pipeline. It is not the production CLI (which does not yet exist in this repo).

### `DevMain.swift`

```swift
@main struct Development {
    static func main() async {
        try await runCodebaseGeneration()   // currently active
        // try await runTemplateStr()       // for testing expression evaluation
    }
}
```

**`runCodebaseGeneration()`:**
- Uses `Pipelines.codegen`
- Config from `Environment.debug`
- Currently set to `config.containersToOutput = ["APIs"]`
- Passing `--perf` sets `config.recordPerformance = true` and prints a timing report after the run
- Commented-out hooks show how to enable per-file debug tracing

**`runTemplateStr()`:**
- Uses `Pipelines.empty`
- Tests raw template string rendering against a small data dictionary

**`inlineModel()`** (unused helper):
- Shows how to define models inline in Swift code (as an alternative to file-based loading)
- Demonstrates the `InlineModelLoader` / `InlineModel` / `InlineCommonTypes` API
- `InlineModel`, `InlineCommonTypes`, and `InlineConfig` accept optional `identifier:` values so parse/config errors can retain a meaningful source filename instead of a generic inline label
- For **full pipeline** runs against inline models and blueprints (tests, CI), use **`InlineGenerationHarness`** — see [§10 Workspace](#10-workspace-context-and-sandbox)

### `Environment.swift`

Defines two `OutputConfig` presets:

| Config | basePath | localBlueprintsPath |
|---|---|---|
| `debug` | Points to a subfolder inside `_Playground/` (gitignored, local only) | Sibling `modelhike-blueprints` repo (must be cloned separately) |
| `production` | `~/Documents/modelhike` | `{basePath}/blueprints` |

> **Note:** Both paths are hardcoded relative to `~/Documents/` using `SystemFolder.documents.path`. The `debug` config points outside the repo root to a sibling `modelhike-blueprints` repository that must be checked out separately.

### Visual debugging

Two debug modes are available:

- **`--debug`** — post-mortem mode: pipeline runs to completion, then the server starts and the browser is opened for inspection.
- **`--debug-stepping`** — live streaming mode: server starts first, WebSocket clients can connect before the pipeline runs, and every debug event is broadcast over WebSocket in real time via `StreamingDebugRecorder`.
- **`--perf`** — enables the pipeline performance recorder and prints total, phase, and pass timings to stdout after the run.

For substring handling, template-cache, and similar optimizations, compare `--perf` output on the **same** model folder and blueprint before and after each change to see the timing delta.

**Flags:** `--debug`, `--debug-stepping`, `--perf`, `--debug-port=<port>`, `--debug-dev` (serve HTML from Assets), `--no-open`

**Full reference:** [`Docs/debug/VISUALDEBUG.md`](Docs/debug/VISUALDEBUG.md) — runtime flow, architecture, integration inventory, event emission matrix, and troubleshooting.

---

## 12. Visual Debugging

ModelHike includes a browser-based visual debugger for pipeline runs. Two modes are available: post-mortem inspection and live event streaming.

### Debug Server Architecture

The debug server (`DevTester/DebugServer/`) is built on **SwiftNIO** (`NIOPosix` + `NIOHTTP1` + `NIOWebSocket`):

| File | Role |
|---|---|
| `DebugHTTPServer.swift` | `ServerBootstrap` setup, channel pipeline configuration |
| `DebugRouter.swift` | Actor; all HTTP routing and response logic |
| `HTTPChannelHandler.swift` | NIO handler; assembles HTTP requests, bridges to `DebugRouter` |
| `WebSocketClientManager.swift` | Actor; manages connected WebSocket clients, provides `broadcast(json:)` |
| `WebSocketHandler.swift` | NIO handler; registers clients via `handlerAdded` (not `channelActive`), handles WS frames |
| `StreamingDebugRecorder.swift` | Actor implementing `DebugRecorder`; broadcasts every event live over WebSocket |

### Debug Console Architecture

The debug console (`DevTester/Assets/debug-console/`) uses a modular architecture with Lit web components loaded from CDN:

```
debug-console/
├── index.html          # Entry point
├── styles/             # CSS (base, layout, themes)
├── components/         # 13 Lit web components
│   ├── debug-app.js    # Root orchestrator (mode-aware: post-mortem vs stepping)
│   ├── file-tree-panel.js  # File explorer
│   ├── source-editor.js    # Template viewer
│   ├── output-editor.js    # Generated output viewer
│   ├── trace-panel.js      # Event trace
│   ├── variables-panel.js  # Variable inspector
│   ├── stepper-panel.js    # Live stepping controls (shown on "paused" WS message)
│   └── ...
└── utils/              # Pure functions (api, state, formatters, WebSocket helpers)
```

### Key Features

- **File tree**: Scrollable list of generated files with folder hierarchy
- **Split view**: Template source and generated output side by side
- **Event trace**: Click events to see source location
- **Variable inspector**: View captured variable state (at file generation points)
- **Model hierarchy**: Browse containers, modules, entities
- **Expression evaluator**: Test expressions in footer input
- **Resizable panels**: Drag handles between panels
- **Live event streaming**: In `--debug-stepping` mode, events appear in real time via WebSocket
- **Stepper panel**: Run / Step Over / Step Into / Step Out controls (UI complete; full stepping semantics in progress)
- **Programmatic breakpoints**: Add breakpoints in Swift via `stepper.addBreakpoint(BreakpointLocation(fileIdentifier:lineNo:))`
- **WebSocket debugging protocol**: Add/remove breakpoints and send resume commands via WebSocket JSON messages; see [`Docs/debug/WEBSOCKET_PROTOCOL.md`](Docs/debug/WEBSOCKET_PROTOCOL.md) for full reference
- **New client sync**: Late-joining WebSocket clients automatically receive current pause state

### Running the Debug Console

```bash
# Post-mortem: pipeline runs first, then open the browser
swift run DevTester --debug --debug-dev --no-open --debug-port=4800

# Live streaming: server starts first, open browser, watch events arrive live
swift run DevTester --debug-stepping --debug-dev --no-open --debug-port=4800
```

Then open `http://localhost:4800` in a browser.

See [`DevTester/Assets/debug-console/README.md`](DevTester/Assets/debug-console/README.md) for detailed component documentation and [`Docs/debug/VISUALDEBUG.md`](Docs/debug/VISUALDEBUG.md) for the full architecture and troubleshooting guidance.

---

## 13. Tests

**Path:** `Tests/`

### `ExpressionParsing_Tests`

Tests the `RegularExpressionEvaluator` and `ExpressionEvaluator` (expression engine):

- `complexExpression1` through `complexExpression4` — various `and`/`or`/parenthesised combos
- `invalidExpressionError` — verifies `TemplateSoup_ParsingError.invalidExpression` is thrown
- `stringEqualityOperator` — string `==` comparison (`kind == "if"`)
- `stringNotEqualsOperator` — string `!=` comparison (`kind != "else"`)
- `stringInStringArrayLiteral` — `in` operator with bracket array literal (`kind in ["if", "elseif", "else"]`)
- `quotedStringWithSpaces` — quoted string with spaces as operand (`name == "hello world"`)
- `bracketArrayInParenGroup` — bracket array inside parenthesised group (`(kind in ["if", "else"]) and var1`)
- `tokenizeDirectly` — unit tests for `RegularExpressionEvaluator.tokenize()` verifying token output for quoted strings, bracket arrays, and parenthesised expressions
- `intComparison` — Int comparison operators (`>`, `<`, `>=`, `<=`, `==`, `!=`) with Int variable and Int literal
- `doubleComparison` — Double comparison operators (`>`, `<`, `==`) with Double variable and Double literal
- `intArithmetic` — Int arithmetic operators (`+`, `-`, `*`, `/`) returning Int results
- `doubleArithmetic` — Double arithmetic operators (`+`, `/`) returning Double results
- `typeMismatchThrows` — verifies that mixing Int variable with Double literal throws a type error

Uses `DynamicTestObj` (implements `DynamicMemberLookup + HasAttributes`) as test data.

### `TemplateSoup_String_Tests`

Tests end-to-end template string rendering:

- `testSimplePrint` — `{{ var1 }}`
- `testExpressionPrint` — `{{ (var1 and var2) and var2 }}`
- `testComplexTemplateWithMacroFunctions` — user-defined functions, set, nested renders, for loops, if/else
- `testSimpleNestedLoops` — deeply nested for + if + for

> **Note:** The test suite uses a synchronous `ws.render()` call which appears to be from an older synchronous API. The current production API is fully `async`. This may cause compilation issues; verify these tests compile and pass with current codebase.

### `BlueprintModifier_Tests` — `InlineBlueprint` suite

The **`@Suite("InlineBlueprint")`** block in `BlueprintModifier_Tests.swift` exercises **`InlineBlueprint`** (nested folders, static files, front matter) and **`InlineGenerationHarness`** end-to-end (`generate` / snapshot assertions). Modifier registration and blueprint `_modifiers_/` behaviour are covered in the same file under related suites.

---

## 14. Playground

**Path:** `_Playground/` — **gitignored; local development testing only. Contents are never committed and are not documented here.**

Used by `DevTester` (via `Environment.debug`) to run the full pipeline against real model files during development.

---

## 15. Current Project State & Known Gaps

### What Is Working

- ✅ Complete DSL parser — containers, modules, submodules, classes, DTOs, UIViews, properties, annotations, tags, attributes, API blocks, custom operations
- ✅ Full 6-phase pipeline (`Discover → Load → Hydrate → Transform → Render → Persist`)
- ✅ SoupyScript engine — all statement types, modifiers, operators, functions, loops, conditionals
- ✅ NestJS monorepo blueprint (TypeScript + MongoDB) — switch `blueprintName` to use it
- ✅ Spring Boot monorepo blueprint (`api-springboot-monorepo`) with Java symbols when that blueprint is active
- ✅ GraphQL + gRPC API scaffolding support in the DSL and modifier libraries
- ✅ Annotation cascade system
- ✅ Semantic validation phase (`Validate.models()`) — emits W301–W307 diagnostics for unresolved types and `@` references, duplicate names, missing modules, and missing blueprint tags, with parsed file/line locations preserved for W301–W306 when available
- ✅ World-class error messages — modifier/operator errors include structured `DiagnosticSuggestion` hints generated via `Suggestions` utility (Levenshtein distance + available-options metadata); nil-condition and nil-variable-clear warnings (W201/W202); blueprint preflight check (E101)
- ✅ Structured diagnostics in debug UI — `/api/diagnostics` endpoint; Problems panel in debug console
- ✅ Type inference and hydration (entity/dto/cache/apiInput/embeddedType classification)
- ✅ Mock data generation library
- ✅ Expression evaluator (boolean/arithmetic/comparison) with proper tokenizer: handles bracket array literals (`["a", "b"]`), quoted strings with spaces, and **type-aware operator dispatch** — operators are registered per type pair (e.g. `==` for `(String,String)`, `(Int,Int)`, `(Double,Double)`) and the runtime types of both operands are matched against registrations without coercion; full infix operator set: `==`, `!=`, `<`, `>`, `<=`, `>=`, `+`, `-`, `*`, `/`, `in`, `not-in`, `starts-with`, `ends-with`, `contains`, `matches`, `and`, `or`; `not` is a condition prefix handled in `ExpressionEvaluator.evaluateCondition`, not a registered operator
- ✅ Scoped variable isolation (snapshot stack)
- ✅ Debug hooks (event system in `CodeGenerationEvents`)
- ✅ Visual debugger — post-mortem browser UI (`swift run DevTester --debug`) and live WebSocket event streaming (`swift run DevTester --debug-stepping`); SwiftNIO-based server with full HTTP + WebSocket upgrade pipeline; stepper-panel UI for future breakpoint-driven stepping; see [Docs/debug/VISUALDEBUG.md](Docs/debug/VISUALDEBUG.md)

### What Is Hardcoded / Needs Refactoring

| Location | Hardcoded Value | Should Be |
|---|---|---|
| `DevTester/Environment.swift:7` | Absolute path to a local test model folder inside `_Playground/` | Configurable |
| `DevTester/Environment.swift:9` | Absolute path to sibling `modelhike-blueprints` repo | Configurable, documented |
| `DevTester/DevMain.swift:31` | `config.containersToOutput = ["APIs"]` | Not hardcoded |

### DSL File Extension

The loader (`LocalFileModelLoader`) only reads files with extension `.modelhike` (via `ModelConstants.ModelFile_Extension`). `DSL/modelHike.dsl.md` uses `.dsl.md` — it is the DSL documentation, not a model file loaded by the engine.

### Gaps Between README and Implementation

The `README.md` describes a CLI tool with commands like `modelhike generate`, `modelhike validate`, `modelhike ai bootstrap`, etc. **None of these CLI commands exist in this repository.** The codebase is currently a Swift library + a developer executable. The CLI layer is not yet implemented.

Other README features not yet implemented:
- `modelhike validate` — validation engine (no standalone validator phase)
- `modelhike template freeze` — no freeze mechanism
- `modelhike adr new` — no ADR scaffolding tool
- `modelhike sbom` — no SBOM generation
- VS Code extension — not in this repo
- Web-based live sandbox — not in this repo

### External Dependency

The blueprints (template files that drive actual code generation) live in a **separate repository** `modelhike-blueprints`. This repo must be cloned alongside `modelhike` for `DevTester` to work. The path relationship is currently hardcoded in `Environment.swift`.

### Test Coverage

Test files (`Tests/`):

| File | What it covers |
|---|---|
| `ExpressionParsing_Tests` | `RegularExpressionEvaluator` + `ExpressionEvaluator` — 16 tests: boolean expressions, string `==`/`!=`, `in` with bracket arrays, quoted strings, tokenizer unit tests, Int/Double comparison & arithmetic, type-mismatch error |
| `TemplateSoup_String_Tests` | End-to-end template string rendering — 4 tests |
| `PropertyParser_Tests` | `Property` parsing: defaults, valid value sets (`[String]`), constraints, attributes |
| `MethodParameterMetadata_Tests` | `>>>` parameter metadata parsing: required/optional markers, `#output` tag, `defaultValue`, constraints, attributes, valid value set, multi-param methods, setext methods |
| `FlatLogicLineData_Tests` | `FlatLogicLineData.flatten` — empty logic, single return, if/else chaining (no spurious close), `isChainedAfter` |
| `BlueprintModifier_Tests` | Blueprint-defined modifiers; **`InlineBlueprint`** (folders, static files, harness); **`InlineGenerationHarness`** smoke tests |

No tests yet for:
- Pipeline phases (aside from inline harness coverage in `BlueprintModifier_Tests`)
- Hydration logic
- Disk-based blueprint discovery (`LocalFileBlueprint`) as an integration suite
- Full file-generation regression suite beyond inline/harness cases

---

## 16. Key Conventions & Patterns

### Naming Conventions

- **CodeLogic** is the project name for fenced method-body logic in `.modelhike` files (`DSL/codelogic.dsl.md`, `CodeLogic` / `CodeLogicStmt` in code). Use **CodeLogic** in documentation and comments—do not use informal names.
- Swift `actor` is used extensively for all mutable model objects and shared state (Swift 6 strict concurrency compliance).
- `givenname` — the original human-readable name from the DSL (may have spaces).
- `name` — the normalised variable-name-safe form (spaces replaced, camelCased).
- `pInfo: ParsedInfo` — threaded through virtually all methods for error reporting context.

### Error Handling Philosophy

Errors fall into two categories — choose the right one:

| Category | When to use | Mechanism |
|---|---|---|
| **Recoverable / authoring mistakes** | The DSL or template has a problem the user can fix (wrong keyword placement, unresolved type, missing blank line, unknown modifier, etc.). The pipeline should continue and surface the issue. | Emit a `needsReview` node (CodeLogic parser), call `ctx.debugLog.recordDiagnostic(.warning, code: "W…", …)` (pipeline phases), or append a `DiagnosticSuggestion` to an existing error. Never `throw` for these. |
| **Fatal / unrecoverable errors** | The input is structurally invalid and further processing would produce corrupt output or a crash (e.g. a required model element is missing, a type constraint is violated, an expression cannot be tokenised at all). | `throw` an explicit typed error — `Model_ParsingError`, `TemplateSoup_ParsingError`, `TemplateSoup_EvaluationError`, or `EvaluationError`. Always include `pInfo` for location context. |

**Rules of thumb:**
- If the user can fix it by editing their `.modelhike` or template file → diagnostic / `needsReview`, not a throw.
- If continuing would produce nonsense output or a Swift crash → throw.
- `needsReview` nodes in CodeLogic are emitted as `// NEEDS REVIEW: reason` comments in generated code, making the problem visible without stopping the pipeline.
- Diagnostic codes: `W3xx` = model validation, `W2xx` = evaluation warnings, `E1xx` = blueprint preflight, `E6xx` = model parsing, `E7xx` = template/evaluation fatal.

CRITICAL:
**Always include suggestions when known alternatives exist:**
- When emitting a diagnostic about a missing or invalid value, **always** provide suggestions if there is a known set of valid options.
- Use `ctx.debugLog.recordLookupDiagnostic(...)` instead of plain `recordDiagnostic` when you can supply a list of candidates — it automatically generates "did you mean?" hints and lists available options.
- Example: missing `#blueprint(name)` tag should show available blueprints; unknown modifier should show available modifiers; unresolved type should show known types.
- The `Suggestions` utility (`Sources/Debug/Suggestions.swift`) provides helpers like `lookupFailureMessage` and `lookupSuggestions` for building rich error context.

### Code Patterns

- `ResultBuilder<T>` — used for `@PipelineBuilder`, `@CodeMemberBuilder`, `@InlineModelBuilder` DSLs.
- `@discardableResult` on append/generate methods — common pattern.
- `Sendable` conformance everywhere — required by Swift 6 strict concurrency. Actors, structs with `Sendable` properties.
- `DynamicMemberLookup + HasAttributes` — the pattern for objects that can be accessed by property name from within templates.

### Function signatures, calls, and computed properties (Swift)

- Put the **full parameter list on one line** for function and method **declarations** (including `async`, `throws`, and the return type), e.g. `private static func applyInfix(named op: String, lhs: Sendable?, rhs: Sendable?, pInfo: ParsedInfo) async throws -> Sendable {` — do not wrap parameters across multiple lines.
- Prefer the same for **calls** with several arguments: one line for the whole call when it remains readable (e.g. `Self.applyInfix(named: op, lhs: accumulated, rhs: rhsResult, pInfo: pInfo)`).
- **Computed property bodies** go on separate lines from the declaration — the opening brace is on the declaration line, the body starts on the next line, and the closing brace is on its own line. Do not inline the body on the same line as the `var` declaration. Example:
  ```swift
  public static var myOperator: InfixOperatorProtocol {
      CreateOperator.infix("==") { (lhs: String, rhs: String) in lhs == rhs }
  }
  ```
  Not: `public static var myOperator: InfixOperatorProtocol { CreateOperator.infix("==") { ... } }`

### String literals and line breaks

- **Do not use magic strings** for Unix line feeds (`"\n"`), Windows line endings (`"\r\n"`), or similar repeated delimiters in Swift source. Use **`String.newLine`** and **`String.newLine2`** defined on `String` in [`Sources/_Common_/Extensions/String.swift`](Sources/_Common_/Extensions/String.swift) (`newLine` → `"\n"`, `newLine2` → `"\r\n"`). This keeps splitting, joining, and containment checks consistent and grep-friendly.
- For other domain-specific character sequences (DSL prefixes, fence characters, etc.), prefer **`ModelConstants`**, **`TemplateConstants`**, or other named statics rather than scattering raw string literals.

### File Naming

- Swift source files follow sub-folder organization, not flat.
- Blueprint template files use `.teso` extension (TemplateSoup → "template soup").
- Model-folder generation config: `main.tconfig` (`ModelConstants.ConfigFile_Extension = "tconfig"`) — loaded in Phase 2 by `LocalFileModelLoader.loadGenerationConfigIfAny()`. Key-value pairs only (not a script). Variables set here are available when `main.ss` runs.
- Blueprint SoupyScript entry point: `main.ss` (`TemplateConstants.ScriptExtension = "ss"`) — executed in Phase 5. Receives all variables populated by `main.tconfig` and the model.
- **ModelHike DSL model files use `.modelhike` extension** — this is the only extension `LocalFileModelLoader` reads.
- `common.modelhike` — special shared-types file loaded into `model.commonModel`.
- `main.tconfig` in model folder — generation config (key-value variables).
- `main.ss` in blueprint folder — SoupyScript entry-point script.

### `ModelConstants` Quick Reference

| Constant | Value | Meaning |
|---|---|---|
| `Member_Mandatory` | `*` | Required property |
| `Member_Optional` | `-` | Optional property |
| `Member_Optional2` | `_` | Optional (underscore; accepted as alias for `-`) |
| `Member_Conditional` | `*?` | Conditionally required |
| `Member_Calculated` | `=` | Calculated/derived property |
| `Member_Derived_For_Dto` | `.` | DTO field |
| `Member_Method` | `~` | Method inside a class |
| `Member_ParameterMetadata` | `>>>` | Parameter metadata line preceding a method header |
| `Member_Description` | `--` | Inline / continuation description lines |
| `Member_Output` | `-->` | Output parameter marker (`>>>` or signature) |
| `Member_InOut` | `<-->` | In-out parameter marker (`>>>` or signature) |
| `Container_Member` | `+` | Module declaration inside container; container reference inside system |
| `SystemFenceChar` | `*` | Asterism fence character for system-level blocks |
| `SystemFenceMinCount` | `3` | Minimum number of asterisks in a valid system fence line |
| `InfraNodeUnderlineChar` | `+` | Setext underline character for infra-node headers inside a system body |
| `VirtualGroupFence` | `+---` | Opening/closing fence for a virtual group; opening has a name after it, closing has nothing |
| `VirtualGroupBodyPrefix` | `\|` | Prefix for body lines inside a virtual group |
| `External_Import_File` | `+` | File import (same prefix as container member) |
| `AttachedSection` | `#` | API block or other attached section |
| `AttachedSubSection` | `##` | Sub-section entry (custom API operation) |
| `Annotation_Start` | `@` | Annotation prefix |
| `Annotation_Split` | `::` | Separator between annotation keyword and values |
| `NameUnderlineChar` | `=` | Class/DTO underline character |
| `UIViewUnderlineChar` | `~` | UIView underline character |
| `ModelFile_Extension` | `modelhike` | Model file extension scanned by loader |
| `ConfigFile_Extension` | `tconfig` | Generation config file extension |

### Concurrency Model

- Swift 6 (`swift-tools-version: 6.0`) with `async/await` throughout.
- All model objects (`C4Container`, `C4Component`, `DomainObject`, `Property`, `TemplateSoup`, `CodeGenerationSandbox`, etc.) are `actor`s.
- `Sendable` protocol conformance is enforced; `nonisolated(unsafe)` used sparingly (e.g., static regex patterns).
- Context snapshot stack (`pushSnapshot`/`popSnapshot`) provides scoped variable isolation without data races.

---

## 17. Glossary

| Term | Definition |
|---|---|
| **Blueprint** | A repository of `.teso` template files, static files, and a `main.ss` entry-point SoupyScript. Blueprints drive what code is generated. |
| **System** | The outermost C4 boundary — a named collection of containers, infra nodes, and virtual groups. Uses three asterism fences: open title / close title / close body. `+` lines reference containers (resolved at load); infra nodes use a setext `++++` header with `key = value` properties; virtual groups use `+--- Name … +---` fences. Maps to `C4System`. |
| **InfraNode** | An inline infrastructure element inside a system body (database, broker, cache, etc.). Declared with a setext `++++` header, `[type]` bracket, and `key = value` property lines. Stored as `InfraNode` struct on `C4System.infraNodes`. |
| **VirtualGroup** | A named visual cluster inside a system body (or nested inside another group). Opening fence: `+--- Name #tags -- desc`. Closing fence: `+---` alone. Body lines prefixed with `\|`. Can contain container refs, infra nodes, and nested virtual groups. Carries no semantic meaning — exists for diagram layout. Optional `[ … ]` on the opening line holds technical implications (`TechnicalImplication`). Stored as `VirtualGroup` struct on `C4System.groups` (or `VirtualGroup.subGroups`). Container refs are resolved during load in `AppModel.resolveAndLinkItems`. |
| **Container** | A deployable unit in the C4 model — maps to a microservice, web app, or database. Defined with `===...===` fences. |
| **Module / Component** | A C4 Component inside a Container; maps to a bounded context or functional grouping. |
| **DomainObject** | A persisted entity class with typed properties, mixins, and optional APIs. |
| **DTO** | Data Transfer Object — a flattened read-model that derives fields from parent types. |
| **UIView** | A UI component model; `dataType = .ui`. |
| **SoupyScript** | The custom scripting language used in blueprint `.ss` script files and `.teso` template files. In `.ss` files statements have no prefix; in `.teso` files script statements are prefixed with `:`. Full syntax in [`DSL/templatesoup.dsl.md`](DSL/templatesoup.dsl.md). |
| **TemplateSoup** | The rendering engine that evaluates `{{ expression }}` print-blocks and SoupyScript statements. Full syntax in [`DSL/templatesoup.dsl.md`](DSL/templatesoup.dsl.md). |
| **Modifier** | A function applied to a template value: `{{ value \| modifier }}`. |
| **Annotation** | A directive starting with `@` that automates tasks like CRUD scaffolding or index creation. |
| **Tag** | A free-form label (`#tag` or `#tag:value`) for searchable metadata. |
| **Attribute** | A key-value pair (`key=value`) attached to model elements; used for validation rules, routing, etc. |
| **Technical implication** | Optional `[ … ]` segment on a line (after `(attributes)`, before `#` tags). Parsed as `TechnicalImplication` text; stored on model elements that support `TechnicalImplications`. On `# APIs` lines, bracket text starting with `/` contributes to the REST route prefix when `@ apis::` runs. |
| **Pipeline** | The 6-phase processing chain: Discover → Load → Hydrate → Transform → Render → Persist. |
| **Sandbox** | `CodeGenerationSandbox` — the actor that executes code generation for a single container against a blueprint. |
| **ModelSpace** | The root in-memory representation of all parsed models: `C4Container`s and `C4Component`s. |
| **PropertyKind** | Swift enum encoding the full DSL type system (int, string, bool, date, id, reference, codedValue, customType, etc.). |
| **pInfo** | `ParsedInfo` — carries line number, file identifier, parser reference, and context; passed through all parsing/evaluation methods for error location reporting. |
| **tconfig** | `main.tconfig` — a key-value config file placed in the model folder (alongside `.modelhike` files). Loaded in Phase 2 before `main.ss` is invoked. Sets generation variables (e.g. port numbers, prefixes) available throughout Phase 5 rendering. Not a script. |
| **.ss** | SoupyScript file extension (`TemplateConstants.ScriptExtension = "ss"`). `main.ss` is the blueprint entry point. |
| **teso** | A TemplateSoup template file (`.teso` extension) rendered against the generation context. |
| **common.modelhike** | Special shared-types file in the model folder. Loaded into `model.commonModel`; types here are available as mixins/parents across all containers. |
| **CodeLogic** | Fenced method-body syntax inside methods (pipe-gutter statements; `DSL/codelogic.dsl.md`). Parsed into `CodeLogic` / `CodeLogicStmt`; flattened for templates via `FlatLogicLineData`. |
| **MethodObject** | A method member inside a class (`~` tilde-prefix or setext style). Has `parameters: [MethodParameter]`, `returnType: TypeInfo`, and `logic: CodeLogic?`. May be preceded by `>>>` parameter metadata lines. |
| **MethodParameter** | A single method parameter: `name`, `type`, `metadata: ParameterMetadata`. |
| **ParameterMetadata** | Rich decoration for a `MethodParameter` parsed from `>>>` lines: `required`, `isOutput`, `defaultValue`, `validValueSet: [String]`, `constraints`, `attribs`, `tags`, optional `[ … ]` as `technicalImplications`, optional `--` inline description. |
| **backend attribute** | `(backend)` on a property or field — marks it as server-side only, excluded from client schemas by blueprints that honour this convention. |
| **MappingAnnotation** | The `@list-api` annotation value type: a list of `(key, value)` pairs expressed as `prop -> prop.sub; prop2 -> prop2`. |
| **Visual Debugger** | Browser-based inspection of pipeline runs. Post-mortem: `swift run DevTester --debug`. Live streaming: `swift run DevTester --debug-stepping`. Full docs in [Docs/debug/VISUALDEBUG.md](Docs/debug/VISUALDEBUG.md). |
