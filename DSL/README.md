# ModelHike DSL Documentation Index

## Declare Your Entire App. Application code is a build artifact, not a human artifact.

---

## The DSL Family

ModelHike is not one DSL. It is a family of ten visual syntaxes, each purpose-built for a category of application logic, unified by shared conventions (`|` scoping, `{ }` constraints, `[ ]` attributes, `@ annotations`, `-- descriptions`, `#tags`).

Each has a distinct underline that tells you what kind of thing you're looking at before reading a single word.

```
=====       Entity / Class          Data: fields, types, constraints, indexes
/===/       DTO                     Projection: field selection from parent types
/;;;;;/     UIView                  Surface: controls, bindings, actions, layout
>>>>>>      Flow (Lifecycle + Wf)   Movement: states, transitions, orchestration
??????      Rules / Decisions       Evaluation: conditions, tables, trees, scoring
/#####/     Printable               Output: merge fields, sections, tables, formatting
::::::::    Config Object           Settings: calendars, sequences, currency, UoM
~~~~~~      Agent / AI              Intelligence: prompts, tools, knowledge, guardrails
++++++      Infra Node              Infrastructure: databases, caches, brokers
------      Method                  Behavior: imperative logic (escape hatch)
```

### How they compose

```
Entity  ──defines──>  DTO  ──projects──>  UI View
  │                                          │
  │         # Import / # Export              │ binds to
  │         # Cache / # Search               │
  │         # Media / # Fixtures             v
  │         # Analytics / # Rate Limit
  │
  ├──governs──>  Flow/Lifecycle (states, transitions, entry/exit)
  │                   │
  │                   │ triggers via entry / run
  │                   v
  ├──orchestrates──>  Flow/Workflow (arrows, wait, parallel)
  │                        │
  │                        │ evaluates via decide
  │                        v
  ├──evaluates──>  Rules (tables, trees, scoring, constraints)
  │
  ├──generates──>  Printables (merge fields, sections, tables)
  │
  ├──configured by──>  Config Objects (calendars, sequences, currency, UoM)
  │
  ├──annotated with──>  Cross-cutting (# Hierarchy, # Versioned, # Audit, # Error Policy)
  │
  ├──scheduled by──>  Jobs (# Jobs on module: trigger, concurrency, delegation)
  │
  └──augmented by──>  Agents (AI layer)
                        ├── Agents / Sub-agents / AI Workflows / AI Automations
                        ├── Skills (SKILL.md) / MCP Servers / Slash Commands
                        └── Knowledge Sources / Guardrails
```

In one breath:

- **Entities** declare the truth. DTOs project it. Views render it. Printables print it.
- **`# Import` / `# Export`** sections on entities declare bulk data operations.
- **Lifecycles** govern how entities change state. Transitions fire entry actions.
- **Workflows** orchestrate multi-step processes across participants and services.
- **Rules** evaluate decisions: pricing, eligibility, risk, allocation, routing.
- **Printables** generate documents: invoices, reports, packing slips, contracts.
- **Config objects** declare system-wide settings: calendars, sequences, currency, UoM conversions.
- **Attached sections** (`# Hierarchy`, `# Versioned`, `# Cache`, `# Search`, `# Media`, etc.) add cross-cutting behaviors to entities.
- **Jobs** schedule recurring or event-driven work, delegating to flows/rules/agents.
- **Agents** add the AI layer — invoked from flows, or driving processes themselves.
- **UI actions** call services, trigger flows, and invoke decisions.
- **Codelogic methods** are the imperative escape hatch for the ~2-3% that's genuinely algorithmic.

The two layers compose bidirectionally:
- **AI calls Deterministic:** `run @"Flow"`, `decide @"Rules"`, `call service.method()`
- **Deterministic calls AI:** `invoke @"Agent"` from within a flow step

Everything connects. Nothing duplicates. One source of truth, ten ways to declare it.


## The Three-Layer Model

```
Entity (=====)        -- truth: all fields, constraints, types
  |
DTO (/===/)           -- shape: which fields the API exposes
  |
UI View (/;;;;;/)     -- surface: how fields render as controls
```

Each layer adds information without duplicating. The entity declares `* status : String <"DRAFT","SUBMITTED","APPROVED">`. The DTO says `. status` to project it. The view says `. status : Dropdown`. The blueprint connects the dots: dropdown options from the valid value set, validation from constraints. Zero wiring code.

