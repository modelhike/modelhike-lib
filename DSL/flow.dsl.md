# ModelHike Flow DSL Guide

**Underline:** `>>>>>>`
**Purpose:** Declare state machines, workflows, and orchestrated processes. One syntax for both lifecycle (reactive state transitions) and workflow (orchestrated multi-step sequences). Use them separately or together.

---

## When to Use This DSL

| You need... | Use flow in... | Example |
|-------------|---------------|---------|
| Entity states and transitions | Lifecycle mode | Order: DRAFT -> SUBMITTED -> APPROVED |
| Multi-step process across participants | Workflow mode | Loan application: check credit, assign reviewer, wait for decision |
| States AND orchestration together | Unified mode | Approval chain with formal states AND participant interactions |

---

## Quick Start: Pure Lifecycle

Just states and transitions. No participants, no arrows.

```modelhike
Order Lifecycle
>>>>>>>>>>>>>>>

state DRAFT
| -- Order being composed.

state SUBMITTED
| entry / capture submittedAt = now()
| entry / emit OrderSubmitted

state APPROVED
| entry / emit OrderApproved
| entry / notify submittedBy, template: order_approved
| terminal

[*] --> DRAFT

\__ DRAFT -> SUBMITTED : submit {items.count > 0} [any]
| api POST /orders/{id}/submit

\__ SUBMITTED -> APPROVED : approve {currentUser() != submittedBy} [finance]
| api POST /orders/{id}/approve

APPROVED --> [*]
```

## Quick Start: Pure Workflow

Just orchestration. No formal states.

```modelhike
Credit Check Flow
>>>>>>>>>>>>>>>>>

[CreditBureau] as external
[FraudService] as service

system --> CreditBureau : pullReport(applicant.ssn)
CreditBureau <-- system : creditReport

system --> FraudService : screen(applicant)
FraudService <-- system : fraudResult

|> IF fraudResult.flagged
| \__ CURRENT -> REJECTED : fraudBlock
end

return creditReport
```

## Quick Start: Unified (Both)

States with entry actions AND orchestration arrows in one block.

```modelhike
Loan Application Flow
>>>>>>>>>>>>>>>>>>>>>

state SUBMITTED
| entry / emit ApplicationSubmitted

state APPROVED
| entry / emit ApplicationApproved
| terminal

[Underwriter] as human

[*] --> SUBMITTED

wait Underwriter : review(application) -> decision
| @ sla:: 3 business days

|> IF decision.approved
| \__ SUBMITTED -> APPROVED : approve
end
```

---

## Part 1: States

### Declaring a State

```modelhike
state NAME
| -- Description text.
| entry / action
| exit / action
| terminal
| after DURATION --> TARGET : event
| every DURATION --> self : event
```

### Entry and Exit Actions

`entry /` runs on ANY transition that enters this state. `exit /` runs on ANY transition that leaves it. This eliminates duplication: if three transitions all lead to APPROVED, the notification fires once from the state, not three times on three transitions.

Available actions after `entry /` and `exit /`:

| Action | Purpose | Example |
|--------|---------|---------|
| `capture` | Stamp fields | `entry / capture approvedAt = now()` |
| `emit` | Publish domain event | `entry / emit OrderApproved` |
| `notify` | Send notification | `entry / notify customer, template: approved` |
| `require` | Validate required input | `entry / require rejectionReason` |
| `run` | Trigger a flow | `entry / run @"Fulfillment Flow" with (order)` |
| `decide` | Evaluate rules | `entry / decide @"Risk Score" with (order) -> risk` |
| `call` | Call a service | `entry / call auditService.log(...)` |

### Terminal States

```modelhike
state CANCELLED
| entry / emit OrderCancelled
| terminal
```

Or using `[*]` notation:

```modelhike
CANCELLED --> [*]
```

Both are valid. `terminal` on the state is more self-documenting. `[*]` is PlantUML-compatible.

### Initial State

```modelhike
[*] --> DRAFT
```

`[*]` is the start pseudo-state. Exactly one per top-level flow (or one per composite state / parallel region).

### Timed Transitions

```modelhike
state PENDING_PAYMENT
| entry / notify customer, template: payment_reminder
| after 1 hour --> CANCELLED : paymentTimeout
```

`after DURATION --> STATE : event` fires automatically after the entity has been in this state for the specified time. The blueprint emits a scheduler.

### Recurring Actions

```modelhike
state OVERDUE
| entry / emit InvoiceOverdue
| every 7 days --> self : reminderCycle
| | notify customer, template: overdue_reminder
```

