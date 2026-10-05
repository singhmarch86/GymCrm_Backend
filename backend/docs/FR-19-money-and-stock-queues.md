# FR-19 — Work queues for money and stock

## 1. The problem, stated plainly

Staff work is a mirror. It reads eight append-only ledgers and reports what
already happened. Nothing on it is *owed*.

Leads → Workflow is the only screen in the product that says "this decision is
outstanding, here is the button". It is also the only screen that changed
anybody's behaviour, and the reason is not the data — the leads were always
there — it is the shape:

| Leads Workflow has | The money screens have |
|---|---|
| A definition of **owed** (no next step, no date, or no owner) | Nothing — just lists |
| **Unattended surfaced before overdue** | Only overdue exists |
| One-tap resolution **in place** | Navigate away to act |
| A count you can drive to **zero** | A total that simply *is* |

This FR applies that shape to money and stock. It is deliberately not "add
more reports".

**The test every queue in this document must pass:** a gym can drive it to
zero, and zero means something good happened. A queue that cannot reach zero
is a report wearing a queue's clothes, and within two weeks nobody reads it.

---

## 2. What the data actually supports

Checked against the live schema before writing, because three of the four
things asked for turned out not to mean what they sound like.

### Stock — fully modelled, better than expected

`products` already carries `stock_qty` and `reorder_level`, there is an
`IsLowStock()` helper, `stock_movements` is an insert-only signed ledger with
501 rows, and the products endpoint already accepts `?low_stock=true`.

Nothing new is needed in the database. The gap is purely that no screen asks
the question. **11 products, 2 currently at or below reorder level.**

### Expected payments — the forward-looking view has no data behind it

All **45** pending payments are already past due. There are zero pending
payments with a future due date, and the `overdue` status in the enum has
never been used.

So "expected payments" cannot come from the payments table: nothing is ever
scheduled into it ahead of time. The real forward-looking signal is membership
expiry — **10 renewals due today, 81 this week, 225 overdue** — which is
derived from `members.expiry_date`, not from a payment row.

**This changes the feature.** Expected Payments is a *renewals* view, and
Collections is a *payments* view. Building one screen called "payments" that
mixes them would produce a number that is neither.

### Invoices — the queue would be 1,053 deep on day one

`payments.invoice_id` exists and is indexed. Of 1,053 paid payments, **zero**
are linked to an invoice. All 4 invoices in the system are standalone.

A naive "money taken with no invoice raised" queue therefore opens at 1,053
and cannot be driven to zero by any realistic amount of work. It fails the
test in §1 on its first day.

This is a real finding and probably a real problem, but it is a **backfill and
policy question**, not a queue. See §6.

---

## 3. Queue 1 — Collections (money owed to the gym)

**Owed means:** a payment row in `pending`, for a member who is still active.

**Grouped, worst first — and "worst" is not "oldest":**

1. **Nobody has chased these** — pending, and no contact recorded against the
   member since the due date. This is the direct analogue of Unattended, and
   it is the group that justifies the whole screen. A due that nobody has
   mentioned to anybody is invisible today.
2. **Chased, no outcome** — somebody called, the money did not arrive.
3. **Promised to pay** — a date was agreed. Sorted by that date.
4. **Due later** — will exist once anything is scheduled forward.

**Actions in place:** Collect payment (the existing dialog), Record a promise
to pay (date + note), Write off (with a reason, owner only).

**Deliberately not:** automatic reminders, dunning escalation, or a "days
late" score against a member's name. FR-13 §1 applies to members as well as
staff.

**Live shape:** 45 rows, ₹2,15,000. Small enough to be workable on day one,
which is exactly why this is the queue to build first.

---

## 4. Queue 2 — Renewals due (money the gym is about to be owed)

**Owed means:** an active membership expiring within the window, with no
renewal recorded and no lapse decision taken.

This is what "Expected Payments" actually is. Grouped by **due today / this
week / this month / already lapsed**, driven by `members.expiry_date`.

**The 225 already-lapsed are the wallpaper risk.** A permanently red pile of
225 will be ignored by week two. Two options, and this is a decision for §7:

