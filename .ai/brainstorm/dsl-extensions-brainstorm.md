# DSL Extensions — Implementation Specification

**Date:** 2026-03-26 · **Status:** Implementation-ready specification (v5)

---

## 0. Project Context

> **Read `AGENTS.md` for the full project analysis.** This section provides the minimum context needed to implement the features below.

### What ModelHike Is

ModelHike is a **code-generation toolchain** written in Swift 6. It parses plain-text, Markdown-flavoured `.modelhike` model files and generates production-grade source code via a template engine (TemplateSoup + SoupyScript) driven by blueprints.

### Repository Structure (relevant paths)

```
Sources/
├── _Common_/           # Shared utilities, file I/O, extensions
├── Modelling/          # DSL parser + in-memory domain model
│   ├── _Base_/
│   │   ├── CodeElement/
│   │   │   ├── Property.swift           # Property actor (fields, parsing)
│   │   │   ├── MethodObject.swift       # MethodObject + MethodParameter + ParameterMetadata
│   │   │   └── CodeLogic/
│   │   │       ├── CodeLogicParser.swift # Fenced logic block parser
│   │   │       ├── CodeLogicStmt.swift   # Statement node types (DB, HTTP, etc.)
│   │   │       └── CodeLogicStmtKind.swift # Statement kind enum
│   │   ├── AttachedSections/
│   │   ├── Annotation/
│   │   ├── C4Component/C4Component.swift
│   │   ├── C4Container/C4Container.swift
│   │   ├── RegEx/ModelRegEX.swift       # All DSL regex patterns
│   │   ├── ModelConstants.swift         # Prefix constants (*, -, =, ~, >>>, etc.)
│   │   ├── ModelSpace.swift
│   │   ├── ParserUtil.swift             # Shared parsing helpers
│   │   └── Artifact.swift               # ArtifactKind enum
│   ├── Container+Module/
│   │   ├── ContainerParser.swift
│   │   ├── ModuleParser.swift           # Module header parsing
│   │   └── SubModuleParser.swift
│   ├── Domain/
│   │   ├── DomainObject.swift           # DomainObject actor
│   │   ├── DomainObjectParser.swift     # Entity parsing loop
│   │   ├── DtoObject.swift
│   │   └── DtoObjectParser.swift
│   ├── API/
│   └── ModelFileParser.swift            # Top-level file parser (dispatches to sub-parsers)
├── Scripting/
│   └── Wrappers/                        # Script-accessible wrappers for template access
├── Workspace/
│   └── Sandbox/
│       ├── AppModel.swift
│       └── ParsedTypesCache.swift
└── Pipelines/
    ├── 3. Hydrate/HydrateModels.swift
    └── 3.5. Validate/ValidateModels.swift

Tests/
├── PropertyParser_Tests.swift
├── MethodParameterMetadata_Tests.swift
├── ExpressionParsing_Tests.swift
└── TemplateSoup_String_Tests.swift
```

### Key Architecture Patterns

- **Swift 6 strict concurrency** — all model objects are `actor`s. Properties and methods on actors are accessed with `await`.
- **`ParsedInfo`** (`pInfo`) — threaded through all parsing methods; carries line number, file identifier, parser reference, and context for error reporting.
- **`LineParser`** protocol — `currentLine()`, `skipLine()`, `lookAheadLine(by:)`, `linesRemaining`, etc. `GenericLineParser` is the concrete implementation.
- **Regex-based parsing** — `ModelRegEX.swift` uses Swift's `RegexBuilder` API. Patterns like `property_Capturing` return typed tuples.
- **`DynamicMemberLookup + HasAttributes`** — how template wrappers expose model object fields to SoupyScript.

### Existing DSL Prefix Reference

| Prefix | Constant | Meaning | Appears where |
|--------|----------|---------|---------------|
| `**` | `Member_PrimaryKey` | Primary key field | Property list in class |
| `*` | `Member_Mandatory` | Required field | Property list |
| `-` | `Member_Optional` | Optional field | Property list |
| `_` | `Member_Optional2` | Optional (alias) | Property list |
| `*?` | `Member_Conditional` | Conditionally required | Property list |
| `=` | `Member_Calculated` | Calculated/derived field | Property list |
| `.` | `Member_Derived_For_Dto` | DTO projected field | DTO property list |
| `~` | `Member_Method` | Method (tilde-prefix) | After properties in class |
| `>>>` | `Member_ParameterMetadata` | Parameter metadata line | Before method header |
| `+` | `Container_Member` | Module declaration | Container body |
| `#` | `AttachedSection` | API/section block start | Class/DTO/UIView body |
| `##` | `AttachedSubSection` | Custom API operation | Inside `# APIs ... #` |
| `@` | `Annotation_Start` | Annotation prefix | Own line, any scope |
| `//` | (not in constants) | Comment (stripped) | Anywhere |

### Existing Property Syntax

A property line has this structure (all parts after `name : Type` are optional):

```
<prefix> <name> : <Type>[<multiplicity>] [= <default>] [<validValueSet>] [{ constraints }] [(attributes)] [#tags]
```

Examples:
```modelhike
* id       : Id
* amount   : Float = 0 { min = 0, max = 100 } (backend) #financial
- status   : String = "NEW" <"NEW", "ACTIVE", "DONE">
* tags     : String[] <"vip">
```

**Regex:** `ModelRegEx.property_Capturing` (lines 278–320 of `ModelRegEX.swift`) captures a 9-element tuple: `(full, name, type, multiplicity?, default?, validValueSet?, constraints?, attributes?, tags?)`.

### Existing Method Syntax

Two styles:

**Tilde-prefix:** `~ methodName(param: Type, param2: Type) : ReturnType #tags`
**Setext:** `methodName(param: Type) : ReturnType` followed by `------` (6+ dashes)

Optional `>>>` metadata lines precede either style. Logic body optionally follows.

**Regex:** `ModelRegEx.method_Capturing` and `methodParamless_Capturing`.

### Existing `>>>` Parameter Metadata Parsing

`ParameterMetadata.parse(from:)` in `MethodObject.swift` (lines 294–335):
1. Strips `>>>` prefix.
2. Extracts marker as the first whitespace-delimited token (`*`, `**`, `-`, etc.).
3. Strips marker, leaving `name: Type [= default] [{ constraints }] [(attributes)] [#tags]`.
4. Matches against `ModelRegEx.property_Capturing`.
5. **Marker switch:** `*` or `**` → `required = .yes`; everything else → `required = .no`.
6. Checks tags for `#output` → sets `isOutput = true`.

### Existing Logic Block Statement Architecture

