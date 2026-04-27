# ModelHike Rules DSL: Declare Your Decisions

**Informed by:** DMN (Decision Model and Notation), Drools DRL, FEEL expressions, decision tables, decision trees

---

## Why Rules?

The unified Flow DSL handles state machines and orchestration. The entity DSL handles data and APIs. But the hardest 5-10% of business logic isn't flow or data. It's **decisions**: pricing, eligibility, risk scoring, routing, allocation, compliance checks, discount calculations, insurance premiums, loan approvals.

This logic currently falls through to imperative codelogic (`|> IF / |> ELSE / assign`). But decisions are fundamentally declarative: given these inputs, evaluate these conditions, produce this output. They shouldn't be coded. They should be declared.

---

## New Element: Rules Block

Rules use a `??????` underline. The `?` character literally means "question", which is what a decision answers.

```modelhike
Rule Set Name
?????????????
```

The `?` underline joins the visual family:

| Element | Underline | Suggests |
|---------|-----------|----------|
| Class | `=====` | Structure, definition |
| DTO | `/===/` | Projection, slicing |
| UIView | `~~~~` | Visual, screen |
| Flow | `>>>>>>` | Direction, progression |
| Infra | `++++++` | Infrastructure, nodes |
| **Rules** | `??????` | **Decision, question, evaluation** |

Rules blocks live inside modules, alongside classes, DTOs, and flows. Rules can also be invoked from flows using `decide @"Rule Set Name" with (inputs) -> result`.

---

## Rule Types Overview

| Type | Use when | Section |
|------|----------|---------|
| **Conditional rules** (when/then) | Simple if-this-then-that business rules | 1 |
| **Decision table** | Tabular multi-condition evaluation with hit policies | 2 |
| **Decision tree** | Nested hierarchical branching | 3 |
| **Scoring rules** | Weighted criteria evaluation producing a score | 4 |
| **Matching/filtering rules** | Multi-criteria entity matching with ranking | 5 |
| **Formula rules** | Named calculations with conditional branches | 6 |
| **Constraint rules** | Cross-entity validation beyond single-field constraints | 7 |
| **Rule composition** | Chaining decisions: output of one feeds input of another | 8 |

---

## 1. Conditional Rules (when/then)

The simplest form. Each rule has a name, a condition, and actions. Rules fire independently.

```modelhike
=== Discount Module ===

Customer Discount Rules
???????????????????????
@ input:: customer: Customer, order: Order
@ output:: discount: Float

rule loyaltyDiscount
| when: customer.yearsActive >= 5
| then: discount = 10%

rule bulkDiscount
| when: order.items.count >= 100
| then: discount = 18%

rule bulkDiscountMedium
| when: order.items.count >= 50
| then: discount = 12%

rule bulkDiscountSmall
| when: order.items.count >= 10
| then: discount = 5%

rule newCustomerWelcome
| when: customer.ordersCount == 0
| then: discount = 15%

rule noDiscount
| when: otherwise
| then: discount = 0%

priority: loyaltyDiscount > bulkDiscount > bulkDiscountMedium > bulkDiscountSmall > newCustomerWelcome > noDiscount
```

### Syntax

- `@ input::` declares what data the rule set evaluates against.
- `@ output::` declares what the rule set produces.
- `rule name` starts a rule. `|` block scoping for body.
- `| when:` is the condition (uses ModelHike expression syntax).
- `| then:` is the action (assignment, call, notify, emit, etc.).
- `| otherwise` matches when no other rule matched (default/fallback).
- `priority:` declares explicit ordering. Higher priority rules are evaluated first. First matching rule wins (unless hit policy says otherwise).

### Hit Policies

Borrowed from DMN. Declared on the rules block:

```modelhike
Customer Discount Rules
???????????????????????
@ hit:: first               -- first matching rule wins (default)
```

| Hit Policy | Meaning |
|------------|---------|
| `first` | First matching rule wins. Rules evaluated in priority order. **(Default)** |
| `unique` | Exactly one rule must match. Error if zero or multiple match. |
| `any` | Multiple rules may match but must all produce the same output. Error on conflict. |
| `collect` | All matching rules fire. Outputs collected as a list. |
| `collect sum` | All matching rules fire. Numeric outputs are summed. |
| `collect max` | All matching rules fire. Maximum output wins. |
| `collect min` | All matching rules fire. Minimum output wins. |
| `priority` | All matching rules fire. Output with highest priority wins. |

