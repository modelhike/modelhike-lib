# ModelHike DSL — Beginner → Pro Guide 🚀

ModelHike DSL lets you capture **architecture, data models, and APIs** in a single file that reads like Markdown while mapping cleanly to the **C4 model**.

> **Why ModelHike?**
>
> 1. One source‑of‑truth for diagrams, docs, and code‑gen.
> 2. Super‑friendly: spaces, hyphens, comments — all allowed.
> 3. Zero tooling lock‑in — plain text forever.

---

## Legend 🎛️ (bookmark this!)

| Pattern / Symbol   | Meaning                               | Appears where            |
| ------------------ | ------------------------------------- | ------------------------ |
| `* * * … * * *`    | **System fence** – top-level C4 system boundary (3 lines: open, name, close; then body, then closing asterism) | File top level  |
| `+--- Name … +---` | **Virtual group** – named visual cluster inside a system body; body lines prefixed with `\|` | Inside system body |
| `Name [type]` + `++++` | **Infra node** – inline infra element inside system | Inside system body |
| `=== … ===`        | **Container fence** – deployable unit | Inside a system or file top level |
| `=== Module ===`   | **Module / Component**                | Inside a container       |
| extra `=` (`====`) | **Sub‑module**                        | Nested under a module    |
| `Class` + `====`   | **Class / Type**                      | Inside a module          |
| `DTO` + `/===/`    | **DTO** – flattened read‑model        | Inside a module          |
| `UIView` + `~~~~`  | **UIView** – UI component model       | Inside a module          |
| `methodName(…)` + `------` | **Method** — setext header + dash underline | After properties in a class |
| `~ methodName(…)` | **Method** — tilde-prefix style (no underline) | After properties in a class |
| `>>> * param: Type …` | **Parameter metadata** — one line per parameter, immediately before method header | Before method header |
| `>>>` (prose) | **Description line** — bare `>>>` text (no `*`, `-->`, `<-->`, …) merges into the next element’s `description` | Before container, module, class, or method |
| `--` (inline) | **Inline description** — ` -- text` at end of a line | After headers / properties / signatures |
| `--` (next lines) | **Continuation description** — lines starting with `--` (not an all-dash underline) | After a parsed element |
| `-->` / `<-->` | **Output / in-out parameter** — in `>>>` lines or in the method signature before `paramName` | Method parameters |
| `@Name` | **Constraint or expression reference** — `@Name` inside `{ … }` applies a named constraint (`appliedConstraints`); `= @Name` default references a module `=` expression | Property lines |
| `= name : { … }` | **Named constraint** — boolean expression in `{ … }` (may span lines); module- or class-level | Module or class body |
| `=` (module) | **Module-level expression** — same shape as a calculated property at module scope | Inside `=== Module ===` |
| `~` (module) | **Module-level function** — method at module scope | Inside `=== Module ===` |
| `---` / ` ``` ` / `'''` / `"""` | **Method logic fence** – wraps the logic body; tilde-style accepts 3+ repetitions of the fence character, opening and closing must match | After method header |

| `**`               | **Primary key field**              | Property list            |
| `*`                | **Required field**                 | Property list            |
| `-`                | **Optional field**                 | Property list            |
| `.`                | **DTO-only field**                 | Property list            |
| `*?`               | **Conditional** required field        | Property list            |
| `=`                | **Calculated** / derived field        | Property list            |
| `(backend)`        | Server‑side only — excluded from DTOs | After property           |
| `<>`               | Valid value set literal               | Property valid value set |
| `{key=value}`      | **Constraint** list                   | After property           |
| `(key=value)`      | **Attribute** (explicit)              | After element / property |
| `[ … ]`            | **Attribute** (inferred)              | Usually after `# APIs`   |
| `@`                | **Annotation** (scaffold / metadata)  | Any element              |
| `#tag`             | **Tag** – free‑form label             | End of header / property |
| `#blueprint(name)` | **Blueprint tag** – selects templates | Container header         |
| `#output-folder(name)` | **Output folder tag** – overrides container output suffix | Container header |
| `# APIs`           | Begin API block                       | In a module or class     |
| `//`               | **Line comment** – ignored by parser  | Anywhere                 |

---

## 0 · Systems — the Grand Boundary

A **System** is the outermost C4 boundary — a named collection of containers and infrastructure that together deliver a product or capability. It maps to a C4 *Software System*.

The system uses an **asterism fence**: spaced `*` characters on otherwise empty lines, with the name sandwiched in between. The body follows after the second fence and runs until a third closing asterism.

```modelhike
* * * * * * * * * * * * * * * * * * *
E-Commerce Platform
* * * * * * * * * * * * * * * * * * *

+ Payments Service
+ Order Service
+ Frontend App

PostgreSQL [database] #primary-db -- Main relational store
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++
host    = db.internal
port    = 5432
version = 14

Kafka Events [message-broker] #async
+++++++++++++++++++++++++++++++++++++
bootstrap.servers = kafka:9092
group.id          = platform

* * * * * * * * * * * * * * * * * * *
```

### System anatomy

```
* * * * * * * * *   ← opening title fence
System Name (attributes) #tags
* * * * * * * * *   ← closing title fence / body starts
  body …
* * * * * * * * *   ← end of system body (consumed by parser)
```

### Key ideas

| Concept                              | Why it matters                             |
| ------------------------------------ | ------------------------------------------ |
| Three asterism lines total           | Open title, close title, close body        |
| `+ Container Name`                   | Reference to a full container — resolved at load time |
| Infra node (setext `++++` header)    | Inline infra element with typed properties |
| `[type]` after infra name            | Classifies the node (database, broker, …)  |
| `key = value` lines after underline  | Configuration properties for the infra node |
| Virtual group (`+--- Name … +---`)   | Named visual cluster; body lines prefixed with `\|`  |
| Groups nest to arbitrary depth       | Outer `\|` prefix is stripped before inner parsing |
| Fence width is cosmetic              | Match name length or use a fixed width     |
| Multiple systems in one file allowed | Model a multi-system landscape             |

### `+` container references

Any `+ Name` line inside the body is stored as an unresolved reference and wired to the matching `C4Container` during the load phase (matched by givenname, then normalised name).

```modelhike
* * * * * * * * * * * * *
Logistics Platform
* * * * * * * * * * * * *
+ Inventory Service
+ Shipping Service
* * * * * * * * * * * * *
```

### Infra nodes

Inline infrastructure elements use a **setext header** with a `++++` underline (width ≥ name length), followed by `key = value` property lines. The type is given in `[...]` brackets after the name.

```modelhike
Redis Cache [cache] #session
+++++++++++++++++++++++++++++
host    = redis.internal
port    = 6379
db      = 0
```

Infra node properties end at the first blank line, the next infra node header, a `+` container ref, a virtual group fence, or the closing asterism.

### Virtual groups

Group related elements visually using a **virtual group** block. Virtual groups carry no semantic meaning — they exist to communicate spatial or logical clustering in architecture diagrams.

```
+--- Group Name #tags -- optional description
|
| + Container Name          ← container reference inside the group
|
| Redis [cache]             ← infra node inside the group
| ++++++++++++++
| host = redis.internal
|
| +--- Nested Group         ← groups nest to arbitrary depth
| | + Inner Service
| +---
|
+---                        ← closing fence (no name after +---)
```

**Rules:**
- **Opening fence:** `+--- Name` — `+---` followed by at least one non-whitespace character (the name). Supports `#tags` and `-- inline description` after the name.
- **Closing fence:** `+---` alone (nothing after the fence token, or only whitespace).
- **Body lines:** each line inside the group must be prefixed with `|`. A bare `|` is an empty line.
- **Nesting:** strip the leading `|` from a body line and the content is parsed with the same rules — so `| +--- Inner` is an inner group opener.  For the next depth level the prefix doubles: `| |`.
- **Content:** the same element types allowed at the system body level work inside groups: `+ Container` references, infra nodes, and nested virtual groups.
- Container references in groups are resolved against the full container list (same matching rules as top-level refs).

```modelhike
* * * * * * * * * * * * *
E-Commerce Platform
* * * * * * * * * * * * *

+--- Data Tier #backend -- Persistent storage layer
| PostgreSQL [database] #primary
| +++++++++++++++++++++++++++++++
| host = db.internal
| port = 5432
|
| Redis [cache]
| ++++++++++++++
| host = redis.internal
+---

+--- API Layer
| + Orders Service
| + Payments Service
|
| +--- Async Messaging
| | Kafka [broker]
| | ++++++++++++++++
| | brokers = kafka-1:9092
| +---
+---

* * * * * * * * * * * * *
```

### System name with attributes and tags

```modelhike
* * * * * * * * * * * * * * * * * * *
E-Commerce Platform (owner="platform-team") #production
* * * * * * * * * * * * * * * * * * *
+ Payments Service
* * * * * * * * * * * * * * * * * * *
```

### Visual hierarchy at a glance

```
* * * * *          ← System — asterism fence, grandest
 ├── +--- Group    ← Virtual group — visual cluster inside system body
 │    ├── + Ref    ← Container reference
 │    └── +---     ← (nested virtual group)
 └── ===           ← Container — triple = fence
      └── === Module ===     ← Module — inline
           └── Class ====    ← Class — underline
```

#### Mini‑cheatsheet

```modelhike
* * * * * * * * * * * * *
Auth Platform
* * * * * * * * * * * * *
+ Identity Service
+ MFA Service
PostgreSQL [database]
+++++++++++++++++++++
host = auth-db.internal
port = 5432
* * * * * * * * * * * * *
```
---

## 1 · Containers — the Big Boxes 🏢

A **Container** is a deployable thing—micro‑service, DB, message queue. Wrap its name in `===` fences.

```modelhike
===
Payments Service #blueprint(api-springboot-monorepo)
===
+ Billing Module
+ Receipts Module
```

### Key ideas

| Concept                                | Why it matters                     |
| -------------------------------------- | ---------------------------------- |
| `===` fence above & below              | Clear visual boundary              |
| Only `+ Module` or nested `===` inside | Keeps root tidy                    |
| Optional parent template `(Base…)`     | Share infra / tags across services |
| Human‑readable names                   | "User Service" beats `user_srv`    |
| `#blueprint(name)` tag                 | Selects which blueprint to render  |
| `#output-folder(name)` tag             | Overrides the output subfolder     |

### Blueprint selection

Every container that will be rendered **must** declare a `#blueprint(name)` tag. This tells the render pipeline which set of templates to use for code generation.

```modelhike
===
APIs #blueprint(api-springboot-monorepo)
===
```

### Output folder selection

Each rendered container is written under its own subfolder inside the configured output root. By default that subfolder is derived from the container name. Use `#output-folder(name)` to override it.

```modelhike
===
APIs #blueprint(api-springboot-monorepo) #output-folder(base-services)
===
```

#### Mini‑cheatsheet

```modelhike
=== 
Analytics Pipeline (Base Service) #blueprint(api-nestjs-monorepo) 
===
+ Collector Module
+ Aggregator Module
```

---

## 2 · Modules & Sub‑modules — the Medium Boxes 📦

Modules map to **C4 Components**; sub‑modules let you nest deeper.

```modelhike
=== Order Module ===            # primary component
=== PDF Renderer ====           # sub‑module (extra '=')
```

### Key ideas

| Concept / Rule                       | Why it helps                         |
| ------------------------------------ | ------------------------------------ |
| `(Parent Module)` after the name     | Inherit behaviour, annotations, tags |
| Sub‑module uses `====` closing fence | Quickly spot hierarchy depth         |
| `@ apis:: …` on module header        | CRUD for **every** class inside      |
| Mix classes, DTOs, API blocks inside | Keeps related pieces together        |

### Module‑level expressions, functions, and named constraints

Inside a module fence (after `=== Module Name ===`), you may declare items **before** any class/DTO/UIView:

* **Expression constants** — same syntax as a calculated property: `= MAX_RETRIES : Int = 5`. These are stored on the `C4Component` as `expressions: [Property]`.
* **Functions** — tilde or setext methods at module scope: `~ helper(x: Int) : Int`. Stored as `functions: [MethodObject]`.
* **Named constraints** — `= positiveAmount : { amount > 0 }` with an optional multi-line `{ … }` body. Stored in `namedConstraints`. Class bodies support the same `= name : { … }` form on `DomainObject`.

Validation (**W302**) warns when a property references `@Something` that cannot be resolved against module/class expressions, named constraints, or `common.modelhike` shared types.

### Anatomy of a module header

```
=== Module Name (Parent1, Parent2) === #tag
```

#### Mini‑cheatsheet

```modelhike
=== Reports Module (Shared UI) ===
@ apis:: list, get-by-id

=== PDF Renderer ====            # sub‑module example
```

---

## 3 · Classes / Types — your Data Schemas 🗄️

Classes describe persistent or in‑memory entities.

```modelhike
Flight View (Base Flight, Timestamps)
====================================
* id            : Id              = auto            # primary key
* flight Number : String
- etd Date      : DateTime        = now()
* is Arrival    : Boolean         = false
```

### Key ideas

| Rule / Concept                  | Why it matters                             |
| ------------------------------- | ------------------------------------------ |
| Underline length = title length | Parsing guard‑rail                         |
| Mix‑ins in `( … )`              | Inherit fields & rules                     |
| Prefixes `*` `-` `.`            | Required / optional / DTO‑field            |
| `Id` type                       | Triggers primary‑key index generation      |
| Type inference                  | Skip `: Type` when default is self‑evident |
| Validation via constraints      | `{min=0, pattern=…}` or `{salary > 0}` directly in property |
| Human‑readable names            | Spaces & hyphens welcome                   |

#### Mini‑cheatsheet

```modelhike
Customer (PersonBase)
=====================
* id   : Id
* name : String
- age  = 30
```

---

## 4 · DTOs — flattened read‑models 🪄

DTOs provide just the data the outside world needs—nothing more.

```modelhike
Invoice Summary (Invoice, Customer)
/===/
. id
. customer Name
. total Amount
```

### Key ideas

| Point                     | Why it helps                   |
| ------------------------- | ------------------------------ |
| Slashed underline `/===/` | Visually distinct from classes |
| Parents mandatory         | Define source types            |
| Fields start with `.`     | Never declare types here       |
| DTOs can inherit DTOs     | Compose unlimited read‑models  |

#### Mini‑cheatsheet

```modelhike
Airport Flight View (Flight View, Airport)
/===/
. id
. airport Code
. etd Date
```

---

## 5 · Properties — the Building Blocks 📑

Everything inside classes/DTOs boils down to **properties**.

**Property names are human‑friendly.** Spaces are allowed — `flight Number`, `arrival Date`, `is Active`. The parser normalises them to camelCase internally (`flightNumber`, `arrivalDate`, `isActive`), but you write them however reads naturally. The original spaced name is preserved as `givenname`; the normalised form is `name`.

### 5.1 Prefixes recap

| Prefix | Meaning                | Notes                                       |
| ------ | ---------------------- | ------------------------------------------- |
| `**`   | **primary key**        | Required field; retains its declared type   |
| `*`    | **required**           |                                             |
| `-`    | **optional**           |                                             |
| `_`    | optional (alias)       | Accepted as alias for `-`; prefer `-`       |
| `*?`   | **conditional** req.   | `RequiredKind.conditional`                  |
| `=`    | **calculated/derived** | Computed value; never stored directly       |
| `.`    | **DTO field**          | Type inherited from parent; never declared  |

### 5.2 Types

| DSL name(s)                       | Meaning / PropertyKind          |
| --------------------------------- | ------------------------------- |
| `Int`, `Integer`                  | integer number (`.int`)         |
| `Number`, `Decimal`, `Double`, `Float` | floating point (`.double`)  |
| `Bool`, `Boolean`, `YesNo`, `Yes/No`   | boolean (`.bool`)           |
| `String`, `Text`                  | string (`.string`)              |
| `Date`                            | calendar date (`.date`)         |
| `DateTime`                        | date + time (`.datetime`)       |
| `Buffer`                          | binary data (`.buffer`)         |
| `Id`                              | primary key — triggers unique index (`.id`) |
| `Any`                             | untyped (`.any`)                |
| `Reference@TypeName`              | reference type (`.reference`) |
| `Ref@TypeName.fieldName`          | foreign key reference, represented as `Ref@table.field` |
| `Ref@"Type Name".fieldName`       | foreign key reference to a spaced table/type name |
| `Reference@Type1,Type2`           | multi-type reference (`.multiReference`) |
| `ExtendedReference@TypeName`      | reference with extra fields (`.extendedReference`) |
| `CodedValue@TypeName`             | coded/enum reference (`.codedValue`) |
| anything else                     | custom object type (`.customType`) |

* `** field : Type` marks a primary key while preserving the declared `Type`.
* `Id` remains available as a normal scalar type when you explicitly want that type.
* Omit `: Type` if default is self‑evident.

### 5.3 Collections made simple

| Write…               | You get           | Example valid value set |
| -------------------- | ----------------- | ----------------------- |
| `String[]`           | list (any length) | `<"vip">`          |
| `Seat[1..*]`         | list, min 1       | `<SeatA>`          |
| `[string => Person]` | dictionary        | `<admin: "Bob">`   |

### 5.4 Descriptions

* **Inline:** append ` -- prose` to the end of a property or header line (space–dash–dash–space). The remainder is stripped from the line and stored as `description`.
* **Following lines:** lines starting with `--` (not a setext/rule underline) attach to the **previous** member or header as extra description text.
* **Prose `>>>` blocks:** consecutive lines beginning with `>>>` whose remainder does **not** start with a parameter marker (`*`, `-->`, `<-->`, …) attach as description to the **next** container, module, class, or method.

### 5.5 `@` references on property lines

* `* field : Type = @ExpressionName` — default value references a module-level `=` expression (`ExpressionName` matches the expression property name).
* `* field : Type { @constraintName }` — applies a named constraint from the module, class, or common model (`appliedConstraints`). The `@name` must appear **inside** the `{ … }` constraint block (you can combine with predicates, e.g. `{ @positiveAmount, min = 0 }`).
* Putting `@constraintName` **outside** `{ … }` (except `= @ExpressionName` above) is a parse error (**E620**): move the reference into `{ … }`.
* Annotation syntax `@word::` is unchanged and is not treated as a reference.

### 5.6 Defaults & validation

```modelhike
- retries : Int = 3                          { min = 0, max = 10 }
* tags    : String[] <"vip">
- seats   : Seat[1..*] <S1>                  { max = 10 }
- status  : String = "NEW" <"NEW", "ACTIVE", "DONE">
- salary  : Float                            { salary > 0 }
```

When both are present, write the default first and the valid value set second: `= value <...>`.

#### Mini‑cheatsheet

```modelhike
Product
=======
* id    : Id
* name  : String = "Widget"
- price : Float  = 9.99 { min = 0 }
```

---

## 6 · Attributes — extra metadata 📎

Attributes add key‑value pairs to **any element**.

### 6.1 Two styles

| Style    | Syntax                        | Result                       |
| -------- | ----------------------------- | ---------------------------- |
| Explicit | `(route="/users", version=2)` | You name every key           |
| Inferred | `["/orders"]`                 | DSL infers `route="/orders"` |

### 6.2 Inheritance / Composition

Parentheses after container/module/class names list parents and act like an `extends` attribute.

```modelhike
=== Logistics Service (Base Service) #blueprint(api-springboot-monorepo) ===
=== Stock Module (Auditable) ===
Order (BaseEntity, SoftDelete)
=====
```

### 6.3 Property attributes

```modelhike
* price : Float = 9.99 { min = 0 } (currency="USD")
```

### 6.4 API‑block attributes

```modelhike
# APIs (route="/orders", version=2, auth="jwt")
# APIs ["/orders"]   # inferred route
```

#### Mini‑cheatsheet

```modelhike
# APIs ["/products"]
```

---

## 7 · Annotations — power‑ups ⚡️

Annotations start with `@` and automate tasks.

### 7.1 Built‑in catalog

| Keyword    | Purpose                            | Typical scope    |
| ---------- | ---------------------------------- | ---------------- |
| `apis`     | CRUD scaffold                      | Module / Class   |
| `no-apis`  | Suppress API generation            | Module / Class   |
| `list-api` | Query param → property mapping for list | Class       |
| `index`    | DB index                           | Class            |
| `roles`    | Access control                     | Class / API      |
| `auth`     | Auth scheme                        | API block        |
| `validate` | Custom validator                   | Property / Class |

### 7.2 `@list-api` mapping syntax

Specifies how query parameters map to entity properties for the list endpoint. Uses `->` for direct mapping and `;` to separate multiple mappings:

```modelhike
@ list-api :: name -> name; type -> type.display
```

* Query param `name` maps to property `name`.
* Query param `type` maps to `type.display` (dot‑path into a nested object).
* Parsed as a `MappingAnnotation` with `mappings: [(key, value)]`.

### 7.3 Resolution rules

1. Closest scope wins.
2. Same‑keyword annotations merge within scope.
3. Annotations cascade down unless overridden.

#### Mini‑cheatsheet

```modelhike
@ roles:: admin, ops
```

---

## 8 · Tags — quick labels 🏷️

Tags add searchable, free‑form metadata. **Always append them at the very end of a line.**

### Key ideas

| Where you can tag                    | Example                               |
| ------------------------------------ | ------------------------------------- |
| **Container / Module / Class / DTO** | `Order Module #bounded-context:Sales` |
| **Property**                         | `* amount : Float #currency`          |
| **API block**                        | `# APIs #public`                      |

### Tag formats

* `#tag` — basic flag
* `#tag:value` — key‑value style
* `#tag(value)` — parentheses variant (good for booleans)

#### Mini‑cheatsheet

```modelhike
Invoice #financial
* total #currency : Float
```

---

## 9 · Comments ☕️

Two comment styles are supported — both are ignored by all parsers:

| Style            | Syntax                             | Notes                                            |
| ---------------- | ---------------------------------- | ------------------------------------------------ |
| **Explicit**     | `// text`                          | Recognised comment prefix; stripped from output  |
| **Unrecognised** | any plain line without a prefix    | Silently skipped; great for TODOs / design notes |
| **Quoted**       | `"TODO: migrate legacy IDs by Q3"` | Quoted strings without a prefix are also skipped |

> Comments on property/method lines: if a line starts with `//`, the `//` prefix is stripped and the rest is discarded. Unrecognised lines that don't begin with a known prefix (`*`, `-`, `~`, `.`, `=`, `@`, `#`, etc.) are silently skipped.

#### Mini‑cheatsheet

```modelhike
// This whole line is a comment
"Legacy field — keep until migration completed"
Legacy mapping to be removed
// deprecated — remove after migration
```
---

## 10 · APIs — wiring data to the outside world 🌐

APIs turn your DSL models into live endpoints. ModelHike supports **REST, GraphQL, and gRPC**—all driven by the same `@ apis` keyword and `# APIs` block.

> **Quick reference**
>
> | Concept                | What it does                                                 |
> | ---------------------- | ------------------------------------------------------------ |
> | `@ apis:: …`           | Scaffold CRUD **and** generate stubs (REST / GraphQL / gRPC) |
> | `protocol="…"` attr    | Explicitly pick `rest` (default), `graphql`, or `grpc`       |
> | `# APIs`               | Start a per‑class API block                                  |
> | `["/path"]`            | Inferred **route** attribute (REST)                          |
> | `[graphql]` / `[grpc]` | Inferred **protocol** attribute                              |
> | `list by <prop>`       | Auto‑builds filter query / resolver / RPC                    |

 Module‑level scaffold

```modelhike
=== Inventory Module ===
@ apis:: list, get-by-id [grpc]
```

**Effect** — every class becomes a gRPC service with `List` & `GetById` RPCs.

### 10.2 Class‑level API block (REST example)

```modelhike
Product
=======
# APIs ["/products"]                 # inferred REST route (protocol defaults to REST)
@ apis:: create, delete, get-by-id   # scaffold CRUD endpoints
## list by name                      # auto GET /products?name={name}
## discount(price: Float) : Product  (route="/products/discount", method=POST)
#                                     # end block
```

### 10.3 Class‑level API block (GraphQL example)

```modelhike
Flight View
===========
# APIs [graphql]
@ apis:: create, list, get-by-id      # generates mutations & queries
## list by arrival Station            # adds `flightsByArrivalStation` resolver
#
```

### 10.4 CRUD keyword table (REST default)

| Keyword   | REST verb | REST route    | GraphQL equivalent        | gRPC method name |
| --------- | --------- | ------------- | ------------------------- | ---------------- |
| create    | POST      | `/route`      | `create<Entity>` mutation | `Create`         |
| delete    | DELETE    | `/route/{id}` | `delete<Entity>` mutation | `Delete`         |
| update    | PUT       | `/route/{id}` | `update<Entity>` mutation | `Update`         |
| patch     | PATCH     | `/route/{id}` | `patch<Entity>` mutation  | `Patch`          |
| list      | GET       | `/route`      | `all<Entity>` query       | `List`           |
| get-by-id | GET       | `/route/{id}` | `<entity>ById` query      | `GetById`        |

### 10.5 Magic `list by` helpers

```modelhike
## list by status & date   # maps to all 3 protocols automatically
```
becomes:

• *REST*: GET `/route?prop=value` 
• *GraphQL*: `entitiesByProp(prop: …)` 
• *gRPC*: `ListByProp` RPC.

### 10.6 Custom operations (any protocol)

```modelhike
## generateReport(month: String="May") : ReportDto (route="/reports/generate", method=POST, protocol="rest", roles=admin)
## streamUpdates() : stream FlightView   (protocol="grpc")
```

* Choose protocol per operation with `protocol="rest|graphql|grpc"`.
* REST needs `route` + `method`; GraphQL/gRPC infer operation names from the signature.

#### Mini‑cheatsheet

```modelhike
# APIs (protocol="graphql")            # whole block is GraphQL
@ apis:: create, list                   # auto mutations & list query
## list by month                        # adds month filter resolver
#
```

---

## 11 · UIViews — UI component models

UIViews model UI screens or components. They use a **tilde underline** (`~~~~`) instead of `====`, and contain only annotations and API blocks — no properties.

```modelhike
My Screen View (attributes) #tags
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
@ annotation:: value
# APIs
...
#
```

### Key ideas

| Rule                              | Why it matters                               |
| --------------------------------- | -------------------------------------------- |
| `~~~~` underline (tilde chars)    | Visually distinguishes UIViews from entities |
| Underline length = title length   | Parsing guard‑rail                            |
| No properties                    | UIViews hold structure, not data fields      |
| Annotations & API blocks allowed | Drive scaffolding just like entities         |

#### Mini‑cheatsheet

```modelhike
Dashboard View
~~~~~~~~~~~~~~
@ roles:: admin
# APIs ["/dashboard"]
@ apis:: get-by-id
#
```

---

## 12 · Methods — behaviour inside classes

Methods appear **after all properties** in a class. Two syntaxes are supported:

**Setext-header style** — signature line + `------` dash underline. For methods **with** a logic body. Logic starts immediately after the underline (no opening fence); closing `---` is mandatory.

**Tilde-prefix style** — `~` prefix on the signature line. Preferred for method stubs (no logic). Supports an optional fenced logic block using ` ``` `, `'''`, or `"""` — any run of 3 or more of the same character is accepted; the closing fence must be the exact same string as the opening fence.

```modelhike
methodName(param1: Type, param2: Type) : ReturnType #tags
----------------------------------------------------------
```

```modelhike
view-sql
--------
```

```modelhike
~ methodName(param1: Type, param2: Type) : ReturnType #tags
```

```modelhike
~ trigger-sql
```

* For setext style: underline must be only `-` characters (`ModelConstants.MethodUnderlineChar`).
* For tilde-prefix style: `~` prefix on the signature (no underline line follows).
* Return type after `:` is optional; if omitted the method has return type `unKnown`.
* Empty `()` may be omitted for paramless methods in both styles.
* Parameters follow the same `name: Type` syntax as properties.
* Produces a `MethodObject` with `parameters: [MethodParameter]` and `returnType: TypeInfo`. Each `MethodParameter` carries a `metadata: ParameterMetadata` field (see §12.1).
* A fenced logic body may follow — see [`codelogic.dsl.md`](codelogic.dsl.md).

### 12.1 · Parameter metadata — `>>>` prefix

To attach rich metadata to individual parameters, write one `>>>` line per parameter **immediately before** the method header (no blank lines between). The format mirrors the property syntax:

```
>>> <marker> <paramName>: <Type> [= default] [<validValueSet>] [{ constraints }] [(attributes)] [#tags]
```

| Marker | Meaning |
| ------ | ------- |
| `*` or `**` | Required parameter (`RequiredKind.yes`) |
| `-` or any other | Optional parameter (`RequiredKind.no`) |
| `-->` | Output parameter — optional (`required = .no`), `isOutput = true` |
| `<-->` | In-out parameter — required (`required = .yes`), `isOutput = true` |

The special tag `#output` marks a parameter as output/return-by-reference (`isOutput = true`) — same as `-->` on the `>>>` line.

You may also prefix parameters in the **signature** with `-->` or `<-->` (e.g. `~ swap(--> out: Int) : Void`). Signature defaults are supported: `~ f(--> x: Int = 0) : Bool`. When both `>>>` metadata and a signature marker exist for the same parameter, the **`>>>` line wins**.

```modelhike
>>> * customerId: Id
>>> - notes: String = nil
>>> * amount: Decimal = 0 { min = 0 } #output
~ placeOrder(customerId: Id, notes: String, amount: Decimal) : Order
```

* Each `>>>` line is matched to its parameter by **name** (normalised to camelCase).
* Parameters with no matching `>>>` line receive default metadata (`required = .no`, no constraints, no default).
* Both tilde-prefix and setext-style methods support `>>>` blocks.
* Valid value set, constraints, attributes, and tags use the same syntax as properties (see §5).
* `MethodParameter.metadata` is a `ParameterMetadata` struct with fields: `required`, `isOutput`, `defaultValue`, `validValueSet: [String]`, `constraints`, `attribs`, `tags`.

#### Mini‑cheatsheet

````modelhike
>>> * orderId: Id
>>> - discount: Float = 0.0 { min = 0, max = 1 } (source=promo)
>>> * result: Decimal #output
~ applyPromo(orderId: Id, discount: Float, result: Decimal) : Boolean
````

#### Full example

````modelhike
Order
=====
* id     : Id
* amount : Float

calculateTotal() : Float
-------------------------

>>> * percent: Float = 0 { min = 0 }
applyDiscount(percent: Float) : Order #admin
---------------------------------------------
|> IF percent <= 0
| return this
assign self.amount = amount * (1 - percent / 100)
return this
---
````

---

## 13 · `(backend)` attribute — server‑side‑only fields

Annotate a property or import with `(backend)` to mark it as server‑side only. Blueprints use this to exclude those fields from client‑facing DTOs and schemas.

```modelhike
- audit : Audit (backend)
- mggOrg : Reference@Organization (backend)
```

* This is an **attribute** (`attribs["backend"]`), not a keyword.
* It has no effect on parsing — only blueprints that explicitly check for it will act on it.
* Use it for fields like audit trails, internal org references, or server‑managed metadata.

---

## 14 · Putting it all together 🧩

A full example combining **every** concept.

```modelhike
=== Order Management Service #blueprint(api-springboot-monorepo) ===
+ Order Module
+ Reports Module

=== Order Module ===
@ apis:: list, get-by-id                     # module‑level scaffold

Order #bounded-context:Sales
=====
@ index:: orderId (unique)
@ roles:: admin, ops
* orderId : Id
* amount  : Float { min = 0 }
- status  : String  = "NEW" { pattern = ^(NEW|PAID|CANCELLED)$ }
- audit   : Audit (backend)

# APIs ["/orders"]
@ apis:: create, delete
@ list-api :: status -> status
## list by status
## cancel(id: Id) : Order (route="/orders/{id}/cancel", method=POST, roles=admin)
#

applyDiscount(percent: Float) : Order
--------------------------------------
|> IF percent <= 0
| return this
assign self.amount = amount * (1 - percent / 100)
return this
---

Order DTO (Order)
/===/
. orderId
. amount
. status

=== Reports Module ===
@ apis:: list

Sales Report (Order)
====================
* id      : Id
* month   : String
* revenue : Float

# APIs (route="/reports")
@ apis:: create
## list by month
#
```

This one file now describes:

1. **Architecture** – one container, two modules.
2. **Domain models** – `Order`, `Sales Report`, DTOs.
3. **Validation & metadata** – regex, min/max, roles, tags.
4. **API surface** – scaffolded + custom endpoints with routing.
5. **Backend‑only fields** – `audit` excluded from client DTOs.

Use it as a template: change names, tweak fields, regenerate code—done! 🚀

And that’s a wrap—go forth and ModelHike like a pro! 🎉
