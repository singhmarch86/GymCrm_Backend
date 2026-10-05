# FR-17 — The Members Table

**This is the specification** — every rule and why. Plain language, but
complete.

---

## Why this exists

The members list is a stack of cards. With **809 members**, a desk screen shows
about six of them at a time.

Everything the front desk does with this list is *scanning* — find a name,
check an expiry, see who has not been in. Scanning is what a table is for and
what a card is not. A card is the right shape for one record you are reading;
it is the wrong shape for eight hundred you are searching.

A table row carries the same information in roughly a quarter of the vertical
space, so the same screen shows **~25 members instead of ~6**. That is the whole
argument.

---

## 1. Table at the desk, cards on the phone

Switched at 900px, the same breakpoint the shell already uses.

A table at 375px is a horizontal-scroll nightmare and the most common complaint
about gym software on a phone. The owner checking on their phone keeps cards;
the desk on a wide screen gets the table. **One data source, two layouts** — not
two implementations of the screen.

## 2. The columns, and why each earns its width

| Column | Why it is here |
|---|---|
| **Name** | — |
| **Phone** | The desk's primary lookup. Members give a number, not an id. |
| **Plan** | Which membership, for renewal conversations |
| **Expiry** | With days-left colouring. The number driving most conversations at the counter. |
| **Status** | active / expired / frozen |
| **Last visit** | See below |

**Last visit is the one nobody else shows.** FitnessForce's member list does not
have it. It is what turns a directory into a retention tool: an owner scrolling
a table where a third of the rows say "6 weeks ago" has learned something no
report told them. It is also the only column here that connects this screen to
the rest of the product.

Anything not on that list is one tap away in the detail panel. A column that
gets read once a month costs width on every row, every day.

## 3. Two actions inline, the rest behind the row

**Collect payment** and **Renew** appear on the row. Clicking the row itself
opens the existing detail panel.

Not a kebab menu on every row: hiding the action somebody performs forty times
a day behind an extra tap is a tax paid all day long. Everything rarer lives in
the detail panel, where there is room to label it properly.

## 4. Sort by expiry and last visit only

Not every column.

Those two are the questions actually asked — "who is expiring" and "who has
stopped coming". Sorting by phone number is not a thing anyone does, and every
sortable header is a click target that can be hit by accident.

## 5. Colour means something or it is not used

Expiry colouring is the only colour on the row, and it maps to urgency:
expired, expiring within 7 days, everything else.

A table where four columns are tinted is a table nobody reads. The eye should
be drawn to the rows that need action, and to nothing else.

## 6. The table needs two fields the list endpoint does not return

This section first claimed no backend change was needed, then over-corrected to
three missing fields. Both were wrong, and only reading the live response over
forty members settled it. The real state:

| Field | Status |
|---|---|
| `expiry_date` | **Already returned.** Present on 36 of 40 sampled (799 of 809 overall) |
| `membership_plan_id` | Already returned |
| `membership_plan_name` | **In the DTO but never populated by the list path — 0 of 40.** The field exists with a comment calling it "resolved plan name for display"; nothing resolves it |
| `last_visit_at` | **Absent entirely** |

So: one **latent bug** (a declared field that is always null, which is worse
than an absent one — a client can reasonably code against it and get nothing),
and one genuinely new field.

Both additions are **read-only and additive**. No migration, no new table, no
write path. Existing clients keep working and the cards ignore what they do not
read.

`last_visit_at` aggregates `attendance`, the largest table in the system —
16,510 rows in the demo and far more in a real gym. It is computed with a
LATERAL join against **only the page being returned**, never the whole member
list, so cost scales with the 30 rows on screen rather than with 809 members.

The lesson worth keeping: **check the live response before specifying columns.**
Two of the three claims in the first draft of this section were wrong, and each
would have produced either a blank column or unnecessary backend work.

## 7. Density is a decision, not a default

Row height, font size and padding are set once in a shared table widget and
used by every list screen that adopts it.

Five hand-rolled tables drift within a month, and the drift is what makes
software look unfinished.

---

## What this deliberately does not do

- **No bulk selection.** This is the real unlock a table offers — select twenty
  expiring members, act on them together — and it is deliberately deferred.
  It needs answers this document cannot invent: which bulk actions, what is
  undoable, what happens when one of twenty fails. The pilot gym should ask for
  it before it is designed.
- **No column customisation.** Which six columns matter is a question for a real
  desk, not a preferences screen. A settings toggle is what you build when you
  refuse to decide.
- **No inline editing.** Editing in a grid is a category of bug — mis-clicks,
  half-saved rows, no undo — that a detail panel does not have.
- **No CSV export.** Worth having; not part of a layout change.
- **No table anywhere else yet.** Payments, Renewals and Invoices are the same
  shape of problem and should follow, but one screen proves the widget first.

---

## Scope

- New shared `AppDataTable` widget (§7)
- Members list renders it at ≥900px, existing cards below
- Sorting on expiry and last visit (§4)
- Row actions: collect payment, renew, open detail (§3)

Leads is explicitly out of scope: the board is the right view for a funnel, and
it was just made the default.

---

## Decisions that are yours

1. **Whether Last visit stays.** It is the most opinionated column here and the
   one a gym owner has never seen in this position before. If it confuses
   rather than informs, it is the first to go.
2. **Whether Plan earns its width**, or belongs with the expiry date.
3. **Which screen follows Members** — Payments is the obvious next, Renewals the
   most-used.
