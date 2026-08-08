# FR-09 — Rhythm-Break Detection

## Why this exists

Every gym CRM on the market — FitnessForce included — measures retention risk the same
way: **count the visits**. "No check-in for 7 days." "No check-in for 14 days." GymCRM
already does this (`inactive_1_week`, `inactive_2_weeks` in FR-01's retention alerts).

The problem with counting visits is that it fires *after* the member has already started
leaving. By the time someone has missed two weeks, they have psychologically checked out;
the call you make is a win-back call, and win-back calls convert badly.

What actually holds a member is a **habit**, and a habit is a *time*, not a count. The
member who came at 7:00am every weekday for four months did not decide each morning to go
to the gym — the 7:00am slot was load-bearing in their day. When that slot breaks (job
change, new shift, a baby, a commute change), they do not stop coming immediately. They
start coming *whenever they can*: 6am one day, 9pm the next, Saturday afternoon. Their
visit count is unchanged. Every count-based system on the market says they are fine.

They are not fine. The habit that was holding them is gone, and attendance follows a few
weeks later.

**Rhythm-break detection fires on the loss of consistency while the visit count is still
healthy.** That is the whole idea, and it is why the signal is early. The data needed is
already in `attendance.checked_in_at` — GymCRM has been storing the timestamp, not just
the date, since day one.

---

## 1. What we compute

All times are evaluated in **India Standard Time (UTC+05:30, fixed offset — India observes
no daylight saving)**, not UTC. A 7:00am check-in must read as hour 7, not 1:30.

For a scan run as of date `D`:

- **Baseline window** — `[D-84, D-28)`. Eight weeks, ending four weeks ago.
- **Recent window** — `[D-28, D]`. The last four weeks.

The windows do not overlap. The baseline is what the member's rhythm *was*; the recent
window is what it *is*.

For each member with an active membership, over their baseline check-ins:

1. **Anchor hour** — the *circular* mean of check-in times of day. Circular matters: a
   23:40 and a 00:20 check-in average to midnight, not to noon. Computed by averaging the
   unit vectors of each time-of-day and taking the resulting angle.
2. **Baseline consistency** — the fraction of baseline check-ins falling within
   **±90 minutes** of the anchor hour (measured circularly, so the window wraps midnight).
3. **Recent consistency** — the fraction of *recent* check-ins within ±90 minutes of that
   same **baseline** anchor. The anchor is deliberately not recomputed: the question is
   "are they still keeping their old slot", not "have they found a new one".
4. **Visit rate** — check-ins per week in each window.
5. **Weekday set** — which days of the week they used in each window. Recorded for context
   in the profile; it does **not** gate the alert (see §6).

---

## 2. Who is eligible to be flagged

You cannot break a rhythm you never had. A member is evaluated **only if all of these hold**:

| Gate | Threshold | Why |
|---|---|---|
| Baseline check-ins | ≥ 12 | Fewer than ~1.5/week is too sparse for a "mean time" to mean anything. |
| Distinct baseline weeks | ≥ 6 of 8 | Twelve visits crammed into one week is not a rhythm. |
| Baseline consistency | ≥ 0.70 | They must actually have kept a slot. A member who always came at random times is a free-floater, not a habit member — nothing has broken. |
| Recent check-ins | ≥ 4 | We need enough recent evidence to judge the pattern. |

Members failing any gate are **never** flagged by this feature. They may still be flagged
by the existing count-based retention alerts — that is a different feature and it still runs.

---

## 3. When the alert fires

A `rhythm_break` alert is raised when **all** of the following hold for an eligible member:

1. `recent_consistency ≤ 0.40` — they are mostly no longer keeping the slot.
2. `baseline_consistency − recent_consistency ≥ 0.30` — the change is large, not noise.
3. `recent_visit_rate ≥ 0.60 × baseline_visit_rate` — **the discriminating rule.**

Rule 3 is the point of the entire feature. If the member's attendance has already
collapsed, the existing `inactive_1_week` / `inactive_2_weeks` alerts own that member, and
firing a second alert would be double-counting the same person in the At Risk queue. This
feature is silent there **by design**. It speaks only about members whose visit count still
looks fine — the ones nobody else is watching.

**Severity** is set from the size of the drop:

| Drop (baseline − recent consistency) | Severity |
|---|---|
| ≥ 0.55 | high |
| ≥ 0.42 | medium |
| otherwise | low |

---

## 4. Where the alert lives

`rhythm_break` is a **new `alert_type` in the existing `retention_alerts` table**, not a
new parallel alert system.

This is deliberate. The At Risk workflow GymCRM already has — de-duplication of open
alerts, auto-resolution, per-alert action notes, and named staff attribution on who
followed up — is the thing that makes retention alerts get *acted on* rather than
admired. A new signal that lived in its own table would need all of that rebuilt, and
staff would have two queues to work. Instead the new signal drops into the queue staff
already work, and every existing behaviour applies to it unchanged:

- The partial unique index `(gym_id, member_id, alert_type) WHERE is_resolved = false`
  means a member can hold at most one open rhythm-break alert, no matter how often you scan.
- `PATCH /api/v1/retention/alerts/{id}/resolve` resolves it, records the action note, and
  attributes it to the logged-in staff member. No new resolution endpoint is added.

Alongside the alert, the scan writes a **`member_rhythm_profiles`** row (one per member,
upserted) holding the computed numbers. The alert message tells staff *what* happened
("used to train around 7:00am, 8 of 10 visits — now only 1 of 9"); the profile row is what
the UI reads to show the detail, so nothing has to be recomputed on page load.

Profiles are written for **every eligible member**, including those who did *not* break
rhythm. A profile is a description, not an accusation — it also powers "this member trains
Tue/Thu around 6:30pm", which is useful on its own.

---

## 5. Auto-resolution

An open `rhythm_break` alert is resolved automatically by a later scan when the member's
**recent consistency returns to ≥ 0.60**. The recovery threshold (0.60) is above the
firing threshold (0.40) on purpose: a member hovering at 0.41 must not flap between raised
and resolved on every scan.

The existing rule that resolves any open alert for a deleted member applies here too, since
it is keyed on the member, not the alert type.

There is **no** rule resolving a rhythm break because the member went inactive. If someone
breaks rhythm and then stops coming, that is the feature being *right*, and the alert
should stay open until a human closes it with a note.

---

## 6. What this deliberately does not do

- **No machine learning.** This is arithmetic on timestamps: a circular mean and two
  fractions. It works correctly on 156 members today. An ML model would need years of
  labelled churn outcomes GymCRM does not have, and would be less explainable to the staff
  member who has to make the phone call.
- **It does not send anything.** No SMS, no WhatsApp, no automated "we miss you" email. It
  raises a flag for a human, exactly like every other alert in GymCRM. *Record, don't
  automate.*
- **It does not re-anchor to a new rhythm.** If a member genuinely moved from 7am to 7pm
  and is now perfectly consistent at 7pm, this fires once, staff see it, and they close it
  with a note. That is the correct outcome — a member who changed their training time is a
  member worth a two-minute conversation, and the next scan's baseline will have moved on.
- **It does not gate on weekday drift.** Day-of-week changes are recorded in the profile
  for context but are not part of the firing rule. Weekday patterns are far noisier than
  time-of-day (public holidays, a single travel week), and a second gate on noisy data
  would cost precision without buying much recall. Revisit once there is real usage data.
- **It does not predict a churn date or produce a risk score out of 100.** A fabricated
  percentage would imply a validation exercise that has not happened. The alert states the
  observed facts and lets staff judge.
- **It does not run automatically on a schedule yet.** It is triggered like the existing
  retention scan — see the open questions.

---

## 7. API

| Method | Path | Purpose |
|---|---|---|
| `POST` | `/api/v1/rhythm/scan` | Run the analysis. Optional `as_of` (YYYY-MM-DD) to evaluate against a past date. Returns counts: evaluated, eligible, raised, resolved. |
| `GET` | `/api/v1/rhythm/breaks` | Open rhythm-break alerts, joined to member and profile. |
| `GET` | `/api/v1/rhythm/members/{id}` | One member's rhythm profile, whether or not they have broken it. |

Resolution goes through the existing `PATCH /api/v1/retention/alerts/{id}/resolve`.

Every query is tenant-scoped by `gym_id` through `database.ScopedDB`, like everything else.
A branch sees its own members' rhythms and no one else's.

---

## 8. Open questions for you

- **POLICY — the ±90 minute window.** This is the single most important number in the
  feature and I picked it from reasoning, not from your data: it is wide enough that
  "I got there at 7:15 instead of 7:00" is not a break, and narrow enough that a morning
  member drifting to evenings is. If your gyms run tightly-scheduled classes, ±45 might be
  right; for a 24-hour floor gym, ±120. It is a single constant and easy to change.
- **POLICY — window lengths (8 weeks baseline, 4 weeks recent).** Shorter windows detect
  faster and produce more false alarms. Eight-plus-four needs a member to have been with
  you ~3 months before this can say anything about them, which means it says nothing about
  brand-new members — who are, separately, your highest churn risk.
- **POLICY — should the scan run nightly?** Right now it is triggered, like the retention
  scan. A nightly cron is easy to add, but the alerts only matter if someone works the
  queue in the morning.
- **OPS — timezone.** Fixed at IST (UTC+05:30). If GymCRM is ever sold outside India this
  becomes a per-gym setting, and the fixed offset must become a real timezone with DST.
