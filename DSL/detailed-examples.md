# Part 1: Already Declarative (~60%)

## 1. Validation Rules

```modelhike
=== Order Module ===

Order
=====
** orderId      : Id
*  email        : String                           { pattern = ^[\\w.-]+@[\\w.-]+\\.[a-z]{2,}$ }
*  total        : Float                            { min = 0.01 }
-  status       : String = "NEW"                   <"NEW", "PAID", "CANCELLED">
*  items        : LineItem[1..50]
-  promoCode    : String                           { minLength = 4, maxLength = 20 }
*? managerApproval : Boolean = false -- required when total > 10000

= requiresApproval : { total > 10000 }
```

Constraints (`{ min, max, pattern }`), valid value sets (`<...>`), collection bounds (`[1..50]`), conditional required (`*?`), and named constraints (`= name : { expr }`) are all first-class. One source of truth drives API validation, DB constraints, and client-side checks.

---

## 2. Access Control Policies

```modelhike
=== Invoice Module ===
@ roles:: finance, admin

Invoice
=======
@ roles:: finance, admin
@ index:: invoiceId (unique)
** invoiceId : Id
*  region    : String
*  status    : String = "DRAFT" <"DRAFT", "SUBMITTED", "APPROVED", "PAID", "CANCELLED">
*  submitter : Reference@User

# APIs ["/invoices"]
@ apis:: list, get-by-id
@ list-api :: region -> region; status -> status
## approve(id: Id) : Invoice (route="/invoices/{id}/approve", method=POST, roles=finance)
## delete(id: Id) : Void     (route="/invoices/{id}", method=DELETE, roles=admin)
#
```

`@ roles::` cascades from module to class to API. Custom endpoints carry per-operation `roles=` attributes. Blueprints emit middleware guards, row-level filters, and UI visibility rules from these declarations.

---

## 3. Data Mappings

```modelhike
=== Customer Module ===

Customer (PersonBase)
=====================
** id           : Id
*  firstName    : String
*  lastName     : String
*  contactEmail : String
*  account      : Reference@Account

// DTOs project exactly the fields the outside world needs

Customer DTO (Customer)
/===/
. id
. firstName
. lastName
. contactEmail

Customer Summary (Customer, Account)
/===/
. lastName
. firstName
. account tier
```

DTOs inherit fields from parent types via `( )`. The `.` prefix means "project this field from the parent." No mapper classes, no serializers, no null-safety boilerplate. Change the entity, the DTO updates.

---

## 4. UI Layouts

UI layouts use the `/;;;;;/` underline. Pages are top-level routable screens. Views are reusable components. Controls derive from bound entity field types unless explicitly overridden. Sections use `Name:` (trailing colon). The `|` prefix continues/configures the previous element.

```modelhike
=== Order UI Module ===

// ---- Reusable view: Order Search ----

Order Search View (Order) (search-layout)
/;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;/
= search : Search => orderId, customerName, status
= dateFilter : DateRange => createdAt
= statusFilter : Filter => status

@ display:: Table
@ pagination:: cursor, pageSize = 25
@ sort:: createdAt desc

. orderId : Link
. customer name
. status : Badge
. total : Currency
. createdAt : Label (format=relative)
+ createButton : Button -- label: "+ New Order" (position=header-right)

# Actions
## orderId link-click (order: Order)
| navigate @"Order Detail Page" with (order.orderId)

## createButton click
| navigate @"Order Create Page"
#

// ---- Reusable view: Order Form ----

Order Edit View (Order) (two-column-layout)
/;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;/

Personal Information:
* customer : Lookup
. orderId : Label

Order Details:
* items : Table (editable, addable, removable)
| columns: name, quantity, unitPrice, total
| footer: sum(total)
- notes : RichText
. status : Badge
+ saveButton : Button -- label: "Save" (style=primary)
+ cancelButton : Button -- label: "Cancel" (style=secondary)

# Actions
## saveButton click
| call orderService.save(self.binding)
| notify user, template: order_saved

## cancelButton click
| navigate back

## items row-add
| assign newItem = LineItem(quantity: 1)
| call self.binding.items.append(newItem)
#

// ---- Reusable view: Order Detail ----

Order Detail View (Order, Customer?) (card-style)
/;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;/

Order Summary:
. orderId : Label
. status : Badge
. createdAt : Label (format=datetime)
. total : Currency

Customer:
-- Shown only when Customer is loaded (? = optional binding)
. customer name : Label
. customer email : Link (href="mailto:{value}")
. customer tier : Badge

Line Items:
. items : Table
| columns: name, quantity, unitPrice, total
| footer: sum(total)

Actions:
+ approveButton : Button -- label: "Approve" (style=primary, visible-when=status:"SUBMITTED")
+ rejectButton : Button -- label: "Reject" (style=danger, visible-when=status:"SUBMITTED")

init(orderId: Id)
-----------------
|> DB Order
| |> WHERE o -> o.id == orderId
| |> INCLUDE customer, items
| |> FIRST
| |> LET order = _
assign self.binding = order
---

# Actions
## approveButton click
| call orderService.approve(self.binding.orderId)
| notify user, template: order_approved_success

## rejectButton click
| call showModal("rejectReasonModal")
#

// ---- Page: Order Management (composes the views) ----

Order Management Page (page) (sidebar-layout)
/;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;/
@ route:: /orders
@ title:: Order Management
@ roles:: [admin, ops, finance]

* sidebar : @"Order Search View" (width=280px, collapsible)
* main : @"Order Detail View" (flex=1)

# Actions
## sidebar row-click (order: Order)
| call main.init(order.orderId)
#
```

### What to notice

1. **`/;;;;;/` signals "this is a screen."** Just as `=====` signals data and `>>>>>>` signals flow. The visual alphabet lets you scan a file and know what everything is.
2. **Controls derive from entity types.** `. status` on an entity with `<"DRAFT","SUBMITTED","APPROVED">` auto-renders as a dropdown. `. total : Currency` overrides derivation explicitly. The entity is the source of truth; the view is the surface.
3. **Three-layer model in action.** `Order` (entity) declares fields and constraints. `Order DTO` projects which fields the API exposes. `Order Edit View` declares how they render. Each layer adds, none duplicates.
4. **`|` continues the previous element.** `. items : Table` then `| columns: name, quantity` then `| footer: sum(total)`. Same `|` rule as state bodies, transition bodies, action handlers. One concept everywhere.
5. **`Section Name:` groups controls visually.** `Order Summary:`, `Customer:`, `Line Items:`. Trailing colon = section header. Not `--` (which is description syntax).
6. **`?` optional bindings for conditional display.** `Order Detail View (Order, Customer?)` means Customer fields render only when the Customer object is loaded. One `?` character replaces show/hide logic.
7. **`# Actions` mirrors `# APIs`.** APIs declare server endpoints. Actions declare UI event handlers. Same pattern: `## controlName eventType` with `|` block for the handler body.
8. **Composite views with `@"View Name"`.** The Order Management Page composes a sidebar and main view. Each view is declared independently, reusable. The page just wires them with layout attributes and cross-view actions.
9. **Validation is automatic.** Entity constraints (`{ min = 0 }`, `{ pattern = ... }`) and valid value sets (`<...>`) wire to form controls without explicit validation code.

---

## 5. Schema Definitions

```modelhike
=== Order Management Service #blueprint(api-springboot-monorepo) ===
+ Order Module

=== Order Module ===

Order #bounded-context:Sales
=====
@ index:: orderId (unique)
@ index:: customer, status
@ index:: dueDate (where=status:SUBMITTED)
** orderId    : Id
*  number     : String                    { pattern = ^INV-\\d{4}-\\d{6}$ }
*  customer   : Reference@Customer
*  items      : LineItem[1..*]
*  status     : String = "DRAFT"          <"DRAFT", "SUBMITTED", "APPROVED", "PAID", "CANCELLED">
=  total      : Float                     -- derived: sum of items.amount
=  tax        : Float                     -- derived: total * customer.region.taxRate
*  dueDate    : Date
*  createdAt  : DateTime = now()          (backend)
-  updatedAt  : DateTime                  (backend)

# APIs ["/orders"]
@ apis:: create, get-by-id, list, update, delete
@ list-api :: status -> status; customer -> customer.id
## list by status
#
```

