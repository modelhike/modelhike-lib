# Diagnostic Code Automation Plan

This document is a future-implementation handoff for removing manual diagnostic code strings (for example `"W201"`) from call sites and replacing them with typed, centralized diagnostics APIs.

## Why this work matters

Current state:
- Thrown errors now have a stable code registry via `ErrorCodeProviding` and `ErrorWithMessage.code` / `infoWithCode`.
- Non-throwing diagnostics still pass codes manually at call sites (`recordDiagnostic(..., code: "W201", ...)`).
- Suggestion payloads are already structured (`DiagnosticSuggestion`) and independent from code assignment.

Problems with current manual diagnostic codes:
- Typos are possible (`"W210"` vs `"W201"`).
- No compile-time safety.
- Code/message/severity can drift across call sites.
- Harder to refactor and harder for future agents to add diagnostics consistently.

Goal:
- Make diagnostic code emission type-safe and centralized, similar to thrown error code handling.
- Keep source-level readability high and avoid repetitive literal strings.

## Scope

In scope:
- Replace manual diagnostic code strings in runtime diagnostics (`recordDiagnostic` and `recordLookupDiagnostic` paths) with typed codes.
- Provide centralized message + severity templates for known diagnostics where appropriate.
- Preserve existing emitted payload shape (UI/API compatibility).
- Update docs and tests.

Out of scope:
- Reworking the full thrown-error code registry (`E2xx`, `E3xx`, etc.) unless needed for consistency.
- Large debugger UI redesign.

## Current architecture (important context)

### Existing code systems

- Thrown errors:
  - `Sources/Debug/ErrorCodes.swift`
  - `ErrorCodeProviding`, `ErrorCodes.code(for:)`, `ErrorWithMessage.code`, `ErrorWithMessage.infoWithCode`
- Diagnostic events:
  - `Sources/Debug/DebugEvent.swift`
  - `DebugEvent.diagnostic(severity:code:message:source:suggestions:)`
- Emission API:
  - `Sources/Debug/DebugUtils.swift`
  - `recordDiagnostic(...)`, `recordLookupDiagnostic(...)`
- UI/API consumption:
  - `DevTester/DebugServer/DebugRouter.swift` (`/api/diagnostics`)
  - `DevTester/Assets/debug-console/components/problems-panel.js`
  - `DevTester/Assets/debug-console/utils/formatters.js`

### Current manual diagnostic code call sites

At the time of writing:
- `E101` in `Sources/Pipelines/5. Render/GenerateCodePass.swift`
- `W201` in `Sources/Workspace/Evaluation/ExpressionEvaluator.swift`
- `W202` in:
  - `Sources/Scripting/SoupyScript/Stmts/SetVar.swift`
  - `Sources/Scripting/SoupyScript/Stmts/SetStr.swift`
- `W301`, `W303`, `W304`, `W305`, `W306` in:
  - `Sources/Pipelines/3.5. Validate/ValidateModels.swift`

These should be the first migration targets.

## Target design

Introduce a typed diagnostic catalog and use it everywhere diagnostics are emitted.

Recommended model:

1. Add `DiagnosticCode` enum
- Raw-value backed (`String`) for wire compatibility.
- Example cases:
  - `.E101`
  - `.W201`
  - `.W202`
  - `.W301`, `.W303`, `.W304`, `.W305`, `.W306`

2. Add metadata on `DiagnosticCode`
- `var severity: DiagnosticSeverity`
- Optionally `var defaultMessage: String` (or message builder helpers if interpolation is needed)

3. Add typed overloads in `ContextDebugLog`
- `recordDiagnostic(_ code: DiagnosticCode, _ message: String, source: ..., suggestions: ...)`
- `recordDiagnostic(_ code: DiagnosticCode, _ message: String, pInfo: ..., suggestions: ...)`
- `recordLookupDiagnostic(_ code: DiagnosticCode, _ message: String, lookup:..., in:..., ...)`
- These overloads should internally call existing string-based versions for compatibility.

4. Keep string overloads temporarily
- Mark as transitional via docs/comments.
- Optionally deprecate after migration:
  - `@available(*, deprecated, message: "Use DiagnosticCode overloads")`

5. Centralize higher-level helpers for recurring diagnostics (optional but recommended)
- Example:
  - `warnConditionResolvedNil(expression:..., pInfo:...)` for `W201`
  - `warnVariableCleared(name:..., expression:..., pInfo:...)` for `W202`