- `CodeLogicStmtKind` enum (in `CodeLogicStmtKind.swift`) — each case has a `rawValue` keyword string. `parse(_ keyword:)` does case-insensitive lookup.
- `CodeLogicStmt` (in `CodeLogicStmt.swift`) — a `Node` enum with associated-value cases. A large `switch kind` factory (lines 906–1038) maps `CodeLogicStmtKind` → `Node` case.
- **Block nodes** (DB, HTTP, etc.) are nested structs with `static siblingChildKinds: Set<CodeLogicStmtKind>` — tells the parser which same-depth keywords belong as children.
- `CodeLogicStmtKind.siblingChildKinds` (lines 126–137) bridges to the struct's set.
- `CodeLogicStmtKind.isBlock` (lines 141–163) — returns `true` for block openers.

### Parser Dispatch Order

In `DomainObjectParser.parse()` (the class body loop), elements are tried in this order:
1. Empty/comment → skip
2. **`>>>` line** → collect into pending metadata/description block; `continue` **(NEW)**
3. **`--` line** → attach as description to the preceding element **(NEW)**
4. `MethodObject.canParse` → parse method (attach pending `>>>` block: description + param metadata)
5. `pInfo.firstWord` humane comment → skip
6. **`=` prefix with `{` after `:`** → parse as named `Constraint`; attach pending `>>>` block description **(NEW)**
7. `Property.canParse` (includes `=` expressions) → parse property; attach pending `>>>` block description **(NEW)**
8. `tryParseAnnotations` → parse annotation
9. `tryParseAttachedSections` → parse attached section
10. Nothing matched → `break` (exit class body; discard pending `>>>` block if any)

In `ModelFileParser.parse()` (file-level), element dispatch order:
1. **`>>>` line** → collect into pending metadata/description block; `continue` **(NEW)**
2. **`--` line** → attach as description to the preceding element **(NEW)**
3. `ContainerParser.canParse` → container (attach pending `>>>` block description)
4. `ModuleParser.canParse` → module (attach pending `>>>` block description)
5. `SubModuleParser.canParse` → submodule
6. **`=` prefix with `{` after `:`** → parse as module-level named `Constraint` **(NEW)**
7. **`=` prefix** → parse as module-level expression (`Property`) **(NEW)**
8. **`MethodObject.canParse`** → parse as module-level function **(NEW)**
9. `DomainObjectParser.canParse` → class/entity (attach pending `>>>` block description)
10. `DtoObjectParser.canParse` → DTO
11. `UIViewParser.canParse` → UIView
12. `tryParseAnnotations` → annotation
13. Unrecognised → `skipLine()` (discard pending `>>>` block if any)

### Test Helper Patterns

**PropertyParser_Tests** (`Tests/PropertyParser_Tests.swift`):
```swift
func parseProperty(_ line: String, firstWord: String = "*") async throws -> Property {
    let ctx = LoadContext(config: PipelineConfig())
    let pInfo = ParsedInfo.dummy(line: line, identifier: "test", loadCtx: ctx)
    await pInfo.firstWord(firstWord)
    return try await Property.parse(pInfo: pInfo)!
}
```

**MethodParameterMetadata_Tests** (`Tests/MethodParameterMetadata_Tests.swift`):
```swift
func parseMethod(_ methodDSL: String, className: String = "TestClass") async throws -> MethodObject {
    // Wraps methodDSL in a minimal container+module+class DSL string,
    // runs ModelFileParser, finds the DomainObject, extracts the MethodObject.
}
```

---

## 1. Descriptions — `--` and `>>>` (bare lines)

### What

A universal way to attach human-readable descriptions to any DSL element. Currently comments (`//`) are stripped and discarded — there is no mechanism to carry descriptive text into the domain model or generated code.

Two mechanisms, both using existing syntax conventions:

| Prefix | Name | Position | Applies to |
|--------|------|----------|------------|
| `--` | Inline/after description | Same line (inline) or next line(s) after element | Any element |
| `>>>` (bare, no marker) | Before-block description | One or more `>>>` lines before the element | Any element (classes, modules, containers, methods) |

`--` inline is the **default recommended style** for short descriptions. `>>>` bare lines are used for longer prose before an element. For methods, `>>>` blocks can mix description lines and parameter metadata lines.

### `--` syntax (inline / after)

`--` can appear **inline** (same line, after the element) or on the **next line** (standalone `--` line immediately after the element):

```modelhike
* amount : Float              -- Total monetary amount before tax
```

```modelhike
* amount : Float
-- The total monetary amount for this order, before tax
```

**Inline is recommended.** Use the next-line form only when the description is too large for a single line. Next-line `--` lines can be stacked for multi-line descriptions:

```modelhike
* amount : Float
-- The total monetary amount for this order.
-- Includes base price and any surcharges.
-- Does not include tax (computed separately).
```

If both inline and next-line are present, concatenate (inline first).

### `>>>` bare lines — before-block description

`>>>` bare lines (without a parameter marker) placed **before** any element serve as its description. For methods, description lines and parameter metadata lines can be mixed in the same `>>>` block.

A `>>>` line is a **description line** if it does not start with a parameter marker (`*`, `**`, `-`, `_`, `*?`, `->`, `<->`). The parser strips the `>>>` prefix and collects the remainder as the description for the element that follows.

**Module:**

```modelhike
>>> Handles invoice generation, tax calculation, and payment processing.
>>> This module is the core of the billing subsystem.
=== Billing Module ===
```

**Class:**

```modelhike
>>> A billable document issued to a customer.
>>> Invoices are immutable once status reaches SENT.
Invoice
=======
```

**Method (description + parameter metadata in one block):**

```modelhike
>>> Looks up the invoice and computes the tax amount.
>>> Uses the module-level BASE_TAX_RATE expression.
>>> * orderId: Id                 -- The order to look up
~ calculateInvoiceTax(orderId: Id, -> taxAmount: Float) : Bool
```

For simple elements, `--` inline is sufficient:

```modelhike
~ calculateTotal() : Float -- Returns the net amount
- discount : Float = 0          -- Percentage discount
```

### Where descriptions can appear

| Element | `--` inline | `--` next-line | `>>>` block before |
|---------|-------------|----------------|-------------------|
| Property | Yes | Yes | No |
| Class/Entity | Yes (on name line) | Yes (after underline) | Yes |
| Method (tilde) | Yes | Yes | Yes (can include param metadata) |
| Method (setext) | No (name line followed by underline) | Yes (after underline) | Yes (can include param metadata) |
| `>>>` param metadata | Yes | Yes | No |
| Named constraint | Yes | Yes | No |
| Module expression | Yes | Yes | No |
| Module/container | Yes | Yes | Yes |
| API block | Yes | Yes | No |

