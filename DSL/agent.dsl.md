# ModelHike Agent DSL Specification (v3)

**Module underline:** `=== agent name (attribs) ===` with `~~~~~~` underneath
**Purpose:** Declare AI agents as modules containing tools, sub-agents, skills, knowledge, commands, and guardrails.

---

## Agent as Module

An agent IS a module. Config goes in parentheses. The `~~~~~~` underline signals AI-driven.

```
=== Support Agent (agent, model=claude-sonnet-4) ===
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
```

| Attribute | Purpose | Values |
|-----------|---------|--------|
| `agent` | Marks module as agent | Required |
| `model` | LLM model | `claude-sonnet-4`, `claude-haiku-4-5` |
| `temperature` | 0.0 (deterministic) to 1.0 (creative) | Float |
| `memory` | Memory strategy | `conversation`, `session`, `persistent`, `none` |
| `@ max-turns::` | Turn limit | Integer |
| `@ fallback::` | When agent can't help | Action description |

---

## System Prompt (Code Block Syntax)

Base prompt always active. Conditional prompts appended when their condition is true.

````modelhike
```system-prompt
You are a customer support agent for {company.name}.
Always be empathetic and solution-oriented.
Escalate if the issue involves legal threats or safety concerns.
```

```system-prompt customer.tier == "ENTERPRISE"
Enterprise customer. Account manager: {customer.accountManager.name}.
SLA: 1 hour. Offer premium resolution options.
```

```system-prompt time.hour >= 22 || time.hour < 6
Outside business hours. No human agents available.
Create priority ticket for morning follow-up on urgent issues.
```

```system-prompt channel == "CHAT"
Keep responses concise. Max 2-3 sentences per message.
```
````

Multiple conditions can match simultaneously. All matching prompts are appended to the base.

---

## Tools (Class-Like Definitions)

Each tool: a name, description (`--` lines the LLM reads), and a single method. Optional delegation line.

```modelhike
Get Order
=========
-- Retrieve a customer's order by ID. Returns order details
-- including items, status, shipping, and payment.
~ getOrder(orderId: Id) : Order

Cancel Order
============
-- Cancel an active order. Only works for DRAFT or SUBMITTED.
~ cancelOrder(orderId: Id, reason: String) : Order

Check Return Eligibility
========================
-- Evaluate return eligibility against policy rules. Pure evaluation.
~ checkEligibility(orderId: Id) : Eligibility
| decide @"Return Eligibility Rules" with (order)

Process Return
==============
-- Execute full return workflow: validate, label, pickup, refund.
~ processReturn(orderId: Id, reason: String) : ReturnResult
| run @"Return Processing Flow" with (order, reason)

Search Support Articles
=======================
-- Search knowledge base for relevant support articles.
~ searchArticles(query: String) : Article[]
| source @"Support Knowledge Base"

Investigate Order
=================
-- Delegate complex investigation to the Order Investigator sub-agent.
~ investigate(orderId: Id) : InvestigationResult
| invoke @"Order Investigator" with (orderId)

Escalate to Human
=================
-- Transfer conversation to human agent with summary.
~ escalate(reason: String, summary: String) : EscalationResult
```

### Delegation keywords

| Delegation | Direction | Calls |
|------------|-----------|-------|
| `decide @"Rules"` | AI -> Deterministic | `??????` rule set |
| `run @"Flow"` | AI -> Deterministic | `>>>>>>` flow |
| `source @"Knowledge"` | AI -> Knowledge | Knowledge config |
| `mcp @"Server"` | AI -> External | MCP server |
| `invoke @"Sub-agent"` | AI -> AI | Sub-agent (own context) |
| `invoke @"Agent"` | Deterministic -> AI | Agent (from inside a flow) |
| (none) | Direct service call | Bound by convention |

---

## Sub-Agents (Deeper Nesting with `====`)