### Multi-action rules

```modelhike
rule fraudAlert
| when: order.total > 10000 && customer.country in riskCountries
| then:
| | assign risk = "HIGH"
| | notify team(Fraud), template: fraud_alert
| | emit FraudAlertRaised
| | call holdOrder(order.id)
```

`| then:` can be a single-line assignment or a `|` block with multiple actions using the same keywords as flow/codelogic.

---

## 2. Decision Tables

Tabular rules where each row is a rule. Columns are inputs and outputs. Directly inspired by DMN decision tables.

```modelhike
=== Shipping Module ===

Shipping Rate Table
???????????????????
@ hit:: first
@ input:: weight: Float, destination: String, memberTier: String
@ output:: rate: Float, carrier: String

| weight     | destination  | memberTier   || rate   | carrier     |
| ---------- | ------------ | ------------ || ------ | ----------- |
| < 1        | "DOMESTIC"   | -            || 5.99   | "USPS"      |
| 1..5       | "DOMESTIC"   | -            || 9.99   | "USPS"      |
| 5..20      | "DOMESTIC"   | -            || 14.99  | "UPS"       |
| > 20       | "DOMESTIC"   | -            || 24.99  | "UPS"       |
| < 1        | "INTL"       | -            || 15.99  | "FedEx"     |
| 1..5       | "INTL"       | -            || 29.99  | "FedEx"     |
| > 5        | "INTL"       | -            || 49.99  | "DHL"       |
| -          | "DOMESTIC"   | "PREMIUM"    || 0.00   | "UPS"       |
| -          | "INTL"       | "PREMIUM"    || 0.00   | "DHL"       |
```

### Syntax

