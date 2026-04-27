# ModelHike Hierarchy DSL Specification

**Problem:** Every ERP has recursive tree structures: BOM (Bill of Materials), org charts, chart of accounts, category trees, menu structures, folder hierarchies. Traversing them requires recursive queries (CTEs), depth tracking, cycle detection, and aggregate rollups. Currently all imperative.

---

## The Core Insight

A hierarchy is an entity that references itself. That's it. `Employee.reportsTo -> Employee`. `Category.parent -> Category`. `BOMItem.parentItem -> BOMItem`. The entity already declares the relationship. What's missing is a way to declare what OPERATIONS you want on that tree.

The hierarchy DSL doesn't introduce a new underline type. Instead, it adds a `# Hierarchy` attached section to self-referential entities (like `# APIs`, `# Import`, `# Export`). The section declares which tree operations the blueprint should generate.

---

## Self-Referential Entity Pattern

Before you can use `# Hierarchy`, the entity must have a self-referential structure:

```modelhike
Category
========
** id       : Id
*  name     : String
*  parent   : Reference@Category?      -- points to same type (? = root has no parent)
*  children : Category[]               -- inverse: all categories where parent == this
-  level    : Int                      -- auto-computed depth in tree
-  path     : String                   -- auto-computed: "Electronics > Phones > Smartphones"
```

The `Reference@Category?` on `parent` and `Category[]` on `children` establish the tree structure. The `?` on parent means root nodes have `nil` parent.

---

## The `# Hierarchy` Section

```modelhike
Category
========
** id       : Id
*  name     : String
*  parent   : Reference@Category?
*  children : Category[]
-  level    : Int
-  path     : String

# Hierarchy
@ parent:: parent
@ children:: children
@ max-depth:: 20
@ cycle-detection:: true

ancestors:
| -- All categories from this node up to the root
| direction: up
| include-self: false
| returns: Category[]

descendants:
| -- All categories below this node at any depth
| direction: down
| include-self: false
| max-depth: 10
| returns: Category[]

path:
| -- Ordered list from root down to this node
| direction: up
| include-self: true
| returns: Category[]
| as: name                             -- returns ["Electronics", "Phones", "Smartphones"]

breadcrumb:
| -- Same as path but returns a formatted string
| direction: up
| include-self: true
| returns: String
| format: "{name}" joined by " > "     -- "Electronics > Phones > Smartphones"

subtree-count:
| -- Count of all descendants
| direction: down
| aggregate: count
| returns: Int

#
```

### Anatomy

```
# Hierarchy                    -- opens the hierarchy section
@ parent:: fieldName           -- which field points to the parent
@ children:: fieldName         -- which field holds the children (inverse)
@ max-depth:: N                -- safety limit for all operations
@ cycle-detection:: true       -- guard against circular references

operationName:                 -- named operation (becomes a generated method/endpoint)
| direction: up | down         -- traverse toward root or toward leaves
| include-self: true | false   -- include the starting node in results
| max-depth: N                 -- override max depth for this operation
| aggregate: count | sum(field) | min(field) | max(field)  -- aggregate instead of returning nodes
| returns: Type                -- return type
| as: fieldName                -- project a single field instead of full entities
| format: "pattern"            -- format the result as a string
| multiply: fieldName          -- multiply a quantity at each level (BOM explosion)
| filter: expression           -- filter nodes during traversal

#                              -- closes the hierarchy section
```

---

## Example 1: Bill of Materials (Manufacturing)

The classic ERP hierarchy. A product is made of sub-assemblies, which are made of parts. "Exploding" a BOM means recursively walking the tree and multiplying quantities at each level.