Sub-agents use `====` (four equals) instead of `===` (three equals), visually signaling they're one level deeper than the parent agent module. They get their own context window.

```modelhike
=== Support Agent (agent, model=claude-sonnet-4) ===
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

// ... system prompts, tools ...

==== Order Investigator (sub-agent, model=claude-sonnet-4) ====
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

```system-prompt
You investigate order issues. Examine order history, payment,
shipping, and prior tickets. Return structured findings.
```

@ output::
| findings: String
| recommended-action: String <"refund", "reship", "escalate", "no-action">
| confidence: Float

Get Order History
=================
-- Full order lifecycle history.
~ getOrderHistory(orderId: Id) : OrderHistory

Get Payment Status
==================
-- Payment and refund history.
~ getPaymentStatus(orderId: Id) : PaymentStatus

Get Shipping Timeline
=====================
-- Shipping events and tracking.
~ getShippingTimeline(orderId: Id) : ShippingTimeline


==== Refund Evaluator (sub-agent, model=claude-sonnet-4) ====
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

```system-prompt
Evaluate refund requests. Consider order age, reason, customer history,
and policy compliance. Be fair but detect abuse patterns.
```

@ output::
| eligible: Boolean
| amount: Float
| reason: String
| requires-approval: Boolean

Check Policy
============
-- Check return eligibility against rules.
~ checkPolicy(order: Order) : Eligibility
| decide @"Return Eligibility Rules" with (order)

Get Customer History
====================
-- Customer order and return history for pattern detection.
~ getCustomerHistory(customerId: Id) : CustomerHistory
```

### Nesting depth convention

| Level | Syntax | Example |
|-------|--------|---------|
| System | `= System =` | Top-level system boundary |
| Container | `== Container ==` | Deployment unit |
| Module | `=== Module ===` | Functional grouping |
| **Agent** | `=== Agent (agent) ===` with `~~~~~~` | AI module |
| **Sub-agent** | `==== Sub-agent (sub-agent) ====` with `~~~~~~` | Nested AI module |

The deeper `====` signals at a glance: this is a child of the parent `===` agent. You see the nesting without reading any attributes.

Parent invokes sub-agents through tools with `| invoke @"Sub-agent Name"`:

```modelhike
Investigate Order
=================
-- Delegate complex investigation to the Order Investigator sub-agent.
~ investigate(orderId: Id) : InvestigationResult
| invoke @"Order Investigator" with (orderId)
```

---

## Knowledge Sources (Config Objects with `::::::::`)

Knowledge sources are config objects, just like calendars, sequences, and currency. They use the `::::::::` underline with a `(knowledge, type)` attribute. This is consistent: config objects are standalone settings referenced by `@"Name"`.

```modelhike
Support Knowledge Base (knowledge, vector-store)
:::::::::::::::::::::::::::::::::::::::::::::::::
-- Searchable support articles and troubleshooting guides.
-- Accessed via tools with `| source @"Support Knowledge Base"`.
provider    = pinecone
embedding   = text-embedding-3-small
ingest:
| paths: /docs/support/**/*.md
| refresh: on-change
| chunking: 500 tokens, overlap: 50
retrieval:
| top-k: 5
| min-similarity: 0.75
| reranking: true


Return Policy (knowledge, static)
::::::::::::::::::::::::::::::::::
-- Complete return policy. Injected into agent context when relevant.
documents = /docs/policies/returns.md, /docs/policies/refunds.md
inject-when = conversation mentions "return" or "refund"


FAQ Database (knowledge, structured)
:::::::::::::::::::::::::::::::::::::
-- FAQ entity data searched by question similarity.
source    = FAQ entity where status == "PUBLISHED"
match-on  = question (text similarity)
return    = answer, category, lastUpdated


Project Codebase (knowledge, code-index)
:::::::::::::::::::::::::::::::::::::::::
-- Indexed codebase for code-aware agents.
paths   = /src/**/*.ts, /src/**/*.py
exclude = node_modules, __pycache__, .git
refresh = on-change
chunking = function-level
```