One class declaration drives: database migration, entity class, DTO, GraphQL type, OpenAPI schema, API response serializer, test fixtures. Seven artifacts from one source of truth.

---

## 6. Configuration

```modelhike
* * * * * * * * * * * * * * * * * * *
E-Commerce Platform (owner="platform-team") #production
* * * * * * * * * * * * * * * * * * *

+--- Data Tier #backend
| PostgreSQL [database] #primary-db
| +++++++++++++++++++++++++++++++++
| host    = db.internal
| port    = 5432
| version = 16
| pool    = 20
|
| Redis [cache] #session
| ++++++++++++++++++++++
| host = redis.internal
| port = 6379
| db   = 0
+---

+--- Messaging
| Kafka [message-broker] #async
| ++++++++++++++++++++++++++++++
| bootstrap.servers = kafka:9092
| group.id          = platform
| auto.offset.reset = earliest
+---

+ Payments Service
+ Order Service
+ Frontend App

* * * * * * * * * * * * * * * * * * *
```

System-level infrastructure uses infra nodes (`++++` underline) with typed `key = value` properties. Virtual groups (`+--- Name ... +---`) organize them visually. All configuration lives in one architectural declaration.

---

## 7. Routing / APIs

```modelhike
Product
=======
** id    : Id
*  name  : String
*  price : Float { min = 0 }
*  sku   : String { pattern = ^[A-Z]{3}-\\d{4}$ }

# APIs ["/products"]
@ apis:: create, delete, get-by-id, list, update
@ list-api :: name -> name; sku -> sku
## list by name                                            -- GET /products?name={name}
## discount(price: Float) : Product (route="/products/{id}/discount", method=POST, roles=admin)
## bulkImport(items: Product[]) : Int (route="/products/import", method=POST, roles=admin)
#
```

`@ apis::` scaffolds standard CRUD. `## list by` auto-generates filtered queries. `## customOp(...)` defines custom endpoints with explicit routes, methods, and roles. One block drives controller, request/response types, authorization middleware, OpenAPI docs, and client SDK.

---

---

# Part 2: Declarative Once You Have the Right Runtime (~30%)

## 8. Workflow Orchestration

Workflows and lifecycles share a unified Flow DSL inside `>>>>>>` blocks. Participants use `[Name] as type`. Sync calls use `-->`, async notifications use `~~>`. State transitions use `\__` with guards in `{  }` and roles in `[ ]`. Branching uses `|> IF / |> ELSE / end` (reusing codelogic syntax). All blocks use `|` prefix for scoping.

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

// ---- Sub-flow: Credit Check (reusable) ----

Credit Check Flow
>>>>>>>>>>>>>>>>>

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

// ---- Sub-flow: Disbursement (reusable) ----

Disbursement Flow
>>>>>>>>>>>>>>>>>

[Compliance] as service
[LedgerService] as service
[PaymentRails] as external

system --> Compliance : finalCheck(application)
| @ timeout:: 10s -> retry 1
Compliance <-- system : clearance

|> IF clearance.hold
| wait Compliance : manualReview(application) -> reviewed
| | @ sla:: 1 business day
| | @ escalate:: after 1 business day -> notify(compliance.manager)
| |> IF reviewed.blocked
| | \__ CURRENT -> REJECTED : complianceHold {denialReason = "Compliance hold"}
| end
end

system --> LedgerService : reserveFunds(amount)
LedgerService <-- system : reservation

system --> PaymentRails : initTransfer(applicant.bankAccount, amount)
| @ timeout:: 60s -> retry 2 backoff exponential
PaymentRails <-- system : transferConfirmation

\__ CURRENT -> FUNDED : confirmFunding

return transferConfirmation

// ---- Main flow: Loan Application (unified states + orchestration) ----

Loan Application Flow
>>>>>>>>>>>>>>>>>>>>>
@ trigger:: application.submitted
@ timeout:: 30 days -> CANCELLED

// States

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

// Participants

[Applicant] as actor
[Underwriter] as human
[Senior Underwriter] as human

// Flow

[*] --> SUBMITTED

==> Step 1: Credit and Fraud Screening

\__ SUBMITTED -> CREDIT_CHECK : startCreditCheck

run @"Credit Check Flow" with (applicant) -> creditReport

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

run @"Disbursement Flow" with (application, amount) -> confirmation

system ~~> Applicant : notify(loan_funded, confirmation.trackingId)
```

### What to notice

1. **States and orchestration in one block.** `state APPROVED` has entry actions. `\__ UNDER_REVIEW -> APPROVED : approve` is the transition. `wait Underwriter : review` is the orchestration between states. All in one place.
2. **`\__` for every state transition.** Same syntax whether in a pure lifecycle or inside orchestration steps. The transition IS the state change. The surrounding arrows are the work that leads to it.
3. **`|> IF / |> ELSE / end` for branching.** Reuses codelogic syntax. No new keywords to learn.
4. **`--- Name --- / ---` for parallel.** Credit bureau and fraud screening run concurrently. `---` without a name is the join point: execution continues only after both regions complete.
5. **`~~>` for async.** `system ~~> Applicant : notify(...)` is fire-and-forget. Visually distinct from `-->` sync calls. The tilde conveys "wavy, loose, don't wait."
6. **`{guard}` and `[roles]` on `\__` lines.** Curly braces for guards match ModelHike constraint syntax. Square brackets for roles match ModelHike inferred attributes.
7. **`|` block scoping everywhere.** State bodies, transition bodies, parallel region bodies, `wait` annotation bodies. Same convention as codelogic.
8. **`==> Step N` for phases.** Cannot be confused with `=== Module ===`. The fat arrow suggests forward progress.
9. **`entry /` uses UML statechart notation.** Each action is its own `| entry /` line. Flat, scannable, no nested blocks.
10. **Sub-flows compose.** `run @"Credit Check Flow" with (applicant) -> creditReport` calls a named sub-flow. The sub-flow has its own participants, its own parallel regions, its own error handling. The main flow doesn't care about those details.

---

## 9. Approval Chains

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
| -- Delegation restarts this step with the delegate as approver
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

// States

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

// Participants

[Submitter] as actor
[Direct Manager] as human
[Department Head] as human
[CFO] as human

// Flow

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

### What to notice

1. **`Approval Step Flow` is a reusable building block.** One level: send for review, `wait` for decision, handle rejection/delegation. Every level in the chain calls the same sub-flow with different params.
2. **Delegation is recursive.** When an approver delegates, the Approval Step Flow calls itself via `run @"Approval Step Flow"` with the delegate. No separate delegation engine.
3. **States have clear context.** `\__ DRAFT -> PENDING_MANAGER : submit` appears right before the manager review. `\__ PENDING_MANAGER -> PENDING_DEPT_HEAD : escalateToDeptHead` appears right before the department head review. A reader always knows why the PO is in that state.
4. **Thresholds are `|> IF` guards.** `|> IF amount > 10000` wraps the department head step. If the amount is $5,000, the flow skips to final approval. No dead states, no unreachable branches.
5. **Vendor review is a separate sub-flow.** Its own participant (Procurement Lead), its own registry check, its own SLA. The main flow just calls `run @"Vendor Review Flow"`.
6. **The chain is readable as a sentence:** "Submit. Manager reviews. If over 10k, department head reviews. If over 50k, CFO reviews. If new vendor, vet the vendor. Approve."

## 10. Notification Logic

```modelhike
=== Notification Module ===

>>> Handles all outbound notifications for Order events
Order Notifier
==============

~ notifyOrderShipped(order: Order) : Void
```
|> NOTIFY EMAIL order.customer.email
| |> SUBJECT Your order has shipped
| |> TEMPLATE order_shipped
| |> DATA
| |  customerName = order.customer.name
| |  trackingUrl  = order.trackingUrl
| |  items        = order.items
|> IF order.customer.smsOptIn
| |> NOTIFY SMS order.customer.phone
| | |> TEMPLATE order_shipped_sms
| | |> DATA
| | |  trackingUrl = order.trackingUrl
|> PUBLISH OrderShipped TO order-events
| |> PAYLOAD
| |  orderId    = order.id
| |  trackingUrl = order.trackingUrl
```

