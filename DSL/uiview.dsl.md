# ModelHike UIView DSL Specification

**Principle:** UIView layout is declared like data models. Controls are properties. Types are widget types. Names are labels. The view IS the spec.

---

## New Element: Pages and Views

UIViews use the `/;;;;;/` underline. The semicolons evoke a screen or panel divider.

```
Page Title (page)
/;;;;;;;;;;;;;;;;/

View Title (bound objects) #tags (attributes)
/;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;/
```

The `/;;;;;/` underline joins the visual family:

| Element | Underline | Suggests |
|---------|-----------|----------|
| Class | `=====` | Structure, definition |
| DTO | `/===/` | Projection, slicing |
| UIView (old) | `~~~~` | Visual, screen |
| Flow | `>>>>>>` | Direction, progression |
| Rules | `??????` | Decision, evaluation |
| **UIView** | `/;;;;;/` | **Screen, panel, interface** |

---

## Pages vs Views

| Concept | Role | Contains |
|---------|------|----------|
| **Page** | Top-level routable screen | Views, layout, navigation |
| **View** | Reusable UI component | Controls, bindings, actions |

Pages have `(page)` attribute. Views are everything else. Views can be nested inside pages or composed into other views.

---

## 1. Basic View with Bound Object

A view binds to one or more data objects. Its fields project from those objects, just like DTOs use `.` prefix.

```modelhike
=== Order Module ===

Order Detail View (Order)
/;;;;;;;;;;;;;;;;;;;;;;;/
. orderId                          -- derived as read-only text (Id type)
. customer name                    -- derived as text (String type)
. status                           -- derived as badge/chip (from valid value set)
. total                            -- derived as formatted currency (Float type)
. items                            -- derived as table/list (collection type)
```

**Key idea:** When a field is left as `. fieldName` with no explicit type, the control is **derived from the data type** of the bound entity field. The display label defaults to the field name (humanised by the blueprint). Supply a quoted string after the name to override it:

```modelhike
. dueDate "Deadline" : DatePicker       -- when the order must be fulfilled
. customerId "Account #"                -- label differs from field name; control derived from Id type
```

| Entity field type | Derived UI control |
|-------------------|--------------------|
| `String` | Text input (or read-only text in detail views) |
| `Int`, `Float` | Numeric input |
| `Boolean` | Toggle / checkbox |
| `Date` | Date picker |
| `DateTime` | Date-time picker |
| `Id` | Read-only text |
| `Text` | Textarea |
| `Reference@Type` | Lookup / autocomplete |
| `String <"A","B","C">` | Dropdown (from valid value set) |
| `Type[]` (collection) | Table / list |
| `(backend)` fields | Excluded from view |

---

## 2. Explicit Control Types

Override the derived control by specifying a type after `:`.

```modelhike
Order Edit View (Order) (two-column-layout)
/;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;/
. orderId                                     -- read-only text (Id)
. customer : Lookup                           -- explicit lookup control
. status : Dropdown                           -- explicit dropdown
. priority : RadioGroup                       -- radio buttons instead of dropdown
. notes : RichText                            -- rich text editor instead of plain textarea
. dueDate : DatePicker                        -- explicit (same as derived, but stated)
. tags : TagInput                             -- tag chips with autocomplete
. attachments : FileUpload (accept="pdf,docx", maxSize=10MB)
```

Explicit control types override derivation. Attributes in `( )` after the type add control-specific config.

### Control Type Catalog

| Control Type | Renders as |
|--------------|------------|
| `Text` | Single-line text input |
| `Textarea` | Multi-line text input |
| `RichText` | Rich text editor (markdown or WYSIWYG) |
| `Number` | Numeric input with step/min/max |
| `Currency` | Formatted currency input |
| `Dropdown` | Select dropdown (options from valid value set or bound collection) |
| `RadioGroup` | Radio button group |
| `Checkbox` | Single checkbox (boolean) |
| `CheckboxGroup` | Multi-select checkboxes |
| `Toggle` | Toggle switch (boolean) |
| `DatePicker` | Calendar date selector |
| `DateTimePicker` | Date + time selector |
| `DateRange` | Start/end date pair |
| `TimePicker` | Time-only selector |
| `Lookup` | Search-as-you-type for references |
| `Autocomplete` | Text input with suggestions |
| `TagInput` | Tag chips with add/remove |
| `FileUpload` | File upload with type/size constraints |
| `ImageUpload` | Image upload with preview |
| `Slider` | Range slider |
| `Rating` | Star rating |
| `ColorPicker` | Color selector |
| `Table` | Data table (for collections) |
| `List` | Simple list display |
| `Card` | Card display (for single objects) |
| `Badge` | Status badge/chip |
| `Avatar` | User avatar |
| `Map` | Map with location pin |
| `Chart` | Embedded chart |
| `Hidden` | Hidden field (in form, not displayed) |
| `Label` | Read-only display text |
| `Link` | Clickable link |
| `Button` | Action button |
| `Search` | Search input with field bindings |
| `Filter` | Filter control with field bindings |