`every DURATION --> self : event` triggers a self-transition at a recurring interval. The `|` block under it contains the actions.

Duration formats: `30 seconds`, `15 minutes`, `1 hour`, `7 days`, `3 business days`.

---

## Part 2: Transitions

### Basic Syntax

```
\__ FROM -> TO : eventName {guard} [roles]
| api METHOD /route
| action lines
```

- `\__` prefix: parser signal for a transition
- `FROM -> TO`: state change
- `: eventName`: semantic trigger (the contract)
- `{guard}`: precondition in curly braces (matches ModelHike constraints)
- `[roles]`: access control in square brackets (matches ModelHike attributes)

### Transition Body

Lines after `\__` starting with `|` belong to the transition:

```modelhike
\__ SUBMITTED -> CANCELLED : cancel [admin]
| run @"Refund Flow" with (order)
| call inventoryService.release(order.items)
| api POST /orders/{id}/cancel
```

- `| api METHOD /route`: HTTP binding
- `| run @"Flow" with (params)`: trigger a flow
- `| decide @"Rules" with (inputs) -> result`: evaluate rules
- `| call service.method()`: call a function
- `| notify recipient, template: name`: transition-specific notification
- `| emit EventName`: transition-specific event

### When to Put Actions on State vs Transition

| Action belongs on STATE (`entry /`) when... | Action belongs on TRANSITION (`\|`) when... |
|--------------------------------------------|---------------------------------------------|
| It happens every time you ENTER that state | It happens only on THIS specific path |
| Multiple transitions lead to the same state | Only one transition triggers it |
| Example: "notify customer when order is approved" | Example: "release inventory when cancelling from SUBMITTED" |

### Self-Transitions

```modelhike
\__ OVERDUE -> OVERDUE : sendReminder
| internal
| notify customer, template: overdue_reminder
```

`\__ A -> A` is a self-transition. `| internal` means don't re-execute `entry /` and `exit /`. Without `internal`, it's an external self-transition that re-triggers them.

---

## Part 3: Arrows (Workflow Mode)

### Arrow Types

| Arrow | Meaning | When to use |
|-------|---------|-------------|
| `-->` | Synchronous call (I wait for response) | Service calls, DB queries |
| `~~>` | Async / fire-and-forget | Notifications, event publishing |
| `<--` | Response / return | Response from a sync call |

```modelhike
system --> CreditService : checkCredit(applicant.id)
CreditService <-- system : creditResult

system ~~> Applicant : notify(loan_approved)
```

### Participants

```modelhike
[Applicant] as actor
[CreditBureau] as external
[Underwriter] as human
[PaymentGateway] as service
[OrderDB] as database
[OrderEvents] as queue
```

Brackets `[Name]` create a visual node. `as type` declares the participant kind. Types: `actor`, `human`, `service`, `external`, `database`, `queue`, `system`.

### Human Tasks (wait)

```modelhike
wait Underwriter : review(application) -> decision
| @ sla:: 3 business days
| @ escalate:: after 2 business days -> notify(underwriter.manager)
| @ escalate:: after 3 business days -> reassign(underwriter.manager)
| @ delegate:: to direct_reports
```

`wait` suspends the flow for a human action. Result bound after `->`. Annotations on `|` lines declare SLA, escalation, and delegation policies.

### Sub-flow Calls

```modelhike
run @"Credit Check Flow" with (applicant) -> creditReport
```

Calls a named sub-flow, passes params, binds result. Use for reusable operations.

```modelhike
decide @"Risk Score" with (customer, order) -> riskResult
```

Calls a named rule set. Use for decision evaluation. `decide` is synchronous and pure (no side effects). `run` may involve waits, state changes, and participants.

### Return

```modelhike
return creditReport
```

Exits a sub-flow and passes value back to the caller's `-> variable` binding.

---

## Part 4: Branching

### If / Else (reuses codelogic)

```modelhike
|> IF creditReport.score < 600
| \__ CURRENT -> REJECTED : failCredit
| system ~~> Applicant : notify(loan_rejected)
|> ELSE
| \__ CURRENT -> UNDER_REVIEW : passCredit
end
```

`|> IF / |> ELSE / end`. Same syntax as codelogic. `|` block lines are the branch body. `\__ CURRENT -> STATE` transitions from whatever state the flow is currently in.

### When to use `|> IF` vs transition guard

