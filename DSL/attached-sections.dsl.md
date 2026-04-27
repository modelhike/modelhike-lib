# ModelHike Attached Sections Guide

**Syntax:** `# SectionName ... #`
**Purpose:** Declare operations ON entities that aren't properties OF the entity. Same open/close pattern throughout.

---

## What Are Attached Sections?

An entity has two kinds of declarations:

1. **Properties** (inside the `=====` block): fields, types, constraints. These ARE the entity.
2. **Attached sections** (after properties): operations, policies, and behaviors that act ON the entity.

```modelhike
Customer                          -- entity header
========                          -- entity underline
** id    : Id                     -- property (IS the entity)
*  name  : String                 -- property
*  email : String                 -- property

# APIs ["/customers"]             -- section (operates ON the entity)
@ apis:: create, get-by-id, list
#

# Import                         -- section (operates ON the entity)
@ format:: csv, xlsx
#

# Cache                           -- section (operates ON the entity)
@ strategy:: read-through
@ ttl:: 1 hour
#
```

Every section opens with `#` and closes with `#`. Inside, `@ keyword::` annotations declare the configuration. Some sections contain named sub-blocks with `|` continuation.

---

## All Attached Sections at a Glance

| Section | Purpose | Typical entity |
|---------|---------|----------------|
| `# APIs` | REST/GraphQL/gRPC endpoint generation | Any entity exposed via API |
| `# Import` | Bulk data import (CSV, XLSX) | Entities with bulk-load needs |
| `# Export` | Bulk data export | Entities with reporting/extract needs |
| `# Cache` | Caching policy | Frequently read entities |
| `# Rate Limit` | API throttling | Entities with public-facing APIs |
| `# Search` | Full-text search indexing | Entities needing search beyond DB queries |
| `# Media` | File/image upload handling | Entities with file fields |
| `# Hierarchy` | Tree traversal operations | Self-referential entities |
| `# Fixtures` | Test data declarations | Any entity needing test scenarios |
| `# Analytics` | Event tracking and funnels | Entities with business events to track |
| `# Error Policy` | Retry/failure handling for methods | Entities with integration methods |
| `# Versioned` | Draft/publish versioning with version history | Content entities (templates, policies, pages) |
| `# Jobs` | Background job scheduling | Module-level (not entity-level) |

---

## 1. `# APIs`

**Already documented in** [modelHike.dsl.md](modelHike.dsl.md). Quick reference:

```modelhike
# APIs ["/orders"]
@ apis:: create, get-by-id, list, update, delete
@ list-api :: status -> status; customer -> customer.id
## list by status
## discount(price: Float) : Order (route="/orders/{id}/discount", method=POST, roles=admin)
#
```

- `["/route"]` inferred route attribute
- `@ apis::` CRUD scaffold keywords
- `@ list-api::` query param mapping
- `## list by field` auto-filtered list endpoint
- `## customOp(params) : ReturnType (attributes)` custom endpoint

---

## 2. `# Import`

Declares how to bulk-load data into this entity from external files.

```modelhike
# Import
@ format:: csv, xlsx
@ column-mapping::
| "Customer Name"     -> name
| "Email Address"     -> email
| "Phone"             -> phone
| "Tier"              -> tier (default="FREE")
@ on-duplicate:: update (match-by=email)
@ on-error:: skip-row, collect-errors
@ max-rows:: 10000
@ preview:: true
#
```

### Directives

| Directive | Purpose | Example |
|-----------|---------|---------|
| `@ format::` | Accepted file formats | `csv, xlsx` |
| `@ column-mapping::` | External column names to entity fields | `"Customer Name" -> name` |
| `(default=value)` | Default when column is missing | `(default="FREE")` |
| `@ on-duplicate::` | What to do when a matching record exists | `update (match-by=email)`, `skip`, `error` |
| `@ on-error::` | Row-level error handling | `skip-row, collect-errors` / `fail-fast` |
| `@ max-rows::` | Safety limit | `10000` |
| `@ preview::` | Show preview before committing | `true` / `false` |

### Blueprint output
- Import endpoint: `POST /entity/import`
- Column mapping UI auto-generated
- Row-level validation using entity constraints
- Error report with row numbers, field names, violations
- Preview mode: dry run showing creates/updates without committing

---

## 3. `# Export`

Declares how to extract data from this entity.

```modelhike
# Export
@ format:: csv, xlsx, pdf
@ columns:: name, email, phone, tier, region, createdAt
@ filename:: "customers-{date}"
@ max-rows:: 50000
#
```

### Directives

| Directive | Purpose | Example |
|-----------|---------|---------|
| `@ format::` | Output file formats | `csv, xlsx, pdf` |
| `@ columns::` | Which fields to include | `name, email, tier` |
| `@ filename::` | Download filename pattern | `"customers-{date}"` |
| `@ max-rows::` | Row limit | `50000` |