---

## 3. Field Prefixes

Reuses ModelHike's property prefix convention with UI-specific meanings:

| Prefix | Meaning | Example |
|--------|---------|---------|
| `.` | **Bound field** from parent object. Control derived or explicit. | `. orderId` |
| `*` | **Required control.** Validation enforced. | `* email : Text` |
| `-` | **Optional control.** No validation. | `- notes : Textarea` |
| `=` | **Computed/derived control.** Not directly bound to a field. | `= search : Search => orderId, customerName` |
| `+` | **Standalone control.** Not bound to any object. UI-only element. | `+ submitButton : Button` |

### Display Label

An optional quoted string immediately after the field/control name sets an explicit display label. Without it, the blueprint derives the label from the field name (camelCase → Title Case).

```modelhike
. dueDate "Deadline" : DatePicker           -- label differs from field name
* firstName "First Name" : Text             -- label matches field name (optional, explicit)
+ saveButton "Save Changes" : Button        -- standalone controls always need a label
= dateFilter "Order Date Range" : DateRange => createdAt
```

The full line grammar is:

```
prefix name ["Display Label"] [: ControlType] [(attributes)] [-- description]
```

All parts after `name` are optional. `--` is exclusively for descriptions and is never used to specify a label.

---

## 4. Computed Controls and Search

Controls that derive from logic rather than direct field binding:

```modelhike
Order Search View (Order) (search-layout)
/;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;/
= search : Search => orderId, customerName, status
= dateFilter : DateRange => createdAt
= statusFilter : Filter => status
= exportButton "Export CSV" : Button

. orderId
. customer name
. status : Badge
. total : Currency
. createdAt

@ display:: Table
@ pagination:: cursor, pageSize = 25
@ sort:: createdAt desc, total desc
```

- `= search : Search => orderId, customerName, status` creates a search input that queries across the listed fields.
- `= dateFilter : DateRange => createdAt` creates a date range filter bound to `createdAt`.
- `= statusFilter : Filter => status` creates a filter dropdown auto-populated from the `status` valid value set.
- `=>` binds a computed control to entity fields it operates on.
- `@ display:: Table` tells the blueprint to render bound fields as a data table.
- `@ pagination::` and `@ sort::` configure table behavior.

### Search at Entity Level

For a control to search a field, the entity must mark it searchable:

```modelhike
Order #searchable
=====
* orderId : Id                    #searchable
* customerName : String           #searchable
* status : String                 #searchable
```

The `#searchable` tag on properties declares which fields participate in search. The view's `Search => field1, field2` binds to these. The blueprint wires the search API, index queries, and result rendering.

---

## 5. Object Binding and Conditional Display

Views bind to objects listed in parentheses. Bound controls are only populated when their object has a value.

```modelhike
Customer Detail View (Customer, Address?, RecentOrders?)
/;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;/
-- Customer fields are always shown (Customer is required binding)
. name
. email
. tier : Badge

-- Address fields shown only when Address is loaded (? = optional binding)
. street
. city
. country : Dropdown

-- RecentOrders shown only after lookup (? = optional binding)
. orders : Table
| columns: orderId, date, total, status
| row-action: navigate @"Order Detail Page" with (order.orderId)
```

- `Customer` in parentheses = required binding. Controls from Customer are always rendered.
- `Address?` = optional binding. Controls from Address render only when the object is non-null.
- `RecentOrders?` = optional binding. The orders table appears only after an action loads the data.

The `?` suffix signals conditional display. The blueprint emits show/hide logic based on binding state.

---

## 6. Layout Attributes

Layout hints are attributes on the view header:

```modelhike
Order Form View (Order) (two-column-layout, card-style)
/;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;/
```

### Available Layout Attributes

