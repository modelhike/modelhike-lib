# ModelHike: App Models -> code, docs, digrams (AI-in-Loop)

![License: MIT](https://img.shields.io/badge/license-MIT-blue) ![Swift 6](https://img.shields.io/badge/Swift-6-orange) ![Platform: macOS](https://img.shields.io/badge/platform-macOS%2013%2B-lightgrey)

> **Declarative Apps from Markdown. Generate production-grade, Git-friendly source code, docs and diagrams from plain-text software models -— with (optional) AI-in-Loop.**

With ModelHike, the idea is to move programming up a level—
- From the weeds of line-by-line code
- Into the elevated terrain of systems thinking and intent-driven modeling

By giving you a **high-level, declarative DSL** to describe your app, ModelHike restores 
clarity and flow. You're not babysitting a chaotic AI assistant. You're building a system — 
with structure, intent, and trust. You're co-creating with AI, not micro-managing it!

It *combines* the raw speed of **AI-assisted prototyping** with the safety of **template-
driven determinism**: explore rapidly while things are fluid, then lock in templates for 
repeatable, reviewable builds.

No black-box surprises —- AI is in-loop (strictly optional) but never out of control.
And, just like a good hike, you always know where you are.

Result: AI accelerates the unknowns, but every production build is template-driven, diffable, 
and CI-safe.

> 🚀 **Speed + Safety:** Use AI to sketch and refactor at warp speed, then let templates take 
over for bullet-proof builds.
---

## What is ModelHike?

ModelHike is an open-source **code-generation toolchain**. You describe your software architecture, domain models, and API surface in plain-text `.modelhike` files — a Markdown-flavoured DSL — and ModelHike generates complete, production-ready source code through customizable template blueprints.

**The core idea:** all implementation boilerplate — entities, repositories, controllers, services, DTOs, validation, API docs — is generated from a single source of truth. Your team focuses on domain rules and business logic. Architecture and implementation stay in sync, always.

```
.modelhike files → Parse → Hydrate → Validate → Render → Output
```

### Key Properties

- **Deterministic** — same model + same templates = identical output, every time. CI-safe.
- **Zero external dependencies** — the core library is fully self-contained. No third-party Swift packages.
- **Swift 6 strict concurrency** — actors throughout, fully `Sendable`-compliant.
- **AI optional** — AI can help bootstrap or refine models, but the generation pipeline is template-driven and fully controllable.

---

## Table of Contents

- [The DSL](#the-dsl)
- [How It Works](#how-it-works)
- [Installation](#installation)
- [Visual Debugger](#visual-debugger)
- [Project Structure](#project-structure)
- [Documentation](#documentation)
- [Current State](#current-state)
- [Why ModelHike?](#why-modelhike)
- [License](#license)

---



## The DSL
ModelHike uses a Markdown-flavoured DSL to describe software systems. Here's what a model looks like:

## Hello, Production — Real-World Walkthrough

### Before ModelHike: The Boilerplate Problem
```typescript
// payment-entity.ts
export class Payment {
  id: string;
  amount: number;
  status: string = "NEW";
  customerId: string;
  createdAt: Date;
  updatedAt: Date;
}

// payment-repository.ts
import { Payment } from './payment-entity';
export class PaymentRepository {
  async findById(id: string): Promise<Payment> { /* implementation */ }
  async save(payment: Payment): Promise<Payment> { /* implementation */ }
  async findByCustomerId(customerId: string): Promise<Payment[]> { /* implementation */ }
}

// payment-controller.ts
import { Request, Response } from 'express';
import { PaymentService } from './payment-service';
export class PaymentController {
  constructor(private paymentService: PaymentService) {}
  async createPayment(req: Request, res: Response) { /* validation, mapping, error handling 
*/ }
  async getPaymentById(req: Request, res: Response) { /* validation, mapping, error handling 
*/ }
  async getCustomerPayments(req: Request, res: Response) { /* validation, mapping, error 
handling */ }
}

// payment-service.ts
import { Payment } from './payment-entity';
import { PaymentRepository } from './payment-repository';
export class PaymentService {
  constructor(private paymentRepository: PaymentRepository) {}
  async createPayment(data: any): Promise<Payment> { /* business logic */ }
  async getPaymentById(id: string): Promise<Payment> { /* business logic */ }
  async getCustomerPayments(customerId: string): Promise<Payment[]> { /* business logic */ }
}

// routes.ts, validation.ts, dto.ts, tests, swagger docs... (30+ files total)
```

### With ModelHike: 1 Model = Complete Microservice

1. **Create a domain model** (`models/payments.dsl.md`):
```modelhike
==============================
Payments Service (microservices)
==============================
+ Payments Module
@ auth:: JWT
@ validation:: strict

=== Payments Module ===

Payment
=======
* _id       : Id
* amount    : Float { min = 0 }
* customerId: Reference@User
- status    : String = "NEW" <NEW, PENDING, COMPLETED, FAILED>
- createdAt : Timestamp
- updatedAt : Timestamp
- audit     : Audit (backend)

~ calculateTotal(items: [LineItem]) : Float
```
|||
```
return items.sum(item.price * item.quantity)
```

# APIs ["/payments"]
@ apis:: create, get-by-id, list
@ api:: get-customer-payments [GET "/customers/{customerId}/payments"]

# Events 
@ publish:: payment.created, payment.status-changed
@ consume:: customer.verified
#
```

From this single model, ModelHike generates entities, repositories, controllers, services, DTOs, validation, and API routing — all wired together and ready to run.

**DSL features:**
- C4-aligned hierarchy: System → Container → Module → Class/DTO/UIView
- Typed properties with constraints (`{ min = 0, max = 100 }`), defaults, and valid value sets (`<A, B, C>`)
- Methods with typed parameters, return types, and optional logic blocks
- API scaffolding via annotations (`@ apis:: create, get-by-id, list`)
- REST, GraphQL, and gRPC protocol support
- Mixins, annotations, attributes, and tags
- Comments and unrecognised lines are silently skipped

Full DSL specification: [DSL/modelHike.dsl.md](DSL/modelHike.dsl.md)

---

## How It Works

### The 6-Phase Pipeline

```
Discover → Load → Hydrate → Validate → Render → Persist
```

| Phase | What it does |
|-------|-------------|
| **Discover** | Walks the model directory, finds all `.modelhike` files |
| **Load** | Parses DSL files into an in-memory model (`ModelSpace` with containers, modules, domain objects, DTOs, UIViews) |
| **Hydrate** | Post-load refinements — port assignment, data type classification, annotation cascade |
| **Validate** | Semantic checks — unresolved types, duplicate names, missing modules. Emits structured diagnostics (never halts) |
| **Render** | Loads a blueprint (templates + scripts), runs `main.ss` entry-point script, generates output files |
| **Persist** | Writes all generated files to the output directory |

### Template Engine: TemplateSoup + SoupyScript

ModelHike includes a custom template engine:

- **`.teso` files** — template files with `{{ expression }}` print blocks and `:statement` script lines
- **`.ss` files** — pure SoupyScript files (no prefix needed for statements)
- **Modifiers** — transform values inline: `{{ name | capitalize }}`, `{{ prop | typescriptType }}`
- **Blueprint-defined modifiers** — drop a `.teso` file in `_modifiers_/` to register custom modifiers with front-matter config
- **Full scripting** — loops, conditionals, variables, functions, file generation, folder copying

Template/script specification: [DSL/templatesoup.dsl.md](DSL/templatesoup.dsl.md)

### Blueprints

A **Blueprint** is a named folder of templates, scripts, and static files that drives code generation for a specific stack. The engine renders the blueprint against the parsed model to produce the output codebase.

Current blueprint: `api-nestjs-monorepo` (NestJS + TypeScript + MongoDB). Spring Boot blueprint infrastructure is wired and ready for an active blueprint.

---

## Installation

### As a Swift Package dependency

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/modelhike/modelhike.git", branch: "main")
]
```

### From source

```bash
git clone https://github.com/modelhike/modelhike.git
cd modelhike
swift build
```

### Running the DevTester

The `DevTester` executable is the development harness for running the full pipeline:

```bash
swift run DevTester
```

> **Note:** `DevTester` requires a `modelhike-blueprints` companion repository cloned alongside this repo. See `DevTester/Environment.swift` for path configuration.

---

## Visual Debugger

ModelHike ships with a browser-based visual debugger for inspecting pipeline runs — a powerful tool for blueprint development and troubleshooting.

```bash
# Post-mortem: run pipeline, then inspect results
swift run DevTester --debug --debug-dev

# Live stepping: watch events stream in real time via WebSocket
swift run DevTester --debug-stepping --debug-dev
```

Then open `http://localhost:4800` in your browser.

**Features:**
- File tree with folder hierarchy of all generated files
- Split view: template source alongside generated output
- Event trace timeline — click events to see source locations
- Variable inspector at each generation point
- Model hierarchy browser (containers → modules → entities)
- Expression evaluator in the footer
- Live WebSocket event streaming in stepping mode
- Stepper panel with breakpoint support

| Flag | Description |
|------|-------------|
| `--debug` | Post-mortem mode — pipeline runs first, then browse the session |
| `--debug-stepping` | Live mode — server starts first, events stream over WebSocket |
| `--debug-port=<port>` | HTTP server port (default: 4800) |
| `--debug-dev` | Serve HTML from `DevTester/Assets` (for live UI edits) |
| `--no-open` | Don't auto-open the browser |

Full guide: [Docs/debug/VISUALDEBUG.md](Docs/debug/VISUALDEBUG.md)

---

## Project Structure

```
modelhike/
├── Package.swift              # Swift Package (zero deps for library)
├── Sources/                   # ModelHike library
│   ├── _Common_/              # Foundation utilities, file I/O, extensions
│   ├── Debug/                 # Debug recorder, events, diagnostics
│   ├── Modelling/             # DSL parser + in-memory domain model
│   ├── Scripting/             # SoupyScript template scripting engine
│   ├── CodeGen/               # TemplateSoup renderer + Blueprint loading
│   ├── Workspace/             # Context, Sandbox, expression evaluator
│   └── Pipelines/             # 6-phase pipeline orchestrator
├── DevTester/                 # Development executable + debug server
│   ├── DebugServer/           # SwiftNIO HTTP + WebSocket server
│   └── Assets/debug-console/  # Browser UI (Lit web components)
├── Tests/                     # Test suites (~120+ test cases)
├── DSL/                       # DSL specifications (the source of truth)
│   ├── modelHike.dsl.md       # Full DSL syntax guide
│   ├── codelogic.dsl.md       # Method logic block syntax
│   └── templatesoup.dsl.md    # Template engine syntax
└── Docs/                      # Documentation
```

---

## Documentation

| Document | Description |
|----------|-------------|
| [ModelHike DSL Spec](DSL/modelHike.dsl.md) | Complete DSL syntax — beginner to pro guide |
| [Code Logic DSL](DSL/codelogic.dsl.md) | Fenced method-body logic blocks |
| [TemplateSoup & SoupyScript](DSL/templatesoup.dsl.md) | Template engine and scripting language |
| [Documentation Hub](Docs/documentation.md) | Index of all available docs |
| [Debugging Guide](Docs/debug/DEBUGGING.md) | Debug flags, hooks, and techniques |
| [Visual Debugger](Docs/debug/VISUALDEBUG.md) | Browser-based pipeline inspector |
| [WebSocket Protocol](Docs/debug/WEBSOCKET_PROTOCOL.md) | Live stepping message format |
| [ADRs](Docs/ADRs.md) | Architecture decision records |
| [Brand Guide](Docs/modelHike.brand.md) | Naming, metaphor, tone |

---

## Current State

### What's Working

- Complete DSL parser — containers, modules, submodules, classes, DTOs, UIViews, properties, methods, annotations, APIs, constraints
- Full 6-phase pipeline (Discover → Load → Hydrate → Validate → Render → Persist)
- TemplateSoup + SoupyScript engine — all statement types, modifiers, operators, functions, loops, conditionals
- NestJS monorepo blueprint generation (TypeScript + MongoDB)
- Semantic validation with structured diagnostics (W301, W303–W306)
- World-class error messages with Levenshtein-distance "did you mean?" suggestions
- Blueprint-defined modifiers with front-matter configuration
- Expression evaluator (boolean, arithmetic, comparison)
- Scoped variable isolation via snapshot stack
- Browser-based visual debugger with post-mortem and live stepping modes
- ~120+ test cases across parsing, templates, code logic, blueprint modifiers, and diagnostics

### Roadmap

- [ ] Production CLI (`modelhike generate`, `modelhike validate`)
- [ ] Spring Boot blueprint
- [ ] More language modifier libraries
- [ ] VS Code extension
- [ ] Plugin system for Transform phase
- [ ] Additional test coverage for pipeline phases

---

## Why ModelHike?

| Pain Point | Traditional Approach | ModelHike Approach |
|------------|---------------------|--------------------|
| Architecture drift | Confluence docs rot, tribal knowledge | Single source-of-truth `.modelhike` models |
| Boilerplate | Copy-paste patterns, reviews on plumbing | Templates generate proven patterns automatically |
| AI unpredictability | Opaque code suggestions | AI is optional; core generation is deterministic |
| Onboarding | Read thousands of files to understand the system | Read one `.modelhike` file to see the full domain |

ModelHike moves programming up a level — from line-by-line code into systems thinking and intent-driven modelling. You define the *what*; templates handle the *how*.

## FAQ / Further Reading
- [Advanced Modeling Patterns](TBD#)
- [Migration Guide](TBD#)
- [Architecture Decision Records](#)
- [Community & Support](TBD#)

## Ranger Station

Need help or want to contribute?

- [Join the Discussions](TBD)
- [Open an Issue](TBD)
- [Contribute a Plugin](TBD)

ModelHike is open source and welcomes fellow explorers.

## License

[MIT](LICENSE)

> **We're building ModelHike to be the most joyful, intuitive, and structured way to develop modern software, in the era of AI.**
Feel the flow, spark creativity, enjoy the journey...
See you on the trail. 🏜️

> **Built by engineers, for engineers.** Describe your architecture once, generate confidently forever.
