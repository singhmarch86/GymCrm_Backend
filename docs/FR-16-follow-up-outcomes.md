# FR-16 — Follow-up Outcomes

**This is the specification** — every rule and why. Plain language, but
complete.

---

## Why this exists

The system records that a follow-up **happened**. It does not record what
**came of it**.

Today a staff member logs `call` with a free-text note. Tomorrow nobody can
answer the two questions that matter:

- *Did anyone actually reach this person, or has the phone rung out six times?*
- *Which of our 47 open leads are worth calling again, and which have said no?*

Both answers are sitting in the notes, in whatever words someone typed at the
time — "no ans", "didnt pick", "will call back", "not interested for now". You
cannot filter on that, count it, or hand it to the next person on shift.

This adds one field: **what happened**. It is the difference between a log and
a worklist.

---

## 1. Two axes, kept separate

An activity now carries two independent facts:

| Axis | Column | Example |
|---|---|---|
| **What you did** | `type` (exists) | call, note, follow_up_set, trial_scheduled |
| **What came of it** | `outcome` (new) | answered, no answer, call back, not interested |

These are deliberately not merged into one list. "Call" and "no answer" are not
alternatives — every call has both a method and a result, and collapsing them
produces a taxonomy where you cannot count calls without also deciding what
happened on them.

## 2. The outcomes

Six, and the count is the point:

| Outcome | Means | Effect |
|---|---|---|
| `answered` | Spoke to them, conversation happened | — |
| `no_answer` | Rang out, no contact made | — |
| `call_back` | They asked to be contacted later | Expects a follow-up date |
| `interested` | Positive, still deciding | — |
| `not_interested` | A clear no, for now | Suggests marking the lead lost |
| `wrong_number` | The number does not reach them | Flags bad contact data |

**Any longer list stops being used.** A desk with fifteen options picks the
first plausible one, and the data becomes noise that looks like signal. Six is
already at the limit; adding a seventh should require deleting one.

## 3. Outcome is optional, and never invented

An activity with no outcome stays valid, and nothing infers one.

A note is not a call and has no outcome. A historical row written before this
existed has none and must never be backfilled with a guess — inventing "answered"
for 111 existing rows would make every count that follows a lie.

Where an outcome is *expected* and missing (a `call` with no result), the UI may
prompt for it. It must not refuse the save.

## 4. Outcomes are facts, not automation

Logging `not_interested` **does not** mark the lead lost. Logging `call_back`
**does not** reschedule anything by itself.

This is the "record, don't automate" rule the rest of the product follows. The
staff member decides; the software offers. A system that silently closes leads
because somebody picked a dropdown value will be distrusted within a fortnight,
and rightly.

The UI may *suggest* the matching action — "mark this lead lost?" — as a
separate, declined-able step.

## 5. Filters exist because the queue is the product

The follow-up queue and the timeline both filter by `type` and `outcome`.

A queue you cannot narrow is a list you scroll. The specific, daily question is
"who have we not reached yet" — that is `outcome = no_answer`, and without a
filter it cannot be asked at all.

## 6. Counts are grouped and visible

The follow-up screen shows counts per outcome for a recent window.

"14 no answer, 3 call back, 2 not interested" tells an owner in one line
whether the phone work is landing. The same information spread across 19
timeline entries tells them nothing.

## 7. Only what a client may write

`outcome` is accepted only on the activity types a client may log
(`call`, `note`, `follow_up_set`, `trial_scheduled`) and is rejected on
server-written history (`stage_change`, `created`, `converted`, `lost`).

Pipeline history is the system's own record. A client able to attach an outcome
to a stage change could rewrite what the funnel analytics report.

---

## What this deliberately does not do

- **No auto-transition of lead status.** See §4.
- **No per-gym custom outcomes.** Six fixed values, so counts mean the same
  thing in every gym and analytics stay comparable. A gym wanting a seventh is
  a conversation, not a settings screen.
- **No backfill.** Existing rows keep a null outcome forever (§3).
- **No SLA or "must be contacted within N days" rules.** That is a target
  system, and the gym has no targets recorded.
- **No outcome on the counter prompt or retention alerts.** Those have their own
  action-note field; merging the vocabularies would mean one list serving two
  different jobs.
- **No WhatsApp/Instagram integration.** Logging that you messaged somebody is
  not the same as sending it, and this FR is only the record.

---

## Data

Migration `026`:

```sql
ALTER TABLE lead_activities ADD COLUMN outcome VARCHAR(30);
CREATE INDEX idx_lead_activities_outcome ON lead_activities (gym_id, outcome, created_at DESC)
  WHERE outcome IS NOT NULL;
```

Nullable, no default, no backfill. The partial index keeps it off the rows that
will never have one — the 102 `stage_change` rows in the demo set alone.

## Endpoints

```
POST  /api/v1/leads/{id}/activities        + optional "outcome"
GET   /api/v1/leads/{id}/activities        ?type=&outcome=
GET   /api/v1/leads/followups              ?outcome=   + outcome_counts in body
```

---

## Decisions that are yours

1. **The six values.** Taken from what a gym desk actually says on the phone,
   cross-checked against FitnessForce's vocabulary. The pilot gym should confirm
   them against a real day before this hardens.
2. **Whether `not_interested` should prompt to mark the lead lost.** Currently
   it suggests nothing; §4 allows a suggestion if you want one.
3. **Whether outcome should be required on `call`.** Currently optional — a
   staff member mid-shift should never be blocked by a dropdown.