### Examples

```modelhike
>>> Handles invoice generation, tax calculation, and payment processing.
=== Billing Module ===

>>> Primary domain object for customer orders.
>>> Tracks the full lifecycle from creation to delivery.
Order
=====
* id       : Id
* amount   : Float              -- Total monetary amount before tax
* currency : String
-- ISO 4217 currency code
- discount : Float = 0

~ calculateTotal() : Float -- Returns the net amount

>>> Processes payment for an order and updates its status.
>>> Returns true if the payment was successfully applied.
>>> * orderId: Id                             -- The order to process
processPayment(orderId: Id, -> taxAmount: Float) : Bool
--------------------------------------------------------
```

### Ambiguity checks

- **`--`** as a line prefix is new. `------` (6+ consecutive dashes) is a setext method underline, but that requires the **entire line** to be only `-` characters. `-- text` (with content after dashes) never matches that.
- **`>>>` bare lines before non-method elements** — `>>>` already exists as a prefix (`Member_ParameterMetadata`). Today it only appears before methods. Extending it to appear before classes/modules/containers is additive — the parser checks for `>>>` lines before dispatching to element parsers, and routes description lines vs param lines based on whether they have a marker.

### Implementation

#### 1. Add constant

**File:** `Sources/Modelling/_Base_/ModelConstants.swift`

```swift
public static let Member_Description = "--"
```

#### 2. Add `description` field to all model types

Add `public var description: String?` to:
- `Property` actor (`Sources/Modelling/_Base_/CodeElement/Property.swift`)
- `MethodObject` actor (`Sources/Modelling/_Base_/CodeElement/MethodObject.swift`)
- `ParameterMetadata` struct (same file)
- `DomainObject` actor (`Sources/Modelling/Domain/DomainObject.swift`)
- `DtoObject` actor (`Sources/Modelling/Domain/DtoObject.swift`)
- `UIView` actor (`Sources/Modelling/UI/UIView.swift`)
- `C4Component` actor (`Sources/Modelling/_Base_/C4Component/C4Component.swift`)
- `C4Container` actor (`Sources/Modelling/_Base_/C4Container/C4Container.swift`)
- `AttachedSection` actor
- `Constraint` struct (`Sources/Modelling/_Base_/CodeElement/Constraint.swift`) — add `description: String?` field for named constraints that have `--` descriptions

#### 3. Inline `--` parsing — modify regex or post-process

**File:** `Sources/Modelling/_Base_/RegEx/ModelRegEX.swift`

After the existing `tags` capture at the end of `property_Capturing`, add an optional `-- description` capture group. The `--` must appear after all existing syntax (tags, attributes, comments). Same for `method_Capturing`, `methodParamless_Capturing`, `containerName_Capturing`, `moduleName_Capturing`, `className_Capturing`.

Alternatively, parse inline `--` as a post-processing step: after the regex match, check if the original line contains ` -- ` and split. This avoids touching every regex.

#### 4. Next-line `--` parsing — consume `--` lines after any element

In every parser loop (`DomainObjectParser.parse`, `DtoObjectParser.parse`, `ModuleParser`, `ContainerParser`, `ModelFileParser`), after successfully parsing an element, check if the next line starts with `--` (but NOT `------`). If so, consume consecutive `--` lines and set the element's `description`.

**Pattern** (add as a shared helper):
```swift
// In ParserUtil or similar
static func consumeDescription(from parser: LineParser) async -> String? {
    var lines: [String] = []
    while await parser.linesRemaining {
        let line = await parser.currentLine().trim()
        // Must start with -- but not be all dashes (setext underline)
        guard line.hasPrefix(ModelConstants.Member_Description),
              !line.hasOnly("-") else { break }
        let text = String(line.dropFirst(ModelConstants.Member_Description.count)).trim()
        lines.append(text)
        await parser.skipLine()
    }
    return lines.isEmpty ? nil : lines.joined(separator: " ")
}
```

#### 5. `>>>` description blocks — bare `>>>` lines before any element

A `>>>` block before an element can contain both **description lines** (bare, no marker) and **parameter metadata lines** (with a marker). For non-method elements (classes, modules, containers), all `>>>` lines are description lines.

The parser collects `>>>` lines into a pending block. When the next non-`>>>` line is parsed as an element, the pending block is split:
- Lines without a parameter marker → concatenated into the element's `description`
- Lines with a parameter marker → parameter metadata (only meaningful for methods)

**Integration into parser loops:**

In `ModelFileParser.parse()` and `DomainObjectParser.parse()`, when the current line starts with `>>>`, consume consecutive `>>>` lines into a pending block. When the next element is parsed, attach description and metadata.

```swift
// Sketch for parser loop
var pendingMetadataBlock: [(line: String, isDescription: Bool)] = []

// ... inside the loop:
if currentLine.hasPrefix(ModelConstants.Member_ParameterMetadata) {
    while await parser.linesRemaining {
        let line = await parser.currentLine().trim()
        guard line.hasPrefix(ModelConstants.Member_ParameterMetadata) else { break }
        let remainder = line.remainingLine(after: ModelConstants.Member_ParameterMetadata).trim()
        let firstToken = remainder.firstWord() ?? ""

        let isMarker = [
            ModelConstants.Member_PrimaryKey,
            ModelConstants.Member_Mandatory,
            ModelConstants.Member_Optional,
            ModelConstants.Member_Optional2,
            ModelConstants.Member_Conditional,
            ModelConstants.Member_Output,
            ModelConstants.Member_InOut
        ].contains(where: { firstToken.hasPrefix($0) })

        pendingMetadataBlock.append((remainder, isDescription: !isMarker))
        await parser.skipLine()
    }
    continue
}

// Helper to extract description from pending block
func consumePendingDescription() -> String? {
    let descLines = pendingMetadataBlock.filter { $0.isDescription }.map { $0.line }
    let paramLines = pendingMetadataBlock.filter { !$0.isDescription }
    pendingMetadataBlock = []
    return descLines.isEmpty ? nil : descLines.joined(separator: " ")
}

// Attach to whichever element is parsed next:
if let container = try await ContainerParser.parse(...) {
    if let desc = consumePendingDescription() { await container.setDescription(desc) }
} else if let module = try await ModuleParser.parse(...) {
    if let desc = consumePendingDescription() { await module.setDescription(desc) }
} else if let entity = try await DomainObjectParser.parse(...) {
    if let desc = consumePendingDescription() { await entity.setDescription(desc) }
} else if let method = try await MethodObject.parse(...) {
    // Methods get both description and param metadata from the pending block
    if let desc = consumePendingDescription() { await method.setDescription(desc) }
    // Param metadata lines are forwarded to ParameterMetadata parsing
}
```