| Use `{guard}` on `\__` when... | Use `|> IF` when... |
|-------------------------------|---------------------|
| Simple yes/no gate on a single transition | Multiple things happen inside the branch |
| `\__ A -> B : event {condition}` | Branch contains transitions, arrows, notifications |
| The transition either fires or doesn't | Different branches lead to different states |

---

## Part 5: Parallel

### Syntax (same for lifecycle and workflow)

```modelhike
--- Credit Check ---
| system --> CreditBureau : pullReport(applicant.ssn)
| CreditBureau <-- system : creditReport

--- Fraud Screening ---
| system --> FraudService : screen(applicant)
| FraudService <-- system : fraudResult

---
-- Both complete before continuing
```

- `--- Name ---` opens a parallel region
- `|` prefixed lines are the region body
- `---` without a name is the **join point**: execution continues only after ALL regions complete

### Parallel in Lifecycle (State Regions)

```modelhike
state ACTIVE
| parallel
|
| --- Payment ---
| | [*] --> UNPAID
| | \__ UNPAID -> CAPTURED : capture
| | | api POST /orders/{id}/capture
|
| --- Fulfillment ---
| | [*] --> PICKING
| | \__ PICKING -> SHIPPED : ship
| | | api POST /orders/{id}/ship
|
| ---
```

`| parallel` on a state means its body contains `--- Name ---` regions that advance independently.

---

## Part 6: Step Dividers

```modelhike
==> Step 1: Credit Screening

==> Step 2: Assign Underwriter

==> Step 3: Review
```

`==>` marks workflow phases. Cannot be confused with `=== Module ===`. The fat arrow suggests forward progress. Blueprints can emit stage-level metrics, logging, and progress tracking from these.

---

## Part 7: Composite States

```modelhike
state ACTIVE
| -- Contains sub-states
| [*] --> PROCESSING
|
| state PROCESSING
| | entry / emit OrderProcessing
|
| state SHIPPING
| | entry / emit OrderShipped
|
| state DELIVERED
| | terminal
|
| \__ PROCESSING -> SHIPPING : ship
| \__ SHIPPING -> DELIVERED : deliver
```

Nested `|` depth for sub-states. Outer `|` = inside composite. Inner `| |` = inside sub-state. Transitions inside the composite scope operate on sub-states.

### History States

```modelhike
state ACTIVE
| [*] --> PROCESSING
| [H] --> history
|
| state PROCESSING
| state SHIPPING

\__ ACTIVE -> SUSPENDED : suspend [admin]
\__ SUSPENDED -> ACTIVE : resume [admin]
| -- Resumes at [H]: last active sub-state
```

`[H]` for shallow history (remembers last direct child). `[H*]` for deep history (remembers full nesting depth).

---

## Part 8: How Lifecycle and Workflow Relate

| Aspect | Lifecycle Mode | Workflow Mode | Unified Mode |
|--------|---------------|---------------|--------------|
| Has `state` blocks? | Yes | No | Yes |
| Has `\__` transitions? | Yes (primary) | Yes (within flow) | Yes |
| Has participants / arrows? | No | Yes | Yes |
| Has `wait` / SLA? | No | Yes | Yes |
| Has `entry /` / `exit /`? | Yes | No | Yes |
| Has `--- parallel ---`? | Yes (regions) | Yes (activities) | Yes |
| Parser signal | `state` keyword | `[Name] as type` | Both present |

**You don't choose lifecycle OR workflow.** You start with whichever you need, and add the other dimension when the domain calls for it. A pure lifecycle can grow into a unified flow. A pure workflow can add formal states. The syntax supports all three.

---

## Decision Guide

```
Do I need states with defined transitions?
├──[ Yes, but no orchestration between states
│   └── Pure lifecycle. States + \__ transitions.
├──[ Yes, AND multi-step orchestration between states
│   └── Unified flow. States + transitions + arrows + participants.
└──[ No formal states, just orchestrate a sequence
    └── Pure workflow. Participants + arrows + wait.
```

```
How complex is my flow?
├──[ Simple: just a few state transitions
│   └── Lifecycle only. No participants needed.
├──[ Medium: some human tasks, some service calls
│   └── Workflow with run/decide delegation.
├──[ Complex: parallel activities, sub-flows, timed escalation
│   └── Unified flow with sub-flows. Extract reusable sub-flows.
└──[ Very complex: 50+ lines in one flow
    └── Decompose into sub-flows connected by run @"Name".
```

---

## Comprehensive Examples

### Pure Lifecycle: Order

No orchestration, no participants, no arrows. Just states and transitions.