~ notifyInvoiceOverdue(invoice: Invoice) : Void
```
|> NOTIFY EMAIL invoice.customer.billingEmail
| |> SUBJECT Invoice overdue
| |> TEMPLATE invoice_overdue
| |> PRIORITY high
| |> DATA
| |  invoiceNumber = invoice.number
| |  dueDate       = invoice.dueDate
| |  amount        = invoice.total
```
```

`|> NOTIFY type recipient` is a first-class DSL block. `|> PUBLISH EventName TO channel` handles domain events. Both use structured child blocks for data, templates, and metadata. Adding a new channel is a new `|> NOTIFY` block.

---

## 11. Integration Glue

```modelhike
=== Integration Module ===

Customer Sync
=============

~ syncToSalesforce(customer: Customer) : Void
```
|> TRY
| |> HTTP POST https://salesforce.example.com/services/data/v58.0/sobjects/Contact
| | |> AUTH bearer sfToken
| | |> BODY
| | |  FirstName    = customer.firstName
| | |  LastName     = customer.lastName
| | |  Email        = customer.contactEmail
| | |  ExternalId__c = customer.id
| | |> EXPECT 201
| | |> LET result = _
| |> PUBLISH CustomerSynced TO integration-events
| | |> PAYLOAD
| | |  customerId    = customer.id
| | |  salesforceId  = result.id
|> CATCH ex: HttpException
| |> IF ex.statusCode == 409
| | call mergeDuplicate(customer)
| |> ELSE
| | call retryQueue.add(customer.id)
| | call logger.error(ex.message)
```

~ pullFromSalesforce(salesforceId: String) : Customer
```
|> HTTP GET https://salesforce.example.com/services/data/v58.0/sobjects/Contact/{salesforceId}
| |> AUTH bearer sfToken
| |> EXPECT 200
| |> LET contact = _
|> DB-UPDATE Customer -> c.id == contact.ExternalId__c
| |> SET salesRep = contact.OwnerId
|> LET customer = _
return customer
```
```

HTTP, GraphQL, and gRPC calls are structural blocks, not string-building exercises. Path params, headers, auth, and response binding are all typed DSL elements.

---

## 12. Retry / Error Policies

Error handling policies are declared as a `# Error Policy` attached section on integration methods. Instead of imperative try/catch with hand-coded retry loops, each error type maps declaratively to a response: retry, notify, escalate, dead-letter.

```modelhike
=== Payment Module ===

Payment Processor
=================

>>> * orderId: Id
>>> * amount: Float { min = 0.01 }
~ processPayment(orderId: Id, amount: Float) : Payment
```
|> HTTP POST https://payments.gateway.com/v1/charge
| |> AUTH api-key gatewayKey
| |> BODY
| |  orderId  = orderId
| |  amount   = amount
| |  currency = "usd"
| |> EXPECT 201
| |> LET payment = _
return payment
```

# Error Policy
@ applies-to:: processPayment

on Timeout:
| retry: 3, backoff: exponential(1s)
| then: dead-letter

on InsufficientFunds:
| retry: none
| notify: customer, template: payment_failed
| | orderId = orderId
| | reason  = "insufficient_funds"

on FraudDetected:
| retry: none
| call: freezeAccount(orderId)
| notify: team(Fraud), template: fraud_alert (priority=critical)
| | orderId = orderId

on Unknown:
| retry: 1
| then: dead-letter
| alert: team(Engineering), severity: high

#
```

Each `on ExceptionType:` block declares the policy for that error. `retry:` specifies count and backoff. `then:` specifies what happens after retries are exhausted. `notify:` sends a notification with template and data. `call:` triggers an action. `alert:` notifies an operations team. The blueprint emits try/catch blocks, retry loops, backoff calculations, dead letter queue integration, and alerting hooks. Error handling is a policy decision, not a coding exercise.

---

## 13. Scheduling

```modelhike
=== Reports Module ===
@ roles:: finance

Scheduled Reports
=================
@ schedule:: cron = "0 0 2 * * MON" -- every Monday 2 AM
@ schedule:: timezone = "company.headquarters.timezone"

~ generateWeeklyReport() : Void
```
|> DB Orders
| |> WHERE o -> o.paidDate >= startOfWeek() && o.paidDate <= endOfWeek()
| |> GROUP-BY o -> o.customer.region.name
| |> AGGREGATE sum(total), count, avg(total)
| |> TO-LIST
| |> LET reportData = _
|> NOTIFY EMAIL finance-team@company.com
| |> SUBJECT Weekly Order Report
| |> TEMPLATE weekly_report
| |> DATA
| |  reportData = reportData
| |  period     = currentWeek()
```
```

Scheduling is annotation-driven (`@ schedule::`). The method body is pure business logic using DB aggregation and notification blocks. The blueprint wires the cron trigger, overlap protection, and failure alerting.

---

## 14. Reporting Queries

```modelhike
=== Reports Module ===

Revenue By Region (Order, Customer, Region)
============================================
@ roles:: finance, executive
* region       : String
=  revenue     : Float     -- sum(order.total) where status == PAID
=  orderCount  : Int       -- count
=  averageOrder : Float    -- avg(order.total)
=  revenuePerCustomer : Float -- revenue / count(distinct customer)

# APIs (route="/reports/revenue-by-region")
@ apis:: list
@ list-api :: dateRange -> paidDate
#

~ computeReport(dateRange: String) : Revenue By Region[]
```
|> DB Orders
| |> WHERE o -> o.status == "PAID" && o.paidDate >= dateRange.start && o.paidDate <= dateRange.end
| |> GROUP-BY o -> o.customer.region.name
| |> AGGREGATE sum(total), count, avg(total)
| |> ORDER-BY sum(total) desc
| |> TO-LIST
| |> LET results = _
return results
```
```

The report is a class with calculated fields (`=`) and a query method using `|> DB`, `|> GROUP-BY`, `|> AGGREGATE`, `|> ORDER-BY`. A finance person can read and validate the report definition. API exposure is one `# APIs` block.

---

## 15. CRUD Operations

```modelhike
=== Invoice Module ===
@ apis:: create, get-by-id, list, update, delete

Invoice
=======
@ index:: invoiceId (unique)
@ index:: customer, status
** invoiceId : Id
*  customer  : Reference@Customer
*  items     : LineItem[1..*]
*  dueDate   : Date
*  status    : String = "DRAFT" <"DRAFT", "SUBMITTED", "APPROVED", "PAID", "CANCELLED">
-  notes     : Text
*  createdAt : DateTime = now() (backend)
-  updatedAt : DateTime          (backend)

# APIs ["/invoices"]
@ apis:: create, delete, get-by-id, list, update
@ list-api :: status -> status; customer -> customer.id; dateRange -> dueDate
## list by status
## list by customer
#

Invoice Summary (Invoice, Customer)
/===/
. invoiceId
. customer name
. status
. dueDate
```

Six lines of `@ apis::` and `# APIs` replace 400 lines of controller + service + repository + DTOs + tests per entity. Multiply by 50 entities. That's the math.

---

## 16. State Machines / Lifecycle Management

Lifecycles use the same unified Flow DSL as workflows. States are first-class with `entry /` and `exit /` actions. Transitions use `\__` with guards in `{ }` and roles in `[ ]`. State bodies and transition bodies use `|` block scoping. `[*]` marks start and end. The syntax generates both executable code AND state diagrams.

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
-  fulfilledAt  : DateTime         (backend)
-  cancelledAt  : DateTime         (backend)
-  rejectionReason : String

# APIs ["/orders"]
@ apis:: get-by-id, list
#

Order Lifecycle
>>>>>>>>>>>>>>>

// ---- States ----

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
| entry / call analytics.track("order_approved", order.id)

state REJECTED
| entry / require rejectionReason
| entry / emit OrderRejected
| entry / notify submittedBy, template: order_rejected

state CANCELLED
| entry / capture cancelledAt = now()
| entry / emit OrderCancelled
| entry / notify submittedBy, template: order_cancelled
| terminal

state FULFILLED
| entry / capture fulfilledAt = now()
| entry / emit OrderFulfilled
| entry / notify submittedBy, template: order_fulfilled
| entry / call warehouse.scheduleShipment(order)
| entry / call loyaltyService.creditPoints(order.customer, order.total)
| terminal

// ---- Flow ----

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

