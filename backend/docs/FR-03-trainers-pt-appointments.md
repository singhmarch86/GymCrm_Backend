# FR-03 — Trainers, PT Packages & Appointments

**Status:** proposed — our own rules, same caveat as FR-01/FR-02.

This completes three related parity items: Instructor/trainer management
(was a stub), Personal training packages (was a stub), and Appointment
booking (was missing — this is the calendar primitive it needed).

---

## 0. Two different things are both called "trainer"

`classes.trainer_user_id` already exists (migration 013) — it's whichever
staff member is teaching a group class, drawn from `users`. That's
deliberately loose: any staff member can be assigned to cover a Zumba class.

**This FR introduces a separate `trainers` table.** A trainer here is a
roster entity with compensation details (salary, commission) and a contact
record of their own — **not necessarily a `users` login**. Many gyms have
instructors who never touch the software; they still need to be tracked for
scheduling and payout. Conflating this with `users` would force every
trainer to have a login account, which is wrong.

The two are intentionally unrelated. A `class_schedules.trainer_user_id`
and a `pt_packages.trainer_id` are different foreign keys pointing at
different tables, and that's fine — group-class coverage and PT-roster
management are different concerns that happen to share an English word.

---

## 1. Trainers

A roster entry: `first_name`, `last_name`, `phone`, `email`,
`specialization`, `status` (`active`/`inactive`), `salary_in_paise`,
`commission_pct`. Matches the `Trainer` Flutter model that already existed
before any backend did — this FR fills that in, not redesigns it.

Deactivating a trainer (`status = inactive`) never touches PT packages or
appointments already tied to them — same non-retroactive principle as
everywhere else in this codebase.

---

## 2. PT packages

**A package is a session-credit counter, not a catalog + purchase pair.**
One row *is* the sold package: `package_name` (free text — "10 Session
Pack"), `total_sessions`, `sessions_used`, `amount_in_paise`,
`expiry_date`, `status` (`active`/`expired`/`cancelled`). Matches the
existing `PtPackage` Flutter model, which already computed
`sessionsRemaining = totalSessions - sessionsUsed`.

- `sessions_used` only increments when an **appointment is marked
  completed** — never at purchase, never at booking. Same principle as
  class bookings: attendance is recorded after the fact, not assumed.
- No automatic expiry. Staff set `status = expired` manually, same
  discipline as referrals and lifecycle.

---

## 3. Appointments — the calendar primitive

One row: `pt_package_id`, `trainer_id`, `member_id` (denormalized off the
package for convenient querying), `scheduled_at`, `duration_minutes`,
`status` (`scheduled`/`completed`/`cancelled`/`no_show`), `notes`.

### Rules

- **Booking never checks or reserves a credit.** A package with 0 sessions
  remaining can still have an appointment scheduled against it — the
  guard is on *completing* it, not booking it. This mirrors classes:
  overbooking a class becomes a waitlist entry; here, staff simply
  shouldn't complete a session against an exhausted package, and the
  system stops them if they try.
- **Completing an appointment increments `sessions_used` by 1** and fails
  if the package has no sessions remaining. This is the one place money
  (in the form of pre-paid session credit) actually moves.
- **Cancelling or marking no-show consumes nothing.** A missed session
  still cost the gym the trainer's time, but that's a business decision
  for a later phase (e.g. a no-show fee), not assumed here.
- **No double-booking detection.** Two appointments can be scheduled for
  the same trainer at overlapping times in v1. This is a real, known gap
  — see §4.

---

## 4. What this deliberately does not do

- **No trainer availability/calendar conflict checking.** Booking two
  overlapping appointments for the same trainer is not blocked. A real
  scheduling system would need this; it's out of scope here and should be
  the very next thing built on top of this primitive if double-booking
  becomes a real problem.
- **No automatic package expiry, no automatic no-show penalties, no
  payment collection.** Same "record, don't automate" boundary as every
  other module in this codebase.
- **No trainer login / permissions.** A trainer row has no relationship
  to `users` at all. If a trainer needs app access, they get a `users`
  row with role `staff`, entirely separately.

---

## 5. Open questions for you

1. **Commission on PT packages** — `commission_pct` exists on the trainer
   record, but nothing calculates a payout from it yet. Deferred, same as
   FitnessForce's "automatic commission calculation" gap noted in the
   parity spec.
2. **Double-booking** — is this a real problem for your target gyms
   (multiple PT trainers, tight schedules), or acceptable for now given
   most PT scheduling is verbal/informal?