---

## Documentation Map

### Core DSL (existing, documented in modelHike.dsl.md)

| Guide | Covers | Categories |
|-------|--------|------------|
| [modelHike.dsl.md](modelHike.dsl.md) | Systems, containers, modules, classes, DTOs, UIViews, properties, types, constraints, attributes, annotations, tags, comments, APIs | 1, 2, 3, 5, 6, 7, 15, 17, 18, 23, 28 |
| [codelogic.dsl.md](codelogic.dsl.md) | Method bodies: if/else, for, while, try/catch, DB operations, HTTP calls, pipelines, transactions, notifications, events | Imperative escape hatch |

### Extended DSL (new, one guide per family)

| Guide | Underline | Covers | Categories |
|-------|-----------|--------|------------|
| [flow.dsl.md](flow.dsl.md) | `>>>>>>` | Unified lifecycle + workflow: states, transitions, orchestration, participants, arrows, wait, parallel, timed transitions, composite states, history | 8, 9, 16 |
| [rules.dsl.md](rules.dsl.md) | `??????` | Business rules: conditional rules, decision tables, decision trees, scoring, matching, formulas, constraints, composition | 29 |
| [uiview.dsl.md](uiview.dsl.md) | `/;;;;;/` | UI: pages, views, controls, bindings, sections, actions, navigation, conditional visibility, composite views | 4 |
| [printable.dsl.md](printable.dsl.md) | `/#####/` | Printables: merge fields, conditional sections, repeating tables, headers/footers, page breaks, multi-format output | 30 |
| [config.dsl.md](config.dsl.md) | `::::::::` | Config objects: calendars, fiscal periods, number sequences, currency, unit of measure | 32, 34, 35 |
| [hierarchy.dsl.md](hierarchy.dsl.md) | `# Hierarchy` | Hierarchical data: BOM explosion, org charts, chart of accounts, category trees, rollup, ancestors, descendants | 33 |
| [attached-sections.dsl.md](attached-sections.dsl.md) | `# Section` | All attached sections on entities: APIs, Import, Export, Cache, Rate Limit, Search, Media, Jobs, Fixtures, Analytics, Error Policy | 7, 10, 12, 19, 20, 22, 24, 25, 26, 27, 31 |
| [agent.dsl.md](agent.dsl.md) | `~~~~~~` | AI agents, sub-agents, AI workflows, AI automations, skills (SKILL.md), MCP servers, slash commands, knowledge sources, guardrails | AI layer |

### Reference

| Guide | Purpose |
|-------|---------|
| [detailed-examples.md](detailed-examples.md) | Master showcase: all 36 categories side-by-side in real ModelHike syntax, with imperative-LOC vs ModelHike-LOC ratios. Complementary to the per-DSL guides above. |

---

## When to Use Which DSL

### "I need to model data"
Use **Entity** (`=====`). Define fields, types, constraints, relationships. Add `# APIs` for endpoints, `# Import`/`# Export` for bulk operations.

### "I need to show a subset of fields"
Use **DTO** (`/===/`). Project fields from parent entities with `.` prefix.

### "I need a user interface"
Use **UIView** (`/;;;;;/`). Bind to entities, declare controls, group into sections, handle events. Compose views into pages.

### "I need states and transitions"
Use **Flow** (`>>>>>>`), lifecycle mode. Declare states with `entry /` actions. Declare transitions with `\__` and guards/roles/api. Add timed transitions, composite states, parallel regions as needed.

### "I need to orchestrate multi-step processes"
Use **Flow** (`>>>>>>`), workflow mode. Declare participants with `[Name] as type`. Use `-->` for sync calls, `~~>` for async. Use `wait` for human tasks with SLAs. Use `--- Name --- / ---` for parallel.

### "I need both states AND orchestration"
Use **Flow** (`>>>>>>`), unified mode. Declare states AND participants in one block. State transitions (`\__`) and orchestration arrows (`-->`) coexist. The Loan Application example in category 8 shows this.

### "I need pricing / eligibility / risk scoring / routing logic"
Use **Rules** (`??????`). Choose the right rule type:
- Flat conditions with priority -> **Conditional rules** (when/then)
- Multiple input columns -> **Decision table** (rows with `||` separator)
- Hierarchical branching -> **Decision tree** (visual `├──[` tree)
- Weighted criteria -> **Scoring rules** (score + points + classify)
- Multi-criteria matching -> **Matching rules** (filter + rank + limit)
- Named calculations -> **Formula rules** (intermediates + final expression)
- Cross-entity validation -> **Constraint rules** (constraint + reject)
- Chaining decisions -> **Composition** (decide @"Name" chaining)

