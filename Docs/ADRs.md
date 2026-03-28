# Architecture Decision Records

This file tracks key architectural decisions made during ModelHike's development.

---

## ADR-001: Actor-based concurrency model

**Date:** 2024

**Context:** ModelHike needs to be safe under Swift 6 strict concurrency. All mutable model objects (containers, components, domain objects, properties, etc.) and shared state (contexts, sandboxes, template engine) require thread-safe access.

**Decision:** Use Swift `actor` for all mutable model objects and shared state. Enforce `Sendable` conformance throughout. Use `nonisolated(unsafe)` sparingly (only for static regex patterns).

**Consequences:** Full Swift 6 strict concurrency compliance. All public APIs are `async`. The codebase is safe from data races by construction.

---

## ADR-002: Zero external dependencies for the core library

**Date:** 2024

**Context:** Code generation libraries are foundational infrastructure. External dependencies increase supply-chain risk and version management burden.

**Decision:** The `ModelHike` library target has zero external Swift package dependencies. All parsing, template rendering, expression evaluation, and scripting is implemented in-house. Only the `DevTester` executable (development tooling) uses SwiftNIO.

**Consequences:** No dependency conflicts for consumers. Minimal attack surface. Full control over behaviour. Trade-off: more code to maintain internally.

---

## ADR-003: Markdown-flavoured DSL over structured formats

**Date:** 2024

**Context:** The input format for software models needs to be human-readable, version-control friendly, and approachable for developers who aren't modelling experts.

**Decision:** Design a Markdown-flavoured DSL (`.modelhike` files) using heading-like fences (`===`), underlined names, and prefix characters (`*`, `-`, `~`, `@`, `#`) rather than XML, JSON, YAML, or a graphical format.

**Consequences:** Models are readable as plain text. Git diffs are meaningful. The learning curve is low for anyone comfortable with Markdown. Trade-off: custom parser required (no off-the-shelf Markdown library handles the extensions).

---

*Add new ADRs above this line.*