```modelhike
=== Order Module ===

Order #bounded-context:Sales
=====
** orderId      : Id
*  items        : LineItem[1..*]
*  submittedBy  : Reference@User
-  approvedBy   : Reference@User  (backend)
-  submittedAt  : DateTime         (backend)
-  approvedAt   : DateTime         (backend)
-  cancelledAt  : DateTime         (backend)
-  rejectionReason : String

# APIs ["/orders"]
@ apis:: get-by-id, list
#

Order Lifecycle
>>>>>>>>>>>>>>>

state DRAFT
| -- Order is being composed. Items can be added and removed.

state SUBMITTED
| entry / capture submittedAt = now(), submittedBy = currentUser()
| entry / emit OrderSubmitted

state UNDER_REVIEW
| entry / emit OrderUnderReview

state APPROVED
| entry / capture approvedAt = now(), approvedBy = currentUser()
| entry / emit OrderApproved
| entry / notify submittedBy, template: order_approved
| entry / run @"Fulfillment Workflow" with (order)

state REJECTED
| entry / require rejectionReason
| entry / emit OrderRejected
| entry / notify submittedBy, template: order_rejected

state CANCELLED
| entry / capture cancelledAt = now()
| entry / emit OrderCancelled
| terminal

state FULFILLED
| entry / emit OrderFulfilled
| terminal

[*] --> DRAFT

\__ DRAFT -> SUBMITTED : submit {items.count > 0} [any]
| api POST /orders/{id}/submit

\__ DRAFT -> CANCELLED : cancel [any]
| api POST /orders/{id}/cancel

\__ SUBMITTED -> UNDER_REVIEW : review [finance]
| api POST /orders/{id}/review

\__ SUBMITTED -> APPROVED : approve {currentUser() != submittedBy} [finance]
| api POST /orders/{id}/approve

\__ UNDER_REVIEW -> APPROVED : approve {currentUser() != submittedBy} [finance]
| api POST /orders/{id}/approve

\__ SUBMITTED -> REJECTED : reject [finance]
| api POST /orders/{id}/reject

\__ UNDER_REVIEW -> REJECTED : reject [finance]
| api POST /orders/{id}/reject

\__ SUBMITTED -> CANCELLED : cancel [admin]
| run @"Refund Workflow" with (order)
| call inventoryService.release(order.items)
| api POST /orders/{id}/cancel

\__ APPROVED -> FULFILLED : fulfill {payment.status == "CAPTURED"} [system]
| api POST /orders/{id}/fulfill

\__ REJECTED -> DRAFT : resubmit [any]
| call clearRejectionFields(order)
| api POST /orders/{id}/resubmit
```

### Pure Workflow: Credit Check

No formal state declarations. Just orchestration with arrows, parallel regions, retry, and a return value.

```modelhike
Credit Check Workflow
>>>>>>>>>>>>>>>>>>>>>

[CreditBureau] as external
[FraudService] as service

--- Credit Bureau ---
| system --> CreditBureau : pullReport(applicant.ssn)
| | @ timeout:: 30s -> retry 3
| CreditBureau <-- system : creditReport

--- Fraud Screening ---
| system --> FraudService : screenApplicant(applicant)
| | @ timeout:: 15s -> retry 2
| FraudService <-- system : fraudResult

---
-- Both complete before continuing

|> IF fraudResult.flagged
| \__ CURRENT -> REJECTED : fraudBlock {denialReason = "Fraud screening failed"}
end

return creditReport
```

### Unified Flow: Loan Application

States + orchestration in one block. This is where unification shines.