CANCELLED --> [*]
FULFILLED --> [*]
```

### What to notice

1. **`\__` for every transition.** `\__ DRAFT -> SUBMITTED : submit {items.count > 0} [any]` packs source, target, event, guard, and roles onto one line. The `|` block below carries api and actions.
2. **`{guard}` matches ModelHike constraints.** `{items.count > 0}` and `{currentUser() != submittedBy}` use the same curly-brace syntax as property constraints `{ min = 0 }`.
3. **`[roles]` matches ModelHike attributes.** `[finance]`, `[admin]`, `[system]` use the same bracket syntax as inferred attributes `["/orders"]`.
4. **`|` block scoping everywhere.** State bodies (`| entry / ...`), transition bodies (`| api ...`, `| run ...`, `| call ...`). Same convention as codelogic.
5. **`entry /` eliminates duplication.** Both `SUBMITTED -> APPROVED` and `UNDER_REVIEW -> APPROVED` exist, but neither carries capture/emit/notify. Those live once on `state APPROVED`. The old imperative version duplicated 5 lines across both transitions.
6. **`[*]` for start and end.** `[*] --> DRAFT` is the initial state. `CANCELLED --> [*]` and `FULFILLED --> [*]` are terminal. PlantUML/Mermaid universal convention.
7. **`-- text` for descriptions.** `| -- Order is being composed.` uses ModelHike's existing description syntax.
8. **Transition bodies have no `do` prefix.** `| run @"Refund Workflow"`, `| call inventoryService.release()`, `| api POST /route`. The `|` scoping is sufficient.

### Advanced: timed transitions, self-transitions

```modelhike
state PENDING_PAYMENT
| entry / emit PaymentPending
| entry / notify customer, template: payment_reminder
| after 1 hour --> CANCELLED : paymentTimeout

state OVERDUE
| entry / emit InvoiceOverdue
| entry / notify customer, template: invoice_overdue
| after 30 days --> COLLECTIONS : escalateToCollections
| every 7 days --> self : reminderCycle
| | notify customer, template: overdue_reminder

\__ OVERDUE -> OVERDUE : sendReminder
| internal
| notify customer, template: overdue_reminder
```

`after DURATION --> STATE` is a timed auto-transition. `every DURATION --> self` is a recurring action. `\__ A -> A` with `| internal` is a self-transition that doesn't re-trigger entry/exit.

### Advanced: composite states

```modelhike
state ACTIVE
| -- Contains sub-states for fulfillment tracking
| [*] --> PROCESSING
|
| state PROCESSING
| | entry / emit OrderProcessing
|
| state SHIPPING
| | entry / capture shippedAt = now()
| | entry / emit OrderShipped
|
| state DELIVERED
| | entry / capture deliveredAt = now()
| | terminal
|
| \__ PROCESSING -> SHIPPING : ship {payment.status == "CAPTURED"} [warehouse]
| | api POST /orders/{id}/ship
|
| \__ SHIPPING -> DELIVERED : confirmDelivery [system, courier]
| | api POST /orders/{id}/deliver
```

Nested `|` depth for composite states. Outer `|` = inside ACTIVE. Inner `||` = inside sub-states and sub-transitions. Same depth-counting as codelogic.

### Advanced: parallel regions

```modelhike
state ACTIVE
| parallel
|
| --- Payment ---
| | [*] --> UNPAID
| |
| | \__ UNPAID -> AUTHORIZED : authorizePayment
| | | api POST /orders/{id}/authorize-payment
| |
| | \__ AUTHORIZED -> CAPTURED : capturePayment
| | | api POST /orders/{id}/capture-payment
|
| --- Fulfillment ---
| | [*] --> PICKING
| |
| | \__ PICKING -> SHIPPED : ship [warehouse]
| | | api POST /orders/{id}/ship
| |
| | \__ SHIPPED -> DELIVERED : deliver [system]
| | | api POST /orders/{id}/deliver
| |
| | DELIVERED --> [*]
|
| ---
| -- Both regions must complete before ACTIVE completes
```

`--- Name ---` opens a parallel region. `---` without a name is the join point. Same syntax used in workflows for concurrent activities.

### Advanced: history states

```modelhike
state ACTIVE
| [*] --> PROCESSING
| [H] --> history
|
| state PROCESSING
| state SHIPPING
|
| \__ PROCESSING -> SHIPPING : ship

\__ ACTIVE -> SUSPENDED : suspend [admin]
| api POST /orders/{id}/suspend

\__ SUSPENDED -> ACTIVE : resume [admin]
| api POST /orders/{id}/resume
| -- Resumes at [H]: last active sub-state
```

`[H]` for shallow history, `[H*]` for deep. On re-entry, the composite state resumes at the last active sub-state.

### What the blueprint emits

- **State machine class** with validated transitions (`409 Conflict` on illegal transitions)
- **API endpoints** per `| api` declaration
- **Entry/exit actions** on state changes (capture, emit, notify, run, call)
- **Guard middleware** per `{expression}` (`422` on failure)
- **Access control** per `[roles]`
- **Timed transitions** as scheduler entries
- **State diagram** (PlantUML or Mermaid) generated from the same source
- **Audit trail** logging every transition: who, when, from, to, event, payload

### Lifecycle vs Workflow (same syntax, different focus)

| | Workflow focus | Lifecycle focus |
|---|---|---|
| Has `state` blocks? | Optional | Yes |
| Has `\__` transitions? | Yes (within flow) | Yes (primary structure) |
| Has participants / arrows? | Yes | No |
| Has `wait` / SLA? | Yes | No |
| Has `entry /` / `exit /`? | Optional | Yes |
| Has `--- parallel ---`? | Yes (concurrent activities) | Yes (state regions) |

Both use `>>>>>>`. Both use `\__`, `|`, `{guards}`, `[roles]`. A pure lifecycle has no arrows or participants. A pure workflow can skip formal `state` blocks. A unified flow (like the Loan Application in category 8) uses both.
## 17. Audit Logging / Change Tracking

```modelhike
=== Core Module ===

// Shared base type — any entity that mixes this in gets audit fields
Auditable
=========
- createdBy  : Reference@User (backend)
- createdAt  : DateTime = now() (backend)
- updatedBy  : Reference@User (backend)
- updatedAt  : DateTime        (backend)
- changeLog  : AuditEntry[]    (backend) -- blueprint tracks field-level diffs

Audit Entry
===========
* field     : String
* oldValue  : String
* newValue  : String
* changedBy : Reference@User
* changedAt : DateTime = now()

=== Customer Module ===

Customer (Auditable) #audit
============================
@ index:: customerId (unique)
** customerId : Id
*  email      : String    #sensitive -- blueprint masks in audit log
*  tier       : String    <"FREE", "PRO", "ENTERPRISE">
*  region     : String
-  ssn        : String    #sensitive #pii -- blueprint logs "changed" only, no values
```

The `(Auditable)` mixin adds change tracking fields. `#sensitive` and `#pii` tags tell blueprints how to mask or redact in audit logs. The blueprint intercepts every update, diffs fields, and writes `AuditEntry` records. You never forget to audit a field because it's structural.

---

## 18. Localization / i18n

```modelhike
=== Localization Module ===

// Declare translatable labels as a typed entity
Order Labels #i18n
==================
@ locales:: en, es, fr, ja
@ fallback:: en
* status.draft     : String = "Draft"         (es="Borrador", fr="Brouillon", ja="下書き")
* status.submitted : String = "Submitted"     (es="Enviado", fr="Soumis", ja="提出済み")
* validation.total.positive : String = "Total must be a positive amount" (es="El total debe ser un monto positivo")
* validation.items.max : String = "Cannot exceed {max} items" (es="No puede exceder {max} artículos")
```

Locale values sit as attributes `(es=..., fr=...)` on each label property. The blueprint generates resource bundles, locale-aware formatters, and missing translation reports. Adding a locale is adding one more attribute.

---

## 19. Caching Policies

Cache is an attached section on entities, like `# APIs`. It declares strategy, TTL, invalidation triggers, and exclusion rules.

```modelhike
=== Product Module ===

Product
=======
** id     : Id
*  name   : String
*  status : String = "ACTIVE" <"DRAFT", "ACTIVE", "ARCHIVED">
*  price  : Float { min = 0 }

# Cache
@ strategy:: read-through
@ ttl:: 1 hour
@ eviction:: lru
@ max-entries:: 10000
@ exclude-when:: status == "DRAFT"
@ invalidate-on:: product.updated, product.deleted
@ warm-on:: product.created
#
```