| Attribute | Meaning |
|-----------|---------|
| `single-column-layout` | All controls stacked vertically |
| `two-column-layout` | Controls in two columns |
| `three-column-layout` | Controls in three columns |
| `horizontal-layout` | Children arranged horizontally |
| `grid-layout` | CSS grid-based layout |
| `card-style` | Wrapped in a card container |
| `compact` | Reduced spacing |
| `full-width` | Spans full container width |
| `sidebar-layout` | Main content + sidebar |
| `split-layout` | Two equal panels |
| `responsive` | Adapts to screen size (default for all) |

---

## 7. Sections within a View

Group related controls into named sections:

```modelhike
Customer Edit View (Customer) (two-column-layout)
/;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;/

Personal Information:
* firstName : Text (span=1)
* lastName : Text (span=1)
* email : Text (span=2)                      -- spans both columns
- phone : Text

Account Settings:
* tier : Dropdown
- referralCode : Text
. createdAt : Label                           -- read-only display

Preferences:
- language : Dropdown <"en", "es", "fr", "ja">
- timezone : Dropdown
- notifications : Toggle
```

`Section Name:` (text followed by a colon on its own line) creates a visual section header. Controls below it belong to that section until the next section header or end of view. This avoids conflict with `-- text` which is ModelHike's description/comment syntax.

`(span=2)` makes a control span multiple columns in a multi-column layout.

---

## 8. Composite Views (View-of-Views)

Views can contain other views for complex layouts:

```modelhike
Order Management View (horizontal-layout)
/;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;/
* leftSidebar : @"Order Filter Sidebar" (width=250px)
* center : @"Order List View" (flex=1)
* rightPanel : @"Order Detail View" (width=400px, collapsible)
```

`@"View Name"` references another view by name. Layout attributes on each slot control sizing.

### Full page layout example

```modelhike
Order Management Page (page) (sidebar-layout)
/;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;/
@ route:: /orders
@ title:: Order Management
@ roles:: [admin, ops, finance]
@ breadcrumb:: Home > Orders

* navigation : @"App Navigation" (position=top)
* sidebar : @"Order Filter Sidebar" (width=280px, collapsible)
* main : @"Order List View" (flex=1)
* detail : @"Order Detail Drawer" (width=480px, drawer, hidden)

# Actions
## sidebar.filter-changed
| call refreshOrderList(sidebar.filters)

## main.row-click (order: Order)
| assign detail.binding = order
| call showDrawer("detail")

## main.create-button click
| navigate @"Order Create Page"
#
```

---

## 9. Init Method

The `init` method runs when the view loads. Uses the same codelogic syntax:

```modelhike
Order Detail View (Order, AuditLog?) (card-style)
/;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;/
. orderId : Label
. customer name : Label
. status : Badge
. items : Table
. auditEntries : Table                       -- shows when AuditLog is loaded

init(orderId: Id)
-----------------
|> DB Order
| |> WHERE o -> o.id == orderId
| |> INCLUDE customer, items
| |> FIRST
| |> LET order = _
assign self.binding = order
---
```

`init` follows the standard ModelHike method syntax (setext header + dash underline). It populates the view's object bindings.

---

## 10. Actions Block

The `# Actions` block handles UI events. Similar to `# APIs` but for user interactions.

```modelhike
Order Edit View (Order) (two-column-layout)
/;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;/
. orderId : Label
* customer : Lookup
* items : Table (editable, addable, removable)
. status : Badge
- notes : RichText
+ saveButton "Save Order" : Button
+ cancelButton "Cancel" : Button (style=secondary)
+ submitButton "Submit for Approval" : Button (style=primary)

# Actions

## saveButton click
| call orderService.save(self.binding)
| notify user, template: order_saved

## cancelButton click
| navigate back

## submitButton click {self.binding.items.count > 0}
| call orderService.submit(self.binding.orderId)
| navigate @"Order Detail Page" with (self.binding.orderId)

## items row-add
| assign newItem = LineItem(quantity: 1)
| call self.binding.items.append(newItem)

## items row-remove (item: LineItem)
| call self.binding.items.remove(item)

## customer lookup-select (selected: Customer)
| assign self.binding.customer = selected
| call refreshShippingOptions(selected.region)

#
```

### Action Syntax

```
## controlName eventType {optional guard}
| action lines
```