```modelhike
=== Manufacturing Module ===

BOM Item
========
** id          : Id
*  partNumber  : String
*  name        : String
*  parent      : Reference@BOM Item?
*  components  : BOM Item[]
*  quantity    : Float = 1              -- how many of this item per parent unit
*  unitCost    : Float
-  level       : Int
-  path        : String

# Hierarchy
@ parent:: parent
@ children:: components
@ max-depth:: 25
@ cycle-detection:: true

explode:
| -- Recursive expansion with quantity multiplication
| -- "10 Bicycles" -> "20 Wheel Assemblies" (2 per bike) -> "720 Spokes" (36 per wheel * 20)
| direction: down
| include-self: true
| multiply: quantity                    -- multiply quantity at each depth level
| returns: BOM Explosion[]

rollup-cost:
| -- Sum cost from leaves up to root
| -- Each node's cost = unitCost * quantity + sum(children costs)
| direction: down
| aggregate: sum(unitCost * quantity)
| returns: Float

where-used:
| -- Given a part, find all assemblies that contain it (reverse explosion)
| direction: up
| include-self: false
| returns: BOM Item[]

leaf-parts:
| -- All parts with no children (raw materials / purchased parts)
| direction: down
| filter: components.count == 0
| returns: BOM Item[]

#
```

### What `explode` does, step by step

Given this BOM tree:
```
Bicycle (qty: 1)
├── Frame Assembly (qty: 1)
│   ├── Frame (qty: 1, cost: $45)
│   ├── Fork (qty: 1, cost: $25)
│   └── Headset (qty: 1, cost: $12)
├── Wheel Assembly (qty: 2)
│   ├── Rim (qty: 1, cost: $18)
│   ├── Hub (qty: 1, cost: $15)
│   └── Spokes (qty: 36, cost: $0.50)
└── Drivetrain (qty: 1)
    ├── Chain (qty: 1, cost: $12)
    ├── Crankset (qty: 1, cost: $35)
    └── Cassette (qty: 1, cost: $28)
```

Calling `explode(bicycleId, requiredQuantity: 10)` produces:

```
BOM Explosion:
| Level | Part            | Qty/Parent | Total Qty | Unit Cost | Extended Cost |
|-------|-----------------|------------|-----------|-----------|---------------|
| 0     | Bicycle         | 1          | 10        |           |               |
| 1     | Frame Assembly  | 1          | 10        |           |               |
| 1     | Wheel Assembly  | 2          | 20        |           |               |
| 1     | Drivetrain      | 1          | 10        |           |               |
| 2     | Frame           | 1          | 10        | $45.00    | $450.00       |
| 2     | Fork            | 1          | 10        | $25.00    | $250.00       |
| 2     | Headset         | 1          | 10        | $12.00    | $120.00       |
| 2     | Rim             | 1          | 20        | $18.00    | $360.00       |
| 2     | Hub             | 1          | 20        | $15.00    | $300.00       |
| 2     | Spokes          | 36         | 720       | $0.50     | $360.00       |
| 2     | Chain           | 1          | 10        | $12.00    | $120.00       |
| 2     | Crankset        | 1          | 10        | $35.00    | $350.00       |
| 2     | Cassette        | 1          | 10        | $28.00    | $280.00       |
```

Total Qty = parent's Total Qty * this item's quantity. That's the `multiply: quantity` directive.

### The generated DTO

The blueprint auto-generates an explosion result type:

```modelhike
BOM Explosion (BOM Item)
/===/
. partNumber
. name
. level                                -- depth in tree (auto-computed)
. quantityPer                          -- quantity relative to immediate parent
. totalQuantity                        -- quantity * all ancestor multipliers
. unitCost
. extendedCost                         -- totalQuantity * unitCost
```

---

## Example 2: Organization Chart (HR)

```modelhike
=== HR Module ===

Employee
========
** id             : Id
*  name           : String
*  title          : String
*  department     : String
*  reportsTo      : Reference@Employee?
*  directReports  : Employee[]
-  level          : Int
-  path           : String

# Hierarchy
@ parent:: reportsTo
@ children:: directReports
@ max-depth:: 15

management-chain:
| -- From this employee up to the CEO
| direction: up
| include-self: true
| returns: Employee[]

team:
| -- All direct and indirect reports
| direction: down
| include-self: false
| returns: Employee[]

team-size:
| -- Count of all direct and indirect reports
| direction: down
| aggregate: count
| returns: Int

department-heads:
| -- All descendants who are department heads
| direction: down
| filter: title == "Department Head" || title == "VP" || title == "Director"
| returns: Employee[]

org-depth:
| -- How many levels below this person
| direction: down
| aggregate: max(level)
| returns: Int

#
```

