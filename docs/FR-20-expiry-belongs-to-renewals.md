# FR-20 — Expiry belongs to Renewals, not At Risk

## 1. The problem

FR-19 §4 gave the renewals queue ownership of membership expiry. At Risk had
been computing the same thing since FR-03, and nobody removed it. The two now
duplicate each other.

Measured on live data, of **470 open alerts**:

| Alert type | Open | Also computed by |
|---|---|---|
| `expired_no_renewal` | 193 | Renewals → Due, "Lapsed" group |
| `expiring_today` | 30 | Renewals → Due, "Expires today" |
| `expiring_in_3_days` | 17 | Renewals → Due, "Expires this week" |
| `activation_no_first_visit` | 126 | nothing else |
| `activation_going_quiet` | 80 | nothing else |
| `rhythm_break` | 22 | nothing else |
| `activation_slow_start` | 2 | nothing else |

**240 of 470 — 51% — are expiry alerts the renewals queue already produces.**
**229 members appear in both lists right now.**

This is not untidiness to clean up later. It is a live hazard: a member
expiring today appears on both screens, resolving the At Risk alert does not
touch the renewals queue and vice versa, so two people work the same member —
or each assumes the other did.

---

## 2. The split

Each screen gets exactly one meaning.

- **Renewals → Due** — *their contract is ending.* A known date, a known
  value, one obvious action. Owned entirely by the queue.
- **At Risk** — *their behaviour changed.* No date, no fixed action, and
  invisible anywhere else in the product.

"Has not come in for three weeks, but their membership runs to December" is a
real signal the renewals queue can never surface. That is the argument for
keeping At Risk as a separate screen rather than folding it in.

The retention scanner stops generating `expiring_in_3_days`, `expiring_today`
and `expired_no_renewal`.

---

## 3. The gap this creates, and how it is closed

Retiring `expired_no_renewal` removes 193 alerts. Roughly **190 of those are
for people who lapsed more than 30 days ago** — outside the renewals window
FR-19 §4 caps at.

Deleted from At Risk and outside the renewals window, those people would be
visible on **no** screen at all. That would be solving duplication by creating
a hole, which is strictly worse than the duplication.

So the window becomes reachable rather than fixed:

```
GET /api/v1/queues/renewals?window=<days>
```

Default stays 30 — the decision FR-19 §4 recorded, and what the screen opens
on. The footnote that currently reads *"88 more lapsed over 30 days ago and are
not listed"* becomes the way in: tapping it widens the window and lists them.

Capped at 365. The cap is the same argument as FR-19 §9's range limit: an
unbounded window scans every member the gym has ever had, and no renewal
conversation is worth having two years late.

---

## 4. Existing alerts are resolved, not deleted

The 240 open expiry alerts are closed with
`action_note = 'superseded by the renewals queue (FR-20)'` and
`resolved_by = NULL`.

Deleting them would erase the record that the gym was once told about these
members, which is the kind of history somebody looks for precisely when they
are trying to work out why a member left. Resolving keeps the row, keeps the
timeline, and takes it off the screen.

`resolved_by` stays NULL on purpose: no person resolved these, a rule did.
Attributing them to whoever ran the migration would be a lie in an audit
column.

---

## 5. What does not change

- **No new UI.** The renewals side already renders the groups; only the window
  becomes adjustable. At Risk simply has fewer alerts.
- **`inactive_1_week` / `inactive_2_weeks`** are untouched. They are about
  attendance and belong exactly where they are.
- **Auto-resolve** keeps its expiry branches. They must keep working for the
  240 historical alerts and for any that predate this change.
- **No change to the dedup index** or the scan's ordering guarantees.

---

## 6. The question this raises, for the gym

After the split, At Risk is ~230 alerts, and **126 of them (55%) are
`activation_no_first_visit`** — people who joined and never once came in.

That is not retention. It is onboarding failure, and it is arguably a third
thing that deserves its own treatment rather than sitting in a list about
members drifting away. A member who never started cannot "drift".

Not decided here. It goes to the pilot gym with the other questions, because
the right answer depends on whether they treat a no-show joiner as a sales
problem, a service problem, or a refund.

---

## 7. Migration

`031_retire_expiry_alerts.sql` — resolves the open expiry alerts. No schema
change; the alert types stay valid so historical rows remain readable.