### Blueprint output
- Export endpoint: `GET /entity/export?format=csv`
- Streaming response for large datasets
- Filename with date substitution

---

## 4. `# Cache`

Declares caching policy for this entity.

```modelhike
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

### Directives

| Directive | Purpose | Values |
|-----------|---------|--------|
| `@ strategy::` | Cache strategy | `read-through`, `write-behind`, `precompute` |
| `@ ttl::` | Time to live | `1 hour`, `15 minutes`, `1 day` |
| `@ eviction::` | Eviction policy | `lru`, `lfu`, `fifo` |
| `@ max-entries::` | Maximum cached items | Integer |
| `@ exclude-when::` | Don't cache if condition | Expression |
| `@ invalidate-on::` | Events that clear cache | `entity.updated, entity.deleted` |
| `@ warm-on::` | Events that pre-populate cache | `entity.created` |

### Blueprint output
- Cache annotations on repository/service methods
- Eviction listeners wired to specified events
- Cache warming jobs
- Monitoring metrics: `hit_rate`, `miss_rate`, `eviction_count`

---

## 5. `# Rate Limit`

Declares API throttling policy.

```modelhike
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

### Directives

| Directive | Purpose | Example |
|-----------|---------|---------|
| `@ default::` | Default rate for all endpoints | `100/minute per user` |
| `@ tiers::` | Per-customer-tier rates | `|` block with tier:rate pairs |
| `@ overrides::` | Per-endpoint overrides | `|` block with route:rate pairs |
| `@ burst::` | Burst allowance | `allow 2x for 10 seconds` |
| `@ response::` | HTTP status when exceeded | `429` |
| `@ headers::` | Response headers to include | Standard rate limit headers |

### Blueprint output
- Middleware wired to API endpoints
- Tier resolution from customer data
- Response headers on every API response
- Monitoring metrics

---

## 6. `# Search`

Declares full-text search indexing for this entity.

```modelhike
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

### Field types

| Type | Purpose | Supports |
|------|---------|----------|
| `text` | Full-text searchable | `boost`, `analyzer` |
| `keyword` | Exact match | `facet` (for filter dropdowns) |
| `keyword[]` | Multi-value exact match | `facet` |
| `numeric` | Number field | `range` (for sliders), `sort` |
| `date` | Date field | `range`, `sort` |

### Sync modes

| Mode | Meaning |
|------|---------|
| `on-change` | Index updated on every entity create/update/delete |
| `batch-interval: 5s` | Batch pending changes every N seconds |
| `full-reindex: Sunday 3 AM` | Complete re-index on schedule |

### Blueprint output
- Index mapping (Elasticsearch/OpenSearch)
- Document sync listener
- Batch indexer
- Full reindex job
- Faceted search query builder
- Autocomplete endpoint
- Synonym configuration

---

## 7. `# Media`

Declares file/image handling for a specific field on the entity.

```modelhike
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

### Directives

| Directive | Purpose | Example |
|-----------|---------|---------|
| `@ field::` | Which entity field holds the file URL | `avatarUrl` |
| `@ accept::` | Allowed MIME types | `image/jpeg, image/png` |
| `@ max-size::` | Maximum file size | `10 MB` |
| `@ deduplicate::` | Dedup strategy | `content-hash` |
| `@ scan::` | Security scanning | `virus-check` |
| `@ variants::` | Image variant generation | `|` block with variant specs |
| `@ storage::` | Where to store files | `|` block with provider config |
| `@ metadata::` | What to extract/strip | `|` block with extract/strip rules |

### Blueprint output
- Upload endpoint with validation
- Virus scanning integration
- Image processing pipeline for each variant
- Storage client (S3, GCS, Azure Blob, local)
- Signed URL generator
- Metadata extraction and privacy stripping

---

## 8. `# Hierarchy`

Declares tree traversal operations for self-referential entities. **Full guide:** [hierarchy.dsl.md](hierarchy.dsl.md)

```modelhike
# Hierarchy
@ parent:: parentField
@ children:: childrenField
@ max-depth:: 25
@ cycle-detection:: true

operationName:
| direction: up | down
| include-self: true | false
| multiply: quantityField
| aggregate: sum(field) | count | min(field) | max(field)
| filter: expression
| returns: Type
| format: "{field}" joined by "separator"

#
```

---

## 9. `# Fixtures`

Declares test data for this entity.