### "I need to generate documents"
Use **Printable** (`/#####/`). Declare merge fields, conditional sections, repeating tables, headers/footers. Output as PDF, HTML, or email.

### "I need system-wide settings"
Use **Config** (`::::::::`). Declare calendars, fiscal periods, number sequences, currency rates, unit of measure conversions. Reference from entities via `@"Config Name"`.

### "I need tree operations on hierarchical data"
Use **Hierarchy** (`# Hierarchy`). Attach to self-referential entities. Declare operations: ancestors, descendants, explode (with quantity multiplication), rollup (aggregation), breadcrumb (path), move (reparent).

### "I need imperative escape-hatch logic"
Use **Method** (`------`). Codelogic body with `|> IF`, `|> FOR`, `|> DB`, `|> HTTP`. This is the 2-3% that's genuinely algorithmic.

### "I need AI to drive a process"
Use **Agent** (`~~~~~~`). Choose the right element:
- Conversational interface -> **Agent** (main agent with system prompt, tools, knowledge)
- Specialized reasoning in isolation -> **Sub-agent** (invoked by parent, own context window)
- Multi-step prompt-driven process -> **AI Workflow** (steps are prompts, not code)
- Event-triggered AI response -> **AI Automation** (like a job, but prompt-driven)
- Packaged AI capability -> **Skill** (SKILL.md standard)
- External tool provider -> **MCP Server** (connects to external services)
- User-facing commands -> **Slash Commands** (routes to agents/workflows/actions)
- Context for AI -> **Knowledge Source** (RAG: documents, code, vector stores)
- Safety constraints -> **Guardrails** (prohibitions, requirements, limits, escalation triggers)

### "Should this step be deterministic or AI?"
If same input must always produce same output -> **Deterministic** (`>>>>>>` flow, `??????` rules).
If the step requires judgment, creativity, or natural language -> **AI** (`~~~~~~` agent).
Both compose: deterministic flows can `invoke @"Agent"` for fuzzy steps, and agents can `run @"Flow"` or `decide @"Rules"` for reliable execution.

---

## Shared Conventions

These apply across ALL ModelHike DSL elements:

| Convention | Syntax | Used in |
|------------|--------|---------|
| Block scoping | `\|` prefix | State bodies, transitions, actions, property config, view slots, codelogic |
| Constraints | `{ expression }` | Properties, transition guards |
| Attributes | `( key=value )` | Elements, properties, controls |
| Inferred attributes | `[ value ]` | API routes, roles on transitions |
| Annotations | `@ keyword:: value` | Modules, classes, sections |
| Tags | `#tag` or `#tag:value` | Any element |
| Descriptions | `-- text` | After any element |
| Comments | `// text` | Anywhere |
| Sections | `# Name ... #` | APIs, Import, Export, Cache, etc. |
| References | `@"Quoted Name"` | Flows, rules, config objects, views |
| Sub-element calls | `run @"Flow"`, `decide @"Rules"` | Flows, rules, lifecycle entry, jobs |

---

## The `|` Rule

One rule governs all block scoping in ModelHike: **`|` means "I belong to the thing above me."** Same character, same meaning, in every DSL.

| Context | Example |
|---------|---------|
| State body | `state APPROVED` / `\| entry / emit OrderApproved` |
| Transition body | `\__ A -> B : event` / `\| api POST /route` |
| Action handler | `## button click` / `\| call service.method()` |
| Wait annotations | `wait Actor : review` / `\| @ sla:: 3 days` |
| Property config | `. items : Table` / `\| columns: name, qty, total` |
| View slot config | `* content : @"Grid"` / `\| mobile: single-column` |
| Codelogic nesting | `\|> IF condition` / `\| return value` |
| Rule body | `rule loyaltyDiscount` / `\| when: customer.yearsActive >= 5` |
| Decision-tree leaf actions | `└── action = "BLOCK"` / `\| notify team(Fraud)` |
| Section directives | `# Import` / `\| "Customer Name" -> name` |

You learn the `|` rule once and it works everywhere. No per-DSL block syntax. No special cases.

---
