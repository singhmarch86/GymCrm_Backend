# FR-02 — Classes & Booking

Class definitions · recurring schedules · sessions · bookings · waitlist

**Status:** proposed — our own rules, not FitnessForce's (same caveat as FR-01:
their capability list names "Class scheduling," "Appointment booking," and
"Wait list management" but publishes no business rules).

This is the structural piece the parity spec flagged first: trainers, PT
packages, online booking, and commission all hang off the shape defined here.
Get the session/booking model right once rather than bolting each of those on
separately.

---

## 0. Shared model

### 0.1 Four objects, not one

| Object | What it is | Lifetime |
|---|---|---|
| **Class type** | "Yoga", "Zumba" — the offering | Long-lived, edited rarely |
| **Class schedule** | "Yoga, Mon/Wed/Fri 7am, Trainer X" | A recurrence rule |
| **Class session** | Monday 4 Aug, 7am Yoga | One materialized occurrence |
| **Booking** | Priya is booked into that session | One member × one session |

Sessions are **materialized rows**, not computed on the fly from the recurrence
rule. A rule change (new trainer, cancelled Wednesdays) must never silently
rewrite history — if Monday's session already has 8 bookings, editing the
schedule afterward does not touch it. Materialization is what makes that true.

### 0.2 Trainer

No `trainer` role exists in `users` today — only `owner` and `staff`. A
trainer is **any user assigned to a schedule or session**, not a new role.
Adding a first-class trainer role (specialities, bios, commission rates) is
its own later piece; FR-02 only needs "which staff member runs this."

### 0.3 Money

Out of scope here by the same rule as FR-01 §5: booking a class never charges
anyone. Whether a class is included in a membership plan, sold as a drop-in, or
part of a PT package is deferred — see §6.

---

## 1. Class type

The offering itself.

| Field | Notes |
|---|---|
| `name` | "Yoga", "HIIT", "Zumba" |
| `duration_minutes` | Default session length |
| `default_capacity` | Overridable per schedule/session |
| `description` | Optional |
| `is_active` | Inactive types can't be scheduled, existing sessions unaffected |

Deleting a class type is never allowed while any future session references it
— same soft-delete-resistant pattern as membership plans.

---

## 2. Class schedule — the recurrence rule

Defines a repeating slot: day-of-week + time + trainer + capacity, with an
effective date range.

| Field | Notes |
|---|---|
| `class_type_id` | What |
| `day_of_week` | 0–6 |
| `start_time` | Local time-of-day |
| `duration_minutes` | Defaults from class type, overridable |
| `capacity` | Defaults from class type, overridable |
| `trainer_user_id` | Nullable — unassigned is valid, filled in later |
| `effective_from` / `effective_until` | `until` nullable = open-ended |

### Generation

- Sessions are generated **30 days ahead on a rolling basis** (`POLICY`), not
  all at once out to `effective_until`. A schedule open-ended for two years
  should not materialize 700 rows on creation.
- Generation is **idempotent**: re-running it for a date range that already
  has sessions must not create duplicates. A partial unique index on
  `(schedule_id, session_date)` enforces this at the database, mirroring the
  retention-alert dedup pattern from migration 011.
- Editing a schedule (new trainer, new capacity) **only affects sessions not
  yet generated**. Already-materialized sessions are untouched — see §0.1.
  To change a specific upcoming session, edit that session directly (§3).
- Deleting/deactivating a schedule stops future generation. It does **not**
  cancel already-materialized future sessions — those must be cancelled
  explicitly (§3.3) so members who booked them are actually notified via the
  cancel path, not silently orphaned.

---

## 3. Class session — one occurrence

The bookable unit.

| Field | Notes |
|---|---|
| `schedule_id` | Nullable — a session can be ad-hoc, not from a recurrence |
| `class_type_id`, `trainer_user_id`, `capacity`, `session_date`, `start_time`, `duration_minutes` | Copied from the schedule at generation time, then independently editable |
| `status` | `scheduled` / `cancelled` / `completed` |

### 3.1 Why fields are copied, not referenced live

If the session merely pointed at its schedule for capacity/trainer, editing
the schedule would retroactively change a session members already booked
into. Copying at generation time, per §0.1, is what prevents that. A
**substitute trainer** for one Monday is an edit to that one session row, not
the schedule.

### 3.2 Status transitions

```
scheduled ──▶ completed   (staff marks after the class runs)
scheduled ──▶ cancelled   (staff cancels; see 3.3)
```

No transition out of `completed` or `cancelled`. Cancelling a `completed`
session is nonsensical and rejected.