For methods, the existing `ParameterMetadata.parseMetadataBlockIfAny()` is extended to also return description lines. The description is set on the `MethodObject` after parsing.

#### 6. Template wrapper exposure

In `Scripting/Wrappers/` — expose `description` via `DynamicMemberLookup` on all wrapper types (`CodeObjectWrap`, `C4ContainerWrap`, `C4ComponentWrap`, etc.).

#### 7. Tests

**File:** `Tests/PropertyParser_Tests.swift` — add tests:
- Inline description: `"* amount : Float -- Total amount"` → property has description "Total amount"
- Next-line description: parse a class with property followed by `-- desc` line
- Multi-line description: two consecutive `-- ` lines concatenated
- No description: property without `--` → description is nil

**File:** `Tests/DescriptionParser_Tests.swift` (new) — add tests:
- `>>>` bare lines before class → class has description
- `>>>` bare lines before module → module has description
- `>>>` bare lines before container → container has description
- `>>>` bare lines before method with `>>> *` param → method has description + param metadata
- `>>>` block with only description lines (no params) before method → method description set, no param metadata
- `>>>` block before class + `--` after underline → both descriptions concatenated
- `--` inline on module header → module has description
- `>>>` block not followed by any element → no crash, block is discarded

---

## 2. Output Parameters — `->` / `<->`

### What

Replace the `#output` tag on `>>>` parameter metadata lines with dedicated directional arrow markers.

### Syntax

Two forms: **inline in the method signature** (recommended default) and **`>>>` metadata lines** (for complex cases).

#### Inline in the method signature (recommended)

Place `->` or `<->` before the parameter name, and include defaults, directly in the method signature. This is the **recommended default** — clean and keeps everything visible in one line:

```modelhike
~ transferFunds(customerId: Id, -> amount: Decimal = 0, <-> buffer: String) : Order
```

Defaults use the same `= value` syntax as properties. The signature captures direction, type, and default in one place.

#### `>>>` metadata form (complex cases only)

Use `>>>` lines only when a parameter needs constraints, valid value sets, or attributes — things that don't fit in a signature:

```modelhike
>>> -> amount: Decimal = 0 { min = 0, max = 1000000 } (source=calculated)
>>> <-> buffer: String = "" <"OK", "ERR"> #internal
~ transferFunds(customerId: Id, amount: Decimal, buffer: String) : Order
```

When a `>>>` line exists for a parameter, it takes precedence over the signature-line marker.

#### Marker reference

| Marker | Meaning | Sets on `ParameterMetadata` |
|--------|---------|---------------------------|
| `*` / `**` | Required input (existing) | `required = .yes` |
| `-` | Optional input (existing) | `required = .no` |
| `->` | **Output** (write-only) | `isOutput = true`, `required = .no` |
| `<->` | **Input/Output** (bidirectional) | `isOutput = true`, `required = .yes` |

`#output` tag is kept as a deprecated backward-compatible alias.

### Implementation

#### 1. Add constants

**File:** `Sources/Modelling/_Base_/ModelConstants.swift`

```swift
public static let Member_Output = "->"
public static let Member_InOut = "<->"
```

#### 2. Modify `ParameterMetadata.parse(from:)`

**File:** `Sources/Modelling/_Base_/CodeElement/MethodObject.swift`, lines ~294–335.

The current marker switch (lines 308–314):
```swift
let required: RequiredKind
switch marker {
case ModelConstants.Member_PrimaryKey, ModelConstants.Member_Mandatory:
    required = .yes
default:
    required = .no
}
```

**Change to:**
```swift
let required: RequiredKind
let isOutputMarker: Bool
switch marker {
case ModelConstants.Member_PrimaryKey, ModelConstants.Member_Mandatory:
    required = .yes
    isOutputMarker = false
case ModelConstants.Member_Output:
    required = .no
    isOutputMarker = true
case ModelConstants.Member_InOut:
    required = .yes
    isOutputMarker = true
default:
    required = .no
    isOutputMarker = false
}
```

Then at the `isOutput` computation (currently line 322):
```swift
// Before:
let isOutput = tags.contains(where: { $0.name == "output" })
// After:
let isOutput = isOutputMarker || tags.contains(where: { $0.name == "output" })
```

**Important:** The marker extraction (line 301) gets the first whitespace-delimited token. `->` and `<->` are single tokens, so this works as-is. However, verify that `<->` is not split at `<` — it should be fine since it's space-delimited, not character-delimited.

#### 3. Signature-line parsing (primary form)

`->` and `<->` appear directly in the method signature as a prefix on the parameter name. This is the **recommended default** for declaring output/inout parameters:

```modelhike
~ process(input: Id, -> output: Float, <-> buffer: String) : Bool
```

**Implementation:** In the method argument parser (uses `ModelRegEx.methodArgument_Capturing`), two changes are needed:

1. **Direction markers:** Before matching the parameter name, check if the token starts with `<->` or `->` (check `<->` first — longest prefix match). If so, strip the prefix, set the output/inout flag on the resulting `MethodParameter`, and parse the rest normally.

2. **Inline defaults:** After extracting `name: Type`, check for `= value` following the type. The existing `methodArgument_Capturing` regex captures `name: Type` pairs but does not capture `= default`. Extend the regex to optionally capture `= <value>` after the type, e.g. add `(?:\s*=\s*(.+?))?` before the `,` or `)` delimiter. Store the captured default on `MethodParameter.metadata.defaultValue`.

If a `>>>` line also exists for the same parameter, the `>>>` metadata takes precedence (it carries richer information like constraints and valid value sets).

#### 4. Tests

**File:** `Tests/MethodParameterMetadata_Tests.swift` — add tests:
- `>>> -> amount: Float` → `isOutput = true`, `required = .no`
- `>>> <-> buffer: String` → `isOutput = true`, `required = .yes`
- `>>> * amount: Float #output` → still works (backward compat)
- `>>> -> amount: Float { min = 0 } (source=calc)` → full decoration preserved
- `~ foo(a: Id, -> b: Float) : Bool` → `b` has `isOutput = true` (signature shorthand)
- `~ foo(a: Id, <-> b: String) : Bool` → `b` has `isOutput = true`, `required = .yes`

---

## 3. Module-Level Expressions, Functions, and Constraints

### What

Allow `=` (expressions), `~` (functions), and `= name : { condition }` (named constraints) at module level — outside any class. For cross-module sharing, place them in `common.modelhike`.

