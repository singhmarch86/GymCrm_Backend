# Rhythm-Break Detection — explained in plain English

A companion to [FR-09](FR-09-rhythm-break-detection.md). That document is the
specification: thresholds, rules, edge cases. **This one is just the idea.**

Read this first. Read FR-09 only when you need to know exactly why a number is
what it is.

---

## The idea in one paragraph

Every gym system on the market asks: **"has this member stopped coming?"** That
question is always late — by the time someone has missed two weeks, they have
already mentally quit.

GymCRM now also asks: **"is this member still coming at their usual time?"**
That question is early, because people quit their *routine* weeks before they
quit the *gym*.

---

## Why the routine breaks first

Think about someone who trains at 7am every weekday. They don't decide each
morning to go. It's just what happens between waking up and work — like
brushing their teeth.

Now their job changes to shifts. The 7am slot is gone. But they haven't quit —
they still want to train. So they start going **whenever they can fit it in**:
6am Monday, 9pm Tuesday, Saturday afternoon.

Count their visits: **still 5 a week. Nothing looks wrong.**

But the thing that was holding them — a habit that ran on autopilot — is gone.
Now every single gym visit requires a *decision*. And decisions lose,
eventually. Three months later they cancel.

**That gap between "routine broke" and "stopped coming" is the window to act.**
Nobody else's software looks at it, because everyone counts visits.

---

## What the screen is telling you

A real example from the demo data — Anika Arora:

**Before** — the 8 weeks running from 12 weeks ago to 4 weeks ago:

> She came **56 times**. **All 56** were around 7:31am.
> She was a 7am person. That was her routine.

**Now** — the last 4 weeks:

> She came **28 times**. Only **4** were around 7:31am.
> The other 24 were scattered all over the day.

**Her visit count did not drop.** Seven times a week before, seven times a week
now. The dashboard is happy. The inactivity alerts say nothing. She looks like
one of the gym's best members.

But something changed in her life about a month ago, and the habit that kept
her here is gone. **That is what the card is flagging.**

---

## The two windows, precisely

| Label on the card | What it means |
|---|---|
| **Before** | The 8 weeks running from 12 weeks ago to 4 weeks ago |
| **Now** | The last 4 weeks |

They never overlap, so no visit is ever counted in both.

"Before" is deliberately not "everything up to now" — if it were, the recent
drift would be mixed into the very baseline it is being compared against, and
the signal would quietly cancel itself out.

---

## The numbers on the card

**"Kept their 7:31am slot — Before 100% (56/56), Now 14% (4/28)"**

The percentage is: *of the visits they made in that window, how many landed
within an hour and a half of their usual time.* So 4/28 means only 4 of their
last 28 visits were anywhere near 7:31am.

**"They are coming just as often — 7.0 visits a week now, against 7.0 a week
before"**

This is visit *frequency*, and it is the whole point. It is staying flat while
the slot collapses. A count-based system sees this number and says "fine".

**The day strip (`.MTWTF.`)**

Which days of the week they used, Sunday first. Context only — a change here
never triggers the alert by itself, because weekday patterns are far noisier
(one holiday, one travel week) than time-of-day.

**Severity colour**

How big the drop was. Red means the routine is essentially gone; amber means it
is going.

---

## So what do you actually do about it?

Call them. Not "we miss you" — they haven't gone anywhere. Something like:

> *"Hi Anika, noticed you're not making your usual morning sessions —
> everything alright? Has your schedule shifted?"*

Then help them build a **new** routine: book them into a fixed evening class,
put them with a trainer at a set time, whatever fits their new life. You are
not chasing a lapsed member. You are re-anchoring a current one before they
drift.

That is a two-minute conversation a normal CRM would never have prompted.

---

## The one rule that makes it worth having

If a member's **visits have already collapsed**, this feature stays quiet. The
existing "Inactive 1 week / 2 weeks" alerts already own that person, and
flagging them twice would just clutter the list.

It only speaks up about members whose **numbers still look fine**.

In the demo data, of 22 flagged members, **14 are coming exactly as often as
before**. Those 14 are invisible to every other retention tool on the market,
FitnessForce included.

---

## Who never gets flagged

- **Free-floaters.** Members who always came at random times have no routine to
  break. About a quarter of any gym. They are never flagged, ever.
- **New members.** It takes roughly three months of check-ins before there is
  enough history to say anything. Brand-new members are a separate churn
  problem, and this feature does not pretend to solve it.
- **Anyone who barely comes.** Fewer than about 12 visits in the baseline is too
  sparse for "their usual time" to mean anything.

---

## What it is not

It is **not** AI in the sense of a trained model. It is arithmetic on the
check-in timestamps that were already being stored: an average time, and two
fractions. That is deliberate —

- it works correctly on 150 members, today, with no training period;
- it can explain itself to the staff member making the call, which a model
  score cannot;
- there is no invented "risk score out of 100" implying a validation exercise
  that never happened.

It also **does not send anything**. No automatic SMS or WhatsApp. It raises a
flag for a human, exactly like every other alert in GymCRM.

---

## Where to find it

App → **At Risk** → **Run scan** → the "Routine has broken" section at the top
of the list.

Resolving works exactly like any other alert: tick it off, add a note about what
you did, and it is recorded against your name.
