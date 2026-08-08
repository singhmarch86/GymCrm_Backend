# FR-04 — Invoicing & Discounts

Status: draft for implementation
Depends on: `members`, `plans`, `payments`, `renewals`, `gyms`
Related: FR-01 (lifecycle — upgrades create amounts owed), FR-03 (PT packages are sellable items)

---

## 0. What this module is

Today the system **records money** (`payments`) and **records membership validity**
(`renewals`), but it produces **no document**. A gym in India cannot operate that way:
a member paying ₹12,000 expects a numbered invoice, and the gym's accountant needs a
gapless, GST-compliant series to file returns against.

This module adds that document layer, plus the discounting that has to happen *before*
a total is struck.

Two distinct things, deliberately built together because a discount that isn't recorded
on the invoice is a discount that can't be audited:

| Object | What it is |
|---|---|
| **Invoice** | An immutable numbered document listing what was sold, at what price, with what discount and tax, totalling to an amount owed. |
| **Discount** | A named, reusable rule (percent or flat) that staff apply to an invoice, recorded on the invoice itself. |

### 0.1 What an invoice is *not*

An invoice is **not** a payment. The existing `payments` table remains the financial
source of truth for money actually received. An invoice says *"₹12,000 is owed"*;
a payment says *"₹12,000 arrived, in cash, on this date"*. They are linked but separate,
and one invoice may be settled by several payments (part payments are normal in gyms).

An invoice is also **not** a renewal. `renewals` remains the source of truth for
membership validity. Issuing an invoice never extends anybody's expiry date.

---

## 1. Numbering — the rule that constrains the design

Indian GST invoicing requires a **gapless, sequential, per-financial-year** series per
place of business. This is the single hardest requirement in this module and it drives
several decisions.

1. Each gym has its own independent series. Gym 1's `INV/2026-27/0001` and gym 2's
   `INV/2026-27/0001` coexist and are unrelated.
2. Numbers are assigned **at issue time, never at draft time**. A draft that is deleted
   must not burn a number.
3. Numbers are **gapless** — no skipping, even under concurrent issue. Two staff
   clicking "Issue" simultaneously must produce `0007` and `0008`, never two `0007`s
   and never `0007` + `0009`.
4. The series **resets on 1 April** (Indian financial year), with the FY embedded in the
   number.
5. Once assigned, a number is **permanent**. Cancelling an invoice does not free its
   number for reuse — the cancelled document keeps it, which is exactly what an auditor
   expects to see.

### 1.1 How gaplessness is enforced

A dedicated `invoice_sequences` row per (gym, financial year), locked with
`SELECT ... FOR UPDATE` inside the same transaction that inserts the invoice. Same
concurrency pattern already used for class booking capacity (FR-02) and PT session
credits (FR-03).

An auto-increment column is **not** acceptable here: Postgres sequences are explicitly
non-transactional and leave gaps on rollback.

**POLICY** — default number format is `{PREFIX}/{FY}/{SEQ:04d}` → `INV/2026-27/0042`,
with `PREFIX` configurable per gym (default `INV`). See open question 5.1.

---

## 2. Invoice lifecycle

```
draft ──issue──> issued ──cancel──> cancelled
  │
  └──delete──> (gone, no number burned)
```

1. **draft** — fully editable. Line items can be added, changed, removed. No number
   assigned. Can be deleted outright.
2. **issued** — has a number, a date, and frozen totals. **Immutable.** No line item,
   price, discount or tax may change after this point.
3. **cancelled** — an issued invoice voided by staff, with a mandatory reason. Keeps
   its number. Excluded from revenue totals. Terminal.

There is no "paid" *status* on the invoice. Payment state is **derived** from the
payments linked to it, at read time — the same computed-not-stored approach already used
for `members.ExpiryStatus` and `payments.effectiveStatus`:

| Derived state | Condition |
|---|---|
| `unpaid` | no payments linked |
| `partial` | linked payments total > 0 but < invoice total |
| `paid` | linked payments total ≥ invoice total |

This avoids a status field that can silently disagree with the actual money. The money
is the truth; the label is computed from it.

### 2.1 Why issued invoices are immutable

Editing an issued tax document is not a feature — it's a compliance problem. If an
issued invoice is wrong, staff cancel it (with a reason, on the record) and issue a new
one. Both documents survive, and the trail explains itself.

---

## 3. Line items

An invoice has one or more line items. Each is a **snapshot**, following the same
principle established in FR-02 §0.1 and FR-03: a line copies the description and price
at the moment it is added, so later edits to a plan's price never retroactively alter a
document already given to a member.

Per line:

- `description` — snapshot text (e.g. "Annual Membership — Gold")
- `item_type` — `plan` | `pt_package` | `product` | `custom`
- `reference_id` — optional FK-ish pointer to the plan/package it came from (nullable,
  not enforced, because the source row may later be deleted and the line must survive)