- `||` separates input columns from output columns. Visual divider.
- `-` in a cell means "any value" (don't care / wildcard).
- `< 1`, `1..5`, `> 20` are range expressions (FEEL-inspired).
- `"DOMESTIC"` is an exact match.
- Rows are evaluated top to bottom. Hit policy determines behavior.
- The header row names match `@ input::` and `@ output::` parameters.

### Why tables matter

The shipping rate example is 9 rows. The imperative equivalent is 9 nested `if/else` branches, typically 40-60 lines. More importantly: a business user can read and modify the table without touching code.

---

## 3. Decision Trees

Hierarchical branching where each level narrows the decision. Uses a visual tree syntax inspired by the `tree` command's folder output. The tree IS the visual. Every branch, every leaf, the shape of the decision is the shape of the text.

### Syntax Mapping (folder tree -> decision tree)

| Folder tree | Decision tree |
|-------------|---------------|
| `├── subfolder/` | `├──[ condition` (branching condition, has siblings) |
| `└── subfolder/` | `└──[ condition` (last branch at this level) |
| `│` | `│` (vertical continuation line) |
| `├── file.txt` | `├── action` (leaf: set a value, one-liner) |
| Multi-line file content | `├── action` + `│  \| block` for multi-line actions |

Rules:

- `├──[` and `└──[` open condition branches (the `[` signals opening a guard). No closing bracket needed; the condition runs to end of line.
- Lines without `[` are leaf actions (assignments, calls, etc.).
- Multi-line action blocks use `|` prefix under the leaf.
- The ruleset header (`??????`) is the root. No root folder line needed.
- Indent depth = tree depth. Standard `│   ` prefix for continuation.

### Before / After: Loan Eligibility

The same logic as deeply nested if-else versus the visual tree:

**Old (codelogic if-else):**

```
|> IF applicant.creditScore >= 750
| |> IF loanAmount <= 500000
| | decision = "APPROVED", maxAmount = 500000, rate = 3.5%
| |> ELSE
| | decision = "REFER", maxAmount = 500000, rate = 4.0%
|> ELSEIF applicant.creditScore >= 650
| |> IF applicant.debtToIncome < 0.36
| | |> IF loanAmount <= 300000
...
```

**New (visual tree):**

```modelhike
=== Lending Module ===

Loan Eligibility Tree
?????????????????????
@ input:: applicant: Applicant, loanAmount: Float
@ output:: decision: String, maxAmount: Float, rate: Float

├──[ applicant.creditScore >= 750
│   ├──[ loanAmount <= 500000
│   │   └── decision = "APPROVED", maxAmount = 500000, rate = 3.5%
│   └──[ loanAmount > 500000
│       └── decision = "REFER", maxAmount = 500000, rate = 4.0%
├──[ applicant.creditScore >= 650
│   ├──[ applicant.debtToIncome < 0.36
│   │   ├──[ loanAmount <= 300000
│   │   │   └── decision = "APPROVED", maxAmount = 300000, rate = 5.0%
│   │   └──[ loanAmount > 300000
│   │       └── decision = "DENIED", maxAmount = 300000, rate = 0
│   └──[ applicant.debtToIncome >= 0.36
│       └── decision = "DENIED", maxAmount = 0, rate = 0
├──[ applicant.creditScore >= 500
│   ├──[ applicant.hasCoSigner
│   │   └── decision = "APPROVED", maxAmount = 100000, rate = 8.5%
│   └──[ !applicant.hasCoSigner
│       └── decision = "DENIED", maxAmount = 0, rate = 0
└──[ otherwise
    └── decision = "DENIED", maxAmount = 0, rate = 0
```

You can literally see the tree. Every branch. Every leaf. The shape of the decision is the shape of the text.

### When a leaf needs multiple actions

```modelhike
Fraud Response Tree
???????????????????
@ input:: transaction: Transaction, customer: Customer
@ output:: action: String, riskLevel: String

├──[ transaction.amount > 50000 && customer.country in highRiskCountries
│   └── action = "BLOCK", riskLevel = "CRITICAL"
│       | notify team(Fraud), template: fraud_critical
│       | call holdTransaction(transaction.id)
│       | emit FraudAlertCritical
├──[ transaction.amount > 10000 && customer.accountAge < 30.days
│   └── action = "REVIEW", riskLevel = "HIGH"
│       | notify team(Fraud), template: fraud_review
│       | call flagForManualReview(transaction.id)
├──[ transaction.velocity > 5.perHour
│   └── action = "THROTTLE", riskLevel = "MEDIUM"
│       | call applyRateLimit(customer.id)
└──[ otherwise
    └── action = "ALLOW", riskLevel = "LOW"
```

The `|` block under a leaf contains additional side effects. Same `|` scoping convention as everywhere else in ModelHike.

### Two-level branching (Tax Bracket example)

When the decision branches on one field, then on a second field inside each branch, the tree makes the hierarchy explicit. A decision table would also work, but the tree communicates "first determine filing status, THEN determine bracket." A table treats all inputs as equal:

```modelhike
Tax Bracket Rules
?????????????????
@ input:: income: Float, filingStatus: String
@ output:: taxRate: Float, bracket: String

├──[ filingStatus == "SINGLE"
│   ├──[ income <= 11000
│   │   └── taxRate = 10%, bracket = "10%"
│   ├──[ income <= 44725
│   │   └── taxRate = 12%, bracket = "12%"
│   ├──[ income <= 95375
│   │   └── taxRate = 22%, bracket = "22%"
│   ├──[ income <= 182100
│   │   └── taxRate = 24%, bracket = "24%"
│   ├──[ income <= 231250
│   │   └── taxRate = 32%, bracket = "32%"
│   ├──[ income <= 578125
│   │   └── taxRate = 35%, bracket = "35%"
│   └──[ income > 578125
│       └── taxRate = 37%, bracket = "37%"
└──[ filingStatus == "MARRIED_JOINTLY"
    ├──[ income <= 22000
    │   └── taxRate = 10%, bracket = "10%"
    ├──[ income <= 89450
    │   └── taxRate = 12%, bracket = "12%"
    ├──[ income <= 190750
    │   └── taxRate = 22%, bracket = "22%"
    └──[ income > 190750
        └── taxRate = 24%, bracket = "24%"
```

### Flat conditions (replacing overkill if-else)

When there's only one level of branching and each branch just sets values, the tree is cleaner than `|> IF / |> ELSEIF`:

```modelhike
Support Tier Routing
????????????????????
@ input:: customer: Customer
@ output:: queue: String, sla: Duration

├──[ customer.tier == "ENTERPRISE"
│   └── queue = "enterprise-support", sla = 1 hour
├──[ customer.tier == "PRO"
│   └── queue = "priority-support", sla = 4 hours
├──[ customer.tier == "FREE" && customer.accountAge > 1.year
│   └── queue = "standard-support", sla = 24 hours
└──[ otherwise
    └── queue = "general-queue", sla = 48 hours
```

Four branches of visual tree vs ~12 lines of `|> IF / |> ELSEIF / |> ELSE`. The structure is instant.

### Tree vs Table vs Conditional Rules vs If-Else

| Pattern | Use when |
|---------|----------|
| **Decision table** | Multiple input columns combine to determine output. Conditions are orthogonal (any combo possible). |
| **Decision tree** | Conditions are hierarchical. You branch on one thing, then branch again inside that branch. The "shape" of the decision matters. |
| **Conditional rules** (when/then) | Independent rules with priority. Rules don't nest; they compete. |
| **Simple if-else** (`\|> IF`) | Inside codelogic method bodies or flow blocks where you need imperative control flow, not a named reusable decision. |

The key signal: **if the conditions are nested/hierarchical, use a tree. If the conditions are flat/orthogonal, use a table.**

Use the **tree** when conditions are hierarchical (branch on one thing, then branch again 
inside that branch). Use a **decision table** when conditions are flat/orthogonal (any 
combination of inputs maps to an output). Use **`|> IF`** inside codelogic method bodies or 
flow blocks for imperative control flow, not named reusable decisions.

### Parser Notes

Tree characters used by the parser:

- `├` (U+251C, BOX DRAWINGS LIGHT VERTICAL AND RIGHT)
- `└` (U+2514, BOX DRAWINGS LIGHT UP AND RIGHT)
- `│` (U+2502, BOX DRAWINGS LIGHT VERTICAL)
- `─` (U+2500, BOX DRAWINGS LIGHT HORIZONTAL)

The parser looks for:

1. `├──[` or `└──[` at any indent level = condition node (branch).
2. `├──` or `└──` without `[` = leaf node (action).
3. `│` at line start = vertical continuation (skip during parsing, used for visual alignment).
4. `|` after a leaf = multi-line action block (same `|` convention as rest of ModelHike).

Condition nodes gather their children (deeper-indented lines) until the next sibling at the same depth or the end of the tree.

The `[` on condition lines is NOT closed. This is intentional. Closing brackets would add visual noise and the condition naturally terminates at end-of-line. This mirrors how ModelHike's `{ constraints }` work on property lines.

### ASCII Fallback

For environments that can't render box-drawing characters, an ASCII equivalent is accepted by the parser:

```
+--[ applicant.creditScore >= 750
|   +--[ loanAmount <= 500000
|   |   \-- decision = "APPROVED", rate = 3.5%
|   \--[ loanAmount > 500000
|       \-- decision = "REFER", rate = 4.0%
\--[ otherwise
    \-- decision = "DENIED", rate = 0
```

`+--[` for branch, `\--` for last branch/leaf, `|` for continuation. The parser accepts both box-drawing and ASCII forms.

---

## 4. Scoring Rules

Weighted criteria evaluation that produces a numeric score. Used for risk assessment, lead scoring, credit scoring, matching quality.

```modelhike
=== Risk Module ===

Customer Risk Score
???????????????????
@ input:: customer: Customer, order: Order
@ output:: riskScore: Int, riskLevel: String
@ score:: range 0..100

score transactionSize
| when: order.total > 50000
| points: 30
| when: order.total > 10000
| points: 15
| when: order.total > 1000
| points: 5

score countryRisk
| when: customer.country in highRiskCountries
| points: 25
| when: customer.country in mediumRiskCountries
| points: 10

score accountAge
| when: customer.createdAt < 30.days.ago
| points: 20
| when: customer.createdAt < 90.days.ago
| points: 10

score velocityCheck
| when: customer.ordersLast24h > 10
| points: 25
| when: customer.ordersLast24h > 5
| points: 15

classify riskLevel
| when: riskScore >= 70 -> "CRITICAL"
| when: riskScore >= 40 -> "HIGH"
| when: riskScore >= 20 -> "MEDIUM"
| otherwise             -> "LOW"
```

### Syntax

- `score name` declares a scoring criterion. Multiple `| when: / | points:` pairs within.
- All matching score rules contribute points (additive by default).
- `@ score:: range 0..100` caps the total score.
- `classify` maps the final score to a category using threshold ranges.
- The blueprint emits a function that evaluates all criteria, sums points, classifies, and returns the result.

---

## 5. Matching/Filtering Rules

Multi-criteria entity matching with filtering, scoring, and ranking. For recommendations, assignment, eligibility matching.

```modelhike
=== Clinical Module ===

Trial Match Rules
?????????????????
@ input:: patient: Patient
@ output:: matches: Trial[]
@ source:: Trial where status == "RECRUITING"

filter
| include: patient.age in trial.ageRange
| include: patient.diagnosis in trial.diagnosisCodes
| exclude: patient.medications intersects trial.excludedMedications
| include: distance(patient.location, trial.siteLocation) <= trial.maxRadiusKm

rank
| by: trial.capacityRemaining / trial.capacityTotal desc    -- prefer trials with more spots
| by: distance(patient.location, trial.siteLocation) asc    -- prefer closer trials
| by: trial.phase desc                                       -- prefer later-phase trials

limit: 5
```

### Syntax

- `@ source::` declares the collection to match against (with optional filter).
- `filter` block: `| include:` keeps entities matching the condition. `| exclude:` removes them.
- `rank` block: `| by:` expressions with `asc` or `desc`. Multiple criteria in priority order.
- `limit:` caps the number of results.

### Another example: Ticket Assignment

```modelhike
Ticket Assignment Rules
???????????????????????
@ input:: ticket: SupportTicket
@ output:: assignee: Agent
@ source:: Agent where status == "ONLINE"

filter
| include: ticket.skillRequired in agent.skills
| include: agent.currentLoad < agent.maxLoad
| include: overlap(ticket.timezone, agent.timezone) >= 4    -- at least 4 hours overlap

rank
| by: relevance(ticket.skillRequired, agent.skills) desc    -- best skill match first
| by: agent.currentLoad asc                                  -- least loaded first
| by: agent.avgResolutionTime asc                            -- fastest resolver first

limit: 1
```

---

## 6. Formula Rules

Named calculations with conditional branches. For pricing, tax, premium calculations, derived values.

```modelhike
=== Insurance Module ===

Premium Calculation
???????????????????
@ input:: applicant: Applicant, coverage: CoverageSelection
@ output:: monthlyPremium: Float

= basePremium : Float
|> IF applicant.age < 30
| basePremium = 150.00
|> ELSEIF applicant.age < 50
| basePremium = 250.00
|> ELSEIF applicant.age < 65
| basePremium = 400.00
|> ELSE
| basePremium = 650.00

= coverageMultiplier : Float
| "BASIC"    -> 1.0
| "STANDARD" -> 1.5
| "PREMIUM"  -> 2.2
| "PLATINUM" -> 3.0
| using: coverage.level

= riderAdjustment : Float = sum(coverage.riders, rider ->
| "DENTAL"   -> 25.00
| "VISION"   -> 15.00
| "MENTAL"   -> 35.00
| "WELLNESS" -> 20.00
)

= smokerSurcharge : Float
|> IF applicant.smoker
| smokerSurcharge = basePremium * 0.40
|> ELSE
| smokerSurcharge = 0

= regionFactor : Float
| lookup: regionRateTable(applicant.state)

monthlyPremium = (basePremium * coverageMultiplier + riderAdjustment + smokerSurcharge) * regionFactor
```

### Syntax

- `= name : Type` declares an intermediate calculation (reuses ModelHike's calculated field syntax).
- `|> IF / |> ELSE` for conditional assignment (reuses codelogic).
- `| "VALUE" -> result` is a lookup/mapping table (inline decision table for a single input).
- `| using: field` specifies which input the mapping table evaluates against.
- `| lookup: table(key)` references an external lookup table or formula.
- The final line is the output formula combining all intermediates.
- Formulas are pure: no side effects, no state mutation. Just inputs to output.

---

## 7. Constraint Rules (Cross-Entity Validation)

Validation that spans multiple entities, aggregates, or temporal conditions. Beyond what single-field `{ constraints }` can express.

```modelhike
=== HR Module ===

PTO Booking Constraints
???????????????????????
@ input:: employee: Employee, request: PTORequest
@ output:: allowed: Boolean, reason: String

constraint noBlackout
| -- Cannot book PTO during company blackout periods
| when: request.dates overlaps companyCalendar.blackoutDates
| reject: "Requested dates fall within a company blackout period"

constraint noConflict
| -- Cannot conflict with mandatory meetings
| when: request.dates overlaps employee.mandatoryMeetings
| reject: "Conflicts with mandatory meeting on {overlap.date}"

constraint minimumStaffing
| -- Team must maintain minimum staffing
| when: countAvailable(employee.team, request.dates) < employee.team.minStaffing
| reject: "Team would fall below minimum staffing of {employee.team.minStaffing}"

constraint allocationRemaining
| -- Cannot exceed annual allocation
| when: employee.ptoUsedThisYear + request.days > employee.annualPTOAllowance
| reject: "Would exceed annual PTO allowance ({employee.annualPTOAllowance - employee.ptoUsedThisYear} days remaining)"

constraint advanceNotice
| -- Must book at least N days in advance
| when: request.startDate - today() < employee.team.minAdvanceNoticeDays
| reject: "Must book at least {employee.team.minAdvanceNoticeDays} days in advance"

// If all constraints pass:
allowed = true
```

### Syntax

- `constraint name` declares a named constraint rule.
- `| when:` is the violation condition (when this is true, the constraint is violated).
- `| reject:` is the rejection message (supports `{interpolation}`).
- All constraints are evaluated (unlike conditional rules which short-circuit on first match). Every violation is collected.
- The output `allowed` is true only if no constraint fires.
- The blueprint emits a validator that returns all violations, not just the first.

---

## 8. Rule Composition (Decision Chains)

Large decisions are composed of smaller decisions. The output of one feeds the input of another. Inspired by DMN Decision Requirements Diagrams (DRDs).

```modelhike
=== Lending Module ===

// Individual decision components

Credit Assessment
?????????????????
@ input:: applicant: Applicant
@ output:: creditGrade: String, creditLimit: Float
// ... (rules inside)

Affordability Check
???????????????????
@ input:: applicant: Applicant, loanAmount: Float, creditLimit: Float
@ output:: affordable: Boolean, maxMonthlyPayment: Float
// ... (rules inside)

Fraud Risk Score
????????????????
@ input:: applicant: Applicant, loanAmount: Float
@ output:: riskScore: Int, riskLevel: String
// ... (scoring rules inside)

// Composed decision

Loan Decision
?????????????
@ input:: applicant: Applicant, loanAmount: Float
@ output:: decision: String, rate: Float, conditions: String[]

// Chain: credit -> affordability -> fraud -> final decision
decide @"Credit Assessment" with (applicant) -> creditResult
decide @"Affordability Check" with (applicant, loanAmount, creditResult.creditLimit) -> affordResult
decide @"Fraud Risk Score" with (applicant, loanAmount) -> fraudResult

|> IF fraudResult.riskLevel == "CRITICAL"
| decision = "DENIED", rate = 0, conditions = ["Fraud risk too high"]
|> ELSEIF !affordResult.affordable
| decision = "DENIED", rate = 0, conditions = ["Fails affordability check"]
|> ELSEIF creditResult.creditGrade == "A"
| decision = "APPROVED", rate = 3.5%, conditions = []
|> ELSEIF creditResult.creditGrade == "B"
| decision = "APPROVED", rate = 5.5%, conditions = ["Requires collateral"]
|> ELSEIF creditResult.creditGrade == "C"
| decision = "CONDITIONAL", rate = 8.0%, conditions = ["Requires co-signer", "Max 60-month term"]
|> ELSE
| decision = "DENIED", rate = 0, conditions = ["Credit grade too low"]
```

### Syntax

- `decide @"Rule Set Name" with (inputs) -> result` invokes another rule set. Same pattern as `run @"Flow Name"` in the flow DSL.
- Results are bound to variables and used in subsequent decisions.
- The final block uses `|> IF` to produce the output from the composed results.
- The blueprint generates a Decision Requirements Diagram (DRD) from the `decide` chain.

---

## Invoking Rules from Flows

Rules can be called from within `>>>>>>` flow blocks:

```modelhike
Loan Application Flow
>>>>>>>>>>>>>>>>>>>>>

// ...

==> Step 1: Evaluate Application

decide @"Loan Decision" with (applicant, amount) -> loanResult

|> IF loanResult.decision == "DENIED"
| \__ SUBMITTED -> REJECTED : deny {denialReason = loanResult.conditions[0]}
|> ELSEIF loanResult.decision == "CONDITIONAL"
| \__ SUBMITTED -> CONDITIONAL_APPROVAL : conditionalApprove
| system ~~> Applicant : notify(conditional_approval, loanResult.conditions)
|> ELSE
| \__ SUBMITTED -> APPROVED : approve
end
```

`decide @"Name"` works like `run @"Name"` but calls a rules block instead of a flow block. The difference: `run` triggers orchestration (may involve waits, participants, async). `decide` is synchronous evaluation: inputs in, output out, no side effects beyond the output.

---

## Invoking Rules from Lifecycle Entry/Exit

Rules can also be called from state entry actions:

```modelhike
state SUBMITTED
| entry / decide @"Fraud Risk Score" with (applicant, amount) -> fraudResult
| entry / emit ApplicationSubmitted
```

---

## Rules vs Codelogic vs Flow

| Concern | Rules (`??????`) | Flow (`>>>>>>`) | Codelogic (`---` / `` ``` ``) |
|---------|---------|------|-----------|
| **Purpose** | Evaluate inputs, produce output | Orchestrate sequences across participants | Implement imperative method bodies |
| **Side effects?** | No (pure evaluation) | Yes (state changes, notifications, waits) | Yes (DB writes, HTTP calls) |
| **Duration** | Instant (single evaluation) | Minutes to days | Single method call |
| **Reusable?** | Via `decide @"Name"` | Via `run @"Name"` | Via `call` |
| **Who reads it?** | Business analysts, compliance | Product managers, ops | Developers |
| **Generates** | Rule engine config, validator, scorer | State machine, orchestrator | Target-language method |

---

## Hit Policy Visual Reference

```
@ hit:: first      -- Stop at first match (default)
@ hit:: unique     -- Exactly one rule must match
@ hit:: any        -- Multiple may match; must agree on output
@ hit:: collect    -- All matches collected as list
@ hit:: collect sum  -- All matches summed
@ hit:: collect max  -- Maximum of all matches
@ hit:: collect min  -- Minimum of all matches
@ hit:: priority   -- All matches; highest-priority output wins
```

---

## Comprehensive Example: E-Commerce Pricing Engine

```modelhike
=== Pricing Module ===

// ---- Lookup: Contract rates ----

Contract Rate Lookup
????????????????????
@ input:: customer: Customer, product: Product
@ output:: contractRate: Float?

| customer.tier | product.category || contractRate |
| ------------- | ---------------- || ------------ |
| "ENTERPRISE"  | "COMPUTE"        || 0.85         |
| "ENTERPRISE"  | "STORAGE"        || 0.80         |
| "ENTERPRISE"  | "NETWORK"        || 0.90         |
| "STRATEGIC"   | -                || 0.75         |
| -             | -                || nil          |

// ---- Scoring: Discount eligibility ----

Discount Score
??????????????
@ input:: customer: Customer, order: Order
@ output:: discountScore: Int
@ score:: range 0..100

score volume
| when: order.items.count >= 100
| points: 40
| when: order.items.count >= 50
| points: 25
| when: order.items.count >= 20
| points: 10

score loyalty
| when: customer.yearsActive >= 10
| points: 30
| when: customer.yearsActive >= 5
| points: 20
| when: customer.yearsActive >= 2
| points: 10

score annualSpend
| when: customer.annualSpend >= 1000000
| points: 30
| when: customer.annualSpend >= 500000
| points: 20
| when: customer.annualSpend >= 100000
| points: 10

// ---- Conditional: Discount tiers from score ----

Discount Tier Rules
???????????????????
@ input:: discountScore: Int
@ output:: discountPercent: Float
@ hit:: first

rule platinumDiscount
| when: discountScore >= 80
| then: discountPercent = 25%

rule goldDiscount
| when: discountScore >= 60
| then: discountPercent = 18%

rule silverDiscount
| when: discountScore >= 40
| then: discountPercent = 12%

rule bronzeDiscount
| when: discountScore >= 20
| then: discountPercent = 5%

rule noDiscount
| when: otherwise
| then: discountPercent = 0%

// ---- Constraint: Price floor ----

Price Floor Constraints
???????????????????????
@ input:: lineItems: LineItem[], proposedTotal: Float
@ output:: allowed: Boolean, adjustedTotal: Float

constraint aboveCost
| when: proposedTotal < sum(lineItems.costPrice) * 1.15
| reject: "Price below cost-plus-15% floor"

adjustedTotal = max(proposedTotal, sum(lineItems.costPrice) * 1.15)
allowed = true

// ---- Composed: Final price ----

Order Pricing
?????????????
@ input:: customer: Customer, order: Order
@ output:: finalTotal: Float, discountApplied: Float, pricingNotes: String[]

decide @"Contract Rate Lookup" with (customer, order.items[0].product) -> contractResult
decide @"Discount Score" with (customer, order) -> scoreResult
decide @"Discount Tier Rules" with (scoreResult.discountScore) -> tierResult

|> IF contractResult.contractRate != nil
| -- Contract rate takes precedence over discount tiers
| assign finalTotal = order.subtotal * contractResult.contractRate
| assign discountApplied = 1.0 - contractResult.contractRate
| assign pricingNotes = ["Contract rate applied"]
|> ELSE
| assign finalTotal = order.subtotal * (1.0 - tierResult.discountPercent)
| assign discountApplied = tierResult.discountPercent
| assign pricingNotes = ["Discount tier: " + tierResult.discountPercent + "%"]

decide @"Price Floor Constraints" with (order.items, finalTotal) -> floorResult

|> IF !floorResult.allowed
| assign finalTotal = floorResult.adjustedTotal
| assign pricingNotes = pricingNotes + ["Adjusted to price floor"]
```

### What this demonstrates

1. **Four rule types composed together.** Decision table (Contract Rate Lookup), scoring (Discount Score), conditional rules (Discount Tier Rules), constraints (Price Floor), and a composed decision (Order Pricing) that chains them all.
2. **A business analyst can read every rule set.** The Contract Rate table is literally a table. The scoring criteria are named and pointed. The discount tiers are thresholds. The constraint is a named guardrail.
3. **`decide @"Name"` chains decisions.** Order Pricing calls four sub-decisions in sequence, threading outputs to inputs. The blueprint generates a Decision Requirements Diagram (DRD) from this chain.
4. **No imperative code.** The entire pricing engine: contract negotiation, volume scoring, loyalty evaluation, tier resolution, floor enforcement. All declarative. All auditable. All modifiable by non-developers.
5. **This replaces ~300 lines of service code** in a typical `PricingService.calculateOrderPrice()` method that nobody wants to touch because changing one condition might break three others.

---

## What the Blueprint Emits

| Rule type | Output |
|-----------|--------|
| Conditional rules | Rule engine config (Drools DRL, or native if/else chain with priority ordering) |
| Decision table | Table evaluator with hit policy enforcement |
| Decision tree | Nested evaluator with path tracing for audit |
| Scoring rules | Score calculator with per-criterion breakdown |
| Matching rules | Filter + rank pipeline with result limiting |
| Formula rules | Pure function with intermediate calculations |
| Constraint rules | Validator returning all violations (not just first) |
| Rule composition | Orchestrator calling sub-decisions in order, with DRD diagram |

All rule types also generate:
- **Audit trail**: which rules fired, with what inputs, producing what outputs
- **Test scaffolding**: one test case per rule, with boundary values
- **Documentation**: human-readable rule catalog per module
- **DMN export** (optional): for organizations using DMN-compliant tools

---

## Updated Coverage Assessment

| Layer | Coverage | What handles it |
|-------|----------|-----------------|
| Structure (schema, API, CRUD, mapping) | 100% declarative | Entity + DTO + `# APIs` + `@ apis::` |
| Flow (state machines, workflows, approvals) | 100% declarative | `>>>>>>` unified flow DSL |
| Cross-cutting (auth, audit, cache, i18n, etc.) | 100% declarative | `@ annotations` + tags + mixins |
| **Business rules (pricing, eligibility, allocation)** | **100% declarative** | **`??????` rules DSL** |
| Genuinely imperative (novel algorithms, perf-critical) | Imperative escape hatch | Codelogic `---` / `` ``` `` |

**The remaining imperative slice is now ~2-3%.** Novel algorithms (custom sort, graph traversal, ML inference). Performance-critical hot paths. Hardware-specific optimizations. Things where the "how" IS the value.

Everything else: **Declare your entire app.**