```modelhike
=== Loan Application Module ===

Loan Application
================
** id          : Id
*  applicant   : Reference@Customer
*  amount      : Float { min = 1000 }
*  status      : String = "SUBMITTED" <"SUBMITTED", "CREDIT_CHECK", "UNDER_REVIEW", "APPROVED", "DISBURSING", "FUNDED", "REJECTED", "CANCELLED">
-  creditScore : Int
-  underwriter : Reference@User
-  denialReason : String

Loan Application Flow
>>>>>>>>>>>>>>>>>>>>>
@ trigger:: application.submitted
@ timeout:: 30 days -> CANCELLED

// ---- States (lifecycle dimension) ----

state SUBMITTED
| entry / emit ApplicationSubmitted

state CREDIT_CHECK
| entry / emit CreditCheckStarted

state UNDER_REVIEW
| entry / emit UnderReview

state APPROVED
| entry / emit ApplicationApproved
| entry / notify applicant, template: loan_approved

state DISBURSING
| entry / emit DisbursementStarted

state FUNDED
| entry / emit LoanFunded
| entry / notify applicant, template: loan_funded
| terminal

state REJECTED
| entry / require denialReason
| entry / emit ApplicationRejected
| entry / notify applicant, template: loan_rejected
| terminal

state CANCELLED
| entry / emit ApplicationCancelled
| terminal

// ---- Participants (workflow dimension) ----

[Applicant] as actor
[Underwriter] as human
[Senior Underwriter] as human

// ---- Flow (combined) ----

[*] --> SUBMITTED

==> Step 1: Credit and Fraud Screening

\__ SUBMITTED -> CREDIT_CHECK : startCreditCheck

run @"Credit Check Workflow" with (applicant) -> creditReport

|> IF creditReport.score < 600
| \__ CREDIT_CHECK -> REJECTED : failCredit {denialReason = "Credit score below threshold"}
| -- Flow ends for low-score applicants.
end

==> Step 2: Assign Underwriter

\__ CREDIT_CHECK -> UNDER_REVIEW : assignUnderwriter

|> IF amount > 50000
| system --> Senior Underwriter : assign(application)
| -- High-value loans route to senior staff
|> ELSE
| system --> Underwriter : assign(application)
end

==> Step 3: Underwriter Review

wait Underwriter : review(application) -> decision
| @ sla:: 3 business days
| @ escalate:: after 2 business days -> notify(underwriter.manager)
| @ escalate:: after 3 business days -> reassign(underwriter.manager)
| @ delegate:: to direct_reports

|> IF decision.approved
| \__ UNDER_REVIEW -> APPROVED : approve
|> ELSE
| \__ UNDER_REVIEW -> REJECTED : reject {denialReason required}
| -- Underwriter rejected. Flow ends.
end

==> Step 4: Disburse Funds

\__ APPROVED -> DISBURSING : startDisbursement

run @"Disbursement Workflow" with (application, amount) -> confirmation

\__ DISBURSING -> FUNDED : confirmFunding

system ~~> Applicant : notify(loan_funded, confirmation.trackingId)
```

What this demonstrates:

1. **States and orchestration in one block.** `state APPROVED` has entry actions. `\__ UNDER_REVIEW -> APPROVED : approve` is the transition. `wait Underwriter : review` is the orchestration between states. All in one place.
2. **`\__` transitions inside workflow flow.** State changes use the same `\__` syntax whether in a pure lifecycle or inside orchestration steps.
3. **`|> IF / |> ELSE / end` for branching.** Reuses codelogic syntax. Reads naturally.
4. **`==> Step N` for phase dividers.** Cannot be confused with `=== Module ===`.
5. **`{guard}` and `[roles]` on `\__` lines.** Curly braces for guard (matching ModelHike constraints) and square brackets for roles (matching ModelHike inferred attributes).
6. **A pure lifecycle section could use this file as-is** by stripping the workflow elements (arrows, wait, participants). Vice versa: a pure workflow with no states works by omitting the `state` blocks.

### Unified Flow: Approval Chain (Purchase Order)

Reusable sub-flows, recursive delegation, and a vendor-review side-flow composed into one approval chain.