### Knowledge types

| Type | How it works | Accessed via |
|------|--------------|--------------|
| `vector-store` | Chunked, embedded, similarity-searched | Tool with `\| source @"Name"` |
| `static` | Full text injected when condition matches | `inject-when` (automatic, no tool needed) |
| `structured` | Queried against entity/DB data | Tool with `\| source @"Name"` |
| `code-index` | Function-level code index | Tool with `\| source @"Name"` |

### Why config, not entity

Knowledge sources don't have CRUD. Users don't create/edit them through the app. They're system configuration: "this is where your docs live, this is how to index them." Same reasoning as calendars and sequences.

### Referencing from agent tools

```modelhike
Search Support Articles
=======================
-- Search the knowledge base for relevant support articles.
~ searchArticles(query: String) : Article[]
| source @"Support Knowledge Base"
```

`static` knowledge with `inject-when` needs no tool. It's auto-injected into the system prompt context when the condition matches.

---

## Skills (Inline Prompts + Script Files)

Skills can be defined three ways: external SKILL.md reference, inline prompt code block, or attached script file. Mix and match.

### External SKILL.md reference

```modelhike
Data Analysis (skill)
=====================
-- Analyze uploaded data files. Charts, statistics, trends.
@ skill-file:: /skills/data-analysis/SKILL.md
@ capabilities:: analyze-csv, generate-chart, statistical-summary
@ requires:: code-execution, file-system
```

### Inline prompt (no external file)

```modelhike
Email Drafter (skill)
=====================
-- Draft professional emails based on context and intent.
@ capabilities:: draft-email, improve-tone, shorten

```skill-prompt draft-email
Given the following context:
- Recipient: {recipient}
- Purpose: {purpose}
- Key points: {keyPoints}
- Tone: {tone}

Draft a professional email. Include subject line.
Keep it concise unless the purpose requires detail.
```

```skill-prompt improve-tone
Rewrite this email to be more {targetTone}:

{originalEmail}

Preserve all factual content. Only change tone and phrasing.
```

```skill-prompt shorten
Condense this email to under {maxWords} words while keeping
all essential information:

{originalEmail}
```
```

Each `skill-prompt capabilityName` is an inline prompt definition for a named capability. The skill exposes these as callable capabilities without needing an external file.

### Attached script for deterministic execution

```modelhike
Code Formatter (skill)
======================
-- Format and lint code files according to project standards.
@ capabilities:: format, lint, fix-imports
@ requires:: file-system

@ script:: /skills/code-formatter/formatter.ts
| -- TypeScript file that runs deterministically.
| -- Exported functions map to capabilities:
| -- export function format(filePath: string): FormattedResult
| -- export function lint(filePath: string): LintResult
| -- export function fixImports(filePath: string): FixResult
```

```modelhike
CSV Processor (skill)
=====================
-- Parse, clean, and transform CSV data.
@ capabilities:: parse, clean, transform, validate

@ script:: /skills/csv-processor/processor.py
| -- Python script for deterministic data processing.
| -- def parse(file_path: str) -> ParseResult
| -- def clean(data: dict, rules: dict) -> CleanResult
| -- def transform(data: dict, mapping: dict) -> TransformResult
| -- def validate(data: dict, schema: dict) -> ValidationResult
```

### Mixed: prompt + script in one skill

```modelhike
Data Explorer (skill)
=====================
-- Explore datasets with AI-guided analysis and deterministic computation.
@ capabilities:: analyze, visualize, summarize
@ requires:: code-execution, file-system

```skill-prompt analyze
Examine this dataset and identify:
- Column types and distributions
- Missing data patterns
- Potential anomalies or outliers
- Correlations between columns

Dataset path: {filePath}
Use the compute tool to run statistical calculations.
```

```skill-prompt summarize
Summarize the key findings from this dataset analysis:
{analysisResult}