The blueprint emits cache annotations, eviction listeners, warming jobs, and monitoring metrics (`hit_rate`, `miss_rate`, `eviction_count`). Cache policy is a system-level concern declared on the entity, not scattered across 200 service methods.

---

## 20. Rate Limiting

Rate limiting is an attached section on entities or modules, applied to API endpoints.

```modelhike
=== Order Module ===

Order
=====
** orderId : Id
*  amount  : Float

# APIs ["/orders"]
@ apis:: create, get-by-id, list
## bulkExport() : Order[] (route="/orders/export", method=GET)
#

# Rate Limit
@ default:: 100/minute per user

@ tiers::
| FREE:       100/minute, 1000/hour
| PRO:        500/minute, 10000/hour
| ENTERPRISE: 5000/minute

@ overrides::
| POST /orders:         20/minute per user
| GET /orders/export:   5/hour per user

@ burst:: allow 2x for 10 seconds
@ response:: 429
@ headers:: X-RateLimit-Limit, X-RateLimit-Remaining, X-RateLimit-Reset
#
```

The blueprint emits middleware, tier resolution from customer data, per-endpoint overrides, burst handling, response headers, and monitoring metrics. Rate limiting is a policy, not code.

---

## 21. Event Publishing / Webhooks

```modelhike
=== Order Module ===

Order
=====
** orderId : Id
*  total   : Float
*  status  : String

// Event definitions as methods using PUBLISH

~ emitOrderApproved(order: Order) : Void
```
|> PUBLISH OrderApproved TO order-events
| |> PAYLOAD
| |  orderId     = order.orderId
| |  total       = order.total
| |  customerName = order.customer.name
| |> METADATA
| |  timestamp   = now()
| |  version     = "1.0"
```

~ emitOrderShipped(order: Order) : Void
```
|> PUBLISH OrderShipped TO order-events
| |> PAYLOAD
| |  orderId          = order.orderId
| |  trackingNumber   = order.trackingNumber
| |  carrier          = order.carrier
| |> METADATA
| |  timestamp = now()
```
```

`|> PUBLISH EventName TO channel` is a first-class code logic block. `|> PAYLOAD` and `|> METADATA` are structured child blocks. Blueprints emit event publishers, webhook dispatchers, payload builders, and retry queues.

---

## 22. File / Media Handling

Media handling is an attached section on entities that have file/image fields. It declares upload rules, variant generation, storage config, and access policies.

```modelhike
=== User Module ===

User Profile
============
** id          : Id
*  name        : String
*  email       : String
-  avatarUrl   : String

# Media
@ field:: avatarUrl
@ accept:: image/jpeg, image/png, image/webp
@ max-size:: 10 MB
@ deduplicate:: content-hash
@ scan:: virus-check

@ variants::
| thumbnail: resize 200x200, crop: center, format: webp
| medium:    resize 800x800, fit: contain, format: webp
| original:  preserve

@ storage::
| provider: s3
| bucket: user-media
| path: {tenant}/{entityId}/{variant}.{ext}
| access: signed-url, expires: 1 hour

@ metadata::
| extract: dimensions, exif.date, dominant-color
| strip: exif.gps, exif.device
#
```

The blueprint emits upload handler with validation, virus scanning integration, image processing pipeline for variants, S3 storage client, signed URL generator, metadata extractor, and privacy stripping. Adding a new variant is one line. Adding virus scanning is one line.

---

## 23. Multi-tenancy

```modelhike
* * * * * * * * * * * * * * * * * * *
SaaS Platform (tenancy=row-level, tenant-column=tenantId, tenant-resolver=subdomain)
* * * * * * * * * * * * * * * * * * *

+ Order Service
+ Customer Service

* * * * * * * * * * * * * * * * * * *

=== Order Service #blueprint(api-springboot-monorepo) ===

=== Order Module ===

// Every entity gets tenantId automatically from the system-level tenancy declaration

Order #tenant-scoped
=====
** orderId  : Id
*  tenantId : String (backend) -- auto-filtered by blueprint on every query
*  amount   : Float
*  status   : String

# APIs ["/orders"]
@ apis:: create, get-by-id, list, delete
#
```

Tenancy is declared once at the system level. `#tenant-scoped` on entities confirms participation. `(backend)` on `tenantId` keeps it out of DTOs. The blueprint injects `WHERE tenantId = :currentTenant` into every query. One missed filter is a data breach. This makes it structurally impossible to forget.

---

## 24. Search / Indexing

Search is an attached section on entities, declaring which fields are searchable, how they're analyzed, and when the index syncs.

```modelhike
=== Product Module ===

Product
=======
** productId   : Id
*  name        : String
*  description : Text
*  category    : String
*  tags        : String[]
*  price       : Float { min = 0 }
*  rating      : Float { min = 0, max = 5 }

# Search
@ engine:: elasticsearch

@ fields::
| name:        text, boost: 2.0
| description: text, analyzer: english
| category:    keyword, facet: true
| tags:        keyword[], facet: true
| price:       numeric, range: true
| rating:      numeric, sort: true

@ synonyms::
| "laptop, notebook, portable computer"
| "phone, mobile, cell"

@ suggestions:: name, category, tags

@ sync::
| trigger: on-change
| batch-interval: 5 seconds
| full-reindex: Sunday 3 AM

#
```

The blueprint emits index mappings, document sync listeners, batch indexers, reindex jobs, faceted query builders, autocomplete endpoints, and synonym configuration. Adding a new searchable field is one line in `@ fields::`. The entity's access control (`@ roles::`) is inherited by the search index.

---

## 25. Background Jobs

Jobs are declared as a `# Jobs` attached section on a module. A job is a **thin scheduling envelope**: it declares *when* to run, *how reliably*, and *what to monitor*. The actual work is always delegated to flows, rules, services, and templates that are defined and testable independently.

**Design principle:** If a job's `action:` block gets complex, that's a smell. Extract a flow or a rule set. The job should be one or two lines of delegation, not 20 lines of inline logic.

```modelhike
=== Billing Module ===

# Jobs

// ---- Simple job: one service call ----

cleanupExpiredSessions:
| trigger: daily at 03:00
| concurrency: 1
| action:
| | call sessionService.deleteExpired()

// ---- Simple job: sync on an interval ----

syncInventory:
| trigger: every 15 minutes
| concurrency: 1
| skip-if: previous-run.still-active
| timeout: 10 minutes
| action:
| | call inventoryService.syncFromWarehouse()

// ---- Complex job: delegates to a flow ----
// The flow handles orchestration: pricing, currency, PDF, email.
// The job just says "when and for whom."

generateMonthlyInvoices:
| trigger: first-of-month at 06:00
| concurrency: 10
| priority: high
| for-each: Account where status == "ACTIVE"
| on-failure: retry 2 then dead-letter
| monitor: duration, processed-count, failure-count
| alert: duration > 2 hours
| action:
| | run @"Invoice Generation Flow" with (account, currentMonth())

// ---- Complex job: delegates to rules + service ----

nightlyRiskReassessment:
| trigger: daily at 02:00
| concurrency: 5
| for-each: Customer where tier != "FREE"
| on-failure: skip-item, collect-errors
| action:
| | decide @"Customer Risk Score" with (customer) -> riskResult
| | call customerService.updateRiskLevel(customer.id, riskResult.riskLevel)

#
```

### What to notice

1. **Jobs are scheduling, not logic.** `trigger:` says when. `concurrency:` says how many in parallel. `on-failure:` says what happens when it breaks. `action:` says what to run. The what is always a delegation.
2. **Simple jobs call a service.** `call sessionService.deleteExpired()` is one line. No flow or rule set needed. The service method already exists.
3. **Complex jobs delegate to flows.** `run @"Invoice Generation Flow" with (account, currentMonth())` hands off to a flow that orchestrates pricing rules, currency conversion, PDF generation, and customer notification. The job doesn't know or care about those details.
4. **Complex jobs delegate to rules.** `decide @"Customer Risk Score" with (customer)` evaluates a scoring rule set. The job iterates over customers; the rule set evaluates each one.
5. **`for-each:` handles batch iteration.** The job iterates over a collection. Per-item failures are handled by `on-failure:` without stopping the batch.
6. **The blueprint emits**: job runner, batch processor, concurrency limiter, skip/retry logic, dead letter queue, monitoring dashboards (duration, processed count, failure count), and alerting hooks.