```modelhike
=== Purchase Order Module ===

Purchase Order
==============
** id         : Id
*  submitter  : Reference@User
*  department : Reference@Department
*  vendor     : Reference@Vendor
*  amount     : Float { min = 0 }
*  status     : String = "DRAFT" <"DRAFT", "PENDING_MANAGER", "PENDING_DEPT_HEAD", "PENDING_CFO", "PENDING_VENDOR_REVIEW", "APPROVED", "REJECTED">
-  rejectionReason : String
-  approvalChain   : Approval Entry[]

Approval Entry
==============
* approver   : Reference@User
* level      : String <"MANAGER", "DEPT_HEAD", "CFO", "PROCUREMENT">
* decision   : String <"APPROVED", "REJECTED", "DELEGATED">
* decidedAt  : DateTime

# APIs ["/purchase-orders"]
@ apis:: create, get-by-id, list
#

// ---- Reusable sub-flow: Single Approval Step ----

Approval Step Flow
>>>>>>>>>>>>>>>>>>
@ params:: approver [human], item, level: String, sla: Duration, escalateTo: Reference@User

system --> approver : review(item, level)

wait approver : decide(item) -> decision
| @ sla:: sla
| @ escalate:: after sla -> notify(escalateTo)
| @ delegate:: to approver.directReports

|> IF decision.decision == "REJECTED"
| \__ CURRENT -> REJECTED : rejectAtLevel {rejectionReason = decision.comment}
| system ~~> submitter : notify(rejected, level)
end

|> IF decision.decision == "DELEGATED"
| run @"Approval Step Flow" with (decision.delegatedTo, item, level, sla, escalateTo) -> delegateDecision
| return delegateDecision
end

return decision

// ---- Reusable sub-flow: Vendor Review ----

Vendor Review Flow
>>>>>>>>>>>>>>>>>>

[Procurement Lead] as human
[Vendor Registry] as service

system --> Vendor Registry : checkExisting(vendor.taxId)
Vendor Registry <-- system : registryResult

|> IF registryResult.found
| -- Vendor already in registry. Auto-approve.
| return registryResult
end

system --> Procurement Lead : reviewNewVendor(vendor)

wait Procurement Lead : vendorDecision(vendor) -> vDecision
| @ sla:: 5 business days
| @ escalate:: after 3 business days -> notify(procurement.manager)

|> IF vDecision.approved
| system --> Vendor Registry : register(vendor)
|> ELSE
| \__ CURRENT -> REJECTED : vendorRejected {rejectionReason = "Vendor not approved: " + vDecision.reason}
| system ~~> submitter : notify(vendor_rejected)
end

return vDecision

// ---- Main flow: Purchase Order Approval ----

Purchase Order Approval Flow
>>>>>>>>>>>>>>>>>>>>>>>>>>>>
@ trigger:: purchase-order.submitted

state DRAFT
| -- PO created, not yet submitted.

state PENDING_MANAGER
| entry / emit POAwaitingManager

state PENDING_DEPT_HEAD
| entry / emit POAwaitingDeptHead

state PENDING_CFO
| entry / emit POAwaitingCFO

state PENDING_VENDOR_REVIEW
| entry / emit POAwaitingVendorReview

state APPROVED
| entry / emit POApproved
| entry / notify submitter, template: po_approved
| terminal

state REJECTED
| entry / require rejectionReason
| entry / emit PORejected
| entry / notify submitter, template: po_rejected
| terminal

[Submitter] as actor
[Direct Manager] as human
[Department Head] as human
[CFO] as human

[*] --> DRAFT

==> Step 1: Submit for Approval

\__ DRAFT -> PENDING_MANAGER : submit

==> Step 2: Manager Approval (always required)

run @"Approval Step Flow" with (
| approver     = submitter.manager,
| item         = purchaseOrder,
| level        = "MANAGER",
| sla          = 2 business days,
| escalateTo   = submitter.manager.manager
) -> managerDecision

-- Manager approved. Check if higher approval is needed.

==> Step 3: Department Head (amount > 10,000)

|> IF amount > 10000
| \__ PENDING_MANAGER -> PENDING_DEPT_HEAD : escalateToDeptHead
|
| run @"Approval Step Flow" with (
| | approver     = department.head,
| | item         = purchaseOrder,
| | level        = "DEPT_HEAD",
| | sla          = 2 business days,
| | escalateTo   = department.head.manager
| ) -> deptHeadDecision
end

==> Step 4: CFO (amount > 50,000)

|> IF amount > 50000
| \__ PENDING_DEPT_HEAD -> PENDING_CFO : escalateToCFO
|
| run @"Approval Step Flow" with (
| | approver     = role(CFO),
| | item         = purchaseOrder,
| | level        = "CFO",
| | sla          = 3 business days,
| | escalateTo   = role(CEO)
| ) -> cfoDecision
end

==> Step 5: Vendor Vetting (when vendor is new)

|> IF vendor.isNew
| \__ CURRENT -> PENDING_VENDOR_REVIEW : startVendorReview
| run @"Vendor Review Flow" with (vendor) -> vendorResult
end

==> Step 6: Final Approval

\__ CURRENT -> APPROVED : finalApprove

system ~~> submitter : notify(po_approved)
system ~~> vendor : notify(po_ready_for_fulfillment)
```

### Pure Lifecycle: Invoice with Timed Transitions

Pure lifecycle, no workflow orchestration. Shows timed transitions, recurring self-transitions, and many parallel paths to terminal states.