### Usage in flows and rules

```modelhike
// In an approval workflow:
==> Step 2: Find Approver

decide @"Approval Level Rules" with (purchaseOrder) -> requiredLevel

// Use the hierarchy to find the right person
call employee.management-chain(submitter.id) -> chain
assign approver = chain.find(e -> e.level <= requiredLevel)
```

```modelhike
// In a rule set:
Staffing Constraint Rules
?????????????????????????
@ input:: employee: Employee, request: PTORequest
@ output:: allowed: Boolean, reason: String

constraint minimumStaffing
| when: employee.team-size(employee.id) - countOnPTO(employee.team, request.dates) < employee.department.minStaffing
| reject: "Team would fall below minimum staffing"
```

The hierarchy operations (`management-chain`, `team-size`) are available as callable functions anywhere in ModelHike: flows, rules, lifecycle guards, UI init methods.

---

## Example 3: Chart of Accounts (Finance)

```modelhike
=== Finance Module ===

Account
=======
** accountCode    : String
*  name           : String
*  accountType    : String <"ASSET", "LIABILITY", "EQUITY", "REVENUE", "EXPENSE">
*  parentAccount  : Reference@Account?
*  subAccounts    : Account[]
*  balance        : Float = 0
-  level          : Int
-  path           : String

# Hierarchy
@ parent:: parentAccount
@ children:: subAccounts
@ max-depth:: 10

rollup-balance:
| -- Sum balances from all descendant accounts up to this account
| -- E.g., "Total Assets" = sum of all asset sub-accounts recursively
| direction: down
| aggregate: sum(balance)
| returns: Float

account-path:
| -- Full account path: "Assets > Current Assets > Cash > Petty Cash"
| direction: up
| include-self: true
| returns: String
| format: "{name}" joined by " > "

leaf-accounts:
| -- Accounts with no children (where transactions are actually posted)
| direction: down
| filter: subAccounts.count == 0
| returns: Account[]

trial-balance:
| -- All leaf accounts with their balances, grouped by accountType
| direction: down
| filter: subAccounts.count == 0
| returns: Account[]
| group-by: accountType

#
```

---

## Example 4: Category Tree (E-Commerce)

```modelhike
=== Catalog Module ===

Category
========
** id          : Id
*  name        : String
*  slug        : String
*  parent      : Reference@Category?
*  children    : Category[]
-  level       : Int
-  path        : String
-  productCount : Int                  -- count of products in this category (direct only)

# Hierarchy
@ parent:: parent
@ children:: children
@ max-depth:: 8

breadcrumb:
| direction: up
| include-self: true
| returns: String
| format: "{name}" joined by " > "

deep-product-count:
| -- Products in this category AND all sub-categories
| direction: down
| aggregate: sum(productCount)
| returns: Int

sibling-categories:
| -- Other categories at the same level under the same parent
| direction: none
| filter: parent == self.parent && id != self.id
| returns: Category[]

root-category:
| -- The top-level ancestor
| direction: up
| include-self: false
| filter: parent == nil
| returns: Category

move-to:
| -- Reparent this category under a new parent
| -- The blueprint validates: no cycles, max-depth not exceeded
| action: reassign parent
| validate: no-cycle, max-depth

#
```

### Move-to as a mutation operation

Most hierarchy operations are reads. `move-to` is a write: it changes the parent. The `action: reassign parent` directive tells the blueprint to generate a mutation endpoint that:

1. Validates no circular reference would be created
2. Validates max-depth won't be exceeded after the move
3. Updates the parent reference
4. Recomputes `level` and `path` for the moved node and all descendants
5. Emits a `CategoryMoved` event

---

## Example 5: Menu Structure (UI)