Write for a {audience} audience. Focus on actionable insights.
```

@ script:: /skills/data-explorer/compute.ts
| -- Deterministic computation called by the AI prompts.
| -- export function statistics(filePath: string): StatsResult
| -- export function correlations(filePath: string): CorrelationMatrix
| -- export function histogram(filePath: string, column: string): HistogramData
```

The AI prompt handles the judgment ("what's interesting in this data?"). The script handles the computation ("calculate the standard deviation"). They compose inside one skill.

---

## MCP Servers

```modelhike
Stripe (mcp-server)
===================
-- Stripe payments, refunds, and customer management.
@ url:: https://mcp.stripe.com/sse
@ auth:: api-key (env=STRIPE_MCP_KEY)

GitHub (mcp-server)
===================
-- GitHub repos, PRs, issues, and code review.
@ url:: https://mcp.github.com/sse
@ auth:: oauth (scope=repo,pull_request)
```

---

## Slash Commands (with Prompts and Execution)

Slash commands can route to agents, execute direct actions, OR run inline prompts. Three modes.

```modelhike
# Slash Commands

// ---- Route to agent (conversational) ----

/help:
| description: "Get help with your order or account"
| routes-to: self

/return {orderId: Id}:
| description: "Start a return"
| routes-to: self with context: "Customer wants to return order {orderId}"

/investigate {orderId: Id}:
| description: "Deep investigation of an order issue"
| invoke: @"Order Investigator" with (orderId)

// ---- Execute a direct action (deterministic, no AI) ----

/track {orderId: Id}:
| description: "Track your order"
| exec: call @"Get Tracking".getTracking(orderId)

/cancel {orderId: Id}:
| description: "Cancel your order"
| exec: call @"Cancel Order".cancelOrder(orderId, "User requested via /cancel")

/status:
| description: "Check your order status"
| exec: call orderService.getMyOrders(currentUser())

// ---- Execute with a prompt (AI-driven, scoped) ----

/summarize:
| description: "Summarize the current conversation"
| prompt:
```prompt
Summarize this conversation in 3-5 bullet points.
Focus on: what the customer asked, what was resolved, what's still open.
```

/draft-reply {ticketId: Id}:
| description: "Draft a reply to a support ticket"
| prompt:
```prompt
Read ticket {ticketId} and draft a professional reply.
Address the customer's concern directly.
If a solution exists in the knowledge base, include it.
If not, explain next steps and set expectations.
```
| tools: @"Search Support Articles", @"Get Order"

/explain {topic}:
| description: "Explain a product feature or policy"
| prompt:
```prompt
Explain {topic} to the customer in simple terms.
Reference the relevant policy or documentation.
Keep it under 200 words.
```
| source: @"Support Knowledge Base", @"FAQ Database"

// ---- Execute with prompt + script (hybrid) ----

/analyze {filePath}:
| description: "Analyze an uploaded data file"
| prompt:
```prompt
Analyze the data file at {filePath}.
Run statistics, identify patterns, and summarize findings.
```
| skill: @"Data Explorer"

#
```

### Command execution modes

| Mode | Keyword | What happens |
|------|---------|--------------|
| **Route** | `routes-to:` | Starts/continues conversation with agent |
| **Invoke sub-agent** | `invoke:` | Calls sub-agent, returns structured result |
| **Direct exec** | `exec:` | Deterministic function call, no AI |
| **Prompt exec** | `prompt:` with `` ```prompt ``` `` | Runs an inline prompt with optional tools/knowledge |
| **Skill exec** | `prompt:` + `skill:` | Runs prompt with skill capabilities |

### Prompt commands with tools and knowledge

When a slash command has `prompt:`, you can also specify which tools and knowledge sources it has access to:

| Directive | Purpose |
|-----------|---------|
| `tools:` | Which agent tools this prompt can call |
| `source:` | Which knowledge sources to search |
| `skill:` | Which skill to use |
| `output:` | Structured output schema (optional) |