### 3a. Module-Level Expressions

Use the existing `=` (computed) prefix. Expressions can hold literals or computed values referencing other expressions.

Module-level expressions are **local to their module** by default. To make them visible to other modules, add the `(exported)` attribute. Expressions in `common.modelhike` are always available to all modules without needing this attribute.

```modelhike
=== Order Module ===

= MAX_RETRIES : Int = 5                             -- Literal value
= BASE_TAX_RATE : Float = 0.18 (exported)           -- Visible to other modules
= HIGH_TAX_RATE : Float = BASE_TAX_RATE * 1.5       -- Computed expression
= MAX_WITH_TAX : Float = MAX_AMOUNT * (1 + BASE_TAX_RATE)
```

#### Implementation

**Add `expressions` storage to `C4Component`:**

**File:** `Sources/Modelling/_Base_/C4Component/C4Component.swift`

```swift
public private(set) var expressions: [Property] = []

public func append(expression item: Property) {
    expressions.append(item)
}
```

**Modify `ModelFileParser.parse()`:**

**File:** `Sources/Modelling/ModelFileParser.swift` — in the main `lineParser.parse` closure.

Currently, after `UIViewParser.canParse` check and before the annotation fallback, add:

```swift
// Module-level expression: = name : Type = value
if pInfo.firstWord == ModelConstants.Member_Calculated {
    if let prop = try await Property.parse(pInfo: pInfo) {
        await self.component.append(expression: prop)
        // consume description if present
        return
    }
}
```

`Property.canParse` currently does **not** accept `=` as a first word (it only accepts `*`, `**`, `-`, `_`, `*?`). The expression check must be done explicitly in `ModelFileParser` by comparing `pInfo.firstWord == "="`, then calling `Property.parse(pInfo:)` directly (which will work since it uses the line remainder after the first word and matches with `property_Capturing`).

The same addition is needed in `DomainObjectParser.parse()` for class-level expressions — add it after the `Property.canParse` block and before annotations.

### 3b. Module-Level Functions

```modelhike
~ calculateTax(amount: Float, rate: Float) : Float
-- Computes tax for the given amount
```

#### Implementation

`MethodObject.canParse` already works at any parser level (it checks for `~` prefix or setext underline). In `ModelFileParser.parse()`, method parsing is already present for containers (see `ContainerParser.parse()` which calls `MethodObject.canParse` and appends to `C4Container.methods`).

**Extend `C4Component` with a `functions` list:**

**File:** `Sources/Modelling/_Base_/C4Component/C4Component.swift`

```swift
public private(set) var functions: [MethodObject] = []

public func append(function item: MethodObject) {
    functions.append(item)
}
```

**In `ModelFileParser.parse()`**, add method parsing at file/module level (before the class/DTO/UIView checks, or after the expression check):

```swift
if await MethodObject.canParse(parser: lineParser) {
    guard let methodPInfo = await lineParser.currentParsedInfo(level: 0) else {
        await lineParser.skipLine(); return
    }
    if let method = try await MethodObject.parse(pInfo: methodPInfo) {
        await self.component.append(function: method)
        return
    }
}
```

### 3c. Named Constraints — `= name : { condition }`

Named constraints follow the same `= name : value` pattern as computed properties, but with `{ condition }` in the type position:

```modelhike
= positiveAmount : { amount > 0 }
-- All monetary amounts must be positive
= validDiscount : { discount >= 0 and discount <= 100 }
-- Discount must be a percentage
```

Named constraints support **multi-line conditions** inside the braces for complex expressions:

```modelhike
= complexConstraint : {
    (amount > 0 and currency in SUPPORTED_CURRENCIES)
    and (status != "CANCELLED" or discount == 0)
}
-- Validates order state consistency
```

Lines inside the `{...}` braces are concatenated (whitespace-joined) into a single condition string.

**Disambiguation from computed properties:** After parsing name and `:`, if the next non-whitespace character is `{`, it's a named constraint; otherwise it's a computed property.

#### Module-level vs class-level named constraints

Named constraints can be defined at **two scopes**, each with a distinct use case:

| Scope | Use case | References | Reusable |
|-------|----------|------------|----------|
| **Module-level** | Reusable invariants applied to properties across multiple classes via `@name` | Module-level expressions and other module-level names | Yes — applied via `@name` on property lines |
| **Class-level** | Instance invariants that validate relationships between the class's own fields | The class's own properties + module-level expressions | No — scoped to the enclosing class |

**Module-level** — reusable, applied to specific properties via `@name`:


```modelhike
=== Order Module ===

= positiveAmount : { amount > 0 }          -- Reusable: any class can apply this
= validDiscount : { discount >= 0 and discount <= 100 }

Order
=====
* amount   : Float @positiveAmount          -- Applied here
- discount : Float @validDiscount           -- And here
```

**Class-level** — internal invariants that reference the class's own fields:

```modelhike
Order
=====
* id       : Id
* amount   : Float
- tax      : Float
- discount : Float

= totalLimit : { amount + tax <= MAX_INVOICE_AMOUNT }   -- Class invariant: validates cross-field state
= discountLimit : { discount <= amount }                 -- Class invariant: discount cannot exceed amount
```

Class-level named constraints can reference module-level expressions (like `MAX_INVOICE_AMOUNT`) alongside the class's own properties. They are not applied via `@name` — they implicitly apply to the enclosing class.

#### Named constraint with attributes and tags:

```modelhike
= positiveAmount : { amount > 0 } (severity=error) #financial
-- Amount must be positive
```

#### Implementation

**No new type needed.** `Constraint` (in `Sources/Modelling/_Base_/CodeElement/Constraint.swift`) already has `name: String?` and `isNamed: Bool`. A named constraint at module/class level is simply a `Constraint` with a non-nil `name`, parsed from a `ConstraintExpr` via the existing `ConstraintParser`. The `Constraints` actor already provides named lookup via `get(_ name:)` and `has(_ name:)`.

Add a `description: String?` field to `Constraint` so `--` descriptions on named constraints are preserved:

```swift
public struct Constraint: Equatable, Sendable {
    public let name: String?
    public let expr: ConstraintExpr
    public var description: String?     // NEW — for named constraints with -- descriptions

    public var isNamed: Bool { name != nil }

    public init(name: String? = nil, expr: ConstraintExpr, description: String? = nil) {
        self.name = name?.trim()
        self.expr = expr
        self.description = description
    }
}
```

The new `description` parameter defaults to `nil`, so all existing call sites remain unchanged.

**1. Add `namedConstraints` storage to `C4Component` and `DomainObject`:**