```modelhike
# Fixtures

happy-path:
| id     = "test-001"
| name   = "Acme Corp"
| email  = "billing@acme.com"
| tier   = "PRO"

edge-case-empty:
| name   = "Minimal Co"
| email  = "test@example.com"
| -- All other fields use entity defaults

@ generators::
| name:   faker.company
| email:  faker.email
| tier:   weighted [FREE: 60%, PRO: 30%, ENTERPRISE: 10%]

@ seed::
| dev:     100
| staging: 1000

#
```

### Parts

| Part | Purpose |
|------|---------|
| Named scenarios (`name:`) | Specific fixtures with explicit values |
| `@ generators::` | How to generate random bulk data |
| `@ seed::` | How many to generate per environment |

### Blueprint output
- Factory methods per scenario
- Scenario loader for integration tests
- Seed scripts per environment
- One test case per scenario with boundary values

---

## 10. `# Analytics`

Declares event tracking, funnels, metrics, and data governance.

```modelhike
# Analytics

@ events::
| order.created:          id, total, items.count, customer.tier
| order.checkout-started: id, items.count, cartValue
| order.payment-failed:   id, total, failureReason

@ funnels::
| purchase:   checkout-started -> payment-attempted -> payment-succeeded -> order.fulfilled
| onboarding: signup -> profile-completed -> first-order (window=30d)

@ metrics::
| conversion-rate:     purchase.completed / purchase.started
| average-order-value: avg(order.total)

@ destinations::
| segment: all-events
| warehouse: batch every 5 minutes

@ governance::
| pii-fields: customer.email, customer.phone
| pii-redact-in: segment
| schema-enforcement: strict

#
```

### Parts

| Part | Purpose |
|------|---------|
| `@ events::` | What to track and with which properties |
| `@ funnels::` | Conversion funnels as step chains |
| `@ metrics::` | Computed metrics |
| `@ destinations::` | Where events are routed |
| `@ governance::` | PII handling and schema enforcement |

### Blueprint output
- Event emitters at entity lifecycle touchpoints
- Event schema validation
- Funnel tracking
- Metric computation
- Multi-destination routing
- PII field redaction per destination

---

## 11. `# Error Policy`

Declares error handling for specific methods on the entity.

```modelhike
# Error Policy
@ applies-to:: processPayment

on Timeout:
| retry: 3, backoff: exponential(1s)
| then: dead-letter

on InsufficientFunds:
| retry: none
| notify: customer, template: payment_failed

on FraudDetected:
| retry: none
| call: freezeAccount(orderId)
| notify: team(Fraud), template: fraud_alert (priority=critical)

on Unknown:
| retry: 1
| then: dead-letter
| alert: team(Engineering), severity: high

#
```

### Error handler directives

| Directive | Purpose | Example |
|-----------|---------|---------|
| `@ applies-to::` | Which method this policy covers | `processPayment` |
| `on ExceptionType:` | Handler for specific error | `on Timeout:`, `on Unknown:` |
| `retry:` | Retry count and strategy | `3, backoff: exponential(1s)` |
| `then:` | After retries exhausted | `dead-letter`, `escalate`, `manual-review` |
| `notify:` | Send notification | `customer, template: name` |
| `call:` | Execute an action | `freezeAccount(orderId)` |
| `alert:` | Operations alert | `team(Engineering), severity: high` |

### Blueprint output
- Try/catch blocks wrapping the method
- Retry loop with configured backoff
- Dead letter queue integration
- Notification dispatch per error type
- Operations alerting

---

## 12. `# Versioned`

Declares a draft/publish content lifecycle with auto-generated version history. For entities whose content evolves over time and needs editorial control: email templates, policy documents, page content, product descriptions.

```modelhike
=== Content Module ===

Email Template (Auditable)
==========================
** id           : Id
*  name         : String
*  subject      : String
*  body         : Text
*  category     : String
-  variables    : String[]                -- merge field names
*  status       : String = "DRAFT" <"DRAFT", "PUBLISHED", "ARCHIVED">

# Versioned
@ strategy:: draft-publish
@ max-versions:: 50
@ auto-archive:: after 1 year
@ diff:: field-level                      -- track which fields changed per version
#
```

### Directives

| Directive | Purpose | Example |
|-----------|---------|---------|
| `@ strategy::` | Versioning strategy | `draft-publish` (only value currently) |
| `@ max-versions::` | Maximum versions retained | `50` |
| `@ auto-archive::` | When to archive old versions | `after 1 year`, `never` |
| `@ diff::` | Diff granularity | `field-level`, `document-level` |

### Blueprint output

The annotation auto-generates four artifacts.

**1. A version history entity:**

```modelhike
// Auto-generated alongside the source entity
Email Template Version
======================
* templateId  : Reference@Email Template
* version     : Int
* status      : String <"DRAFT", "PUBLISHED", "ARCHIVED">
* fields      : JSON                      -- snapshot of all fields at this version
* diff        : JSON                      -- field-level diff from previous version
* createdBy   : Reference@User
* createdAt   : DateTime
* publishedAt : DateTime?
* publishedBy : Reference@User?
```

