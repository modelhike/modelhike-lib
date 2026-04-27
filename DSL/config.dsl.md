# ModelHike Config Objects Guide

**Underline:** `::::::::`
**Purpose:** Declare system-wide configuration that entities reference: business calendars, fiscal periods, number sequences, currency rates, unit of measure conversions.

---

## When to Use Config Objects

Config objects are for settings that:
- Are **shared** across multiple entities (a calendar used by invoices, orders, and SLAs)
- Are **not entity data** (they don't have CRUD, they don't have APIs)
- Have **key:value structure** (settings, conversion tables, patterns)
- Are **referenced** from entities via `@"Config Name"`

If it has fields and CRUD, it's an entity (`=====`). If it's settings referenced by entities, it's a config (`::::::::`).

---

## Syntax

```
Config Name (config-type)
:::::::::::::::::::::::::
key = value
key:
| list items
```

The attribute in `( )` tells the blueprint what kind of config: `(calendar)`, `(calendar, fiscal)`, `(sequence)`, `(currency)`, `(uom, weight)`.

---

## 1. Business Calendars

```modelhike
US Business Calendar (calendar)
:::::::::::::::::::::::::::::::
holidays      = US-Federal
custom-holidays:
| 2026-12-24  "Christmas Eve"
| 2026-12-26  "Day after Christmas"
working-hours = 09:00-17:00
working-days  = Mon-Fri
timezone      = America/New_York
```

### Settings

| Key | Purpose | Example |
|-----|---------|---------|
| `holidays` | Named holiday set | `US-Federal`, `UK-Bank`, `IN-Gazetted` |
| `custom-holidays:` | Additional non-standard holidays | `|` block with date + name |
| `working-hours` | Business hours | `09:00-17:00` |
| `working-days` | Working days | `Mon-Fri` |
| `timezone` | Timezone for calculations | `America/New_York` |

### Built-in functions (available after declaring a calendar)

| Function | Returns | Example |
|----------|---------|---------|
| `nextBusinessDay(date, cal)` | Date | `nextBusinessDay(dueDate, @"US Business Calendar")` |
| `addBusinessDays(date, n, cal)` | Date | `addBusinessDays(today(), 5, @"US Business Calendar")` |
| `businessDaysBetween(d1, d2, cal)` | Int | `businessDaysBetween(dueDate, today(), @"US Business Calendar")` |
| `isBusinessDay(date, cal)` | Boolean | `isBusinessDay(today(), @"US Business Calendar")` |
| `workingHoursUntil(dt, deadline, cal)` | Float | SLA hours remaining |

---

## 2. Fiscal Calendars

```modelhike
Company Fiscal Calendar (calendar, fiscal)
::::::::::::::::::::::::::::::::::::::::::
year-start = April 1
periods:
| Q1: Apr-Jun
| Q2: Jul-Sep
| Q3: Oct-Dec
| Q4: Jan-Mar
```

### Built-in functions

| Function | Returns | Example |
|----------|---------|---------|
| `fiscalPeriod(date, cal)` | String | `"Q3 FY2026"` |
| `fiscalYear(date, cal)` | String | `"FY2026"` |
| `startOfFiscalPeriod(period, cal)` | Date | Start date of Q3 |
| `endOfFiscalPeriod(period, cal)` | Date | End date of Q3 |

### Usage in entities

```modelhike
Invoice
=======
*  dueDate        : Date
=  dueDateBusiness : Date = dueDate | nextBusinessDay(@"US Business Calendar")
=  agingDays      : Int = businessDaysBetween(dueDate, today(), @"US Business Calendar")
=  fiscalPeriod   : String = fiscalPeriod(createdAt, @"Company Fiscal Calendar")
```

---

## 3. Number Sequences

```modelhike
Invoice Numbering (sequence)
::::::::::::::::::::::::::::
target   = Invoice.invoiceNumber
pattern  = "INV-{YYYY}-{seq:6}"
scope    = tenant
reset    = fiscal-year
gap-free = true
```

