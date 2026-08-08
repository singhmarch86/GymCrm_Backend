# FR-09 — Rhythm-Break Detection

**This is the specification** — every rule, every number, and the reasoning
behind each one. It is written in plain language, but it is complete: if you
want to change how the feature behaves, this is the document to argue with.

If you just want to understand *what the feature is*, read
[FR-09 explained in plain English](FR-09-explained-in-plain-english.md) first.
It's shorter and has no rules in it.

---

## Why this exists

Every gym system on the market measures churn risk the same way: **it counts
visits.** "No check-in for 7 days." "No check-in for 14 days." GymCRM already
does this — those are the `inactive_1_week` and `inactive_2_weeks` alerts from
FR-01.

The problem with counting visits is that it tells you **after** the member has
already started leaving. By the time somebody has missed two weeks, they've
mentally quit, and the call you make is a win-back call. Win-back calls rarely
work.

What actually holds a member is a **habit**, and a habit is a *time*, not a
count. Somebody who came at 7am every weekday for four months wasn't deciding
each morning to go — the 7am slot was simply part of their day. When that slot
breaks (new job, new shift, a baby, a longer commute), they don't stop coming
straight away. They start coming **whenever they can**: 6am one day, 9pm the
next, Saturday afternoon.

Their visit count hasn't changed. Every count-based system in the world says
they're fine.

They are not fine. The thing that was holding them is gone, and the attendance
follows a few weeks later.

**This feature fires when the consistency breaks but the visit count is still
healthy.** That's the whole idea, and it's why the warning is early. The data
needed is already there — GymCRM has stored the check-in *timestamp*, not just
the date, since day one.

---

## 1. What gets measured

**All times are read in India Standard Time** (UTC+05:30, a fixed offset —
India has no daylight saving). A 7am check-in must read as 7am, not 1:30am.

For a scan run on date `D`, two windows are used:

- **Before** — from 12 weeks ago to 4 weeks ago. Eight weeks long.
- **Now** — the last 4 weeks.

They don't overlap, so no visit is ever counted twice. "Before" is what the
member's routine *was*; "Now" is what it *is*.

"Before" deliberately stops four weeks short of today. If it ran right up to
now, the recent drift would be mixed into the very baseline it's being compared
against, and the signal would quietly cancel itself out.

For each member whose membership is still active, using their "Before" visits:

1. **Their usual time.** The average time of day they checked in — calculated
   *around the clock*, so an 11:40pm and a 12:20am visit average to midnight,
   not to noon. (Get this wrong and every late-night member's usual time lands
   12 hours out.)

2. **How well they kept it, before.** Of their "Before" visits, what fraction
   landed within **90 minutes either side** of that usual time. The 90-minute
   window also wraps around midnight.

3. **How well they're keeping it now.** Of their "Now" visits, what fraction
   landed within 90 minutes of that **same, original** usual time. The usual
   time is deliberately *not* recalculated — the question is "are they still
   keeping their old slot", not "have they settled into a new one".

4. **How often they come.** Visits per week, in each window separately.

5. **Which days they use.** Recorded for context on the card. This never
   affects whether the alert fires — see §6.

---

## 2. Who can be flagged at all

**You cannot break a routine you never had.** A member is only considered if
*all four* of these are true:

| Requirement | Threshold | Why it's there |
|---|---|---|
| Visits in "Before" | at least 12 | Fewer than about 1.5 a week is too sparse for "their usual time" to mean anything. |
| Different weeks covered | at least 6 of the 8 | Twelve visits crammed into one week is not a routine. |
| How well they kept the slot, before | at least 70% | They must actually have had a slot. Someone who always came at random times is a free-floater — nothing has broken for them. |
| Visits in "Now" | at least 4 | Not enough recent evidence below this to judge fairly. |

A member failing **any** of these is **never** flagged by this feature. The
ordinary count-based alerts still apply to them — that's a separate feature and
it keeps running.

---

## 3. When the alert actually fires

All three must be true for an eligible member:

1. **They're mostly not keeping the slot any more** — 40% or less of recent
   visits are near their usual time.

2. **The change is big, not noise** — the drop from "Before" to "Now" is at
   least 30 percentage points.

3. **They're still coming nearly as often** — recent visits per week is at
   least **60%** of what it was.

**Rule 3 is the point of the whole feature.** If the member's attendance has
already collapsed, the existing "Inactive 1 week / 2 weeks" alerts own that
person. Firing here too would list the same member twice and bury the early
signal among the late ones. **This feature stays silent there on purpose.** It
only speaks about members whose numbers still look fine — the ones nobody else
is watching.

**How urgent it looks** depends on the size of the drop:

| Drop from "Before" to "Now" | Shown as |
|---|---|
| 55 points or more | High (red) |
| 42 to 55 points | Medium (amber) |
| below 42 points | Low |

---

