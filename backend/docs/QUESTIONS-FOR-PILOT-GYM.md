# Questions for the pilot gym

Open questions the product cannot answer for itself. Each one is a taxonomy or
threshold decision where guessing produces a number that looks authoritative
and means nothing.

Keep the questions about **what they do**, not about what the software should
show. A gym owner asked "should stage moves count?" will try to be helpful and
guess. Asked "walk me through what happens after a call" they will describe
their actual day, which is the answer.

---

## 1. Does moving a lead's stage count as work? (FR-18 §9)

**The concrete problem.** Staff work shows two numbers for the same person over
the same month that do not agree. On the development database, August reads 16
against 5. The missing rows are `stage_change` (a lead moved from one column to
another) and `created` — the system writes those itself when somebody drags a
card.

Both numbers are correct. They answer different questions. Right now the screen
says which is which, but one of them is probably not worth showing.

> **Do not show them the development numbers.** 88 of the 102 stage moves in
> the local database have no user against them at all, which means they were
> seeded rather than performed by a person. The remaining 14 are the developer
> login. Those figures describe the seed script, not a gym, and putting them in
> front of an owner as "your data" would invite them to explain behaviour that
> never happened.
>
> The design question below stands on its own and does not need the numbers.
> Ask it about their working day. If they are already running on real data,
> pull the figures fresh on the day and read them off their own screen.

**Do not ask "should stage changes count as lead work?"** Ask:

1. *"Show me what you do after you speak to a lead."* Watch whether they log
   the call, or just move the card, or both. If moving the card **is** how they
   record the call, then a stage move is the work and the funnel is undercounting
   most of what happens.
2. *"Who moves cards on the board, and when?"* If a manager tidies the board at
   the end of the week, those moves are admin, not lead work, and counting them
   would credit the wrong person on the wrong day.
3. *"If I told you Simran moved 40 cards last month, would that tell you
   anything about how she did?"* If the answer is a shrug, stop counting it.

**What each answer changes**

- *Moving the card is how they record contact* → add a stage-moves count to the
  funnel, and reconsider whether calls need logging separately at all.
- *Cards get moved in batches, after the fact* → leave the funnel as it is, and
  drop "Lead activity" from the Money & work tally, because it is inflating a
  person's day with bookkeeping.
- *Both happen, by different people* → keep both numbers, and label them
  "contacted" vs "board updates" so nobody adds them together.

---

## 2. What does "counselling" mean here? (FR-18, carried over)

A scheduled sit-down, or any in-person conversation?

This decides whether it gets logged weekly or six times a day, and therefore
whether the count means anything at all. Ask them to describe the last one they
did, start to finish, and see whether it is an appointment or a chat.

---

## 3. Should "unattended" be this loud? (FR-18)

A lead is unattended when it has no next step, no date, or no owner. The screen
puts the count in red at the top.

On real data this will be the first honest picture the gym gets of its own
pipeline, and it may be the most useful thing the system ever tells them. But
if a gym runs at 40% unattended as a matter of course, a permanent red number
becomes wallpaper and stops being read.

Ask what they would consider normal *before* showing them their figure —
otherwise the number anchors the answer. Then show it.

Do not soften it because it looks alarming. It is supposed to look alarming the
first time.

(The development database currently reads 34 of 35, but the leads there are
seeded and never had a next step set, so that ratio is an artefact of the seed
script and means nothing.)

---

## 4. The default next-step due dates (FR-18 §2)

These were invented from how gym sales usually run, not from watching this gym.
They should be corrected or confirmed:

| After | Next step | Due |
|---|---|---|
| First contact | Call back | +2 days |
| Call back, interested | Book trial | +3 days |
| Trial booked | Confirm trial | day before |
| Trial done | Counselling | +1 day |
| Counselling | Close | +2 days |

Ask what they actually do. "How long before you chase somebody who said they
were interested?" gets a real number; showing them this table gets agreement.

---

## 5. Follow-up categories (parked since FR-16)

Deliberately not invented. FitnessForce has a list; copying it would be
copying somebody else's gym.

Ask what reasons they write down when a follow-up does not land, and use their
words.

---

## Notes for whoever runs this

- Record the answers verbatim before interpreting them. The phrasing is the
  data — "we ring them back" and "we follow up" are different processes.
- Where an answer contradicts something already built, that is a finding, not a
  problem. Write it down rather than arguing the software's case.
- Nothing here needs deciding on the spot. A wrong answer given to be helpful
  is worse than no answer.