---

## 26. Test Data / Fixtures

Fixtures are declared as a `# Fixtures` attached section on entities. Each named scenario provides seed values. Environment seeding is declared per scenario.

```modelhike
=== Customer Module ===

Customer
========
** id     : Id
*  name   : String
*  email  : String
*  tier   : String <"FREE", "PRO", "ENTERPRISE">
*  region : String

# Fixtures

happy-path:
| id     = "test-customer-001"
| name   = "Acme Corp"
| email  = "billing@acme.com"
| tier   = "PRO"
| region = "US"

enterprise-customer:
| id     = "test-customer-002"
| name   = "GlobalTech Inc"
| email  = "finance@globaltech.com"
| tier   = "ENTERPRISE"
| region = "EU"

minimal:
| name   = "Test Co"
| email  = "test@example.com"
| -- All other fields use entity defaults

@ generators::
| name:   faker.company
| email:  faker.email
| region: random from Region
| tier:   weighted [FREE: 60%, PRO: 30%, ENTERPRISE: 10%]

@ seed::
| dev:     100 customers
| staging: 1000 customers

#
```

Each named scenario (`happy-path:`, `enterprise-customer:`, `minimal:`) is a fixture with explicit values. `@ generators::` declares how to create randomized bulk data. `@ seed::` declares how many to generate per environment. The blueprint emits factory methods, scenario loaders, seed scripts, and one test case per scenario with boundary values.

---

## 27. Analytics / Event Tracking

Analytics is an attached section on entities, declaring which events to track, what properties to include, funnel definitions, metrics, and data governance.

```modelhike
=== Order Module ===

Order
=====
** orderId  : Id
*  total    : Float
*  status   : String
*  customer : Reference@Customer

# Analytics

@ events::
| order.created:          id, total, items.count, customer.tier, customer.region
| order.checkout-started: id, items.count, cartValue
| order.payment-failed:   id, total, paymentMethod, failureReason
| order.fulfilled:        id, total, fulfillmentTime

@ funnels::
| purchase:   checkout-started -> payment-attempted -> payment-succeeded -> order.fulfilled
| onboarding: signup -> profile-completed -> first-order -> second-order (window=30d)

@ metrics::
| conversion-rate:      purchase.completed / purchase.started
| time-to-first-order:  first(order.created) - signup
| average-order-value:  avg(order.total)

@ destinations::
| segment: all-events
| internal-warehouse: batch every 5 minutes

@ governance::
| pii-fields: customer.email, customer.phone
| pii-redact-in: segment
| schema-enforcement: strict

#
```

`@ events::` declares what to track and with which properties. `@ funnels::` defines conversion funnels as step chains. `@ metrics::` declares computed metrics. `@ destinations::` routes events to analytics providers. `@ governance::` handles PII redaction and schema enforcement. The blueprint wires event emitters at the right touchpoints, validates event schemas, and routes to configured destinations.

---

## 28. API Versioning / Deprecation

```modelhike
=== Customer Service #blueprint(api-springboot-monorepo) ===
+ Customer Module v2
+ Customer Module v1

=== Customer Module v2 ===
@ api-version:: current = true
@ api-version:: released = 2025-06-01

Customer (PersonBase)
=====================
** id        : Id
*  firstName : String
*  lastName  : String
*  tier      : String <"FREE", "PRO", "ENTERPRISE">

# APIs ["/api/v2/customers"]
@ apis:: create, get-by-id, list, update
#

=== Customer Module v1 ===
@ api-version:: deprecated = 2025-06-01
@ api-version:: sunset     = 2025-12-31
@ api-version:: migration  = fullName -> split(" ") -> firstName, lastName; tier -> map(gold:Gold, silver:Silver)

Customer v1
===========
** id       : Id
*  fullName : String
*  tier     : String <"gold", "silver", "enterprise">

# APIs ["/api/v1/customers"]
@ apis:: get-by-id, list
#
```

API versions are separate modules with `@ api-version::` annotations. Deprecation dates, sunset dates, and field migration mappings are declared. The blueprint emits versioned controllers, request transformers, deprecation headers, and sunset enforcement.

---

## 29. Business Rules / Decisions

Business rules use the `??????` underline. The `?` character literally means "question", which is what every decision answers. Seven rule types cover the full spectrum: conditional rules, decision tables, decision trees, scoring, matching, formulas, and constraints. Rules are pure evaluation: inputs in, output out, no side effects. They're invoked from flows via `decide @"Name"`, from lifecycle `entry /` blocks, or from other rules for composition.

```modelhike
=== Pricing Module ===

// ---- Decision table: Contract rates ----

Contract Rate Lookup
????????????????????
@ input:: customer: Customer, product: Product
@ output:: contractRate: Float?
@ hit:: first

| customer.tier | product.category || contractRate |
| ------------- | ---------------- || ------------ |
| "ENTERPRISE"  | "COMPUTE"        || 0.85         |
| "ENTERPRISE"  | "STORAGE"        || 0.80         |
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

// ---- Conditional rules: Discount tiers from score ----

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

// ---- Decision tree: Loan eligibility ----

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

// ---- Matching: Trial patient matching ----

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
| by: trial.capacityRemaining / trial.capacityTotal desc
| by: distance(patient.location, trial.siteLocation) asc

limit: 5

// ---- Constraint: Cross-entity validation ----

PTO Booking Constraints
???????????????????????
@ input:: employee: Employee, request: PTORequest
@ output:: allowed: Boolean, reason: String

constraint noBlackout
| when: request.dates overlaps companyCalendar.blackoutDates
| reject: "Requested dates fall within a company blackout period"

constraint minimumStaffing
| when: countAvailable(employee.team, request.dates) < employee.team.minStaffing
| reject: "Team would fall below minimum staffing of {employee.team.minStaffing}"

constraint allocationRemaining
| when: employee.ptoUsedThisYear + request.days > employee.annualPTOAllowance
| reject: "Would exceed annual PTO allowance"

allowed = true

// ---- Composed decision: chains sub-decisions ----

Order Pricing
?????????????
@ input:: customer: Customer, order: Order
@ output:: finalTotal: Float, discountApplied: Float, pricingNotes: String[]

decide @"Contract Rate Lookup" with (customer, order.items[0].product) -> contractResult
decide @"Discount Score" with (customer, order) -> scoreResult
decide @"Discount Tier Rules" with (scoreResult.discountScore) -> tierResult

|> IF contractResult.contractRate != nil
| assign finalTotal = order.subtotal * contractResult.contractRate
| assign discountApplied = 1.0 - contractResult.contractRate
| assign pricingNotes = ["Contract rate applied"]
|> ELSE
| assign finalTotal = order.subtotal * (1.0 - tierResult.discountPercent)
| assign discountApplied = tierResult.discountPercent
| assign pricingNotes = ["Discount tier: " + tierResult.discountPercent + "%"]
end
```

### What to notice

1. **Seven rule types, one underline.** `??????` handles decision tables (Contract Rate), scoring (Discount Score), conditional rules (Discount Tier), decision trees (Loan Eligibility), matching (Trial Match), constraints (PTO Booking), and composition (Order Pricing). Each type has the right syntax for its pattern.
2. **Decision tables use `||` to separate inputs from outputs.** `| customer.tier | product.category || contractRate |` reads like a spreadsheet. `-` means "any value." Hit policies (`@ hit:: first`, `collect sum`, `unique`) control evaluation behavior, borrowed from DMN.
3. **Decision trees use folder-tree syntax.** `├──[` opens a condition branch. `└──` marks the last branch. `│` continues the vertical line. You literally see the tree shape. The structure of the decision IS the structure of the text.
4. **Scoring rules accumulate points.** Each `score` criterion contributes independently. `@ score:: range 0..100` caps the total. This replaces 80-150 lines of accumulator logic in a typical risk scoring service.
5. **Matching rules are filter-rank pipelines.** `filter / | include: / | exclude:` then `rank / | by: expression asc/desc` then `limit: N`. Replaces 100-200 lines of filter/sort code.
6. **Constraints collect ALL violations.** Unlike conditional rules that short-circuit, every `constraint` is evaluated. The output is the full list of violations, not just the first. A PTO request might fail on both blackout AND staffing simultaneously.
7. **`decide @"Name"` chains decisions.** Order Pricing calls Contract Rate Lookup, then Discount Score, then Discount Tier Rules, threading outputs to inputs. The blueprint generates a Decision Requirements Diagram (DRD) from this chain.
8. **Rules are pure.** No side effects. No state mutation. No DB writes. Inputs in, output out. This makes them testable, cacheable, and safe to call from anywhere: flows, lifecycle entry actions, other rules, or UI action handlers.
9. **Invoked from flows and lifecycles.** `decide @"Loan Eligibility Tree" with (applicant, amount) -> result` works inside a `>>>>>>` flow block. `| entry / decide @"Risk Score" with (order) -> risk` works inside a lifecycle state's entry actions.