```swift
// C4Component.swift
public let namedConstraints = Constraints()

// DomainObject.swift
public let namedConstraints = Constraints()
```

**2. Add constraint parsing:**

When an `=` line is encountered (at module level in `ModelFileParser`, or inside a class in `DomainObjectParser`), after extracting the name and reaching the `:`, check if the type starts with `{`:

```swift
// Pseudocode for constraint vs expression disambiguation
let remainder = line.remainingLine(after: firstWord) // strip "="
// remainder: "positiveAmount : { amount > 0 } (severity=error) #tags -- desc"
if let colonIndex = remainder.firstIndex(of: ":") {
    let afterColon = remainder[remainder.index(after: colonIndex)...].trimmingCharacters(in: .whitespaces)
    if afterColon.hasPrefix("{") {
        // Extract name (before :), strip outer { }, parse condition via ConstraintParser.parseList()
        // Result: Constraint(name: name, expr: parsedExpr)
        // Then: await component.namedConstraints.add(constraint)
    } else {
        // Parse as computed Property (expression)
    }
}
```

For multi-line conditions (opening `{` with no closing `}` on the same line), consume subsequent lines until a line containing `}` is found, then concatenate all lines before parsing.

**3. Expose in template wrappers:**

**File:** `Sources/Scripting/Wrappers/C4ComponentWrap.swift` — add `namedConstraints`, `expressions`, `functions` to the dynamic member lookup.

### 3d. Applying Constraints and Expressions — `@name` on Property Lines

Once defined at module level (or in `common.modelhike`), named constraints and expressions can be referenced from property lines using `@name`:

```modelhike
= positiveAmount : { amount > 0 }
= DEFAULT_CURRENCY : String = "USD"

Order
=====
* amount   : Float @positiveAmount @maxAmount     // apply named constraints
* currency : String = @DEFAULT_CURRENCY            // default from expression
```

**`@name`** (no space after `@`, no `::`) is syntactically distinct from annotations (`@ keyword:: value` — always on its own line, space after `@`).

- After the type: `@name` applies a named constraint to the property.
- After `=`: `@name` references an expression as the default value.

#### Implementation

**1. Add field to `Property`:**

```swift
// Property.swift
public private(set) var appliedConstraints: [String] = []

public func appendAppliedConstraint(_ name: String) {
    appliedConstraints.append(name)
}
```

**2. Modify property regex or post-process:**

After the existing regex match, scan the original line for `@<identifier>` tokens that appear after the type/default/constraints/attributes/tags. Store them on `Property.appliedConstraints`.

For `= @NAME` in the default position, detect the `@` prefix in the default value and store it as an expression reference rather than a literal.

**3. Validation:**

In `ValidateModels.swift` (Phase 3.5), add a check: for each `@name` reference on a property, verify it resolves to a known named constraint or expression in the module or `commonModel`. Emit a W302 diagnostic if not found.

---

## 4. Messaging / Alert Blocks in Method Bodies

### What

Structured block keywords for sending notifications and publishing domain events inside method logic bodies — following the same `|> KEYWORD` / `|> CHILD` pattern as `DB` and `HTTP`.

### Two keyword families

- **`NOTIFY type recipient`** — direct messaging (email, SMS, push, alert, webhook)
- **`PUBLISH EventName [TO channel]`** — domain events to message bus, optionally targeting a named channel/topic

### `NOTIFY` examples

```modelhike
processOrder(order: Order) : void
-----------------------------------
|> NOTIFY EMAIL admin
| |> TO admin@example.com
| |> SUBJECT "Order Processed: " + order.id
| |> BODY
| |  "Order " + order.id + " has been processed successfully."
| |> PRIORITY high
---
```

```modelhike
flagFraud(transaction: Transaction) : void
--------------------------------------------
|> NOTIFY ALERT admin
| |> MESSAGE "Fraud detected on transaction " + transaction.id
| |> SEVERITY critical
| |> CHANNEL slack
---
```

```modelhike
shipOrder(order: Order) : void
--------------------------------
|> NOTIFY PUSH customer
| |> TITLE "Your order has shipped!"
| |> BODY
| |  "Order " + order.id + " is on its way."
| |> DATA
| |  orderId = order.id
| |  trackingUrl = order.trackingUrl
---
```

### `PUBLISH` examples

```modelhike
completeOrder(order: Order) : void
------------------------------------
|> PUBLISH OrderCompleted
| |> PAYLOAD
| |  orderId = order.id
| |  completedAt = now()
| |  amount = order.amount
---
```

With optional `TO` clause for a named channel/topic:

```modelhike
cancelOrder(order: Order, reason: String) : void
--------------------------------------------------
|> PUBLISH OrderCancelled TO order-events
| |> PAYLOAD
| |  orderId = order.id
| |  reason = reason
| |> METADATA
| |  source = "order-service"
---
```

If `TO` is omitted, the event is published to the default channel.

### Keyword reference

| Statement | Syntax | Kind | Description |
|-----------|--------|------|-------------|
| `notify` | `\|> NOTIFY type recipient` | Block | Notification block |
| `to` | `\|> TO value` or `\|> TO` + child lines | Leaf or Block | Recipient address(es) — inline for single value, block for multiple |
| `subject` | `\|> SUBJECT value` or `\|> SUBJECT` + child lines | Leaf or Block | Email/message subject — inline for simple, block for complex |
| `body` (reused) | `\|> BODY` | Block | Message body content |
| `message` | `\|> MESSAGE value` or `\|> MESSAGE` + child lines | Leaf or Block | Short-form message (alerts) — inline for simple |
| `title` | `\|> TITLE value` or `\|> TITLE` + child lines | Leaf or Block | Notification title (push) — inline for simple |
| `priority` | `\|> PRIORITY low\|normal\|high\|critical` | Leaf | Priority level |
| `severity` | `\|> SEVERITY info\|warning\|error\|critical` | Leaf | Alert severity |
| `channel` | `\|> CHANNEL name` | Leaf | Delivery channel hint |
| `data` | `\|> DATA` | Block | Key-value payload |
| `template` | `\|> TEMPLATE name` | Leaf | Named template ref |
| `publish` | `\|> PUBLISH EventName [TO channel]` | Block | Domain event (optional channel/topic) |
| `payload` (reused) | `\|> PAYLOAD` | Block | Event payload |
| `metadata` (reused) | `\|> METADATA` | Block | Event metadata |

### Notification types

