# FR-13 — The Staff Work Dashboard

**This is the specification** — every rule and why. Plain language, but
complete.

---

## Why this exists

The owner is not at the gym all day. They employ two or three people to run the
counter, chase renewals, call leads and work the At Risk list, and at the end of
the day they have no idea what any of it amounted to.

The usual answer is to ask. That produces a story rather than a record, and the
story is always "it was busy". A gym owner deciding whether to keep paying for
this software will ask one blunt question: *does it tell me whether my staff are
doing their jobs?*

**Every one of those actions is already recorded, attributed to the person who
did it.** Payments carry `collected_by_user_id`. Renewals carry
`renewed_by_user_id`. Sales, invoices, wallet top-ups, stock movements,
membership freezes, resolved retention alerts and logged lead calls all carry
the acting user. The database has known the answer all along; nothing reads it
back.

This dashboard adds **no new data**. It is a view over ledgers that already
exist — which is why it needs no migration, and why nothing here can be wrong in
a way that corrupts anything.

---

## 1. It records; it does not measure

This screen answers **"what happened today, and who did it"**.

It does not answer "who is the best employee". It computes no score, no ranking,
no efficiency percentage, and no target attainment. Those are the owner's
judgement to make with context the software does not have — who was on shift,
who was training a new joiner, who spent an hour on a walk-in that did not
convert.

This is the same discipline as the rest of the product: **record, don't
automate**. A number the software presents as a verdict will be treated as one.

## 2. Nothing is inferred

A row appears under a staff member's name **only** because that row carries
their user id.

No guessing from who was logged in, no attributing a payment to whoever happened
to be on shift, no splitting credit. If a row has no user recorded, it belongs
to **Unattributed** — never to the nearest plausible person.

## 3. Unattributed work is shown, never hidden

Work with no user id gets its own row in the list, counted and visible.

Hiding it would be the more flattering choice and the wrong one. A gym seeing
"41 payments, 12 unattributed" learns something true and actionable — probably
that somebody is sharing a login, which is worth knowing. A dashboard that
silently drops those 12 makes the day's takings appear not to reconcile, and the
owner will trust nothing else on the screen once they notice.

## 4. A day is the gym's day, not UTC

All grouping is by **local calendar day in Asia/Kolkata**.

An 11pm sale belongs to that day, not tomorrow. This has bitten the seeder and
the rhythm detector already; the boundary is local midnight, everywhere, always.

## 5. The categories are the ledgers

There is no new taxonomy. Each category is one existing table:

| Category | Source | Counts |
|---|---|---|
| Payments collected | `payments.collected_by_user_id` | count + ₹ total |
| Renewals closed | `renewals.renewed_by_user_id` | count + ₹ total |
| Shop sales | `sales.created_by_user_id` | count + ₹ total |
| Invoices raised | `invoices.created_by_user_id` | count + ₹ total |
| At Risk handled | `retention_alerts.resolved_by` | count |
| Lead activity | `lead_activities.user_id` | count, split by type |
| Membership changes | `membership_events.performed_by_user_id` | count |
| Wallet top-ups | `wallet_transactions.created_by_user_id` | count + ₹ total |

This is deliberate. **Inventing categories before a real gym tells us how they
divide their day would be guessing**, and a wrong taxonomy is worse than none —
staff file work into the wrong bucket and stop trusting the screen. The ledgers
are ground truth and need no agreement from anyone.

## 6. Money shown is money *handled*, not money *earned*

The rupee totals are what passed through that person's hands.

They are not commission, not revenue attribution, and not a sales target. A
receptionist who collects a ₹40,000 annual renewal did not generate ₹40,000 of
value, and the screen must never imply they did. Labelled "collected", never
"achieved".

## 7. Staff see themselves; owners see everyone

An owner sees all staff. A staff user sees **only their own row**.

Not because their colleagues' numbers are secret, but because a screen where
juniors watch each other's counts becomes a competition the moment it is
visible, and the behaviour that follows is logging work rather than doing it.
The owner having the comparison is the point; everyone having it is the risk.

## 8. Every number opens the rows behind it

Tapping a count shows the underlying items — which member, which amount, what
time.

An aggregate nobody can drill into is an accusation. If the screen says somebody
collected three payments, the owner must be able to see which three before
raising it with them, and the staff member must be able to show their work.

## 9. Ordering is stable, not ranked

The list is ordered by **name**, with Unattributed last.

Sorting by count turns the screen into a leaderboard on every load, which rule 1
exists to prevent. The owner can compare perfectly well from a stable list.

---

## What this deliberately does not do

- **No staff attendance or hours.** The software does not know who was on shift.
  It cannot tell you somebody was present and idle — only what they recorded.
  Presenting activity counts as a proxy for hours would be a lie with someone's
  wages attached.
- **No productivity score.** No composite number, no weighting of a sale against
  a retention call. Any such weighting would be invented.
- **No targets and no alerts on staff.** The gym has no target data, and "Simran
  is behind" is a management conversation, not a notification.
- **No check-in attribution.** The `attendance` table has no acting-user column,
  so the most frequent front-desk action of the day is absent from this screen.
  This is a known and stated gap, not an oversight — see below.
- **No editing.** Nothing on this screen writes. It cannot correct a
  misattribution, because the ledgers are append-only by design.
- **No cross-gym view.** One gym at a time, `gym_id` scoped like everything else.

---

## The check-in gap, stated plainly

Marking members in at the counter is the single most common thing a receptionist
does, and **this dashboard cannot show any of it**, because `attendance` records
who came in but not who served them.

Closing it means a migration adding `marked_by_user_id`, and it only becomes
truthful from the day it ships — historical check-ins can never be attributed.

That is deferred on purpose. The pilot gym should confirm the dashboard is worth
having before we alter a hot, high-volume table to feed it.

---

## The endpoint

```
GET /api/v1/staff-work?date=YYYY-MM-DD
```

`date` defaults to today in IST. Owners get every staff member; staff get only
themselves, enforced server-side from the token — never by a client-supplied
user id.

```
GET /api/v1/staff-work/items?date=YYYY-MM-DD&user_id=&category=
```

The rows behind one number (rule 8). `user_id` omitted means unattributed.

Both are read-only, both are `gym_id` scoped through the standard tenant
context.

---

## Decisions that are yours

1. **Should staff see their own screen at all**, or is this owner-only? Showing
   people their own record is fairer and encourages logging; it also makes the
   count feel like a target. Currently: staff see themselves.
2. **How far back to allow.** Currently any past date, one day at a time. A
   week-at-a-glance view is a natural next ask and deliberately not built yet.
3. **Whether to add `marked_by_user_id` to attendance.** Until then the busiest
   part of the day is invisible here.
4. **Whether "Unattributed" should be loud.** It is currently a plain row. If
   shared logins turn out to be normal in Indian gyms, this may deserve a
   warning instead.