```modelhike
=== Invoice Module ===

Invoice
=======
** invoiceId : Id
*  customer  : Reference@Customer
*  total     : Float { min = 0 }
-  paidAmount : Float = 0
-  sentAt    : DateTime (backend)
-  paidAt    : DateTime (backend)

Invoice Lifecycle
>>>>>>>>>>>>>>>>>

state DRAFT
| -- Invoice being prepared.

state SENT
| entry / capture sentAt = now()
| entry / emit InvoiceSent
| entry / notify customer, template: invoice_sent

state VIEWED
| entry / emit InvoiceViewed

state PARTIALLY_PAID
| entry / emit InvoicePartiallyPaid

state PAID
| entry / capture paidAt = now()
| entry / emit InvoicePaid
| entry / notify customer, template: payment_complete
| terminal

state OVERDUE
| entry / emit InvoiceOverdue
| entry / notify customer, template: invoice_overdue
| after 30 days --> COLLECTIONS : escalateToCollections
| every 7 days --> self : reminderCycle
| | notify customer, template: overdue_reminder

state COLLECTIONS
| entry / emit InvoiceInCollections
| entry / run @"Collections Workflow" with (invoice)

state VOID
| terminal

[*] --> DRAFT

\__ DRAFT -> SENT : send {total > 0} [finance]
| api POST /invoices/{id}/send

\__ SENT -> VIEWED : markViewed [system]
| api POST /invoices/{id}/viewed

\__ SENT -> PARTIALLY_PAID : recordPartialPayment {paidAmount > 0 && paidAmount < total} [system]
| api POST /invoices/{id}/partial-payment

\__ VIEWED -> PARTIALLY_PAID : recordPartialPayment {paidAmount > 0 && paidAmount < total} [system]
| api POST /invoices/{id}/partial-payment

\__ SENT -> PAID : recordFullPayment {paidAmount >= total} [system]
| api POST /invoices/{id}/paid

\__ VIEWED -> PAID : recordFullPayment {paidAmount >= total} [system]
| api POST /invoices/{id}/paid

\__ PARTIALLY_PAID -> PAID : recordFullPayment {paidAmount >= total} [system]
| api POST /invoices/{id}/paid

\__ OVERDUE -> PAID : recordFullPayment {paidAmount >= total} [system]
| api POST /invoices/{id}/paid

\__ SENT -> OVERDUE : markOverdue [system]
| api POST /invoices/{id}/overdue

\__ VIEWED -> OVERDUE : markOverdue [system]
| api POST /invoices/{id}/overdue

\__ PARTIALLY_PAID -> OVERDUE : markOverdue [system]
| api POST /invoices/{id}/overdue

\__ DRAFT -> VOID : void [finance, admin]
| api POST /invoices/{id}/void

\__ SENT -> VOID : void [admin]
| api POST /invoices/{id}/void
```

---

## Completeness Checklist

Every concept the unified Flow DSL is expected to express, with example references.

### Lifecycle concepts

| Concept | Status | Example |
|---------|--------|---------|
| State declarations | Present | `state APPROVED` |
| `entry /` actions | Present | `entry / capture`, `entry / emit`, `entry / notify`, `entry / run`, `entry / require` |
| `exit /` actions | Present | `exit / call auditService.logExit(...)` |
| `terminal` states | Present | `state CANCELLED / terminal` |
| `[*] -->` initial | Present | `[*] --> DRAFT` |
| `--> [*]` terminal | Present | `CANCELLED --> [*]` |
| `\__` transitions with guards | Present | `\__ DRAFT -> SUBMITTED : submit {items.count > 0}` |
| Roles on transitions | Present | `[finance]`, `[admin]`, `[system]` |
| API bindings | Present | `api POST /orders/{id}/submit` |
| Transition-specific actions | Present | `run @"Refund Workflow"`, `call service.method()` |
| Self-transitions | Present | `\__ OVERDUE -> OVERDUE : sendReminder` |
| Internal self-transitions | Present | `internal` keyword |
| Timed transitions (`after`) | Present | `after 30 days --> COLLECTIONS` |
| Recurring actions (`every`) | Present | `every 7 days --> self : reminderCycle` |
| Composite/nested states | Present | `state ACTIVE` + `\|` nested block |
| Parallel regions | Present | `--- Payment ---` / `--- Fulfillment ---` / `---` |
| History states | Present | `[H]`, `[H*]` |
| State descriptions | Present | `-- text` |
| Named events on transitions | Present | `: eventName` on every `\__` line |

### Workflow concepts

