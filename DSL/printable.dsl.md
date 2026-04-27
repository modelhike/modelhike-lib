# ModelHike Printable DSL Guide

**Underline:** `/#####/`
**Purpose:** Declare printables for invoices, purchase orders, packing slips, contracts, statements, and compliance reports. One printable generates PDF, HTML, and email.

---

## When to Use Printables

Use a printable when you need to **generate a printable or sendable document** from entity data. If it goes to a printer, an inbox, or a PDF viewer, it's a printable.

| Need | Use |
|------|-----|
| Invoice PDF | Printable |
| Packing slip | Printable |
| Contract with conditional clauses | Printable |
| Monthly statement | Printable |
| Email body with merge fields | Printable |
| Screen layout for a web app | UIView (`/;;;;;/`), not Printable |
| API response shape | DTO (`/===/`), not Printable |

---

## Syntax

```
Printable Name (bound objects)
/#########################/
@ output:: formats
@ page:: size, orientation, margins
```

The `#####` underline suggests a printed page. The hash character evokes a form.

### Bound objects

Objects in `( )` after the printable name are the data sources. All merge fields inside the printable resolve against these objects.

```modelhike
Invoice Document (Invoice, Customer, LineItem[])
/###############################################/
```

This printable binds to an `Invoice`, a `Customer`, and a collection of `LineItem[]`. Every merge field like `"{invoice.number}"` resolves against these bindings.

---

## Printable Blocks

### Header and Footer

```modelhike
header:
| Company Logo                      (position=left)
| "{company.name}"                  (position=center, style=bold)
| "Invoice"                         (position=right, style=h1)

footer:
| "Page {pageNumber} of {pageCount}"    (position=center)
| "{company.name} | {company.phone}"    (position=right, size=small)
```

`header:` and `footer:` appear on every page. `{pageNumber}` and `{pageCount}` are built-in variables.

### Sections

```modelhike
section Invoice Details: (two-column)
| "Invoice #:"    "{invoice.number}"
| "Date:"         "{invoice.createdAt | format: date}"
| "Due Date:"     "{invoice.dueDate | format: date}"
```

`section Name:` groups related content. Layout attributes like `(two-column)` control arrangement. Each `|` line is a row of content.

### Merge Fields

```
"{entity.field}"                     -- simple field
"{entity.field | format: date}"      -- with format pipe
"{entity.field | format: currency}"  -- currency formatting
"{entity.nested.field}"              -- nested access
```

Merge fields are quoted strings with `{expression}` inside. Format pipes apply output formatting.

### Available format pipes

| Pipe | Output | Example |
|------|--------|---------|
| `format: date` | Localized date | "March 15, 2026" |
| `format: datetime` | Date + time | "March 15, 2026 2:30 PM" |
| `format: currency` | Currency with symbol | "$1,234.56" |
| `format: number` | Formatted number | "1,234.56" |
| `format: percent` | Percentage | "18.5%" |
| `format: phone` | Formatted phone | "(555) 123-4567" |
| `uppercase` | All caps | "ACME CORP" |
| `lowercase` | All lower | "acme corp" |
| `truncate: N` | Limit to N chars | "Long description..." |

### Repeating Tables

```modelhike
section Line Items:
| table: invoice.items
| | column: "Item"         -> item.name
| | column: "Description"  -> item.description
| | column: "Qty"          -> item.quantity          (align=right)
| | column: "Unit Price"   -> item.unitPrice         (format=currency)
| | column: "Total"        -> item.total             (format=currency)
| footer-row:
| | ""  ""  ""  "Subtotal:"   "{invoice.subtotal | format: currency}"
| | ""  ""  ""  "Tax ({invoice.taxRate}%):"  "{invoice.taxAmount | format: currency}"
| | ""  ""  ""  "Total:"      "{invoice.total | format: currency}"  (style=bold)
```

- `table: collection` iterates over a bound collection
- `| | column: "Header" -> item.field` declares each column
- `(align=right)`, `(format=currency)` are column attributes
- `footer-row:` adds summary rows below the table

### Conditional Sections

```modelhike
|> IF invoice.notes
| section Notes:
| | "{invoice.notes}"
end

|> IF invoice.status == "OVERDUE"
| section Overdue Notice: (style=warning)
| | "This invoice is {daysBetween(invoice.dueDate, today())} days overdue."
| | "Please remit payment immediately to avoid further action."
end
```