- **(a)** Cap the queue at a working horizon (say 30 days either side) and
  treat the older tail as a separate "gone quiet" list — which is what At Risk
  already does for attendance.
- **(b)** Require a lapse decision on each one: renewed, or marked lapsed with
  a reason. That makes the queue drivable to zero but front-loads 225
  decisions on somebody.

(a) is safer. (b) is more honest. Ask the gym.

**Actions in place:** Renew (existing dialog), Mark lapsed with reason, Set a
follow-up date.

---

## 5. Queue 3 — Low stock

**Owed means:** `stock_qty <= reorder_level` on a product that is not
discontinued.

The smallest, cleanest queue in this document: the definition already exists in
the model, the filter already exists in the repository, and it reaches zero
whenever somebody restocks.

**Grouped:** out of stock (qty 0, actively losing sales) before low.

**Actions in place:** Record a stock movement (the receipt of new stock),
Adjust reorder level, Mark discontinued.

**Live shape:** 2 of 11 products. Genuinely actionable today.

**Explicitly out of scope:** purchase orders, supplier records, cost tracking,
and stock valuation. Those are an inventory product, not a queue, and the gym
has not asked for them.

---

## 6. Invoices — what to do instead of a queue

1,053 payments with no invoice is not a work queue, it is a policy gap. Three
questions decide it, and none are ours:

1. **Does this gym issue invoices at all?** 4 invoices against 1,053 payments
   suggests not, or only on request.
2. **If they must (GST registered), is the gap historic or ongoing?** Historic
   needs a one-off backfill, not a daily queue.
3. **Should an invoice be raised automatically when a payment is collected?**
   If yes, this whole problem disappears at the source and the queue never
   needs to exist.

**Recommendation:** answer 3 first. If invoicing should be automatic, wire it
into payment collection and backfill the history once. Only if invoices are
genuinely a discretionary, per-member decision does a queue make sense — and
then it should be scoped to "this month", never all history.

Do not build an invoice queue in this FR.

---

## 7. Decisions that are yours

1. **Lapsed renewals: cap the window (a) or force a decision (b)?** §4.
2. **Should collections show a member's total outstanding, or just this row?**
   Total is more useful and also much closer to a credit score against a
   person's name.
3. **Who sees collections?** FR-13 §7 gives owners everything and staff their
   own. Money owed by members is not obviously the same shape — a receptionist
   probably needs the whole list to work the desk.
4. **Write-off authority.** Owner only, or anybody? A write-off is the one
   irreversible action in this document.
5. **Invoices: automatic on payment, or discretionary?** §6.

---

## 8. What this deliberately does not do

- **No automatic reminders or messages.** Same rule as FR-18: the queue records
  that you chased somebody, it does not chase them. WhatsApp remains a separate,
  unstarted project.
- **No dunning ladder, no escalation, no manager alerts.** Overdue is shown,
  not policed.
- **No collection targets and no per-staff collection totals.** A collections
  queue with names against it is one design decision away from a sales
  leaderboard, and FR-13 §1 exists to prevent exactly that. Collections are
  grouped by member, never by collector.
- **No credit scoring of members.** Ever.
- **No purchase orders or supplier management.** §5.
- **No invoice queue.** §6.

---

## 9. Build order

1. **Low stock** — smallest, definition already in the model, no new questions.
   Proves the shared queue shape outside Leads.
2. **Collections** — 45 rows, real money, the "nobody has chased these" group
   is the one genuinely new piece of information.
3. **Renewals due** — largest and most exposed to the wallpaper risk; build
   after §7.1 is answered.

Each reuses the FR-18 queue widget: grouped, worst-first, empty groups shown as
a quiet line rather than dropped, one-tap action in place.

---

## 10. Endpoints (proposed)

```
GET   /api/v1/queues/collections
GET   /api/v1/queues/renewals?horizon=
GET   /api/v1/queues/stock
PATCH /api/v1/payments/{id}/promise      { date, note }
PATCH /api/v1/payments/{id}/write-off    { reason }
POST  /api/v1/products/{id}/movements    { quantity, reason }
```

A shared `queues` package rather than one endpoint per module: the grouping,
the "owed" vocabulary, and the empty-group rule are the same in all three, and
that consistency is the whole point of the FR.
