# FR-18 — The Lead Workflow

**This is the specification** — every rule and why. Plain language, but
complete.

---

## Why this exists

The product records where a lead *is*. It never says what happens *next*.

The board shows six columns. The follow-up queue shows whoever has a date set.
Between them sits the actual failure: a lead moves to **Contacted**, nobody
sets a follow-up date, and it sits there for nine days until it is dead. No
screen shows it, because no screen is asking the question. It is not overdue —
it was never due. It simply has nothing scheduled and nobody looking at it.

That is not a reporting gap. It is a missing workflow.

**The invariant this FR introduces: every open lead has exactly one next step,
owned by one person, with a date.** Everything below follows from that.

---

## 1. One next step. Always. Or the lead is visibly unattended

Every lead not yet `joined` or `lost` carries:

- **what** the next step is
- **who** owns it
- **when** it is due

If any of the three is missing, the lead appears in **Unattended** — its own
group, at the top, before overdue.

Unattended is the state this whole document exists to make visible. A gym
losing leads is almost never losing the ones being chased badly; it is losing
the ones nobody picked up. Today that state is invisible, which is why it
persists.

## 2. The stage proposes the next step

Each pipeline stage has a default next step, so a lead is never left without
one just because somebody was busy:

| Stage | Default next step | Default due |
|---|---|---|
| New Lead | Make first contact | Same day |
| Contacted | Book a trial | +2 days |
| Trial Scheduled | Confirm they are coming | day before the trial |
| Trial Completed | **Counselling** — sit down, discuss plans | +1 day |
| Joined / Lost | *none — workflow ends* (§6) | — |

An earlier draft of this table included a **Negotiation** stage. There is no
such stage: the pipeline is new_lead → contacted → trial_scheduled →
trial_completed → joined / lost, and inventing a sixth would have meant either
a dead constant or a migration nobody asked for. Closing happens from Trial
Completed, after counselling.

These are defaults, not rules. Staff override any of them.

## 3. The software proposes; the staff member decides

Logging an outcome **suggests** the next step and pre-fills the date. It never
sets one silently.

This is FR-16 §4 carried forward, and it matters more here. A workflow that
reschedules itself becomes a workflow nobody trusts, because the dates stop
meaning "somebody decided this" and start meaning "the computer guessed".

Concretely, after logging a call:

| Outcome | Suggested next step |
|---|---|
| No answer | Try again — **+1 day** |
| Call back later | Call back — **date they asked for** |
| Answered / Interested | Book a trial |
| Not interested | Mark lost — with a reason |
| Wrong number | Fix the number, or mark lost |

Each arrives as a pre-filled, one-tap confirmation. Each is declinable.

## 4. Counselling is a real step, not a note

`counselling` becomes an activity type alongside call, note, follow_up_set and
trial_scheduled.

It is the conversation where somebody sits down after a trial and talks about
plans and price — the single highest-conversion moment in the pipeline, and
currently indistinguishable from "note". A gym that cannot count how many
counselling sessions happened cannot tell whether its best-converting activity
is being done at all.

No migration: `type` is a varchar validated in Go.

## 5. Stage age is visible, because stuck is not a status

Every lead shows how long it has been in its current stage.

A lead sitting in Contacted for three weeks is not "contacted". It is dying,
and the only signal available today is a date column somebody has to compare
against today's date in their head. `lead_activities` already holds every
`stage_change`, so this is a read, not new data.

## 6. Conversion ends the workflow. So does lost.

`joined` and `lost` clear the next step entirely and remove the lead from every
queue.

Nothing nags about a member who already joined. This sounds obvious; it is the
most common failure mode in CRMs that bolt a task system onto a pipeline, and
it is how staff learn to ignore the queue.

## 7. Staff work → Leads shows the live workflow, not a scorecard

The tab shows, per person: what they are carrying and what is falling over.

> **Simran** — 14 leads · 3 unattended · 2 overdue · next: Karan Mehta, today

Then the funnel *they* worked over the chosen period: reached → trials →
counselling → joined.

Ordered by name, never by conversion rate (FR-13 §9). The unattended count is
the number the owner should react to, and it is a workload signal as often as a
performance one — somebody carrying 60 leads will have unattended ones, and
that is a staffing fact, not a personal failing.

## 8. Reassignment moves the whole workflow