Standard `|> IF / end` from codelogic. Entire sections show or hide based on runtime data. The PDF doesn't have blank space where the section would be; it simply doesn't appear.

### Page Breaks

```modelhike
pageBreak: after 25 line items
pageBreak: before section "Terms and Conditions"
```

`pageBreak:` controls pagination. `after N line items` breaks the table. `before section "Name"` starts a new page.

### Styles

```modelhike
| "{customer.name}"                 (style=bold)
| "OVERDUE"                         (style=warning)
| "{invoice.total | format: currency}"  (style=h2, color=red)
```

| Style | Effect |
|-------|--------|
| `bold` | Bold text |
| `italic` | Italic text |
| `h1`, `h2`, `h3` | Heading sizes |
| `warning` | Warning styling (typically orange/red box) |
| `info` | Info styling (typically blue box) |
| `muted` | De-emphasized (gray, smaller) |
| `small` | Smaller font size |

---

## Full Example: Invoice

```modelhike
=== Invoice Module ===

Invoice Document (Invoice, Customer, LineItem[])
/###############################################/
@ output:: pdf, html, email
@ page:: A4, portrait, margins: 20mm
@ locale:: inherit from customer.locale

header:
| Company Logo                      (position=left)
| "{company.name}"                  (position=center, style=bold)
| "INVOICE"                         (position=right, style=h1)

section Company Details:
| "{company.address.line1}"
| "{company.address.city}, {company.address.state} {company.address.zip}"
| "Tax ID: {company.taxId}"

section Invoice Details: (two-column)
| "Invoice #:"    "{invoice.number}"
| "Date:"         "{invoice.createdAt | format: date}"
| "Due Date:"     "{invoice.dueDate | format: date}"
| "Terms:"        "{invoice.paymentTerms}"
| "Status:"       "{invoice.status}"

section Bill To:
| "{customer.name}"                 (style=bold)
| "{customer.billingAddress.line1}"
| "{customer.billingAddress.city}, {customer.billingAddress.state}"
| "{customer.billingAddress.country}"

|> IF invoice.shippingAddress != invoice.billingAddress
| section Ship To:
| | "{invoice.shippingAddress.name}"   (style=bold)
| | "{invoice.shippingAddress.line1}"
| | "{invoice.shippingAddress.city}, {invoice.shippingAddress.state}"
end

section Line Items:
| table: invoice.items
| | column: "Item"         -> item.name
| | column: "SKU"          -> item.sku              (style=muted)
| | column: "Qty"          -> item.quantity          (align=right)
| | column: "Unit Price"   -> item.unitPrice         (format=currency)
| | column: "Discount"     -> item.discount          (format=percent)
| | column: "Total"        -> item.lineTotal         (format=currency)
| footer-row:
| | ""  ""  ""  ""  "Subtotal:"   "{invoice.subtotal | format: currency}"
| | ""  ""  ""  ""  "Discount:"   "-{invoice.totalDiscount | format: currency}"
| | ""  ""  ""  ""  "Tax ({invoice.taxRate}%):"  "{invoice.taxAmount | format: currency}"
| | ""  ""  ""  ""  "Total Due:"  "{invoice.total | format: currency}"  (style=bold, style=h2)

pageBreak: after 25 line items

|> IF invoice.notes
| section Notes:
| | "{invoice.notes}"
end

|> IF invoice.status == "OVERDUE"
| section Overdue Notice: (style=warning)
| | "This invoice is {daysBetween(invoice.dueDate, today())} days overdue."
| | "A late fee of {invoice.lateFee | format: currency} has been applied."
end

section Payment Instructions:
| "Bank: {company.bankName}"
| "Account: {company.bankAccount}"
| "Routing: {company.routingNumber}"
| "Reference: {invoice.number}"

|> IF invoice.paymentLink
| section Online Payment:
| | "Pay online: {invoice.paymentLink}"
end

section Terms and Conditions: (style=small)
| "{company.invoiceTerms}"

footer:
| "Page {pageNumber} of {pageCount}"    (position=center)
| "Generated {now() | format: datetime}"  (position=right, size=small)
```