- Benefit: prevents message drift.

## Migration plan (step-by-step)

### Phase 1: Introduce typed foundation

1. Add `DiagnosticCode` (likely in `Sources/Debug/ErrorCodes.swift` or a nearby `Sources/Debug/DiagnosticCodes.swift`).
2. Add metadata properties:
   - severity mapping
   - optional category/family label if useful for docs
3. Add typed `ContextDebugLog` overloads.
4. Keep existing string code APIs functional.

Acceptance criteria:
- Build passes.
- No behavior change in emitted JSON except equivalent `code` value.

### Phase 2: Migrate call sites

1. Replace manual strings in:
   - `GenerateCodePass.swift`
   - `ExpressionEvaluator.swift`
   - `SetVar.swift`
   - `SetStr.swift`
   - `ValidateModels.swift`
2. Use typed enum values (`.W201`, etc.).
3. Where appropriate, switch to centralized message helper wrappers.

Acceptance criteria:
- No remaining literal `code: "W..."/"E..."` in diagnostic emission call sites.
- `rg` checks for direct manual code strings in diagnostics paths return none (except tests/docs).

### Phase 3: Tighten API and docs

1. Optionally deprecate string-based code overloads in debug log API.
2. Update `Docs/errorcodes.md` with:
   - typed mapping source
   - rule: new diagnostics must be added to `DiagnosticCode`.
3. Update this plan doc status section.

Acceptance criteria:
- Team guidance is explicit and discoverable.
- New diagnostics can be added safely by code completion.

### Phase 4: Test hardening

1. Update/extend tests in `Tests/Debug/EnrichedDX_Tests.swift`:
   - Assert typed code usage still serializes same raw values.
   - Add regression tests for each migrated code path.
2. Add a test that validates every `DiagnosticCode` case appears in docs or registry snapshot (if desired).
3. Run full test suite (`swift test`).

Acceptance criteria:
- Tests pass.
- Diagnostics JSON contract remains stable.

## Suggested implementation details

### Option A: Minimal typed wrapper (recommended first)

- Keep `DebugEvent` unchanged (`code: String?`).
- Convert enum to string only at emission boundary.
- Lowest risk, no JSON/API changes.

### Option B: Deep typing through `DebugEvent`

- Change `DebugEvent.diagnostic` from `code: String?` to `code: DiagnosticCode?`.
- Encode as raw value via `Codable`.
- Higher churn across API/UI and test fixtures; not required initially.

Recommendation:
- Start with Option A. Move to Option B only if there is strong value in stricter internal typing.

## Risks and pitfalls

- Severity mismatch:
  - If `DiagnosticCode.severity` conflicts with passed severity, behavior can drift.
  - Prefer deriving severity from code to avoid duplicates.
- Message drift:
  - If code and message are still free-form, semantics may diverge.
  - High-value codes should get helper emitters with canonical message text.
- Partial migration confusion:
  - Mixed typed + string call sites can persist.
  - Mitigate with temporary lint/search rule and migration checklist.
- Tests that assert exact text:
  - Refactors may cause small wording changes; keep tests focused on key semantics and code.

## Verification checklist

After implementation:

1. Build and test:
   - `swift test`
2. Search checks:
   - No direct `code: "W..."/"E..."` in production diagnostic emitters.
3. Runtime diagnostics:
   - `W201`, `W202`, and validation warnings still appear in Problems panel with expected codes.
4. Docs:
   - `Docs/errorcodes.md` updated if code catalog changes.

## Concrete TODO list for future AI agent

1. Create `DiagnosticCode` enum with current diagnostics (`E101`, `W201`, `W202`, `W301`, `W303`, `W304`, `W305`, `W306`).
2. Add severity mapping on `DiagnosticCode`.
3. Add typed overloads in `ContextDebugLog` for `recordDiagnostic` and `recordLookupDiagnostic`.
4. Migrate all manual diagnostic code call sites to typed enum.
5. Optionally add helper methods for high-frequency diagnostics (`W201`, `W202`).
6. Update tests in `Tests/Debug/EnrichedDX_Tests.swift`.
7. Run `swift test`.
8. Update `Docs/errorcodes.md` and mark this plan as completed.

## Definition of done

This work is done when:
- No production diagnostic path relies on hand-typed code string literals.
- Diagnostics remain wire-compatible and visible in the debug console.
- Full test suite passes.
- Docs clearly describe the typed workflow for adding new diagnostics.