- `## controlName eventType` binds to a UI event.
- `{guard}` is an optional condition (matches ModelHike constraint syntax). The action only fires if the guard is true.
- `|` block lines contain actions: `call`, `assign`, `navigate`, `notify`, `emit`, `run`, `decide`.

### Common Event Types

| Event | Applies to | Meaning |
|-------|------------|---------|
| `click` | Button, Link | User clicked |
| `change` | Any input | Value changed |
| `submit` | Form | Form submitted |
| `focus` / `blur` | Any input | Focus gained/lost |
| `row-click` | Table | Row selected |
| `row-add` / `row-remove` | Table (editable) | Row added/removed |
| `row-edit` | Table (editable) | Cell edited |
| `lookup-select` | Lookup | Item selected from dropdown |
| `filter-changed` | Filter, Search | Filter criteria changed |
| `file-selected` | FileUpload | File chosen |
| `sort-changed` | Table | Sort order changed |
| `page-changed` | Table (paginated) | Page navigation |
| `drag-drop` | Sortable list | Item reordered |
| `toggle` | Toggle | Toggled on/off |

---

## 11. Navigation

Navigate between pages:

```modelhike
## viewOrder click (order: Order)
| navigate @"Order Detail Page" with (order.orderId)

## backButton click
| navigate back

## createButton click
| navigate @"Order Create Page"
```

`navigate @"Page Name" with (params)` routes to a named page with parameters. `navigate back` goes to the previous page.

---

## 12. Conditional Visibility and Validation

```modelhike
Order Form View (Order) (two-column-layout)
/;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;/
* orderType : RadioGroup <"STANDARD", "RUSH", "CUSTOM">

Standard Fields:
* items : Table

Rush Fields (orderType == "RUSH"):
*? rushFee : Currency (visible-when=orderType:"RUSH")
*? rushDeadline : DatePicker (visible-when=orderType:"RUSH")

Custom Fields (orderType == "CUSTOM"):
*? customSpec : FileUpload (visible-when=orderType:"CUSTOM", accept="pdf")
*? designNotes : RichText (visible-when=orderType:"CUSTOM")
```

- `(visible-when=field:"value")` shows/hides the control based on another field's value.
- `*?` is conditional required: required only when visible.
- Validation from entity constraints (`{ min, max, pattern }`) is automatically wired to the corresponding controls.

---

## 13. Full Page Example: Order Management

```modelhike
=== Order UI Module ===

// ---- Reusable view: Filter Sidebar ----

Order Filter Sidebar (compact)
/;;;;;;;;;;;;;;;;;;;;;;;;;;;/
= search : Search => orderId, customerName
= statusFilter : Filter => status
= dateFilter : DateRange => createdAt
= tierFilter : Filter => customer.tier
+ clearButton "Clear Filters" : Button (style=link)

# Actions
## clearButton click
| call resetAllFilters()
#

// ---- Reusable view: Order List ----

Order List View (Order[])
/;;;;;;;;;;;;;;;;;;;;;;;/
@ display:: Table
@ pagination:: cursor, pageSize = 25
@ sort:: createdAt desc
@ empty-state:: "No orders found. Try adjusting your filters."

. orderId : Link
. customer name
. status : Badge
. total : Currency
. createdAt : Label (format=relative)    -- "3 hours ago"
+ createButton "+ New Order" : Button (position=header-right)

# Actions
## orderId link-click (order: Order)
| navigate @"Order Detail Page" with (order.orderId)

## createButton click
| navigate @"Order Create Page"
#

// ---- Reusable view: Order Detail ----

Order Detail Drawer (Order, Customer?, LineItem[]?) (card-style)
/;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;/

Order Summary:
. orderId : Label
. status : Badge
. createdAt : Label (format=datetime)

Customer:
. customer name : Label
. customer email : Link (href="mailto:{value}")
. customer tier : Badge

Line Items:
. items : Table
| columns: name, quantity, unitPrice, total
| footer: sum(total)

Actions Bar:
+ approveButton "Approve" : Button (style=primary, visible-when=status:"SUBMITTED")
+ rejectButton "Reject" : Button (style=danger, visible-when=status:"SUBMITTED")
+ cancelButton "Cancel Order" : Button (style=secondary)

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
| decide @"Order Approval Rules" with (self.binding) -> result
| |> IF result.canApprove
| | call orderService.approve(self.binding.orderId)
| | notify user, template: order_approved_success
| |> ELSE
| | notify user, template: cannot_approve, message: result.reason
| end

## rejectButton click
| call showModal("rejectReasonModal")

## rejectReasonModal confirm (reason: String)
| call orderService.reject(self.binding.orderId, reason)
| navigate back

## cancelButton click
| call showConfirm("Are you sure you want to cancel this order?")

## cancelConfirm confirmed
| call orderService.cancel(self.binding.orderId)
| navigate @"Order List Page"
#

// ---- Page: Order Management (composes the views) ----

Order Management Page (page) (sidebar-layout)
/;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;/
@ route:: /orders
@ title:: Order Management
@ roles:: [admin, ops, finance]
@ breadcrumb:: Home > Orders

* navigation : @"App Navigation" (position=top)
* sidebar : @"Order Filter Sidebar" (width=280px, collapsible)
* main : @"Order List View" (flex=1)
* detail : @"Order Detail Drawer" (width=480px, drawer, hidden)

# Actions
## sidebar filter-changed (filters)
| call main.refresh(filters)

## main row-click (order: Order)
| call detail.init(order.orderId)
| call showDrawer("detail")
#

// ---- Page: Order Detail (standalone) ----

Order Detail Page (page)
/;;;;;;;;;;;;;;;;;;;;;;/
@ route:: /orders/{orderId}
@ title:: Order #{orderId}
@ roles:: [admin, ops, finance]
@ breadcrumb:: Home > Orders > #{orderId}

* navigation : @"App Navigation" (position=top)
* content : @"Order Detail Drawer" (full-width)

init(orderId: Id)
-----------------
call content.init(orderId)
---
```