---

## Full Example: Packing Slip

```modelhike
Packing Slip (Order, ShipmentDetails)
/###################################/
@ output:: pdf
@ page:: letter, portrait

header:
| "PACKING SLIP"                    (position=center, style=h1)
| "Ship Date: {shipment.date | format: date}"

section Ship To:
| "{order.shippingAddress.name}"    (style=bold)
| "{order.shippingAddress.line1}"
| "{order.shippingAddress.city}, {order.shippingAddress.state} {order.shippingAddress.zip}"

section Ship From:
| "{company.warehouse.name}"
| "{company.warehouse.address}"

section Items:
| table: shipment.items
| | column: "SKU"       -> item.sku
| | column: "Item"      -> item.name
| | column: "Ordered"   -> item.quantityOrdered    (align=right)
| | column: "Shipped"   -> item.quantityShipped    (align=right)
| | column: "Backorder" -> item.quantityBackorder  (align=right)

|> IF shipment.hasBackorder
| section Backorder Notice:
| | "Items on backorder will ship separately when available."
| | "Estimated restock: {shipment.estimatedRestock | format: date}"
end

section Tracking:
| "Carrier: {shipment.carrier}"
| "Tracking #: {shipment.trackingNumber}"
| "Estimated Delivery: {shipment.estimatedDelivery | format: date}"

footer:
| "Order #{order.number} | {shipment.items.count} items | {shipment.totalWeight} lbs"
```

---

## Invoking Printables

### From a flow

```modelhike
Fulfillment Flow
>>>>>>>>>>>>>>>>

==> Step 5: Generate Invoice PDF

generate @"Invoice Document" with (invoice, customer, invoice.items) -> pdfResult
| output: pdf
| store: @"Document Storage" as invoice-{invoice.number}.pdf
system ~~> customer : email(invoice_ready, attachment: pdfResult.url)
```

`generate @"Printable Name" with (bindings)` produces the document. The `|` block specifies output format and storage.

### From a job

```modelhike
# Jobs

monthlyStatements:
| trigger: first-of-month at 08:00
| for-each: Customer where hasOutstandingBalance == true
| action:
| | generate @"Monthly Statement" with (customer, customer.invoices) -> statement
| | notify customer.email, template: statement_ready, attachment: statement.url
```

### From a lifecycle entry

```modelhike
state APPROVED
| entry / generate @"Purchase Order Document" with (po, vendor, po.items) -> poDoc
| entry / emit PODocumentGenerated
```

---

## Printable Directives Reference

| Directive | Purpose | Example |
|-----------|---------|---------|
| `@ output::` | Output formats | `pdf, html, email` |
| `@ page::` | Page setup | `A4, portrait, margins: 20mm` / `letter, landscape` |
| `@ locale::` | Localization | `inherit from customer.locale` / `en-US` |
| `header:` | Page header | Logo, company name, document title |
| `footer:` | Page footer | Page numbers, generation date |
| `section Name:` | Content section | Grouped related content |
| `(two-column)` | Section layout | Two-column arrangement |
| `table: collection` | Repeating table | Iterates over bound collection |
| `footer-row:` | Table summary row | Subtotals, totals |
| `|> IF / end` | Conditional section | Show/hide based on data |
| `pageBreak:` | Page break rule | `after 25 line items`, `before section "Terms"` |
| `"{field}"` | Merge field | Data interpolation |
| `"{ \| format: type}"` | Format pipe | Date, currency, number formatting |
| `(style=X)` | Text styling | bold, italic, h1, warning, muted |
| `(position=X)` | Alignment | left, center, right |
| `(align=X)` | Column alignment | left, center, right |

---

## Printables vs UIView

| | Printable (`/#####/`) | UIView (`/;;;;;/`) |
|--|---|---|
| **Produces** | PDF, HTML, email (static document) | Interactive screen |
| **User interaction** | None (read-only output) | Events, actions, navigation |
| **Controls** | Merge fields, tables, sections | Input fields, buttons, dropdowns |
| **When** | Generate once, send/print | Rendered live in a browser |
| **Data binding** | `"{entity.field}"` | `. fieldName` |
| **Conditional** | `\|> IF` shows/hides sections | `visible-when` on controls |