| Concept | Status | Example |
|---------|--------|---------|
| Participants | Present | `[Applicant] as actor` |
| Sync calls (`-->`) | Present | `system --> CreditBureau : pullReport()` |
| Async notifications (`~~>`) | Present | `system ~~> Applicant : notify(...)` |
| Responses (`<--`) | Present | `CreditBureau <-- system : creditReport` |
| Step dividers | Present | `==> Step 1: Name` |
| Branching (if-else) | Present | `\|> IF / \|> ELSE / end` |
| Parallel execution | Present | `--- Name --- / --- / ---` |
| Human tasks (wait + SLA) | Present | `wait Underwriter : review() -> decision` |
| Escalation policies | Present | `@ escalate::` |
| Delegation | Present | `@ delegate::` |
| Sub-flow calls | Present | `run @"Name" with (params) -> result` |
| Sub-flow params | Present | `@ params::` |
| Sub-flow return | Present | `return value` |
| State transitions in flow | Present | `\__ CURRENT -> STATE : event` |
| Trigger annotation | Present | `@ trigger:: event` |
| Timeout annotation | Present | `@ timeout:: duration -> STATE` |
| Workflow timeout | Present | `@ timeout:: 30 days -> CANCELLED` |

### Unified concepts

| Concept | Status | Example |
|---------|--------|---------|
| States + orchestration in one block | Present | Loan Application Flow |
| `\__` transitions inside orchestration | Present | `\__ CREDIT_CHECK -> REJECTED : failCredit` inside flow |
| Parallel join (`---` without name) | Present | `---` after parallel regions |
| `\|` block scoping everywhere | Present | State bodies, transition bodies, parallel bodies |
| `{guard}` matching ModelHike constraints | Present | `{items.count > 0}` |
| `[roles]` matching ModelHike attributes | Present | `[finance]` |
| `~~>` for async | Present | `system ~~> Applicant : notify(...)` |
| `==>` for steps | Present | `==> Step 1: Credit Check` |
| `-- text` for descriptions | Present | `-- Order is being composed.` |
| `CURRENT` pseudo-state in workflows | Present | `\__ CURRENT -> REJECTED` when exact source is contextual |

---

## Parser Rules

The parser enters a `>>>>>>` block and determines mode by scanning content:

1. **If `state` keyword appears**: lifecycle mode (or unified mode if arrows also present).
2. **If `[Name] as type` appears**: workflow mode (or unified mode if states also present).
3. **If both appear**: unified mode.

In all modes:

- `\__` starts a transition.
- `|` scopes a block.
- `-->`, `~~>`, `<--` are message arrows.
- `|> IF` / `|> ELSE` / `end` are branches.
- `--- Name ---` opens a parallel region; `---` closes/joins.
- `[*]` is start/end pseudo-state.
- `==> Name` is a step divider.
- `wait` is a human task.
- `run @"Name"` is a sub-flow call.
- `return` exits a sub-flow.

---

## Appendix: Syntax Choices and Rationale

The flow DSL evolved from separate lifecycle and workflow notations to a single unified syntax. This table records the key syntactic choices and why each was made, so parser implementers and DSL extenders share the same vocabulary.

| Concern | Syntax | Rationale |
|---------|--------|-----------|
| Async arrow | `~~>` | Tilde reads as "loose / async" visually; distinct from solid `-->` |
| Transition prefix | `\__` everywhere | Single parser signal for state transitions, in any mode |
| API binding | `api POST /route` | Direct keyword, no preposition ambiguity |
| Guard | `{expression}` | Matches ModelHike constraint syntax `{ }` |
| Roles | `[finance]` | Matches ModelHike inferred-attribute brackets `[ ]` |
| Transition actions | `call ...` (no `do` prefix) | Less noise; `\|` block scoping handles nesting |
| Multi-line blocks | `\|` prefixed lines | Matches codelogic DSL block scoping; one rule everywhere |
| State body | `\| entry / action` block | Consistent `\|` scoping for all bodies |
| Composite state | `state NAME` + `\|\|` nested block | Codelogic-style nesting; depth = block depth |
| Parallel (lifecycle and workflow) | `--- Name ---` / `---` | Same syntax across modes; `---` (no name) = join point |
| Workflow branching | `\|> IF / \|> ELSE / end` | Reuses codelogic if-else; no separate `ALT/ELSE/END` |
| Step divider | `==> Name` | Cannot be confused with `=== Module ===` |
| State transition (workflow) | `\__ CURRENT -> STATE : event` | Same syntax as lifecycle transitions |
| Description | `-- text` | Matches ModelHike `--` description syntax |
| End of parallel join | `---` (no name) | Explicit, symmetric with the opener |