## 4. Where the alert lives

A rhythm break is **a new kind of row in the existing alerts table**, not a
separate alert system.

This is deliberate. The At Risk workflow GymCRM already has — no duplicate
alerts for the same member, automatic closing when the problem goes away, a
note recording what staff actually did, and their name against it — is the
thing that makes alerts get **acted on** rather than admired. A new signal
living in its own table would need all of that rebuilt, and staff would have
two lists to work instead of one.

So the new signal drops into the list they already work, and everything above
applies to it unchanged:

- A member can hold **at most one open rhythm-break alert**, however often you
  scan. The database enforces this, not the code — so rescanning, or two people
  scanning at the same moment, cannot produce duplicates.
- It's closed through the **same** "mark handled" action as every other alert,
  with the same note and the same staff attribution. No second way to do it.

Alongside the alert, each scan saves a **rhythm profile** for the member —
their usual time and all the numbers behind it. The alert message says *what*
happened; the profile is what the screen reads so nothing has to be recalculated
when you open it.

Profiles are saved for **every eligible member**, including those who did *not*
break their routine. A profile is a description, not an accusation — it also
answers "when does this member usually train?", which is useful on its own.

---

## 5. When an alert closes by itself

An open rhythm-break alert closes automatically once the member's recent
consistency is back to **60% or better**.

That recovery bar (60%) is deliberately **above** the firing bar (40%). If they
were the same, a member hovering right at the line would flip between flagged
and cleared on every single scan.

The existing rule that closes any alert for a deleted member applies here too.

There is deliberately **no** rule that closes a rhythm break because the member
went inactive. If someone breaks their routine and *then* stops coming, that's
the feature being **right**, and the alert should stay open until a human closes
it with a note.

---

## 6. What this deliberately does not do

- **No machine learning.** This is arithmetic on timestamps — one average and
  two fractions. It works correctly on 150 members today with no training
  period. A model would need years of labelled churn outcomes GymCRM doesn't
  have, and would be far harder to explain to the staff member making the call.

- **It doesn't send anything.** No SMS, no WhatsApp, no automated "we miss you"
  email. It raises a flag for a human, exactly like every other alert. *Record,
  don't automate.*

- **It doesn't learn a member's new routine.** If someone genuinely moved from
  7am to 7pm and is perfectly consistent at 7pm now, this fires once, staff see
  it, and they close it with a note. That's the right outcome — a member who
  changed their training time is worth a two-minute conversation — and by the
  next scan the baseline has moved on anyway.

- **It ignores which days of the week they use.** Day changes are shown on the
  card for context but never trigger the alert. Weekday patterns are far
  noisier than time-of-day — one public holiday or one week of travel throws
  them — and a second test on noisy data would cost accuracy without catching
  much more. Worth revisiting once there's real usage data.

- **It doesn't predict a churn date or invent a risk score out of 100.** A made-
  up percentage would imply somebody validated it against real outcomes. Nobody
  has. The alert states what was observed and lets staff judge.

- **It doesn't run on a schedule yet.** It's triggered by the Run scan button,
  like the existing retention scan. See the open questions.

---

## 7. What the software exposes

| Action | What it does |
|---|---|
| **Run scan** | Analyses everyone, saves the profiles, raises new alerts, closes recovered ones. Reports how many were evaluated, how many were eligible, how many broke, how many alerts were raised and closed. Can optionally be run against a past date. |
| **List rhythm breaks** | The open ones, with the numbers behind each. |
| **One member's rhythm** | That member's profile, whether or not it has broken. |

Closing an alert goes through the existing "mark handled" action.

Every query is restricted to the branch you're logged into, like everything
else in GymCRM. A branch sees its own members' rhythms and nobody else's.

---

## 8. Decisions that are yours, not mine

These are the numbers I chose by reasoning rather than from your data. Each is a
single constant and easy to change.

- **The 90-minute window.** The most important number in the feature. Wide
  enough that "I arrived at 7:15 instead of 7:00" isn't a break; narrow enough
  that a morning person drifting to evenings is. If your gyms run tightly
  scheduled classes, 45 minutes might be better. For a 24-hour floor gym, 120.

- **The window lengths (8 weeks, then 4 weeks).** Shorter windows spot problems
  faster but raise more false alarms. Eight-plus-four means a member has to have
  been with you about three months before this can say anything about them —
  which means it says **nothing about brand-new members**, who are separately
  your highest churn risk. That's a real gap, and a different feature's job.

- **Should the scan run every night?** Right now somebody presses a button. A
  nightly automatic run is easy to add — but the alerts only matter if somebody
  works the list in the morning, so this is really a question about how the gym
  operates, not about the software.

- **Timezone.** Fixed to India. If GymCRM is ever sold outside India this
  becomes a per-gym setting, and the fixed offset has to become a real timezone
  that understands daylight saving.