---

## 14. Form Validation Wiring

Validation rules from entity constraints are automatically applied to view controls:

```modelhike
// Entity
Order
=====
* total : Float { min = 0.01 }
* email : String { pattern = ^[\w.-]+@[\w.-]+\.[a-z]{2,}$ }
- notes : Text { maxLength = 2000 }
* status : String <"DRAFT", "SUBMITTED", "APPROVED">

// View
Order Edit View (Order)
/;;;;;;;;;;;;;;;;;;;;;/
* total                         -- min=0.01 constraint auto-wired
* email                         -- pattern validation auto-wired
- notes                         -- maxLength=2000 auto-wired
* status : Dropdown             -- options from valid value set auto-populated
```

The blueprint reads entity constraints (`{ min, max, pattern, maxLength }`) and valid value sets (`<...>`) and wires them to the corresponding controls. No manual validation code.

---

## 15. Responsive and Theme

```modelhike
Order Dashboard Page (page) (responsive)
/;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;/
@ route:: /dashboard
@ theme:: dark-compatible
@ breakpoints:: mobile=640px, tablet=1024px

* stats : @"Order Stats Bar" (full-width)
* content : @"Dashboard Grid" (flex=1)
| mobile: single-column-layout
| tablet: two-column-layout
| desktop: three-column-layout
```

`@ breakpoints::` defines responsive breakpoints. The `|` block under a view slot overrides layout per breakpoint.

---

## What the Blueprint Emits

From view and page declarations:

| Output | Source |
|--------|--------|
| **Component code** (React, SwiftUI, Vue, etc.) | View structure + control types |
| **Form validation** | Entity constraints auto-wired to controls |
| **Data binding** | `.` field projections from bound objects |
| **Event handlers** | `# Actions` block |
| **Search/filter** | `= search : Search => fields` |
| **Pagination/sorting** | `@ pagination::`, `@ sort::` |
| **Conditional visibility** | `visible-when` attributes + `?` optional bindings |
| **Routing** | `@ route::` on pages + `navigate` in actions |
| **Layout CSS** | Layout attributes (column, grid, sidebar) |
| **Responsive breakpoints** | `@ breakpoints::` + per-breakpoint overrides |
| **Accessibility** | Labels from explicit `"..."` or humanised field name; ARIA from control types |
| **OpenAPI client** | Init methods and action API calls |

---

## Visual Summary: Element Underline Family

```
Class          =====         Structure
DTO            /===/         Projection
UIView         /;;;;;/       Screen, panel
Flow           >>>>>>        Direction, progression
Rules          ??????        Decision, evaluation
Infra Node     ++++++        Infrastructure
Method         ------        Behavior (setext)
```

Every visual shape in the DSL tells you what kind of thing you're looking at before you read a single word.
