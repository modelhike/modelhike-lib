# Error Handling & Debugging Improvements — Action Plan and Implementation Status

> **Vision:** Error messages so precise they feel like a mentor standing over your shoulder. A debugging experience so transparent that every generated line can explain itself. Inspired by the Rust compiler, Elm's error messages, and VS Code's diagnostic system.

> **Status note (March 2026):** This document started as a forward-looking plan. Large parts of it are now implemented. It has been updated to reflect the current shipped state, what was verified, and what remains intentionally unfinished.

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Current State Assessment](#2-current-state-assessment)
3. [PART I — Error Message Quality (Rust-Grade Messages)](#3-part-i--error-message-quality)
   - [3.1 "Did You Mean?" Suggestions Everywhere](#31-did-you-mean-suggestions-everywhere)
   - [3.2 Show Expected vs Found on Every Error](#32-show-expected-vs-found-on-every-error)
   - [3.3 List Available Options on Lookup Failures](#33-list-available-options-on-lookup-failures)
   - [3.4 Structured Error Formatting (Rich Diagnostics)](#34-structured-error-formatting-rich-diagnostics)
   - [3.5 Error Codes and Documentation Index](#35-error-codes-and-documentation-index)
4. [PART II — Eliminate Silent Failures](#4-part-ii--eliminate-silent-failures)
   - [4.1 Replace try? with Precise Errors in Statement Execution](#41-replace-try-with-precise-errors-in-statement-execution)
   - [4.2 Make Condition nil → false Visible](#42-make-condition-nil--false-visible)
   - [4.3 Prevent Silent Variable Clearing](#43-prevent-silent-variable-clearing)
   - [4.4 Surface Constraint Parsing Errors](#44-surface-constraint-parsing-errors)
   - [4.5 Surface File I/O Failures in Template/Script Loading](#45-surface-file-io-failures-in-templatescript-loading)
   - [4.6 Fix PipelineErrorPrinter Mislabelling](#46-fix-pipelineerrorprinter-mislabelling)
   - [4.7 ObjectAttributeManager Silent Path Truncation](#47-objectattributemanager-silent-path-truncation)
   - [4.8 TemplateRenderedFile Silent nil Contents](#48-templaterenderedfile-silent-nil-contents)
5. [PART III — Model Validation Phase](#5-part-iii--model-validation-phase)
   - [5.1 Add a Dedicated Validate Phase After Hydrate](#51-add-a-dedicated-validate-phase-after-hydrate)
   - [5.2 Unresolved Type References](#52-unresolved-type-references)
   - [5.3 Unresolved Mixin References](#53-unresolved-mixin-references)
   - [5.4 Unresolved Container Module References](#54-unresolved-container-module-references)
   - [5.5 Duplicate Name Detection](#55-duplicate-name-detection)
   - [5.6 API-Property Consistency](#56-api-property-consistency)
   - [5.7 Blueprint Pre-Flight Check](#57-blueprint-pre-flight-check)
6. [PART IV — Warnings & Diagnostics System](#6-part-iv--warnings--diagnostics-system)
   - [6.1 Introduce a Diagnostics Channel](#61-introduce-a-diagnostics-channel)
   - [6.2 Non-Fatal Continuation Mode](#62-non-fatal-continuation-mode)
   - [6.3 Wire captureError into Pipeline Catch Blocks](#63-wire-captureerror-into-pipeline-catch-blocks)
   - [6.4 Pipeline.run Should Return a Typed Result](#64-pipelinerun-should-return-a-typed-result)
7. [PART V — Debug Event Completeness](#7-part-v--debug-event-completeness)
   - [7.1 Emit All Defined DebugEvent Cases](#71-emit-all-defined-debugevent-cases)
   - [7.2 Record Expression Evaluations](#72-record-expression-evaluations)
   - [7.3 Record Variable Mutations with captureDelta](#73-record-variable-mutations-with-capturedelta)
   - [7.4 Wire consoleLog and announce to Events](#74-wire-consolelog-and-announce-to-events)
   - [7.5 Fix Empty SourceLocations on Convenience Methods](#75-fix-empty-sourcelocations-on-convenience-methods)
   - [7.6 Wire setContainerName for Multi-Container](#76-wire-setcontainername-for-multi-container)
   - [7.7 Expose Call Stack in DebugSession](#77-expose-call-stack-in-debugsession)
8. [PART VI — Output-to-Template Traceability](#8-part-vi--output-to-template-traceability)
   - [8.1 Per-Line Source Mapping](#81-per-line-source-mapping)
   - [8.2 "Why Was This File Generated?" Summary](#82-why-was-this-file-generated-summary)
   - [8.3 Register Model Files as Debug Sources](#83-register-model-files-as-debug-sources)
   - [8.4 Full Provenance Chain](#84-full-provenance-chain)
9. [PART VII — Debug Console UI Overhaul](#9-part-vii--debug-console-ui-overhaul)
   - [9.1 Problems Panel (VS Code-Style)](#91-problems-panel-vs-code-style)
   - [9.2 Event Search and Filtering](#92-event-search-and-filtering)
   - [9.3 File Tree Error Indicators](#93-file-tree-error-indicators)
   - [9.4 Keyboard Navigation and Shortcuts](#94-keyboard-navigation-and-shortcuts)
   - [9.5 Variable Inspector Enhancements](#95-variable-inspector-enhancements)
   - [9.6 Source Editor Enhancements](#96-source-editor-enhancements)
   - [9.7 Complete formatters.js Event Labels](#97-complete-formattersjs-event-labels)
   - [9.8 Session Load Error Recovery](#98-session-load-error-recovery)
   - [9.9 Generation Diff View](#99-generation-diff-view)
   - [9.10 Performance Timeline](#910-performance-timeline)
   - [9.11 Breakpoint UI](#911-breakpoint-ui)
   - [9.12 Theme Support](#912-theme-support)
10. [PART VIII — Stepping & Live Debugging](#10-part-viii--stepping--live-debugging)
    - [10.1 Wire Global Keyboard Shortcuts](#101-wire-global-keyboard-shortcuts)
    - [10.2 Stack Frames on Pause](#102-stack-frames-on-pause)
    - [10.3 Evaluate Over WebSocket at Pause](#103-evaluate-over-websocket-at-pause)
    - [10.4 Conditional Breakpoints](#104-conditional-breakpoints)
    - [10.5 WebSocket Error/Ack Messages](#105-websocket-errorack-messages)
11. [Priority Matrix](#11-priority-matrix)
12. [Implementation Roadmap](#12-implementation-roadmap)

---

## 1. Executive Summary

After auditing every error type, every `throw`/`catch`/`try?` site, every error message string, every debug event emission point, every wrapper property lookup path, the full visual debugger UI, and the model validation surface, there are **five systemic issues**:

1. **Error messages are vague** — Messages like `"Invalid prop : name"` don't say what properties ARE available, don't suggest close matches, and don't show expected syntax. Compare this to Rust's `"field 'naem' not found in 'User'; did you mean 'name'?"`.

2. **Silent failures everywhere** — 5 statement types swallow errors via `try?`, condition evaluation maps `nil` to `false`, `set-var`/`set-str` silently clear variables, `ObjectAttributeManager` silently truncates property paths, and `TemplateRenderedFile` silently produces empty files. A user sees wrong/missing output with zero indication of what went wrong.

3. **No model validation** — There is no pre-render validation phase. Undefined type references, unresolved mixins, unresolved container modules, duplicate names, and API-property mismatches all pass silently through Load and Hydrate and only surface (if at all) as cryptic template errors deep in the Render phase.

4. **Incomplete debug event coverage** — This was one of the biggest original gaps. Most of it is now fixed; the notable remaining blind spots are `expressionEvaluated` and `parseBlockStarted`.

5. **Debug console had blind spots** — Search/filter, Problems panel, keyboard shortcuts, event formatter coverage, variable search, theme support, and session-load recovery are now implemented. The biggest remaining UI gaps are file-tree problem badges, provenance/source maps, and breakpoint UX.

The actions below originally defined a 45-item roadmap. The current codebase now implements the majority of the high-value work:

- **Error quality:** richer wording, "did you mean?" suggestions, expected/found messaging, available-options lists, and file-system-specific evaluation errors
- **Silent-failure removal:** the previously swallowed file/folder path-evaluation failures now throw explicit errors; nil conditions and variable clearing now emit diagnostics
- **Validation:** a dedicated `Validate.models()` phase emits W301/W303-W306 diagnostics without halting generation
- **Diagnostics infrastructure:** `DebugEvent.diagnostic`, `/api/diagnostics`, structured Problems panel rendering, and pipeline-side `captureError(...)`
- **Debug event completeness:** `phaseStarted`, `phaseCompleted`, `phaseFailed`, `modelLoaded`, `scriptCompleted`, `templateCompleted`, `consoleLog`, `announce`, `variableSet`, and `error` are all wired
- **Visual debugger UX:** Problems panel, trace search/filter, keyboard shortcuts, session-load recovery, theme toggle, variable search, virtualized event list, and Problems -> Trace/Source click-through

The highest-value remaining gaps are now concentrated in **traceability** (per-line output-to-template mapping), **richer structured diagnostics** (secondary locations / notes / actionable suggestions), and **advanced stepping** (real step semantics, breakpoint UI, pause-time stack frames).

### 1.1 Implemented Now

| Area | Current State |
|---|---|
| Suggestions | Implemented via `Sources/Debug/Suggestions.swift` (Levenshtein + available-options formatting) |
| Expected / found error text | Implemented for modifier/operator/type mismatch paths |
| Silent file path failures | Implemented via `TemplateSoup_EvaluationError.invalidFileSystemPath(...)` in `copy-file`, `render-file`, `copy-folder`, `render-folder`, `fill-and-copy-file` |
| Nil condition visibility | Implemented as warning diagnostic `W201` |
| Variable clear visibility | Implemented as warning diagnostic `W202` |
| Semantic validation phase | Implemented as `Validate.models()` in the codegen pipeline |
| Validation codes | Implemented: `W301`, `W303`, `W304`, `W305`, `W306`; blueprint preflight `E101` |
| Structured diagnostics channel | Implemented as `DebugEvent.diagnostic(...)` plus `/api/diagnostics` |
| Variable deltas / time travel | Implemented via `captureBaseSnapshot(...)` + `captureDelta(...)` wiring in variable mutation paths |
| Problems panel | Implemented in the visual debugger |
| Problems click-through | Implemented and browser-verified against a real debug session |
| Theme support | Implemented (dark/light toggle, persisted in `localStorage`) |
| Event-list performance | Implemented via virtual scrolling in `trace-panel.js` |

### 1.2 Still Planned / Not Yet Shipped

| Area | Status |
|---|---|
| Rich `Diagnostic` model with secondary locations / notes | Not implemented; current payload is `DebugEvent.diagnostic(severity, code, message, source, suggestions)` |
| Expression evaluation events (`expressionEvaluated`) | Still defined but not emitted consistently |
| `parseBlockStarted` events | Still defined but not emitted |
| Per-line output-to-template source mapping | Not implemented |
| "Why was this file generated?" summary panel | Not implemented |
| Model files registered as debug sources | Not implemented broadly |
| Breakpoint gutter UI | Not implemented |
| Conditional breakpoints | Not implemented |
| Pause-time call stack in WebSocket pause payload | Not implemented |

### 1.3 Test Coverage

The enriched error-handling work is backed by dedicated test suites:

- **`Tests/Debug/EnrichedDX_Tests.swift`** — 9 tests verifying precise error message wording: unknown modifier/variable/function/operator suggestions, no-arg vs args-required modifier guidance, type mismatch messages, and diagnostic event JSON encoding
- **`Tests/Debug/DebugRecorder_Tests.swift`** — 3 tests verifying event recording, base snapshot + delta reconstruction, generated file tracking, and source file registration

Run with `swift test --filter Debug`.

---

## 2. Current State Assessment

### What's Already Good

| Area | Assessment |
|------|-----------|
| `ParsedInfo` threading | Consistently passed through nearly all parsing and evaluation paths — solid foundation |
| Error type hierarchy | Well-structured: 6 error enums, all with `pInfo`, protocol-based |
| `PipelineErrorPrinter` | Prints call stack + memory dump + debug info — rich when it fires |
| Debug event infrastructure | `DebugRecorder`, `DebugSession`, `DebugEventEnvelope` with sequence numbers — good bones |
| Visual debugger UI | File tree, source/output split, trace, variables, model browser, expression eval — functional |
| Stepping infrastructure | `LiveDebugStepper` with breakpoints, step modes, `onPause` — working backend |
| Wrapper property access | Throws on miss (not silent) for direct property access on wrappers |

### Remaining Gaps

| Area | Severity | Summary |
|------|----------|---------|
| Structured `Diagnostic` object | Medium | Current diagnostics are encoded as `DebugEvent.diagnostic(...)`, not as a richer multi-location document model |
| Expression evaluation trace events | Medium | `expressionEvaluated` exists in the schema but is not broadly emitted yet |
| Parse-start granularity | Low | `parseBlockStarted` exists but is not emitted yet |
| Per-line traceability | High | No output-line -> template-line mapping yet |
| File provenance summary | Medium | No dedicated "why was this file generated?" panel yet |
| Model source registration | Medium | Templates/scripts are registered as sources, but model/config files are not comprehensively surfaced in the UI |
| Breakpoint UX | Medium | WebSocket protocol exists, but there is still no gutter/list breakpoint UI |
| Advanced stepping semantics | Medium | Run/Step Over/Into/Out controls exist, but differentiated stepping semantics are still incomplete |
| File-tree diagnostics | Low | Problems exist in the Problems panel, but file-tree badges/indicators are not implemented |
| Pause-time call stack | Low | Runtime error call stacks are captured in the session, but pause payloads do not yet expose live stack frames |

---

## 3. PART I — Error Message Quality

> **Goal:** Every error message answers three questions: What went wrong? Where? What should I do instead?

### 3.1 "Did You Mean?" Suggestions Everywhere

**Problem:** When a variable, property, modifier, operator, function, template, or type name is not found, the error just says "not found." The user has to guess what they misspelled.

**What Rust does:** `field 'naem' not found in 'User'; did you mean 'name'?`

**Action:** Create a shared `Suggestions` utility:

```swift
public enum Suggestions {
    /// Levenshtein distance with threshold-based filtering.
    static func closestMatches(
        for query: String,
        in candidates: [String],
        maxDistance: Int = 2,
        maxResults: Int = 3
    ) -> [String]
}
```

Wire it into every lookup failure:

| Lookup Type | Available Candidates Source | File |
|---|---|---|
| Variable | `context.variables.keys` | `Context.swift` |
| Object property | wrapper's known property list (add `availableProperties: [String]` to wrapper protocol) | `CodeObjectWrap.swift`, `C4ComponentWrap.swift`, etc. |
| Modifier | `context.symbols.template.modifiers.names` | `Modifiers.swift` |
| Operator | `context.symbols.template.operators.names` | `RegularExpressionEvaluator.swift` |
| Template function | `context.templateFunctions.keys` | `FunctionCall.swift` |
| Template file | `blueprint.listFiles(inFolder:)` (already exists on `LocalFileBlueprint`) | `LocalFileBlueprint.swift` |
| Script file | Same as above | `LocalFileBlueprint.swift` |
| Blueprint name | `blueprintFinder.blueprintsAvailable` (already exists) | `BlueprintAggregator.swift` |
| Type name (model) | `ctx.model.types.allNames` | `AppModel.swift` |

**Example improved error:**

```
error[E102]: Property 'nme' not found on entity 'User'
  --> main.ss:42
   |
42 | render-file entity.nme
   |                    ^^^ not found
   |
   = available properties: name, email, age, role
   = did you mean: 'name'?
```

**Impact:** Transformative — this single change makes most errors self-diagnosing.

---

### 3.2 Show Expected vs Found on Every Error

**Problem:** Errors like `"modifier: 'camelCase' called on wrong type:Optional<Any>"` show the actual type but not the expected type. Errors like `"invalid property: * status = active"` don't explain the expected syntax.

**Action:** For every error case, add "expected" and "found" fields:

| Error | Current | Improved |
|---|---|---|
| `modifierCalledOnwrongType` | `"modifier: 'foo' called on wrong type:Array<Any>"` | `"Modifier 'foo' expects String, but received Array<Any>"` |
| `infixOperatorCalledOnwrongLhsType` | `"operator: '>' called on wrong LHS type:Optional<Any>"` | `"Operator '>' expects a comparable value on left side, but received Optional<Any> (nil)"` |
| `invalidPropertyLine` | `"invalid property: some text"` | `"Invalid property syntax. Expected: '* name Type' or '- name Type'. Found: 'some text'"` |
| `invalidMethodLine` | `"invalid method: some text"` | `"Invalid method syntax. Expected: '~ methodName(param: Type) : ReturnType'. Found: 'some text'"` |
| `invalidContainerLine` | `"invalid container: text"` | `"Invalid container syntax. Expected: '=== ContainerName ===' (3+ '=' on each side). Found: 'text'"` |
| `invalidAnnotationLine` | `"invalid annotation: text"` | `"Invalid annotation. Expected: '@annotationName' or '@annotationName :: value'. Found: 'text'"` |
| `blueprintDoesNotExist` | `"There is no blueprint called foo"` | `"Blueprint 'foo' not found in [paths]. Available: api-nestjs-monorepo, api-springboot-monorepo"` |

**For blueprint modifiers**, include the declared input type from front matter:

```swift
// Before:
throw TemplateSoup_ParsingError.modifierCalledOnwrongType(name, String(describing: type(of: value)), pInfo)

// After:
throw TemplateSoup_ParsingError.modifierCalledOnwrongType(
    name,
    "expected \(inputType.rawValue), got \(String(describing: type(of: value)))",
    pInfo
)
```

**Impact:** High — users immediately understand what to fix.

---

### 3.3 List Available Options on Lookup Failures

**Problem:** When a modifier, operator, function, or template is not found, the error doesn't list what IS available.

**Action:** Append available options to not-found errors:

```swift
// modifierNotFound — in Modifiers.swift:
let available = context.symbols.template.modifiers.names.sorted().joined(separator: ", ")
throw TemplateSoup_ParsingError.modifierNotFound(
    "\(str) (available: \(available))", pInfo
)

// templateFunctionNotFound — in FunctionCall.swift:
let available = await ctx.templateFunctions.keys.sorted().joined(separator: ", ")
throw TemplateSoup_ParsingError.templateFunctionNotFound(
    "\(FnName) (defined functions: \(available))", pInfo
)

// templateDoesNotExist — in TemplateSoup.swift:
let files = try? await blueprint.listFiles(inFolder: "")
let available = files?.joined(separator: ", ") ?? "unknown"
throw TemplateSoup_EvaluationError.templateDoesNotExist(
    "\(templateName) (available templates: \(available))", pInfo
)
```

**Impact:** High — eliminates the "what name was I supposed to use?" guessing game.

---

### 3.4 Structured Error Formatting (Rich Diagnostics)

**Problem:** `PipelineErrorPrinter` outputs flat strings. There's no visual code snippet, no caret pointing at the problem, no related notes.

**Action:** Create a `DiagnosticFormatter` that produces Rust/Elm-style output:

```
error[E204]: Variable 'seviceName' not found
  --> api-nestjs-monorepo/main.ss:47:15
   |
47 | set working_dir = seviceName
   |                   ^^^^^^^^^^ undefined variable
   |
   = did you mean: 'serviceName'?
   = variables in scope: container, module, entity, serviceName, port

note: 'serviceName' was set here:
  --> api-nestjs-monorepo/main.ss:31:5
   |
31 | set serviceName = module.name | camelCase
   |     ^^^^^^^^^^^
```

**Implementation:**
1. Define a `Diagnostic` struct with `severity`, `code`, `message`, `primaryLocation`, `secondaryLocations`, `notes`, `suggestions`.
2. `DiagnosticFormatter.format(_:sourceFiles:)` renders the snippet by reading source lines from `SourceFileMap`.
3. Replace `PipelineErrorPrinter`'s flat `print` calls with `DiagnosticFormatter`.
4. Also serialize `Diagnostic` objects into `DebugSession` for the browser console.

**Impact:** Very High — this is the difference between "what happened?" and "I see exactly what to fix."

---

### 3.5 Error Codes and Documentation Index

**Problem:** Errors have no stable identifiers. Users can't search for help or link to documentation.

**Action:**
1. Assign error codes (`E100`-`E199` for model parsing, `E200`-`E299` for template/script, `E300`-`E399` for evaluation, `E400`-`E499` for I/O and blueprints).
2. Create a `Docs/errors/` folder with one file per code (or a single index).
3. Print error codes in diagnostic output and link to docs.

**Impact:** Medium — enables searchable, documentable errors.

---

## 4. PART II — Eliminate Silent Failures

> **Goal:** No code path should swallow an error, return nil, or produce empty output without leaving a trace.

### 4.1 Replace try? with Precise Errors in Statement Execution

**Problem:** Five SoupyScript statement types use `try? ... as? String` with `return nil` on the `to`/`toFolder` path. When the expression fails, the entire statement is silently skipped.

**Affected files and lines:**
- `Sources/Scripting/SoupyScript/Stmts/RenderFile.swift` (70-71)
- `Sources/Scripting/SoupyScript/Stmts/CopyFile.swift` (72-73)
- `Sources/Scripting/SoupyScript/Stmts/RenderFolder.swift` (72-73)
- `Sources/Scripting/SoupyScript/Stmts/CopyFolder.swift` (72-73)
- `Sources/Scripting/SoupyScript/Stmts/FillAndCopyFile.swift` (75-76)

**Action:** Replace every `try?` + `return nil` with `try` + descriptive error:

```swift
// Before:
guard let toFile = try? await ctx.evaluate(value: ToFile, with: pInfo) as? String
    else { return nil }

// After:
let rawValue = try await ctx.evaluate(value: ToFile, with: pInfo)
guard let toFile = rawValue as? String else {
    let actualType = rawValue.map { String(describing: type(of: $0)) } ?? "nil"
    throw TemplateSoup_EvaluationError.errorInExpression(
        "Output path '\(ToFile)' expected String, got \(actualType)", pInfo
    )
}
```

**Impact:** Critical — this is the #1 source of mysterious missing files.

---

### 4.2 Make Condition nil → false Visible

**Problem:** `ExpressionEvaluator.evaluateCondition()` returns `false` when `evaluate()` returns `nil`. `:if myVarTypo` silently takes the else branch.

**File:** `Sources/Workspace/Evaluation/ExpressionEvaluator.swift` (63-68)

**Action:** Emit a diagnostic when a condition resolves to nil:

```swift
public func evaluateCondition(expression: String, pInfo: ParsedInfo) async throws -> Bool {
    if let result = try await evaluate(expression: expression, pInfo: pInfo) {
        return getEvaluatedBoolValueFor(result)
    } else {
        // Expression resolved to nil — likely a typo or undefined variable.
        await pInfo.ctx.debugLog.recordDiagnostic(
            .warning,
            "Condition '\(expression)' resolved to nil — treating as false. "
            + "If this is unexpected, check for typos in variable names.",
            pInfo: pInfo
        )
        return false
    }
}
```

In strict mode (opt-in flag), throw instead of warn.

**Impact:** Critical — this is the #2 source of "why is this block missing?"

---

### 4.3 Prevent Silent Variable Clearing

**Problem:** `SetVar` and `SetStr` silently clear variables when the RHS expression returns nil.

**Files:**
- `Sources/Scripting/SoupyScript/Stmts/SetVar.swift` (63-90)
- `Sources/Scripting/SoupyScript/Stmts/SetStrVarStmt.swift` (93-128)

**Action:** Emit a warning when an expression clears a previously-set variable:

```swift
if actualBody == nil {
    let hadValue = await ctx.variables.has(varName)
    if hadValue {
        await ctx.debugLog.recordDiagnostic(
            .warning,
            "Variable '\(varName)' cleared: expression '\(expression)' resolved to nil",
            pInfo: pInfo
        )
    }
}
```

**Impact:** High — silent variable clearing causes cascading wrong output.

---

### 4.4 Surface Constraint Parsing Errors

**Problem:** `ParserUtil.parseConstraints` uses `try?`, discarding `ConstraintParseError`.

**File:** `Sources/Modelling/_Base_/ParserUtil.swift` (~line 45)

**Action:** Replace `try?` with `try` and wrap the error with location:

```swift
do {
    constraints = try ConstraintParser.parseList(from: constraintStr)
} catch {
    throw Model_ParsingError.invalidPropertyLine(
        "Invalid constraint syntax '\(constraintStr)': \(error)", pInfo
    )
}
```

**Impact:** Medium.

---

### 4.5 Surface File I/O Failures in Template/Script Loading

**Problem:** `LocalFileTemplate.init?` and `GenericLineParser.init?(file:)` catch all errors and return `nil`. The underlying I/O error (permission denied, encoding error, etc.) is lost.

**Files:**
- `Sources/CodeGen/TemplateSoup/_Base_/Templates/LocalFileTemplate.swift`
- `Sources/Scripting/_Base_/Parsing/LineParser.swift`

**Action:** Convert to throwing factories or propagate the underlying error through the evaluation error that wraps them.

**Impact:** Medium — important when blueprint paths are misconfigured.

---

### 4.6 Fix PipelineErrorPrinter Mislabelling

**Problem:** `TemplateSoup_ParsingError`, `TemplateSoup_EvaluationError`, `ResourceReadingError`, and `ResourceDoesNotExist` all conform to `ErrorWithMessageAndParsedInfo` and hit the catch-all labelled "UNKNOWN ERROR."

**File:** `Sources/Pipelines/PipelineErrorPrinter.swift` (107-116)

**Action:** Add explicit branches for each concrete error type before the protocol catch-all:

```swift
} else if let err = err as? TemplateSoup_ParsingError {
    // "TEMPLATE SYNTAX ERROR" — with pInfo and info
} else if let err = err as? TemplateSoup_EvaluationError {
    // "TEMPLATE EVALUATION ERROR"
} else if let err = err as? ResourceReadingError {
    // "BLUEPRINT RESOURCE ERROR"
} else if let err = err as? ResourceDoesNotExist {
    // "BLUEPRINT RESOURCE NOT FOUND"
} else if let err = err as? ErrorWithMessageAndParsedInfo {
    // "UNHANDLED ERROR (\(type(of: err)))" — include type name
}
```

**Impact:** Medium — reduces confusion on template errors.

---

### 4.7 ObjectAttributeManager Silent Path Truncation

**Problem:** In `ObjectAttributeManager.getDynamicLookupValue`, when navigating `a.b.c`, if `b` resolves to a value that is NOT `DynamicMemberLookup`, the remaining path `.c` is silently dropped and `b`'s value is returned.

**File:** `Sources/Workspace/Context/ObjectAttributeManager.swift` (lines 67-71)

**Action:** When there are remaining path segments but the current value is not navigable, throw:

```swift
if afterDot.isNotEmpty {
    throw TemplateSoup_ParsingError.invalidPropertyNameUsedInCall(
        "Cannot access '\(afterDot)' on '\(beforeDot)' "
        + "(value is \(type(of: currentValue)), not an object with properties)", pInfo
    )
}
```

**Impact:** High — prevents wrong values from propagating silently.

---

### 4.8 TemplateRenderedFile Silent nil Contents

**Problem:** In `TemplateRenderedFile.render()`, if `renderTemplate` returns `nil`, `contents` stays at its initial value (empty) and the file is written with no content — no error is raised.

**File:** `Sources/_Common_/FileGen/FileTypes/TemplateRenderedFile.swift` (23-35)

**Action:** After rendering, if contents is still empty/nil and the template was supposed to produce output, emit a warning or throw.

**Impact:** Medium — prevents empty files from being silently written to disk.

---

## 5. PART III — Model Validation Phase

> **Goal:** Catch semantic errors at model-load time, not deep inside template rendering.

### 5.1 Add a Dedicated Validate Phase After Hydrate

**Problem:** The Transform phase is empty. There is no semantic validation between Hydrate and Render. Broken type references, missing mixins, duplicates, and API inconsistencies only surface (if at all) as cryptic template errors deep in the Render phase — or worse, as silently wrong output.

**Action:** Implement a `Validate` phase (using the existing but empty Transform phase slot, or as a new phase between Hydrate and Transform):

```swift
public enum Validate {
    static func models() -> PipelinePass { ValidateModelsPass() }
}

struct ValidateModelsPass: HydrationPass {
    func processAfterLoad(model: AppModel, with ctx: LoadContext) async throws {
        var diagnostics: [Diagnostic] = []
        diagnostics += await validateTypeReferences(model, ctx)
        diagnostics += await validateMixinReferences(model, ctx)
        diagnostics += await validateUnresolvedModules(model, ctx)
        diagnostics += await validateDuplicateNames(model, ctx)
        diagnostics += await validateApiPropertyConsistency(model, ctx)

        let errors = diagnostics.filter { $0.severity == .error }
        if errors.isNotEmpty {
            // Print all errors, not just the first
            for d in diagnostics { print(DiagnosticFormatter.format(d)) }
            throw PipelineValidationError(diagnostics: diagnostics)
        }
        // Warnings are recorded but don't stop the pipeline
        for d in diagnostics.filter({ $0.severity == .warning }) {
            await ctx.debugLog.recordDiagnostic(d)
        }
    }
}
```

Update `Pipelines.codegen`:

```swift
public static let codegen = Pipeline {
    Discover.models()
    Load.models()
    Hydrate.models()
    Hydrate.annotations()
    Validate.models()      // NEW
    Render.code()
    Persist.toOutputFolder()
}
```

**Impact:** Very High — catches entire classes of errors before rendering starts.

---

### 5.2 Unresolved Type References

**Problem:** In `AppModel.resolveAndLinkItems`, when a `customType` or `reference` target is not found, the raw string is kept with no error. A property typed as `UserProfiel` (typo) passes through silently.

**File:** `Sources/Workspace/Sandbox/AppModel.swift` (43-58, 117-132)

**Action:** In the Validate phase, scan all properties. For each `customType` or `reference` where the target name doesn't match any known type:

```
warning[W301]: Type 'UserProfiel' referenced by property 'profile' not found
  --> models/user.modelhike:15
   |
15 | * profile UserProfiel
   |          ^^^^^^^^^^^^ unknown type
   |
   = known types: User, UserProfile, Product, Order
   = did you mean: 'UserProfile'?
```

**Impact:** High — catches typos in type names before they cause confusing template failures.

---

### 5.3 Unresolved Mixin References

**Problem:** `ParserUtil.extractMixins` silently keeps attributes that don't match any type. An entity with `(AuditTrail)` where the correct name is `Audit` just retains `AuditTrail` as a regular attribute.

**File:** `Sources/Modelling/_Base_/ParserUtil.swift` (74-94)

**Action:** In the Validate phase, check for attributes that look like they might be intended as mixins (capitalized single-word attributes not matching known attribute patterns):

```
warning[W302]: Attribute '(AuditTrail)' on entity 'User' may be an unresolved mixin
  --> models/user.modelhike:8
   |
   = known types that could be mixins: Audit, Timestamp, SoftDelete
   = did you mean: 'Audit'?
```

**Impact:** Medium — prevents silent mixin failures.

---

### 5.4 Unresolved Container Module References

**Problem:** In `AppModel.resolveAndLinkItems`, `unresolvedMembers` that don't match any module are left in the list with no error.

**File:** `Sources/Workspace/Sandbox/AppModel.swift` (18-26)

**Action:** After resolution, validate that `unresolvedMembers` is empty:

```
error[E303]: Module 'UserMgmt' referenced in container 'APIs' not found
  --> models/system.modelhike:5
   |
5  | + UserMgmt
   |   ^^^^^^^^ unresolved module reference
   |
   = known modules: UserManagement, ProductCatalog, OrderService
   = did you mean: 'UserManagement'?
```

**Impact:** Medium.

---

### 5.5 Duplicate Name Detection

**Problem:** `ParsedTypesCache.append` doesn't check for duplicates. Two entities named `User` in different modules silently coexist, causing unpredictable behavior in template lookups.

**File:** `Sources/Workspace/Sandbox/ParsedTypesCache.swift` (61-67)

**Action:** In the Validate phase, check for:
- Duplicate type names (entity/DTO/UIView with same normalized name)
- Duplicate property names within a single entity
- Duplicate method names within a single entity

Emit warnings (not errors, since some duplicates across modules may be intentional).

**Impact:** Medium.

---

### 5.6 API-Property Consistency

**Problem:** `@list-api` annotation mappings store arbitrary `key -> value` strings that are never validated against actual entity properties. Default CRUD APIs don't verify that `id` exists for `getById`.

**Files:**
- `Sources/Modelling/_Base_/Annotation/AnnotationTypes/MappingAnnotation.swift`
- `Sources/Modelling/API/API+Extension.swift`

**Action:** In the Validate phase:
- For `getById`, verify the entity has an `id` or `_id` property
- For `@list-api` mappings, verify each key references an actual property
- For `listByCustomProperties`, verify referenced properties exist

**Impact:** Medium — catches broken API definitions early.

---

### 5.7 Blueprint Pre-Flight Check

**Problem:** There's no upfront validation that a blueprint is well-formed. Missing `main.ss` is only discovered at execution time. Missing templates referenced by `render-file` are discovered one at a time during rendering.

**Action:** Add a `ValidateBlueprintPass` that runs at the start of the Render phase:

1. Check `main.ss` exists
2. Parse `main.ss` and collect all `render-file` / `copy-file` references to template names
3. Verify those templates exist in the blueprint
4. Validate `_modifiers_/` front matter syntax
5. Check for `_root_/` folder existence

Report all issues at once:

```
error[E401]: Blueprint 'api-nestjs-monorepo' is missing entry point 'main.ss'
  = searched paths: /path/to/blueprints/api-nestjs-monorepo/

warning[W402]: Template 'sevice.module.teso' referenced in main.ss:42 not found
  = did you mean: 'service.module.teso'?
  = available templates: service.module.teso, service.controller.teso, ...
```

**Impact:** High — catches all blueprint issues before rendering starts.

---

## 6. PART IV — Warnings & Diagnostics System

> **Goal:** A dedicated channel for non-fatal issues, so the pipeline can continue while accumulating all problems.

### 6.1 Introduce a Diagnostics Channel

**Action:** Define structured diagnostics:

```swift
public enum DiagnosticSeverity: String, Codable, Sendable {
    case error, warning, info, hint
}

public struct Diagnostic: Codable, Sendable {
    public let code: String?                    // "E204", "W301"
    public let severity: DiagnosticSeverity
    public let message: String
    public let primarySource: SourceLocation
    public let relatedSources: [SourceLocation]  // "note: set here" pointers
    public let suggestions: [DiagnosticSuggestion]
}
```

Add a new `DebugEvent` case:

```swift
case diagnostic(Diagnostic)
```

Add `ContextDebugLog.recordDiagnostic(_:pInfo:)` as the primary emission point.

At pipeline completion, print a summary:

```
Generation complete. 47 files generated.
⚠ 3 warnings:
  [main.ss:42] W204: Condition 'entity.hasAudit' resolved to nil
  [main.ss:67] W205: Variable 'svcName' cleared by nil expression
  [service.teso:18] W301: Type 'UserProfiel' not found; did you mean 'UserProfile'?
```

**Impact:** Very High — the #1 structural improvement for the entire error experience.

---

### 6.2 Non-Fatal Continuation Mode

**Problem:** Most errors abort the pipeline immediately. When building a new blueprint, you fix one error, re-run, hit the next. This is slow.

**Action:** Add `PipelineConfig.continueOnError: Bool` (default `false`). When `true`:
- Template rendering errors for a single file are caught, recorded as diagnostics, and the file is skipped
- The pipeline continues to the next file
- At the end, all errors are printed together
- Exit code is still non-zero if any errors occurred

**Impact:** High — dramatically faster blueprint development iteration.

---

### 6.3 Wire captureError into Pipeline Catch Blocks

**Original problem:** `DebugRecorder.captureError()` existed but was not called.

**Action:** In `Pipeline.run`'s catch blocks, call `captureError` with the full call stack and variable dump before printing.

**Status:** Implemented in pipeline catch paths and surfaced in the debug session / Problems panel.

**Impact:** Medium — errors appear in the debug console.

---

### 6.4 Pipeline.run Should Return a Typed Result

**Problem:** `Pipeline.run()` is `async throws -> Bool` but catches errors and returns `false` instead of rethrowing. The `throws` annotation is misleading.

**Action:** Return a `PipelineResult`:

```swift
public struct PipelineResult: Sendable {
    public let success: Bool
    public let filesGenerated: Int
    public let diagnostics: [Diagnostic]
    public let duration: TimeInterval
}
```

**Impact:** Medium — enables proper programmatic error handling.

---

## 7. PART V — Debug Event Completeness

> **Goal:** Every meaningful action in the pipeline should leave a trace in the event timeline.

### 7.1 Emit All Defined DebugEvent Cases

| Event | Where to Emit | Effort |
|---|---|---|
| `modelLoaded` | `LoadModels` pass, after successful parse | Small |
| `scriptCompleted` | `ScriptFileExecutor`, after successful return | Small |
| `templateCompleted` | `TemplateEvaluator`, after successful return | Small |
| `parseBlockStarted` | `DebugUtils.parseLines(startingFrom:...)` | Small |
| `phaseStarted/Completed/Failed` | `Pipeline.run`, as `recordEvent` (not just `PhaseRecord`) | Small |
| `error(...)` | Pipeline catch blocks (see §6.3) | Small |

**Status:** Implemented for `modelLoaded`, `scriptCompleted`, `templateCompleted`, `phaseStarted`, `phaseCompleted`, `phaseFailed`, `consoleLog`, `announce`, `variableSet`, and `error`. `expressionEvaluated` and `parseBlockStarted` remain outstanding.

**Impact:** High — most major timeline blind spots are now filled.

---

### 7.2 Record Expression Evaluations

**Problem:** `{{ expression }}` evaluations are invisible in the timeline.

**Action:** In `PrintExpressionContent.execute`, after evaluation:

```swift
ctx.debugLog.recordEvent(.expressionEvaluated(
    expression: originalExpression,
    result: String(describing: evaluatedValue),
    source: sourceLocation(from: pInfo)
))
```

Gate behind `ContextDebugFlags.recordExpressions` (default `false`, enabled under `--debug`).

**Impact:** High — directly answers "what did this expression evaluate to?"

---

### 7.3 Record Variable Mutations with captureDelta

**Original problem:** `captureDelta` existed but was not wired, so variable time-travel was inaccurate.

**Action:** In `Context.setValueOf`, emit both the event and the delta:

```swift
let oldStr = await variables[key].map { String(describing: $0) }
// ... set value ...
debugLog.recordEvent(.variableSet(name: key, oldValue: oldStr, newValue: newStr, source: ...))
await recorder?.captureDelta(eventIndex: currentEventIndex, variable: key, oldValue: oldStr, newValue: newStr)
```

**Status:** Implemented. `captureBaseSnapshot(...)` is taken on snapshot push, and `captureDelta(...)` is recorded for variable mutations in `Context` and object-property mutations in `ObjectAttributeManager`. The debug console variables tab now reconstructs state from base + delta snapshots.

**Impact:** Medium — precise variable inspection at any timeline point.

---

### 7.4 Wire consoleLog and announce to Events

**Problem:** `ConsoleLog` and `AnnnounceStmt` only `print()`. Their output is invisible in the debug console.

**Files:**
- `Sources/Scripting/SoupyScript/Stmts/ConsoleLog.swift`
- `Sources/Scripting/SoupyScript/Stmts/AnnnounceStmt.swift`

**Action:** Add `recordEvent` calls alongside the existing `print`. One-liner each.

**Status:** Implemented.

**Impact:** Medium — blueprint authors' debug output appears in the visual debugger.

---

### 7.5 Fix Empty SourceLocations on Convenience Methods

**Problem:** ~15 methods in `ContextDebugLog` emit events with `SourceLocation(fileIdentifier: "", lineNo: 0, ...)`.

**File:** `Sources/Debug/DebugUtils.swift` (lines 212-308)

**Action:** Add `pInfo` parameters to every affected method and propagate actual source locations from callers.

**Status:** Partially implemented. Key file-generation and working-directory helpers now carry better source data, and Problems panel items can jump to the corresponding event/source. Some convenience events still legitimately use synthetic or empty locations where no concrete source line exists.

**Impact:** Medium — every timeline event becomes more navigable.

---

### 7.6 Wire setContainerName for Multi-Container

**Action:** In `CodeGenerationSandbox.generateFilesFor(container:)`, call `await recorder?.setContainerName(container.name)`.

**Status:** Implemented in `CodeGenerationSandbox.generateFilesFor(container:)`.

**Impact:** Low — future-proofing for multi-container runs.

---

### 7.7 Expose Call Stack in DebugSession

**Problem:** `CallStack` is printed by `PipelineErrorPrinter` but not serialized to the debug session.

**Action:** Include a `callStack: [SourceLocation]` field on `DebugEventEnvelope` for error and file-generation events. Serialize from `debugLog.stack.snapshot()`.

**Impact:** Medium — enables call stack display in the browser.

---

## 8. PART VI — Output-to-Template Traceability

> **Goal:** Click any line in generated output and see exactly which template line, model object, and script call produced it.

### 8.1 Per-Line Source Mapping

**Problem:** There's no line-level mapping from generated output back to template lines.

**Action:** During `TemplateEvaluator` execution, build a `SourceMap`:

```swift
public struct SourceMap: Codable, Sendable {
    public struct Mapping: Codable, Sendable {
        let outputLineRange: ClosedRange<Int>
        let templateIdentifier: String
        let templateLine: Int
        let expressionText: String?
    }
    let mappings: [Mapping]
}
```

As each `ContentLine.execute` appends to the output, record `(output line range, template pInfo)`. Attach to `GeneratedFileRecord`.

In the debug console, when the user clicks a line in the output editor, highlight the corresponding template line.

**Impact:** Very High — the killer debugging feature. Most code generators lack this.

---

### 8.2 "Why Was This File Generated?" Summary

**Action:** Create a `file-summary-panel.js` component that shows, for the selected file:

- **Template:** `.teso` file that rendered it (clickable)
- **Script line:** The `render-file` statement (with source link)
- **Model object:** The entity/DTO being iterated
- **Loop context:** `@loop` index and count
- **Working directory:** Output path context
- **Variables at generation:** Reconstructed from the base snapshot

Most data already exists in `GeneratedFileRecord` and `MemorySnapshot`.

**Impact:** High.

---

### 8.3 Register Model Files as Debug Sources

**Problem:** `.modelhike` files aren't registered in `SourceFileMap`, so the debug console can't show model source.

**Action:** In `LoadModels`, register each parsed model file:

```swift
await recorder?.registerSourceFile(SourceFile(
    identifier: fileIdentifier,
    content: fileContents,
    fullPath: filePath,
    fileType: .model  // add to SourceFileType enum
))
```

**Impact:** Medium.

---

### 8.4 Full Provenance Chain

**Vision (longer-term):** For any character in generated output, trace the full chain:

```
Output line 15: "export class UserService {"
  ← template: service.teso:3 → "export class {{ entity.name }}Service {"
    ← expression: {{ entity.name }} → "User"
      ← model: user.modelhike:12 → "User\n======"
        ← script: main.ss:42 → "render-file service.teso as {{ entity.name }}.service.ts"
          ← loop: main.ss:38 → "for entity in module.entities"
            ← iteration 3/7 (entity = User)
```

This requires combining source maps (§8.1), event timeline, and model registration (§8.3).

**Impact:** Transformative for complex debugging.

---

## 9. PART VII — Debug Console UI Overhaul

> **Goal:** A VS Code-grade debugging experience in the browser.

### 9.1 Problems Panel (VS Code-Style)

**Current state:** Errors show only as a banner in `debug-app.js` (lines 421-425).

**Action:** Create `problems-panel.js`:
- List all diagnostics from `session.errors` and `diagnostic` events
- Group by severity (errors first, then warnings)
- Each entry: severity icon, code, message, source location (clickable)
- Filter by severity, file, category
- Badge count in tab header
- Auto-focus if errors exist

**Impact:** Very High — the primary error discovery surface.

---

### 9.2 Event Search and Filtering

**Current state:** Implemented. The trace panel now supports search, event-type filtering, keyboard navigation, scroll-to-selection, and virtual scrolling for large sessions.

**Action:** Add to `trace-panel.js`:
- Text search across event labels and content
- Filter checkboxes by event type (control flow, file ops, expressions, variables, errors)
- Filter by severity
- Result count display
- Keyboard shortcut (Ctrl+F)

**Impact:** High — essential for large traces.

---

### 9.3 File Tree Error Indicators

**Current state:** File tree has no error/warning indicators.

**Action:** In `file-tree-panel.js`:
- Cross-reference `session.errors` and `diagnostic` events with file paths
- Show red dot on files with errors, yellow dot for warnings
- Show count badge on folders
- Sort errored files to top (optional)

**Impact:** Medium — instant visibility of which files have problems.

---

### 9.4 Keyboard Navigation and Shortcuts

**Current state:** Implemented for the main high-value interactions. The debug console now wires global shortcuts such as `F5`, `F10`, `F11`, `Shift+F11`, and panel shortcuts like `Ctrl+1-4`.

**Action:**
- File tree: Arrow keys, Enter to select
- Trace: Arrow keys to navigate events, Enter to select
- Global: `Ctrl+Shift+P` for command palette, `Escape` to close panels
- Stepper: `F5` Continue, `F10` Step Over, `F11` Step Into, `Shift+F11` Step Out
- Tab navigation between panels

**Impact:** Medium — essential for power users.

---

### 9.5 Variable Inspector Enhancements

**Current state:** Improved. The variables tab now supports search/filtering and toggling `@`-prefixed internal variables. Expand/collapse, comparison, and change highlighting remain future work.

**Action:**
- Search/filter variables by name
- Expand nested objects (render JSON tree for complex values)
- "Compare at index" — select two timeline points and see diff
- Toggle visibility of `@`-prefixed internal variables
- Highlight variables that changed since last snapshot

**Impact:** Medium.

---

### 9.6 Source Editor Enhancements

**Current state:** Plain text display, no syntax highlighting, no hover previews.

**Action:**
- Basic syntax highlighting for `.teso` and `.ss` files (keywords, expressions, strings)
- Hover preview for `{{ expression }}` showing the evaluated result (from `expressionEvaluated` events)
- Gutter breakpoint indicators (clickable, wired to WebSocket `addBreakpoint`)
- Line-level error indicators from diagnostics
- In-editor search (Ctrl+F)

**Impact:** High — makes the source editor useful for actual debugging.

---

### 9.7 Complete formatters.js Event Labels

**Current state:** `eventLabel` in `formatters.js` only handles ~8 event types. The other ~22 fall through to raw type names.

**Action:** Add formatted labels for all `DebugEvent` cases:

```javascript
case 'expressionEvaluated': return `{{ ${e.expression} }} → ${e.result}`;
case 'variableSet': return `${e.name} = ${e.newValue}`;
case 'diagnostic': return `${e.severity}: ${e.message}`;
case 'consoleLog': return `📝 ${e.value}`;
case 'fileExcluded': return `⊘ ${shortPath(e.path)}`;
case 'fileSkipped': return `⊘ ${shortPath(e.path)}: ${e.reason}`;
case 'fatalError': return `💥 ${e.message}`;
case 'parseBlockStarted': return `⟨${e.keyword}`;
case 'parseBlockEnded': return `${e.keyword}⟩`;
// ... etc for all cases
```

**Impact:** Medium — makes the trace panel actually readable.

---

### 9.8 Session Load Error Recovery

**Problem:** If `/api/session` fails, the UI stays on "Loading session data…" forever.

**File:** `DevTester/Assets/debug-console/components/debug-app.js` (197-199)

**Action:** Show an error state with retry button:

```javascript
} catch (e) {
    this.loadError = `Failed to load session: ${e.message}. Is the server running?`;
    this.loading = false;
}
```

Render a retry button and diagnostic information in the error state.

**Impact:** Small but prevents frustration.

---

### 9.9 Generation Diff View

**Action:** Store previous run's output. Add a `/api/diff` endpoint. Create `diff-panel.js` showing added/removed/modified files with inline diffs.

**Impact:** Medium — useful during iterative blueprint development.

---

### 9.10 Performance Timeline

**Action:** Add a `timeline-panel.js` showing:
- Phase durations (bar chart)
- Per-file generation time (calculated from event timestamps)
- Slowest templates
- Total event count per file

**Impact:** Low-Medium — useful for optimizing large blueprints.

---

### 9.11 Breakpoint UI

**Current state:** WebSocket protocol supports `addBreakpoint`/`removeBreakpoint` but the UI has no way to set them (only hardcoded in Swift).

**Action:**
- Clickable gutter in source editor to toggle breakpoints
- Breakpoint list panel (show all, enable/disable, delete)
- Wire to `sendAddBreakpoint`/`sendRemoveBreakpoint` (already defined in `api.js` but unused)

**Impact:** Medium — essential for live debugging.

---

### 9.12 Theme Support

**Current state:** Implemented. The debug console now has:

- a CSS design-token system shared through custom properties
- dark theme by default
- light theme via `<html data-theme="light">`
- a persisted theme toggle in `header-bar.js`
- `localStorage` persistence under `modelhike-debug-theme`

**Action:** Add light/dark toggle with CSS custom properties. Persist preference in localStorage.

**Status:** Implemented.

**Impact:** Low — quality of life.

---

## 10. PART VIII — Stepping & Live Debugging

### 10.1 Wire Global Keyboard Shortcuts

**Problem:** Stepper tooltips show F5/F10/F11 but keys aren't bound.

**Action:** In `debug-app.js`, add a `keydown` listener that dispatches to stepper actions.

**Impact:** Small — essential for usability.

---

### 10.2 Stack Frames on Pause

**Problem:** Pause message only includes single `location` + flat `vars`. No call stack.

**Action:** Extend the `paused` WebSocket message with `callStack: [SourceLocation]` from the stepper context.

**Impact:** Medium.

---

### 10.3 Evaluate Over WebSocket at Pause

**Action:** Add a `evaluate` WebSocket message type so expressions can be evaluated at the current pause point without HTTP round-trip.

**Impact:** Low.

---

### 10.4 Conditional Breakpoints

**Action:** Extend `BreakpointLocation` with an optional `condition: String?`. The stepper evaluates the condition and only pauses if true.

**Impact:** Medium — standard debugger feature.

---

### 10.5 WebSocket Error/Ack Messages

**Problem:** Invalid WebSocket commands are silently ignored.

**Action:** Send error/ack messages back:

```json
{"type": "error", "message": "Unknown command: foo", "originalType": "foo"}
{"type": "ack", "originalType": "resume", "success": true}
```

**Impact:** Low — protocol robustness.

---

## 11. Priority Matrix

This matrix is preserved for historical context, but it should now be read alongside the actual implementation status below.

### 11.1 Implementation Snapshot

| Status | Items |
|---|---|
| Implemented | 3.1, 3.2 (major paths), 3.3 (major lookup paths), 4.1, 4.2, 4.3, 4.7, 5.1, 5.2, 5.4, 5.5, 5.7, 6.1, 6.3, 7.1 (most items), 7.3, 7.4, 7.5 (partial), 7.6, 9.1, 9.2, 9.4, 9.5 (search/filter improvements), 9.7, 9.8, 9.12, 10.1 |
| Partially implemented | 6.2, 7.1 (`expressionEvaluated`, `parseBlockStarted` still open), 7.7, 9.6, 10.x stepping enhancements |
| Not yet implemented | 3.4 full rich-diagnostic formatter, 3.5 docs index, 5.3, 5.6, 6.4, 8.1, 8.2, 8.3, 8.4, 9.3, 9.9, 9.10, 9.11, 10.2, 10.3, 10.4, 10.5 |

### Tier 1 — Transformative (do first)

| # | Action | Effort | Category |
|---|--------|--------|----------|
| 3.1 | "Did you mean?" suggestions everywhere | Medium | Error Quality |
| 3.4 | Structured Diagnostic formatting (Rust-style) | Large | Error Quality |
| 4.1 | Replace `try?` silent failures in 5 statements | Small | Silent Failures |
| 4.2 | Make condition nil → false visible | Small | Silent Failures |
| 5.1 | Validate phase after Hydrate | Medium | Validation |
| 6.1 | Diagnostics channel (warning accumulation) | Medium | Infrastructure |
| 8.1 | Per-line output-to-template source mapping | Large | Traceability |
| 9.1 | Problems panel in debug console | Medium | Debug UI |

### Tier 2 — High Impact

| # | Action | Effort | Category |
|---|--------|--------|----------|
| 3.2 | Expected vs found on every error | Medium | Error Quality |
| 3.3 | List available options on lookup failures | Medium | Error Quality |
| 4.3 | Warn on silent variable clearing | Small | Silent Failures |
| 4.7 | Fix ObjectAttributeManager path truncation | Small | Silent Failures |
| 5.2 | Unresolved type reference validation | Medium | Validation |
| 5.7 | Blueprint pre-flight check | Medium | Validation |
| 6.2 | Non-fatal continuation mode | Medium | Infrastructure |
| 7.1 | Emit all defined DebugEvent cases | Small | Debug Events |
| 7.2 | Record expression evaluations | Small | Debug Events |
| 8.2 | "Why was this file generated?" panel | Medium | Debug UI |
| 9.2 | Event search and filtering | Medium | Debug UI |
| 9.6 | Source editor enhancements | Large | Debug UI |
| 9.7 | Complete event formatters | Small | Debug UI |

### Tier 3 — Important

| # | Action | Effort | Category |
|---|--------|--------|----------|
| 3.5 | Error codes and documentation index | Medium | Error Quality |
| 4.4 | Surface constraint parse errors | Small | Silent Failures |
| 4.5 | Surface file I/O failures | Medium | Silent Failures |
| 4.6 | Fix PipelineErrorPrinter mislabelling | Small | Silent Failures |
| 4.8 | TemplateRenderedFile silent nil contents | Small | Silent Failures |
| 5.3-5.6 | Remaining validation checks | Medium | Validation |
| 6.3 | Wire captureError | Small | Infrastructure |
| 6.4 | Typed PipelineResult | Medium | Infrastructure |
| 7.3-7.5 | Variable deltas, consoleLog, fix SourceLocations | Small | Debug Events |
| 7.7 | Call stack in DebugSession | Medium | Debug Events |
| 8.3 | Register model files as sources | Small | Traceability |
| 9.3-9.5 | File tree indicators, keyboard nav, variables | Medium | Debug UI |
| 9.8 | Session load error recovery | Small | Debug UI |
| 9.11 | Breakpoint UI | Medium | Debug UI |

### Tier 4 — Nice to Have

| # | Action | Effort | Category |
|---|--------|--------|----------|
| 7.6 | Wire setContainerName | Tiny | Debug Events |
| 8.4 | Full provenance chain | Very Large | Traceability |
| 9.9 | Generation diff view | Large | Debug UI |
| 9.10 | Performance timeline | Medium | Debug UI |
| 9.12 | Theme support | Small | Debug UI |
| 10.1-10.5 | Stepping enhancements | Medium | Live Debug |

---

## 12. Implementation Roadmap

The roadmap below is the original sequencing plan. Actual implementation landed non-linearly, with diagnostics, validation, event coverage, and debug-console UX improvements shipped first because they unlocked the biggest day-to-day developer experience gains.

### 12.1 What Was Actually Delivered

1. `Suggestions` utility and higher-quality messages across parser/evaluation failure paths
2. explicit non-silent file/folder statement failures, including filesystem-path type mismatch errors
3. warning diagnostics for nil conditions (`W201`) and variable clearing (`W202`)
4. `Validate.models()` semantic validation phase with `W301`, `W303`, `W304`, `W305`, `W306`
5. blueprint pre-flight diagnostic `E101`
6. structured diagnostics channel via `DebugEvent.diagnostic(...)`
7. pipeline `captureError(...)` wiring and richer error events
8. event coverage for phase lifecycle, model loaded, script/template completion, console logs, announces, and variable mutation
9. variable base snapshots + deltas for debugger time-travel
10. debug console Problems panel, `/api/diagnostics`, search/filtering, keyboard shortcuts, load recovery, and completed event formatter coverage
11. variable inspector search + system-variable toggle
12. theme token system, persisted light/dark toggle, and trace-panel virtual scrolling
13. Problems -> Trace/Source click-through, browser-verified against a real debug session

### Phase 1: "Errors That Explain Themselves" (2-3 weeks)

Focus: Make errors precise and eliminate silent failures.

1. Create `Suggestions` utility with Levenshtein distance (§3.1)
2. Replace all 5 `try?` patterns with throwing errors (§4.1)
3. Add nil-condition warnings (§4.2)
4. Add variable-clearing warnings (§4.3)
5. Improve error messages with expected/found and available options (§3.2, §3.3)
6. Fix PipelineErrorPrinter branches (§4.6)
7. Fix ObjectAttributeManager path truncation (§4.7)

**Deliverable:** Every error tells you what went wrong, where, and what to do instead.

### Phase 2: "Catch It Early" (2-3 weeks)

Focus: Model validation and diagnostics infrastructure.

1. Implement `Diagnostic` type and `DiagnosticFormatter` (§3.4, §6.1)
2. Implement Validate phase with type/mixin/duplicate/API checks (§5.1-5.6)
3. Blueprint pre-flight check (§5.7)
4. Wire captureError (§6.3)
5. Non-fatal continuation mode (§6.2)

**Deliverable:** Semantic errors caught at load time, not render time. Multiple errors reported per run.

### Phase 3: "See Everything" (2-3 weeks)

Focus: Complete the debug event timeline and traceability.

1. Emit all missing DebugEvent cases (§7.1)
2. Record expression evaluations (§7.2)
3. Record variable mutations + captureDelta (§7.3)
4. Wire consoleLog/announce (§7.4)
5. Fix empty SourceLocations (§7.5)
6. Implement output-to-template source mapping (§8.1)
7. Register model files as sources (§8.3)

**Deliverable:** Every action leaves a trace. Every output line traces to its template.

### Phase 4: "World-Class Debug Console" (3-4 weeks)

Focus: Browser UI overhaul.

1. Problems panel (§9.1)
2. Event search and filtering (§9.2)
3. Complete event formatters (§9.7)
4. File tree error indicators (§9.3)
5. "Why was this file generated?" panel (§8.2)
6. Source editor enhancements (§9.6)
7. Variable inspector enhancements (§9.5)
8. Keyboard navigation (§9.4)
9. Breakpoint UI (§9.11)
10. Session load error recovery (§9.8)

**Deliverable:** A debugging experience that makes the competition look primitive.

### Phase 5: "Polish" (ongoing)

- Error codes and documentation (§3.5)
- Generation diff view (§9.9)
- Performance timeline (§9.10)
- Full provenance chain (§8.4)
- Stepping enhancements (§10.x)
- Theme support (§9.12)
- Typed PipelineResult (§6.4)