---

## 30. Document Templates

Document templates use the `/#####/` underline. Templates have merge fields (`"{entity.field}"`), conditional sections (`|> IF`), repeating tables (`table: collection`), headers, footers, and page breaks. One template generates PDF, HTML, and email.

```modelhike
=== Invoice Module ===

Invoice Document (Invoice, Customer, LineItem[])
/###############################################/
@ output:: pdf, html, email
@ page:: A4, portrait, margins: 20mm

header:
| Company Logo                      (position=left)
| "{company.name}"                  (position=center, style=bold)
| "Invoice"                         (position=right, style=h1)

section Invoice Details: (two-column)
| "Invoice #:"    "{invoice.number}"
| "Date:"         "{invoice.createdAt | format: date}"
| "Due Date:"     "{invoice.dueDate | format: date}"

section Bill To:
| "{customer.name}"                 (style=bold)
| "{customer.billingAddress.line1}"
| "{customer.billingAddress.city}, {customer.billingAddress.state}"

section Line Items:
| table: invoice.items
| | column: "Item"         -> item.name
| | column: "Qty"          -> item.quantity          (align=right)
| | column: "Unit Price"   -> item.unitPrice         (format=currency)
| | column: "Total"        -> item.total             (format=currency)
| footer-row:
| | ""  ""  "Subtotal:"   "{invoice.subtotal | format: currency}"
| | ""  ""  "Tax:"        "{invoice.taxAmount | format: currency}"
| | ""  ""  "Total:"      "{invoice.total | format: currency}"  (style=bold)

|> IF invoice.notes
| section Notes:
| | "{invoice.notes}"
end

|> IF invoice.status == "OVERDUE"
| section Overdue Notice: (style=warning)
| | "This invoice is {daysBetween(invoice.dueDate, today())} days overdue."
end

footer:
| "Page {pageNumber} of {pageCount}"    (position=center)
```

The blueprint emits PDF/HTML renderers, email wrappers, preview endpoints, and bulk generation support. Merge fields bind to entity data. Conditional sections show/hide based on runtime values. The template IS the spec.

---

## 31. Data Import/Export Pipelines

Import and export are attached sections on entities, like `# APIs`. They're dependent operations, not part of the class definition itself. `# Import` and `# Export` blocks declare column mapping, format support, duplicate handling, and error policies.

```modelhike
=== Customer Module ===

Customer
========
** id     : Id
*  name   : String
*  email  : String { pattern = ^[\w.-]+@[\w.-]+\.[a-z]{2,}$ }
- phone  : String
*  tier   : String = "FREE" <"FREE", "PRO", "ENTERPRISE">
*  region : String

# Import
@ format:: csv, xlsx
@ column-mapping::
| "Customer Name"     -> name
| "Email Address"     -> email
| "Phone"             -> phone
| "Tier"              -> tier (default="FREE")
| "Region"            -> region
@ on-duplicate:: update (match-by=email)
@ on-error:: skip-row, collect-errors
@ max-rows:: 10000
@ preview:: true
#

# Export
@ format:: csv, xlsx, pdf
@ columns:: name, email, phone, tier, region, createdAt
@ filename:: "customers-{date}"
@ max-rows:: 50000
#
```

The blueprint emits: import endpoint (`POST /customers/import`) with column mapping UI, row-level validation (reuses entity constraints), duplicate detection, error report with row numbers and violation messages, and preview mode showing what will be created/updated before committing. Export generates `GET /customers/export?format=csv`. All validation comes from the entity's existing constraints and valid value sets.

---

## 32. Date/Calendar Logic

Calendars are standalone config objects using the `::::::::` underline. The colon character suggests key:value configuration. The attribute in `( )` tells what kind of config: `(calendar)`, `(sequence)`, `(currency)`, `(uom)`.

```modelhike
=== Core Module ===

US Business Calendar (calendar)
:::::::::::::::::::::::::::::::
holidays = US-Federal
custom-holidays:
| 2026-12-24  "Christmas Eve"
| 2026-12-26  "Day after Christmas"
working-hours = 09:00-17:00
working-days  = Mon-Fri
timezone      = America/New_York

Company Fiscal Calendar (calendar, fiscal)
::::::::::::::::::::::::::::::::::::::::::
year-start = April 1
periods:
| Q1: Apr-Jun
| Q2: Jul-Sep
| Q3: Oct-Dec
| Q4: Jan-Mar
```

Usage in entities via `@"Config Name"` references:

```modelhike
Invoice
=======
*  dueDate       : Date
=  dueDateBusiness : Date = dueDate | nextBusinessDay(@"US Business Calendar")
=  agingDays     : Int = businessDaysBetween(dueDate, today(), @"US Business Calendar")
=  fiscalPeriod  : String = fiscalPeriod(createdAt, @"Company Fiscal Calendar")
```

Built-in functions: `nextBusinessDay`, `addBusinessDays`, `businessDaysBetween`, `isBusinessDay`, `fiscalPeriod`, `fiscalYear`, `workingHoursUntil`. All take a `@"Calendar Name"` reference to know which calendar to evaluate against.

---

## 33. Hierarchical Data Operations

Hierarchies are self-referential entities (an entity whose field points to the same type: `Employee.reportsTo -> Employee`). The `# Hierarchy` attached section (like `# APIs`, `# Import`, `# Export`) declares what tree operations the blueprint should generate: ancestors, descendants, breadcrumbs, BOM explosion, cost rollup, reparenting.

```modelhike
=== Manufacturing Module ===

BOM Item
========
** id          : Id
*  partNumber  : String
*  name        : String
*  parent      : Reference@BOM Item?       -- self-referential (? = root has no parent)
*  components  : BOM Item[]                -- inverse: children
*  quantity    : Float = 1                 -- how many of this per parent unit
*  unitCost    : Float
-  level       : Int                       -- auto-computed tree depth
-  path        : String                    -- auto-computed: "Bicycle > Wheel Assembly > Rim"

# Hierarchy
@ parent:: parent
@ children:: components
@ max-depth:: 25
@ cycle-detection:: true

explode:
| -- Recursive expansion with quantity multiplication at each level
| -- "10 Bicycles" needs "20 Wheel Assemblies" (2 per bike) needs "720 Spokes" (36 per wheel)
| direction: down
| include-self: true
| multiply: quantity
| returns: BOM Explosion[]

rollup-cost:
| -- Sum cost from leaves up to root
| direction: down
| aggregate: sum(unitCost * quantity)
| returns: Float

where-used:
| -- Given a part, find all assemblies that contain it
| direction: up
| include-self: false
| returns: BOM Item[]

leaf-parts:
| -- All raw materials (parts with no children)
| direction: down
| filter: components.count == 0
| returns: BOM Item[]

#
```

The same pattern works for any tree structure:

```modelhike
=== HR Module ===

Employee
========
** id            : Id
*  name          : String
*  title         : String
*  reportsTo     : Reference@Employee?
*  directReports : Employee[]
-  level         : Int

# Hierarchy
@ parent:: reportsTo
@ children:: directReports
@ max-depth:: 15

management-chain:
| direction: up
| include-self: true
| returns: Employee[]

team:
| direction: down
| include-self: false
| returns: Employee[]

team-size:
| direction: down
| aggregate: count
| returns: Int

#
```

```modelhike
=== Finance Module ===

Account
=======
** accountCode   : String
*  name          : String
*  parentAccount : Reference@Account?
*  subAccounts   : Account[]
*  balance       : Float = 0

# Hierarchy
@ parent:: parentAccount
@ children:: subAccounts

rollup-balance:
| direction: down
| aggregate: sum(balance)
| returns: Float

account-path:
| direction: up
| include-self: true
| returns: String
| format: "{name}" joined by " > "

#
```