This scoping is important. `/explain` only needs knowledge base access. `/draft-reply` needs knowledge AND order lookup. The slash command declares exactly what the prompt can reach.

---

## AI Workflows (Prompt-Driven Steps)

```modelhike
Content Creation Workflow (ai-workflow)
>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
@ trigger:: content-request.created

==> Step 1: Research

```prompt
Research "{request.topic}" thoroughly.
Focus: {request.focusAreas}. Find 5+ authoritative sources.
```
tools: web-search, web-fetch
output:
| research: String
| sources: Source[]

==> Step 2: Draft

```prompt
Write a {request.contentType} about "{request.topic}".
Research: {step1.research}. Tone: {request.tone}. Length: {request.wordCount} words.
```
output:
| draft: String

==> Step 3: Review

```prompt
Review for accuracy, tone, grammar, SEO ({request.keywords}).
Provide specific revisions.
```
input: {step2.draft}
output:
| score: Int (1-10)
| revisions: Revision[]

|> IF step3.score < 7
| goto: Step 2
end

==> Step 4: Publish
run @"Content Publishing Flow" with (step2.draft, request.channel)
```

---

## AI Automations (Event-Triggered AI)

```modelhike
Ticket Auto-Triage (ai-automation)
>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
@ trigger:: support-ticket.created
@ condition:: ticket.priority != "URGENT"
@ model:: claude-haiku-4-5

```prompt
Classify this ticket. Subject: {ticket.subject}. Body: {ticket.body}.
Determine category, priority, and sentiment.
```

output:
| category: String <"billing", "shipping", "product", "account", "technical">
| priority: String <"low", "medium", "high", "urgent">
| sentiment: String <"positive", "neutral", "frustrated", "angry">

then:
| decide @"Routing Rules" with (output) -> routing
| call ticketService.assignQueue(ticket.id, routing.queue)
```

---

## Guardrails

Enforceable constraints on tool use. The blueprint wraps tool calls with pre-checks and monitors conversation state.

```modelhike
# Guardrails

@ tool-constraints::
| Cancel Order:       requires confirmation from user
| Process Return:     blocked when refundAmount > 500 without human approval
| Escalate to Human:  always allowed

@ require-before::
| Cancel Order:       must call Get Order first
| Process Return:     must call Check Return Eligibility first

@ rate-limits::
| Cancel Order:       max 3 per conversation
| Process Return:     max 2 per conversation

@ escalation-triggers::
| on: user says "lawyer" or "legal" or "supervisor" -> escalate
| on: 3 consecutive low-confidence responses -> escalate
| on: conversation exceeds 30 turns -> escalate

@ output-rules::
| max-response-length: 300 tokens
| must-include-order-number: when discussing an order

#
```

---

## Bridge Keywords Summary

| Keyword | Direction | Calls |
|---------|-----------|-------|
| `decide @"Rules"` | AI -> Deterministic | `??????` rule set |
| `run @"Flow"` | AI -> Deterministic | `>>>>>>` flow |
| `source @"Knowledge"` | AI -> Knowledge | `::::::::` knowledge config |
| `mcp @"Server"` | AI -> External | MCP server |
| `invoke @"Sub-agent"` | AI -> AI | `====` sub-agent |
| `invoke @"Agent"` | Deterministic -> AI | `===` agent (from inside a flow) |

---

## The Ten Visual Shapes

```
=====       Entity / Class          Data
/===/       DTO                     Projection
/;;;;;/     UI Layout               Surface
>>>>>>      Flow (Lifecycle + Wf)   Movement
??????      Rules / Decisions       Evaluation
/#####/     Document Template       Output
::::::::    Config Object           Settings (calendars, sequences, currency, knowledge)
~~~~~~      Agent / AI              Intelligence
++++++      Infra Node              Infrastructure
------      Method                  Behavior
```
