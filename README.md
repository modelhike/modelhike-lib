# ModelHike

**Markdown-like App Models → Production Code, Docs & Diagrams**

| ⚔️ **Enemy** | Drift — when docs say one thing and code does another |
|:--|:--|
| 📜 **Philosophy** | Zero Dead Docs |
| ⚙️ **Mechanism** | One model, multiple views |
| 🤝 **Promise** | Intent stays synchronized across docs, diagrams, and code |
| 🤖 **AI Angle** | AI can help author and evolve, but never silently forks intent from implementation |

One source of truth. Zero dead documentation.  
AI in the loop — but never in control.  
Explore with AI. Ship with determinism.  
Build systems with structure, intent, and trust.


```
.modelhike files → Parse → Hydrate → Validate → Render → Output
```

All boilerplate — entities, repositories, controllers, services, DTOs, validation, and API docs — is generated from a single source of truth, so your team can focus on domain rules and business logic.

| Property | Description |
|:---------|:------------|
| 🔒 **Deterministic** | Same model + same templates = identical output. CI-safe, diffable builds. |
| 📦 **Zero Dependencies** | Core library is fully self-contained. No third-party Swift packages. |
| ⚡ **Swift 6** | Actors throughout, strict concurrency, fully `Sendable`-compliant. |
| 🤖 **AI Optional** | AI bootstraps and refines; templates drive production builds. No babysitting. |

Result: 🚀 **Speed + Safety:** AI accelerates exploration while the system is still fluid. Templates drive bullet-proof production builds — deterministic, diffable, CI-safe.

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

### Hello, Production — Real-World Walkthrough

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
ModelHike uses a Markdown-flavoured DSL to describe software systems. Here's what a model looks like:

1. **Create a domain model** (`models/payments.dsl.md`):
```modelhike
==============================
Payments Service (microservices) #blueprint(api-springboot-monorepo)
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

calculateTotal(items: [LineItem]) : Float
--------------------------------------------
return items.sum(item.price * item.quantity)
---

# APIs ["/payments"]
@ apis:: create, get-by-id, list
@ api:: get-customer-payments [GET "/customers/{customerId}/payments"]

# Events 
@ publish:: payment.created, payment.status-changed
@ consume:: customer.verified
#
```

From this single model, ModelHike generates entities, repositories, controllers, services, DTOs, validation, and API routing — all wired together and ready to run.


**DSL Highlights**

| Feature | Capabilities |
|:--------|:-------------|
| 🏗️ **C4 Hierarchy** | System → Container → Module → Class/DTO/UIView |
| 📐 **Typed Properties** | Constraints `{min, max}`, defaults, value sets `<A, B, C>` |
| ⚙️ **Methods** | Typed params, return types, fenced logic blocks |
| 🚀 **API Scaffolding** | Annotations `@apis:: create, get-by-id, list` |
| 🌐 **Protocols** | REST, GraphQL, gRPC support |
| 🏷️ **Extensibility** | Mixins, annotations, attributes, tags |

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

| Component | Description |
|:----------|:------------|
| 📄 **`.teso` Files** | Templates with `{{ expression }}` blocks and `:statement` script lines |
| 📜 **`.ss` Files** | Pure SoupyScript — no prefix needed for statements |
| 🔧 **Modifiers** | Transform inline: `{{ name &#124; capitalize }}`, `{{ prop &#124; typescriptType }}` |
| 🎨 **Custom Modifiers** | Drop `.teso` files in `_modifiers_/` with front-matter config |
| 🧩 **Full Scripting** | Loops, conditionals, variables, functions, file/folder operations |

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

| Feature | Description |
|:--------|:------------|
| 🗂️ **File Tree** | Folder hierarchy of all generated files |
| 🪟 **Split View** | Template source alongside generated output |
| 📊 **Event Trace** | Click events to jump to source locations |
| 🔍 **Variable Inspector** | Capture state at each generation point |
| 🌳 **Model Browser** | Navigate containers → modules → entities |
| 🧮 **Expression Eval** | Test expressions in the footer |
| 🔴 **Live Streaming** | WebSocket events in stepping mode |
| ⏯️ **Stepper Panel** | Breakpoints with step over/into/out |

| Flag | Description |
|------|-------------|
| `--debug` | Post-mortem mode — pipeline runs first, then browse the session |
| `--debug-stepping` | Live mode — server starts first, events stream over WebSocket |
| `--debug-port=<port>` | HTTP server port (default: 4800) |
| `--debug-dev` | Serve HTML from `DevTester/Assets` (for live UI edits) |
| `--no-open` | Don't auto-open the browser |

Full guide: [Docs/debug/VISUALDEBUG.md](Docs/debug/VISUALDEBUG.md)

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

| Status | Feature |
|--------|---------|
| ✅ | Complete DSL parser with containers, modules, classes, DTOs, UIViews, properties, methods, APIs |
| ✅ | 6-phase pipeline: Discover → Load → Hydrate → Validate → Render → Persist |
| ✅ | TemplateSoup + SoupyScript engine with full scripting (loops, conditionals, modifiers) |
| ✅ | NestJS monorepo blueprint (TypeScript + MongoDB) |
| ✅ | Semantic validation with structured diagnostics |
| ✅ | World-class error messages with "did you mean?" suggestions |
| ✅ | Blueprint-defined modifiers with front-matter configuration |
| ✅ | Browser-based visual debugger with live stepping |
| ✅ | ~120+ test cases |
| ⏳ | Production CLI (`modelhike generate`, `modelhike validate`) |
| ⏳ | Spring Boot blueprint |
| ⏳ | VS Code extension |
| ⏳ | Plugin system for Transform phase |

---

## Why ModelHike?

| Pain Point | Traditional Approach | ModelHike Approach |
|------------|---------------------|--------------------|
| Architecture drift | Confluence docs rot, tribal knowledge | Single source-of-truth `.modelhike` models |
| Boilerplate | Copy-paste patterns, reviews on plumbing | Templates generate proven patterns automatically |
| AI unpredictability | Opaque code suggestions | AI is optional; core generation is deterministic |
| Onboarding | Read thousands of files to understand the system | Read one `.modelhike` file to see the full domain |

ModelHike moves programming up a level — from line-by-line code into systems thinking and intent-driven modelling. You define the *what*; templates handle the *how*.

And, just like a good hike, you always know where you are.

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

> **We're building ModelHike to be the most joyful, intuitive, and structured way to develop modern software, in the era of AI.**
Feel the flow, spark creativity, enjoy the journey...
See you on the trail. 🏜️

> **Built by engineers, for engineers.** Describe your architecture once, generate confidently forever.