| Type | Use case |
|------|----------|
| `EMAIL` | Email (SendGrid, SES, SMTP) |
| `SMS` | SMS (Twilio, SNS) |
| `PUSH` | Push notification (FCM, APNs) |
| `ALERT` | Admin alert (Slack, PagerDuty) |
| `WEBHOOK` | Outgoing webhook (HTTP POST) |

### Implementation

#### 1. Add cases to `CodeLogicStmtKind`

**File:** `Sources/Modelling/_Base_/CodeElement/CodeLogic/CodeLogicStmtKind.swift`

Add to the enum (after the `// MARK: HTTP / API` section):

```swift
// MARK: Notifications
case notify     = "notify"
case to         = "to"
case subject    = "subject"
case title      = "title"
case message    = "message"
case priority   = "priority"
case severity   = "severity"
case channel    = "channel"
case data       = "data"
case template   = "template"

// MARK: Domain events
case publish    = "publish"
```

Note: `body`, `payload`, `metadata` already exist from the HTTP/gRPC section.

#### 2. Add to `isBlock`

In the `isBlock` computed property's switch, add block cases:

```swift
case .notify, .data, .publish:
    return true
```

**Leaf-or-block keywords** (`to`, `subject`, `title`, `message`) can take an inline value (leaf: `|> TO admin@example.com`) or have child lines (block). These should **not** be in `isBlock` — they are leaf by default. The parser handles child lines normally when they appear at the expected depth. The inline value is part of the keyword's expression string (already captured by the expression extraction in `CodeLogicParser`).

Pure leaf cases (`priority`, `severity`, `channel`, `template`) also fall through to `default: return false`.

#### 3. Add node structs to `CodeLogicStmt`

**File:** `Sources/Modelling/_Base_/CodeElement/CodeLogic/CodeLogicStmt.swift`

Add `NotifyNode` and `PublishNode` following the same pattern as `HttpNode` / `DbQueryNode`:

```swift
public struct NotifyNode: Sendable {
    public let notificationType: String  // EMAIL, SMS, PUSH, ALERT, WEBHOOK
    public let recipient: String?
    public let children: [Node]

    static let siblingChildKinds: Set<CodeLogicStmtKind> = [
        .to, .subject, .body, .message, .title,
        .priority, .severity, .channel, .data, .template, .let
    ]

    static func parse(expression: String, children: [Node]) -> NotifyNode {
        let parts = expression.split(separator: " ", maxSplits: 1)
        return NotifyNode(
            notificationType: parts.first.map(String.init) ?? "",
            recipient: parts.count > 1 ? String(parts[1]) : nil,
            children: children
        )
    }
}

public struct PublishNode: Sendable {
    public let eventName: String
    public let channel: String?   // from optional TO clause
    public let children: [Node]

    static let siblingChildKinds: Set<CodeLogicStmtKind> = [
        .payload, .metadata, .let
    ]

    static func parse(expression: String, children: [Node]) -> PublishNode {
        // expression: "OrderCancelled TO order-events" or just "OrderCompleted"
        let parts = expression.split(separator: " ", maxSplits: 2).map(String.init)
        if parts.count >= 3 && parts[1].uppercased() == "TO" {
            return PublishNode(eventName: parts[0].trim(), channel: parts[2].trim(), children: children)
        }
        return PublishNode(eventName: expression.trim(), channel: nil, children: children)
    }
}
```

#### 4. Wire into `siblingChildKinds` and `Node.parse` factory

In `CodeLogicStmtKind.siblingChildKinds`:
```swift
case .notify:   return CodeLogicStmt.NotifyNode.siblingChildKinds
case .publish:  return CodeLogicStmt.PublishNode.siblingChildKinds
```

In `CodeLogicStmt.Node.parse(kind:expression:children:)`:
```swift
case .notify:   return .notify(NotifyNode.parse(expression: expression, children: children))
case .publish:  return .publish(PublishNode.parse(expression: expression, children: children))
```

Add the corresponding `Node` enum cases:
```swift
case notify(NotifyNode)
case publish(PublishNode)
```

#### 5. Tests

**File:** `Tests/CodeLogicParser_Tests.swift` (new or extend existing) — add tests:
- `|> NOTIFY EMAIL admin` with `|> TO`, `|> SUBJECT`, `|> BODY` children → `NotifyNode` with `notificationType = "EMAIL"`, `recipient = "admin"`, 3 children
- `|> NOTIFY PUSH customer` with `|> TITLE`, `|> BODY`, `|> DATA` children → `NotifyNode` with `notificationType = "PUSH"`, `recipient = "customer"`
- `|> TO admin@example.com` (inline value) → leaf node with expression `"admin@example.com"`
- `|> SUBJECT "Order " + order.id` (inline value) → leaf node with expression `"Order " + order.id`
- `|> PUBLISH OrderCompleted` with `|> PAYLOAD` child → `PublishNode` with `eventName = "OrderCompleted"`, `channel = nil`
- `|> PUBLISH OrderCancelled TO order-events` → `PublishNode` with `eventName = "OrderCancelled"`, `channel = "order-events"`
- Verify `body`, `payload`, `metadata` are correctly reused (already existing cases, context-dependent)

---

## 5. Summary Matrix

| Feature | Syntax | Files to modify | New types |
|---------|--------|----------------|-----------|
| **Descriptions (inline/after)** | `-- text` inline or next-line | `ModelConstants`, `Property`, `MethodObject`, `ParameterMetadata`, `DomainObject`, `DtoObject`, `UIView`, `C4Component`, `C4Container`, all parsers, all wrappers | None |
| **Descriptions (before)** | Bare `>>>` lines before any element | All parser loops (pending block logic), `ParameterMetadata.parseMetadataBlockIfAny` | None |
| **Output params (signature)** | `-> param` / `<-> param` in method signature (recommended) | Method argument parser, `ModelRegEx.methodArgument_Capturing` | None |
| **Output params (`>>>`)** | `->` / `<->` on `>>>` lines (complex cases only) | `ModelConstants`, `ParameterMetadata.parse()` in `MethodObject.swift` | None |
| **Module expressions** | `=` lines at module level | `C4Component`, `ModelFileParser`, `DomainObjectParser` | None |
| **Module functions** | `~` / setext at module level | `C4Component`, `ModelFileParser` | None |
| **Named constraints** | `= name : { condition }` | `C4Component`, `DomainObject`, `ModelFileParser`, `DomainObjectParser`, wrappers | None — reuses `Constraint` + `Constraints` |
| **Named constraint/expr refs** | `@name` inline on property | `Property`, property regex or post-processing, `ValidateModels` | None |
| **Notifications** | `\|> NOTIFY type recipient` | `CodeLogicStmtKind`, `CodeLogicStmt` (node + factory + isBlock + siblingChildKinds) | `NotifyNode` struct |
| **Domain events** | `\|> PUBLISH EventName [TO channel]` | Same as above | `PublishNode` struct |
| **Expression export** | `(exported)` attribute on `=` expressions | Attribute check during hydration/validation | None |