### What to notice

1. **`# Hierarchy` is an attached section.** Same pattern as `# APIs`, `# Import`, `# Export`. It declares operations on the entity, not properties of the entity.
2. **Each named operation is declarative.** `explode:`, `rollup-cost:`, `where-used:`, `management-chain:`. The `|` block specifies direction, aggregation, filtering, and return type. The blueprint generates the recursive query.
3. **`multiply: quantity` is the BOM magic.** It tells the blueprint to accumulate quantity at each tree level. "10 bicycles * 2 wheels per bike * 36 spokes per wheel = 720 spokes." One directive replaces 50 lines of recursive accumulator code.
4. **`aggregate: sum(field)` does bottom-up rollup.** Chart of accounts: `rollup-balance` sums all descendant balances. One directive replaces a recursive CTE with accumulation.
5. **`format: "{name}" joined by " > "` produces breadcrumbs.** The blueprint traverses up, collects the `name` field at each level, and joins them. `"Electronics > Phones > Smartphones"` from one declaration.
6. **Hierarchy operations are callable everywhere.** From flows: `call employee.management-chain(submitter.id)`. From rules: `employee.team-size(employee.id)`. From lifecycle guards: `{account.rollup-balance > 0}`. They're generated as methods/endpoints like any other.
7. **The blueprint emits recursive CTEs, cycle detection, depth limits, and materialized paths.** `level` and `path` fields are auto-maintained on insert/update. Circular references are caught before they corrupt the tree.

---

## 34. Number Sequences

Sequence generators are config objects with the `::::::::` underline. Each config declares a pattern, scope, and reset policy for auto-generated identifiers.

```modelhike
=== Finance Module ===

Invoice Numbering (sequence)
::::::::::::::::::::::::::::
target  = Invoice.invoiceNumber
pattern = "INV-{YYYY}-{seq:6}"
scope   = tenant
reset   = fiscal-year
gap-free = true

PO Numbering (sequence)
::::::::::::::::::::::::
target  = Purchase Order.poNumber
pattern = "PO-{region}-{seq:5}"
scope   = region
gap-free = false

Receipt Numbering (sequence)
::::::::::::::::::::::::::::
target  = Receipt.receiptNumber
pattern = "RCV-{YYYY}{MM}-{seq:4}"
scope   = global
reset   = monthly
```

`target` binds the sequence to a specific entity field. Pattern tokens: `{seq:N}` (zero-padded), `{YYYY}`, `{YY}`, `{MM}`, `{DD}`, `{region}`, `{tenant}`, `{FY}`, `{FQ}`. The blueprint emits sequence generators with the configured scope, reset, and gap-free guarantees.

---

## 35. Multi-currency / Unit of Measure

Currency and UoM are config objects with the `::::::::` underline. They declare conversion rules, rate sources, and rounding behavior as standalone configuration.

```modelhike
=== Finance Module ===

Platform Currency (currency)
::::::::::::::::::::::::::::
base         = USD
supported    = USD, EUR, GBP, JPY, INR
rate-source  = external-api
rate-refresh = daily
triangulation = true
rounding:
| USD -> 2 decimals
| EUR -> 2 decimals
| JPY -> 0 decimals

=== Inventory Module ===

Weight Conversions (uom, weight)
::::::::::::::::::::::::::::::::
base = kg
conversions:
| kg  -> lb   * 2.20462
| lb  -> kg   * 0.453592
| oz  -> g    * 28.3495
| g   -> oz   * 0.035274

Volume Conversions (uom, volume)
::::::::::::::::::::::::::::::::
base = l
conversions:
| l   -> gal  * 0.264172
| gal -> l    * 3.78541
| ml  -> fl_oz * 0.033814

Quantity Conversions (uom, quantity)
::::::::::::::::::::::::::::::::::::
base = piece
conversions:
| piece -> dozen  / 12
| piece -> case   / 24
| piece -> pallet / 480
```

Usage in entities via built-in functions:

```modelhike
Invoice
=======
*  amount        : Float
*  currency      : String = "USD"
=  amountBase    : Float = convert(amount, currency, "USD", @"Platform Currency")

Product
=======
*  weight        : Float
*  weightUnit    : String <"kg", "lb", "oz">
=  weightKg      : Float = convertUoM(weight, weightUnit, "kg", @"Weight Conversions")
```

Built-in functions: `convert(amount, from, to, config)`, `convertAsOf(amount, from, to, date, config)`, `convertUoM(value, from, to, config)`, `round(amount, currency, config)`.

---

## 36. Draft/Publish Versioning

One `@ versioned::` annotation auto-generates version history, a draft/publish lifecycle, diff tracking, and rollback APIs.

```modelhike
Email Template (Auditable)
==========================
@ versioned:: strategy = draft-publish
@ versioned:: max-versions = 50
@ versioned:: diff = field-level

** id      : Id
*  name    : String
*  subject : String
*  body    : Text
*  status  : String = "DRAFT" <"DRAFT", "PUBLISHED", "ARCHIVED">
```

From this single annotation, the blueprint generates: a version history entity (with snapshots and field-level diffs), a lifecycle with `DRAFT -> PUBLISHED -> ARCHIVED` transitions, and API endpoints for `GET /templates/{id}/versions`, `POST /templates/{id}/versions/{ver}/restore`, and `GET /templates/{id}/diff/{v1}/{v2}`.

---

---

# The Math

| # | Category | Imperative LOC | ModelHike LOC | Ratio |
|---|---|---|---|---|
| 1 | Validation | 2,000 | 200 | 10:1 |
| 2 | Access Control | 1,500 | 150 | 10:1 |
| 3 | Data Mappings | 3,000 | 300 | 10:1 |
| 4 | UI Layouts/Forms | 8,000 | 800 | 10:1 |
| 5 | Schema/Models | 4,000 | 400 | 10:1 |
| 6 | Configuration | 1,000 | 100 | 10:1 |
| 7 | Routing/API | 3,000 | 300 | 10:1 |
| 8 | Workflows | 5,000 | 500 | 10:1 |
| 9 | Approvals | 2,000 | 150 | 13:1 |
| 10 | Notifications | 2,500 | 200 | 12:1 |
| 11 | Integrations | 4,000 | 300 | 13:1 |
| 12 | Error Handling | 3,000 | 200 | 15:1 |
| 13 | Scheduling | 1,000 | 100 | 10:1 |
| 14 | Reporting | 3,000 | 300 | 10:1 |
| 15 | CRUD | 20,000 | 1,500 | 13:1 |
| 16 | State Machines | 3,000 | 250 | 12:1 |
| 17 | Audit / Change Tracking | 2,500 | 150 | 17:1 |
| 18 | Localization / i18n | 3,000 | 300 | 10:1 |
| 19 | Caching Policies | 1,500 | 100 | 15:1 |
| 20 | Rate Limiting | 1,000 | 80 | 13:1 |
| 21 | Events / Webhooks | 2,000 | 150 | 13:1 |
| 22 | File / Media Handling | 2,500 | 200 | 13:1 |
| 23 | Multi-tenancy | 3,000 | 150 | 20:1 |
| 24 | Search / Indexing | 2,000 | 150 | 13:1 |
| 25 | Background Jobs | 2,500 | 200 | 13:1 |
| 26 | Test Data / Fixtures | 3,000 | 200 | 15:1 |
| 27 | Analytics / Event Tracking | 2,000 | 150 | 13:1 |
| 28 | API Versioning | 2,000 | 150 | 13:1 |
| 29 | Business Rules / Decisions | 5,000 | 400 | 13:1 |
| 30 | Document Templates | 3,000 | 250 | 12:1 |
| 31 | Data Import/Export | 2,000 | 100 | 20:1 |
| 32 | Date/Calendar Logic | 1,500 | 80 | 19:1 |
| 33 | Hierarchical Operations | 3,000 | 200 | 15:1 |
| 34 | Number Sequences | 1,000 | 50 | 20:1 |
| 35 | Multi-currency / UoM | 1,500 | 100 | 15:1 |
| 36 | Draft/Publish Versioning | 2,000 | 100 | 20:1 |
| | **Total** | **~110,000** | **~8,710** | **~13:1** |

---