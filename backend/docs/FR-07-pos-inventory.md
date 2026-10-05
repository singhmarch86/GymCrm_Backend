# FR-07 — Retail: POS & Inventory

Status: draft for implementation
Depends on: `members`, `payments`, `invoicing`
Related: FR-04 (a sale can be invoiced), FR-06 (stock is per branch)

---

## 0. What this is

Gyms sell things: protein, shakers, tape, gloves, water, joining kits. Today the
system has no way to record any of it, so that revenue either goes into a
notebook or gets miscoded as a membership payment.

Two halves, deliberately built together because one is useless without the other:

| Object | What it is |
|---|---|
| **Product** | Something the gym sells, with a price, a cost, and a stock level |
| **Sale** | A counter transaction: items, quantities, total, how it was paid |

### 0.1 Stock is per branch

A product row belongs to one gym, which under FR-06 means one branch. The Model
Town branch running out of protein says nothing about Sarabha Nagar's shelf.
This falls out of the existing tenancy and needs no special handling.

---

## 1. The rule that shapes the design: stock is never edited directly

Every change to a stock level is recorded as a **movement** — an immutable row
saying what changed, by how much, why, and who did it.

```
stock_movements:  purchase | sale | adjustment | return | wastage
```

The product's `stock_qty` is a running figure kept in step with those movements,
never set by hand. The reason is practical rather than theoretical: stock
discrepancies are the single most common source of retail arguments, and
"someone changed the number" with no record is unanswerable. With movements, the
question "why does the system say 12 when the shelf has 9?" always has a trail.

This mirrors the immutable-audit approach already used for `membership_events`
(FR-01) and `lead_activities`.

### 1.1 Concurrency

Selling decrements stock, which is a read-then-write and therefore races: two
staff selling the last tub of protein simultaneously would both succeed.

The product row is locked `SELECT ... FOR UPDATE` inside the same transaction as
the sale, exactly as class booking capacity (FR-02) and PT session credits
(FR-03) already do.

**POLICY** — selling more than you hold is **blocked by default** but can be
allowed per gym (`allow_negative_stock`), because small gyms genuinely do sell
from a delivery that hasn't been counted in yet. See open question 4.1.

---

## 2. Sales

A sale is a completed counter transaction. There is no cart/draft state: at a
gym counter the transaction is finished in one interaction, and a half-finished
sale sitting in the database is a liability, not a feature.

- One or more line items, each a **snapshot** of the product's name and price at
  the time of sale (same principle as FR-03 and FR-04 — later price changes must
  not rewrite history)
- Optional **member link**: a sale can be attached to a member, which is how
  "put it on my account" and per-member purchase history work
- A **payment mode** (cash/UPI/card), recorded on the sale itself
- Optionally **invoiceable** — a sale can raise an invoice with `item_type =
  'product'`, using the machinery already built in FR-04

### 2.1 Refunds

A refund is a **new sale with negative quantities**, not an edit or deletion of
the original. The original sale stays exactly as it was, and the refund carries
its own reason and its own stock movement (a `return`, which puts stock back).

This is why sales are never edited or deleted: a till that can be rewritten
after the fact is a till nobody can reconcile.

---

## 3. What the gym actually needs to see

- **Low stock** — products at or below their reorder threshold, which is the one
  report that prevents lost sales
- **Stock value** — quantity × cost, for the balance sheet
- **Sales summary** — revenue and units by period, and by product
- **Margin** — sale price minus cost, which is why `cost_price` is captured at
  all rather than only the selling price

---

## 4. Open questions for you

1. **Should overselling be blocked or warned?** Default is blocked. Small gyms
   often sell stock that physically arrived but hasn't been entered, and a hard
   block means the sale can't be recorded at all — which is worse than a
   negative number, because the money then goes unrecorded.
2. **Barcode scanning?** SKUs are stored, so a USB scanner (which types the code
   and presses Enter) works with a search box today. Camera scanning in the app
   is a bigger piece.
3. **Supplier / purchase orders?** v1 records a `purchase` movement to add stock,
   but has no supplier records, POs, or payables. Do your gyms need that, or is
   "stock arrived, add it" enough?

---

## 5. Deliberately out of v1

- **No supplier or purchase-order management.** Stock in is a movement, not a
  procurement workflow.
- **No cart/parked sales.** See §2.
- **No editing or deleting a sale.** Refunds only. See §2.1.
- **No barcode camera scanning.** See §4.2.
- **No stock transfer between branches** — branches are separate tenants
  (FR-06 §0.1); a transfer would be a movement out of one and into another, and
  needs a deliberate cross-branch design.
- **No automatic reordering.** The system flags low stock; a human decides.
- **No product variants** (size/flavour as one product with options). Each
  variant is its own product, which is clumsy for apparel but perfectly fine for
  supplements, and avoids a variant model that v1 doesn't need.