**2. A lifecycle:**

```modelhike
Email Template Lifecycle
>>>>>>>>>>>>>>>>>>>>>>>>

state DRAFT
| entry / capture updatedAt = now(), updatedBy = currentUser()
| entry / emit TemplateDraftSaved

state PUBLISHED
| entry / capture publishedAt = now(), publishedBy = currentUser()
| entry / emit TemplatePublished

state ARCHIVED
| entry / emit TemplateArchived
| terminal

[*] --> DRAFT

\__ DRAFT -> PUBLISHED : publish [editor, admin]
| api POST /templates/{id}/publish
| call createVersionSnapshot(self, "PUBLISHED")

\__ PUBLISHED -> DRAFT : unpublish [admin]
| api POST /templates/{id}/unpublish

\__ DRAFT -> DRAFT : saveDraft [editor, admin]
| internal
| call createVersionSnapshot(self, "DRAFT")

\__ PUBLISHED -> ARCHIVED : archive [admin]
| api POST /templates/{id}/archive

\__ ARCHIVED -> DRAFT : restore [admin]
| api POST /templates/{id}/restore
| call restoreFromVersion(self, latestPublishedVersion)
```

**3. API endpoints:**

```
GET    /templates/{id}/versions          -- list version history
GET    /templates/{id}/versions/{ver}    -- get specific version
POST   /templates/{id}/versions/{ver}/restore  -- rollback to version
GET    /templates/{id}/diff/{v1}/{v2}    -- diff between two versions
```

**4. Snapshot helpers:**

- `createVersionSnapshot(entity, status)`: invoked from lifecycle transitions; persists current field values plus a diff against the previous version.
- `restoreFromVersion(entity, version)`: copies the snapshot back onto the entity and creates a new version entry recording the restore.

All from one `# Versioned` section. The source entity itself stays simple: it just has its own fields, optionally a `status` field if the application surface needs it. Everything else: history entity, lifecycle, snapshot pipeline, REST endpoints, is generated.

---

## 13. `# Jobs` (Module-level)

Unlike other sections that attach to entities, `# Jobs` attaches to a **module**. Jobs schedule background work.

```modelhike
=== Billing Module ===

# Jobs

generateMonthlyInvoices:
| trigger: first-of-month at 06:00
| for-each: Account where status == "ACTIVE"
| concurrency: 10
| on-failure: retry 2 then dead-letter
| monitor: duration, processed-count, failure-count
| action:
| | run @"Invoice Generation Flow" with (account, currentMonth())

syncInventory:
| trigger: every 15 minutes
| skip-if: previous-run.still-active
| timeout: 10 minutes
| action:
| | call inventoryService.syncFromWarehouse()

#
```

### Job directives

| Directive | Purpose | Example |
|-----------|---------|---------|
| `trigger:` | When to run | `first-of-month at 06:00`, `daily at 03:00`, `every 15 minutes` |
| `for-each:` | Iterate over a collection | `Account where status == "ACTIVE"` |
| `concurrency:` | Parallel execution limit | `10` |
| `priority:` | Scheduling priority | `high`, `low` |
| `skip-if:` | Condition to skip execution | `previous-run.still-active` |
| `timeout:` | Max duration | `10 minutes` |
| `on-failure:` | Error handling | `retry 2 then dead-letter`, `skip-item, collect-errors` |
| `monitor:` | Metrics to track | `duration, processed-count, failure-count` |
| `alert:` | Alert condition | `duration > 2 hours` |
| `action:` | The work (always delegation) | `run @"Flow"`, `decide @"Rules"`, `call service.method()` |

### Design principle: jobs delegate

A job is a thin scheduling envelope. If `action:` grows beyond 2-3 lines, extract a flow or rule set. The job says "when and how reliably." The flow says "what steps." The rules say "what logic."

---

## Section Ordering Convention

When an entity has multiple sections, the recommended order is:

```modelhike
Entity
======
** fields
*  fields

# APIs          -- how it's exposed
#

# Import        -- how it's bulk-loaded
#

# Export        -- how it's extracted
#

# Cache         -- how it's cached
#

# Rate Limit    -- how it's throttled
#

# Search        -- how it's indexed
#

# Media         -- how files are handled
#

# Hierarchy     -- how tree operations work
#

# Fixtures      -- test data
#

# Analytics     -- event tracking
#

# Error Policy  -- failure handling
#

# Versioned     -- draft/publish versioning
#
```

Not every entity needs every section. Most entities have `# APIs` and maybe one or two others. A fully decorated entity with all 13 sections would be unusual but valid.