- `quantity` — integer ≥ 1
- `unit_price_in_paise`
- `discount_in_paise` — the resolved cash value of any discount on this line
- `tax_rate_pct` — e.g. `18.00`
- `sac_code` — optional; India's SAC for fitness services is `999723`

### 3.1 Money arithmetic

All amounts are `int64` **paise**, never floats — consistent with the whole codebase.

Per line, in this exact order:

```
gross          = unit_price_in_paise × quantity
taxable        = gross − discount_in_paise
tax            = round_half_up(taxable × tax_rate_pct / 100)
line_total     = taxable + tax
```

Invoice totals are the sum of line values. Rounding happens **once per line**, at the
tax step, using half-up to the nearest paise. Never round intermediate values twice, and
never compute tax on the invoice total when lines carry different rates.

### 3.2 GST split

For an intra-state sale (gym and member in the same state — effectively always, for a
gym), the tax splits evenly into **CGST + SGST**, each half of `tax_rate_pct`. For
inter-state it is a single **IGST** line at the full rate.

v1 assumes **intra-state** and stores the split as derived display values, not columns.
The `place_of_supply` state is snapshotted on the invoice so the split can be recomputed
correctly later if inter-state ever matters.

**POLICY** — default `tax_rate_pct` is `18.00`, configurable per gym, overridable per
line. See open question 5.2.

---

## 4. Discounts

A discount is a **named reusable rule**, not a free-text number, so that "why was this
member charged less?" always has an answer.

```
Discount
  code             e.g. "NEWYEAR25"     (unique per gym, case-insensitive)
  name             e.g. "New Year 25% off"
  type             percent | flat
  value            25.00  |  50000 (paise)
  valid_from       date, optional
  valid_until      date, optional
  max_uses         optional; NULL = unlimited
  times_used       counter
  is_active        bool
```

Rules:

1. A discount applies to **one invoice**, recorded with its code, name and the resolved
   paise value at the time of application — snapshotted, so later edits to the rule never
   change a document already issued.
2. `percent` discounts resolve to a paise value **at application time** and that value is
   what is stored. The percentage is kept only for display/audit.
3. A discount can never make a line total negative. Resolved discount is clamped to the
   line's gross value.
4. `times_used` increments **on issue, not on draft** — and only once per invoice.
5. Expired, inactive, or exhausted discounts are **rejected at application time** with a
   clear reason. They are never silently ignored.
6. Staff may also apply an **ad-hoc discount** (a plain paise amount with a mandatory
   reason) without a code, for one-off negotiation — which is what actually happens at
   a gym front desk. It is recorded identically, just with a null discount code.

Nothing about discounts is automatic. No auto-applied promotions, no "best discount
wins" resolution engine — staff choose, the system records.

---

## 5. Open questions for you

1. **Invoice number format.** Default is `INV/2026-27/0042`. Some gyms want their branch
   code in there (`INV/LDH/2026-27/0042`). Configurable prefix covers most of it — is
   that enough, or do you need a fully templated format?
2. **Default GST rate.** 18% is standard for gym/fitness services in India. Should this
   be a per-gym setting (some gyms below the ₹20L threshold aren't registered at all and
   want tax entirely off), and should the gym's GSTIN be a required field before any
   invoice can be issued?
3. **Tax-inclusive pricing.** Gyms usually advertise "₹12,000 all inclusive". Should plan
   prices be treated as **tax-inclusive** (back-calculate tax out of the price) or
   **tax-exclusive** (add tax on top)? This materially changes every total and is the
   single most important answer here. v1 assumes **exclusive** unless you say otherwise.
4. **Credit notes.** Cancelling covers "this invoice was wrong". It does not cover
   "member paid, then we refunded half". Proper credit notes are a separate document
   type — deliberately out of v1. Do you need them soon?
5. **Who can cancel?** Cancelling a tax document is significant. Should it be
   owner/manager-only via RBAC, or can any front-desk user cancel?

---

## 6. What this deliberately does not do

- **No payment collection.** Issuing an invoice never charges anyone. Money still enters
  only through the existing payments flow. (Gateways are blocked on business
  registration anyway.)
- **No automatic invoice generation.** No invoice is created by a renewal, a lifecycle
  upgrade, or a PT sale on its own. Staff create them. Consistent with the
  "record, don't automate" discipline in FR-01 through FR-03.
- **No recurring/subscription billing.** No mandates, no scheduler. That is a separate
  module that depends on a payment gateway.
- **No PDF rendering.** The API returns structured invoice data; turning it into a
  printable document is a client concern for now. A server-side PDF endpoint is a
  reasonable v2 once the data shape has settled.
- **No credit notes, no proforma invoices, no e-invoicing/IRN.** E-invoicing only applies
  above a turnover threshold most single gyms won't hit; if a chain does, it's a
  dedicated piece of work.
- **No editing of issued invoices**, by anyone, ever. See §2.1.
- **No automatic discount application.** See §4.