### 3.3 Cancelling a session

- Every **active booking** (booked or waitlisted) on that session is set to
  `cancelled` with `reason = "session_cancelled"`. This is the one case where
  a booking is cancelled by the system rather than the member.
- This is the trigger point a notification system (future phase) hooks into —
  members whose class got cancelled need to know. FR-02 records the fact;
  sending the notice is out of scope here, same boundary as FR-01 §5.

---

## 4. Booking

One member, one session.

| Field | Notes |
|---|---|
| `member_id`, `session_id` | |
| `status` | `booked` / `waitlisted` / `cancelled` / `attended` / `no_show` |
| `booked_at` | |
| `cancelled_at`, `cancel_reason` | Nullable |
| `waitlist_position` | Nullable, only meaningful while `waitlisted` |

### 4.1 Booking rules

- A member cannot book a session that has already started. (`POLICY` — no
  grace window; walk-ins are a front-desk check-in, not a booking.)
- A member cannot hold two active (`booked` or `waitlisted`) bookings for the
  **same session**. Rebooking after cancelling is fine.
- **Frozen or terminated members cannot book.** Same gate as check-in in
  FR-01 §1 — a frozen membership is on hold, not active.
- If `capacity` is not yet reached: status = `booked`.
- If `capacity` is reached: status = `waitlisted`, position = current
  waitlist length + 1.

### 4.2 Cancelling a booking

- Members may cancel **up to 2 hours before session start** (`POLICY`)
  without consequence.
- Cancelling inside that window is still allowed (a hard block here just
  produces angry front-desk calls) but is recorded as a **late cancellation**
  — `cancel_reason = "late"` — visible in reporting. What a late cancellation
  *costs* (forfeited class credit, a fee) is deferred to §6, same as FR-01
  deferred money to the payments module.
- Cancelling a `booked` slot **promotes the next waitlisted member** (§4.3)
  in the same transaction. This must never be two operations that could
  partially fail — a promotion without a freed slot, or a freed slot with no
  promotion, is the one bug users will notice immediately.

### 4.3 Waitlist promotion

- FIFO by `waitlist_position`. No priority tiers in v1.
- Promotion changes status `waitlisted → booked` and clears
  `waitlist_position`. Remaining waitlisted members are **not** renumbered —
  position is assigned once at waitlist-join time and never recomputed,
  because recomputing on every cancellation is a needless write amplification
  for a number nobody but the query needs to sort by.
- Promotion does **not** auto-notify the member in FR-02. Same notification
  boundary as §3.3 — this is the hook point for a future phase, not a gap
  hidden inside this one.

### 4.4 Attendance

- Staff mark each booking `attended` or `no_show` **after the session
  completes** — not before, since "did they show up" isn't knowable earlier.
- Marking a session `completed` (§3.2) does **not** auto-mark every booking
  `attended`. An explicit no-show is information; silence is not the same
  as attendance.
- A class `attended` mark is **independent of gym check-in** (the existing
  `attendance` table). A member could check into the gym and skip their
  class, or (less common but real) a trainer could mark attendance for a
  session the member never checked into the building for, e.g. an outdoor
  class. Auto-linking the two is a plausible future enhancement, not a v1
  requirement — see §6.

---

## 5. What this deliberately does not do

Same discipline as FR-01 §5:

- **No automatic charging.** Whether a class booking is covered by the
  member's plan, needs a drop-in fee, or draws down a PT package is entirely
  deferred to §6. Booking a session never touches money.
- **No notification sending.** Cancellations and promotions are recorded;
  dispatching the notice is a later phase's job, same boundary as retention
  alerts and lifecycle events.
- **No capacity override at booking time.** Overbooking a full class is not
  a feature — it becomes a waitlist entry, always.
- **No recurring generation beyond the rolling window.** See §2.

---

## 6. Open questions for you

1. **Plan-gated classes** — are classes included free with membership, sold
   per-visit, or capped ("3 classes/month" on some plans)? This is the single
   biggest unknown and shapes whether §0.3's "no money" boundary needs a
   plan-allowance check before allowing a booking at all.
2. **Late-cancellation consequence** — nothing today beyond a reporting flag.
   Should a late cancel forfeit a class credit, once §6.1 exists?
3. **Cancellation window** — 2 hours is a guess. Yoga studios often use 12–24;
   an independent gym's HIIT class might use 30 minutes.
4. **Session ↔ gym-attendance linkage** — should marking a class `attended`
   also write a gym check-in row if the member has none for that day?