### Complete prefix family

| Prefix | Meaning | Domain |
|--------|---------|--------|
| `*` / `**` | must **have** / primary key | Data shape |
| `-` / `_` | may **have** | Data shape |
| `*?` | **conditionally** required | Data shape |
| `=` | is **computed** (expression) | Data shape |
| `.` | is **projected** (DTO) | Data shape |
| `~` | **does** something (method) | Behaviour |
| `= name : {...}` | must be **true** (named constraint) | Constraint |
| `@name` | **applies** a named constraint or references an expression | Reference |
| `--` | **describes** something (inline/after) | Documentation |
| `>>>` | **metadata** block + description (bare lines before any element) | Metadata / Documentation |
| `->` | flows **out** (output param) | Parameter direction |
| `<->` | flows **both ways** (inout param) | Parameter direction |

### Compatibility notes

- **No existing syntax breaks.** All changes are additive.
- **`--`** — `------` (6+ dashes, entire line) is a setext method underline. `-- text` is unambiguous.
- **`#output`** tag — kept as deprecated alias.
- **`->` / `<->`** — never appear at the start of a `>>>` line today.
- **Named constraints vs expressions** — parser checks character after `:` — `{` means named constraint, anything else means property.
- **`@name`** inline — distinct from annotations (`@ keyword::` on own line, space after `@`).
- **`BODY`/`PAYLOAD`/`METADATA`** — reused across HTTP, gRPC, NOTIFY, PUBLISH. Context (parent block) determines meaning. This is the existing pattern (`PARAMS` is reused in `DB-PROC-CALL` and `DB-RAW`).

---

## 6. Full End-to-End Example

This example uses **every** new feature together:

```modelhike
>>> The backend API layer for the billing platform.
===
Billing APIs
===
+ Billing Module


>>> Handles invoice generation, tax calculation, and payment processing.
>>> This module is the core of the billing subsystem.
=== Billing Module ===
@ roles:: admin, billing-ops

= BASE_TAX_RATE : Float = 0.18 (exported)           -- Standard tax rate, visible to other modules
= MAX_INVOICE_AMOUNT : Float = 1000000
= DEFAULT_CURRENCY : String = "USD"
= MAX_WITH_TAX : Float = MAX_INVOICE_AMOUNT * (1 + BASE_TAX_RATE)     -- Maximum amount including tax
= SUPPORTED_CURRENCIES : String[] = <"USD", "EUR", "GBP", "JPY">      -- ISO 4217 codes accepted by the system

= positiveAmount : { amount > 0 }                  -- All amounts must be positive
= validCurrency : { currency in SUPPORTED_CURRENCIES }     -- Currency must be in the supported set

>>> Computes tax for the given amount using the specified rate.
~ calculateTax(amount: Float, rate: Float = @BASE_TAX_RATE) : Float

~ formatCurrency(amount: Float, currency: String = @DEFAULT_CURRENCY) : String
-- Formats a monetary amount with the correct currency symbol

>>> A billable document issued to a customer.
>>> Invoices are immutable once status reaches SENT.
Invoice
=======
* id       : Id
* amount   : Float @positiveAmount                  -- Named constraint applied from module level
* currency : String = @DEFAULT_CURRENCY @validCurrency       -- Defaults to USD; must be in the supported set
- tax      : Float = @BASE_TAX_RATE                 -- Defaults to the base rate
- notes    : String

= totalLimit : { amount + tax <= MAX_INVOICE_AMOUNT }      -- Total including tax cannot exceed system limit

# APIs ["/invoices"] -- Invoice management endpoints
@ apis:: create, get-by-id, list, delete
## list by currency
#

>>> Looks up the invoice by ID and computes its tax amount.
>>> Uses the module-level BASE_TAX_RATE expression.
calculateInvoiceTax(invoiceId: Id, -> taxAmount: Float) : Bool
---------------------------------------------------------------
|> DB Invoices
| |> WHERE i -> i.id == invoiceId
| |> FIRST
| |> LET invoice = _
assign taxAmount = invoice.amount * BASE_TAX_RATE
|> NOTIFY EMAIL admin
| |> TO billing@example.com
| |> SUBJECT "Tax calculated for invoice " + invoice.id
| |> BODY
| |  "Invoice " + invoice.id + " tax: " + taxAmount
|> PUBLISH InvoiceTaxCalculated TO billing-events
| |> PAYLOAD
| |  invoiceId = invoice.id
| |  taxAmount = taxAmount
return true
---
```

---

## 7. Resolved Design Decisions

1. **Description placement:** `--` (inline or next-line) for short descriptions on any element. Bare `>>>` lines (no marker) before any element for longer prose descriptions. For methods, `>>>` blocks can mix description lines and parameter metadata. No separate `>` prefix — `>>>` already covers this.
2. **Output params and defaults — inline is the default:** `->` / `<->` and `= value` defaults go directly in the method signature: `~ process(input: Id, -> output: Float = 0, <-> buffer: String) : Bool`. Use `>>>` lines only when a parameter needs constraints `{ min = 0 }`, valid value sets `<"A", "B">`, or attributes `(backend)`.
3. **Multi-line constraint conditions:** Yes — named constraints support multi-line conditions inside `{...}` braces. Lines inside the braces are concatenated.
4. **`PUBLISH` with `TO` clause:** Yes — `|> PUBLISH EventName TO channel-name` is supported. The `TO` part is optional; if omitted, the event is published to the default channel.
5. **Expression export visibility:** Module-level expressions are local to their module by default. To make them visible to other modules, use the `(exported)` attribute: `= BASE_TAX_RATE : Float = 0.18 (exported)`. Expressions in `common.modelhike` are always available to all modules without needing this attribute.
6. **Constraint severity:** Severity is an attribute, not a dedicated syntax element: `= positiveAmount : { amount > 0 } (severity=error)`.
7. **NOTIFY keywords inline values:** `TO`, `SUBJECT`, `TITLE`, and `MESSAGE` can take their value inline on the same line (`|> TO admin@example.com`) or as child lines. They are "leaf or block" depending on context.
8. **`>>>` before any element:** Bare `>>>` lines (without a parameter marker) work as before-block descriptions for any element — not just methods. For non-methods (classes, modules, containers), all `>>>` lines are descriptions. For methods, description lines and parameter metadata lines can coexist in the same block.