Changing the owner moves the next step, its date and the history with it.

Half-transferred work is worse than untransferred work: both people assume the
other has it.

## 9. Date ranges — and an explicit reversal of FR-13 §4

The staff-work view gains **Day · Month · Custom range** with a calendar.

**FR-13 §4 said one day at a time, and deferred ranges as an open decision.
This supersedes it.** An owner asking "what did Simran do in July" is a
legitimate question that a single-day view cannot answer.

What does **not** change: FR-13 §1 still holds. No score, no ranking, ordered by
name. A month of aggregates reads much more like a performance review than a
day does, so the anti-leaderboard rules matter *more* here, not less. Both ends
of the range use the IST local-day boundary.

### What building it turned up

Four things only became visible once a month could be on screen at all. All
four are shipped:

1. **Carrying is still "now".** Only the funnel moves with the range. Asking
   for July does not un-neglect a lead still sitting untouched today, so the
   card labels the block **Carrying now** — unlabelled counts under a date
   range read as being scoped to it.
2. **The drill-down cap is now honest.** It was `LIMIT 200`, silently. A day
   rarely reached it; a month will. The API now fetches one row over the cap
   and returns `truncated`, and the sheet says so *above* the list.
3. **Drill-down rows carry a date.** Across a span, three rows at 18:30 could
   be three days or three minutes apart.
4. **A range is capped at a year** and both ends must be given together. A
   lone `from` silently completed to today would answer a question nobody
   asked, and a mistyped year would drag every row the gym has ever written
   through the eight-ledger union.

### Known gap, not fixed here

The **Lead activity** tally on the Money & work tab counts every row in
`lead_activities`; the Leads funnel counts only the five types a person logs by
hand. Over August that is 16 against 5 — the other 11 are `stage_change` and
`created`, written by the server. The two numbers have always disagreed; a
single day just never showed enough of them to notice.

The screen now says which it is counting rather than leaving the reader to
reconcile them. Whether a stage move should count as lead work is a real
question and belongs with the pilot gym, not with a guess here.

---

## What this deliberately does not do

- **No automatic stage transitions.** Logging a trial does not move the lead to
  Trial Scheduled. The staff member moves it, as today.
- **No SLA enforcement, no escalation, no manager alerts.** "Not contacted
  within 24 hours" is a target system, and this gym has no targets. Unattended
  is shown, not policed.
- **No auto-assignment or round-robin.** Who owns a lead is a human decision.
- **No messaging.** The workflow records that you contacted somebody; it does
  not send anything. WhatsApp/Instagram remain a separate, unstarted project.
- **No workflow for members.** Retention alerts are the member equivalent and
  already exist. Merging the two vocabularies would make both worse.
- **No custom stages.** Six stages, fixed. Configurable pipelines are a
  different product.

---

## Data

Migration `027`:

```sql
ALTER TABLE leads ADD COLUMN IF NOT EXISTS next_step VARCHAR(40);
ALTER TABLE leads ADD COLUMN IF NOT EXISTS next_step_due DATE;
```

`follow_up_date` already exists and stays as-is — it is what the follow-up
queue reads. `next_step_due` is deliberately separate: a follow-up date answers
"when do I call again", the next step answers "what am I doing and why". A lead
can have a booked trial next Tuesday *and* a confirmation call on Monday.

No backfill. Existing leads start with a null next step, which places them in
**Unattended** — correct, and the first honest picture the gym will get.

## Endpoints

```
GET   /api/v1/leads/workflow?assigned_to=&group=stage|due
PATCH /api/v1/leads/{id}/next-step        { step, due }
GET   /api/v1/staff-work?from=&to=        (replaces ?date=)
GET   /api/v1/staff-work/leads?user_id=&from=&to=
```

---

## Decisions that are yours

1. **What counselling means** — a scheduled sit-down, or any in-person
   conversation? This decides whether it is logged weekly or six times a day,
   and therefore whether the count means anything.
2. **Whether Unattended should be loud.** It is a group at the top today. If a
   real gym runs at 40% unattended it may need to be quieter, or it becomes
   wallpaper.
3. **The default due dates in §2.** Invented from how gym sales usually run,
   not from watching this gym. The pilot should correct them.
4. **Whether staff see each other's workflow** or only their own. Currently
   owner sees all, staff see themselves (FR-13 §7).