```modelhike
=== Navigation Module ===

Menu Item
=========
** id          : Id
*  label       : String
*  icon        : String?
*  route       : String?
*  parent      : Reference@Menu Item?
*  children    : Menu Item[]
*  sortOrder   : Int = 0
-  level       : Int
-  visible     : Boolean = true

# Hierarchy
@ parent:: parent
@ children:: children
@ max-depth:: 5

full-menu:
| -- Complete menu tree from root, ordered by sortOrder at each level
| direction: down
| include-self: true
| filter: visible == true
| order-by: sortOrder asc
| returns: Menu Item[]

menu-path:
| -- Path from root to this item (for active state highlighting)
| direction: up
| include-self: true
| returns: Menu Item[]

#
```

---

## Operation Reference

| Directive | Values | Default | Purpose |
|-----------|--------|---------|---------|
| `direction` | `up`, `down`, `none` | required | Which way to traverse |
| `include-self` | `true`, `false` | `false` | Include the starting node |
| `max-depth` | integer | Section-level `@ max-depth::` | Limit recursion depth |
| `returns` | Type or Type[] | required | Return type |
| `aggregate` | `count`, `sum(field)`, `min(field)`, `max(field)` | none | Aggregate instead of returning nodes |
| `multiply` | fieldName | none | Multiply a quantity at each depth (BOM explosion) |
| `filter` | expression | none | Filter nodes during traversal |
| `order-by` | field asc/desc | none | Order results |
| `as` | fieldName | none | Project single field instead of full entity |
| `format` | `"{field}" joined by "sep"` | none | Format as string |
| `group-by` | fieldName | none | Group results by a field |
| `action` | `reassign parent` | none | Mutation operation (move/reparent) |
| `validate` | `no-cycle`, `max-depth` | none | Validation rules for mutations |

---

## Section-Level Directives

| Directive | Purpose | Example |
|-----------|---------|---------|
| `@ parent::` | Field pointing to parent | `@ parent:: reportsTo` |
| `@ children::` | Field holding children | `@ children:: directReports` |
| `@ max-depth::` | Global safety limit | `@ max-depth:: 20` |
| `@ cycle-detection::` | Guard against circular refs | `@ cycle-detection:: true` |

---

## What the Blueprint Emits

For each declared operation:

| Output | Source |
|--------|--------|
| **Recursive CTE** (SQL) | `direction: up/down` generates `WITH RECURSIVE` queries |
| **API endpoint** | Each named operation becomes `GET /entity/{id}/operationName` |
| **Depth tracking** | `level` field auto-populated on insert/update |
| **Path computation** | `path` field auto-populated as materialized path |
| **Cycle detection** | On insert/update, validates no circular reference |
| **Max depth enforcement** | On insert/update, validates tree doesn't exceed limit |
| **Quantity multiplication** | `multiply:` generates accumulator logic for BOM explosion |
| **Aggregate computation** | `aggregate:` generates bottom-up or top-down rollup queries |
| **Filter during traversal** | `filter:` applies WHERE clause at each recursion level |
| **Reparent mutation** | `action: reassign parent` generates move endpoint with validation |
| **Event emission** | Mutations emit events: `NodeMoved`, `NodeCreated`, `NodeDeleted` |

---

## Common Patterns Quick Reference

**"Get all ancestors" (breadcrumb, management chain):**
```
ancestors:
| direction: up
| include-self: false
| returns: Entity[]
```

**"Get all descendants" (team, subtree):**
```
descendants:
| direction: down
| include-self: false
| returns: Entity[]
```

**"Formatted path string" (breadcrumb display):**
```
breadcrumb:
| direction: up
| include-self: true
| returns: String
| format: "{name}" joined by " > "
```

**"Count descendants" (team size, subtree count):**
```
count:
| direction: down
| aggregate: count
| returns: Int
```

**"Sum up from leaves" (cost rollup, balance rollup):**
```
rollup:
| direction: down
| aggregate: sum(fieldName)
| returns: Float
```

**"BOM explosion" (recursive quantity multiplication):**
```
explode:
| direction: down
| include-self: true
| multiply: quantity
| returns: Explosion[]
```

**"Find filtered descendants" (department heads, leaf nodes):**
```
filtered:
| direction: down
| filter: expression
| returns: Entity[]
```

**"Reparent / move node":**
```
move:
| action: reassign parent
| validate: no-cycle, max-depth
```