### Settings

| Key | Purpose | Values |
|-----|---------|--------|
| `target` | Entity.field to auto-generate | `Invoice.invoiceNumber` |
| `pattern` | Format pattern | `"INV-{YYYY}-{seq:6}"` |
| `scope` | Sequence isolation | `global`, `tenant`, `region` |
| `reset` | When to restart numbering | `never`, `calendar-year`, `fiscal-year`, `monthly` |
| `gap-free` | Guarantee no gaps | `true` (slower) / `false` (faster) |

### Pattern tokens

| Token | Output | Example |
|-------|--------|---------|
| `{seq:N}` | Zero-padded sequence | `{seq:6}` -> `000042` |
| `{YYYY}` | Four-digit year | `2026` |
| `{YY}` | Two-digit year | `26` |
| `{MM}` | Month | `03` |
| `{DD}` | Day | `15` |
| `{region}` | Entity field value | Value of entity's `region` field |
| `{tenant}` | Current tenant | `acme-corp` |
| `{FY}` | Fiscal year | `FY2026` |
| `{FQ}` | Fiscal quarter | `Q3` |

---

## 4. Currency

```modelhike
Platform Currency (currency)
::::::::::::::::::::::::::::
base          = USD
supported     = USD, EUR, GBP, JPY, INR
rate-source   = external-api
rate-refresh  = daily
triangulation = true
rounding:
| USD -> 2 decimals
| EUR -> 2 decimals
| JPY -> 0 decimals
```

### Settings

| Key | Purpose | Example |
|-----|---------|---------|
| `base` | Base currency for conversions | `USD` |
| `supported` | Supported currency codes | `USD, EUR, GBP` |
| `rate-source` | Where to get exchange rates | `external-api`, `manual` |
| `rate-refresh` | How often rates update | `daily`, `hourly` |
| `triangulation` | Convert via base when no direct rate | `true` |
| `rounding:` | Decimal rules per currency | `|` block |

### Built-in functions

| Function | Returns | Example |
|----------|---------|---------|
| `convert(amount, from, to, config)` | Float | `convert(100, "EUR", "USD", @"Platform Currency")` |
| `convertAsOf(amount, from, to, date, config)` | Float | Historical rate conversion |
| `round(amount, currency, config)` | Float | Currency-aware rounding |

---

## 5. Unit of Measure

```modelhike
Weight Conversions (uom, weight)
::::::::::::::::::::::::::::::::
base = kg
conversions:
| kg  -> lb   * 2.20462
| lb  -> kg   * 0.453592
| oz  -> g    * 28.3495
```

### Settings

| Key | Purpose | Example |
|-----|---------|---------|
| `base` | Base unit for this category | `kg`, `l`, `piece` |
| `conversions:` | Conversion factors | `|` block with `from -> to * factor` |

Conversion syntax: `from -> to * multiplier` or `from -> to / divisor`.

### Built-in function

| Function | Returns | Example |
|----------|---------|---------|
| `convertUoM(value, from, to, config)` | Float | `convertUoM(5, "kg", "lb", @"Weight Conversions")` |

### Usage

```modelhike
Product
=======
*  weight     : Float
*  weightUnit : String <"kg", "lb", "oz">
=  weightKg   : Float = convertUoM(weight, weightUnit, "kg", @"Weight Conversions")
```

---

## Config Objects vs Entities

| | Entity (`=====`) | Config (`::::::::`) |
|--|---|---|
| Has CRUD? | Yes | No |
| Has API endpoints? | Yes | No |
| Has instances in DB? | Yes (rows in a table) | No (one instance, loaded at startup) |
| Referenced how? | `Reference@Entity` | `@"Config Name"` |
| Changes at runtime? | Yes (users create/edit) | Rarely (admin changes, redeploy) |

If users create/edit it through the app, it's an entity. If it's system configuration that rarely changes, it's a config object.
