# FR-10 — First 90 Days: Activation

**This is the specification** — every rule, every number, and why. Written in
plain language, but complete: if you want to change how it behaves, argue with
this document.

---

## Why this exists

A gym loses more members in their first three months than in any other period.
Not because those members are unhappy — because they never actually started.
They paid in January, came twice, life got busy, and by March they've quietly
gone. Nobody called, because nothing in the software noticed.

GymCRM's existing alerts don't help here, and it's worth being precise about
why:

- **"Inactive 1 week"** fires the same way for a five-year regular and for
  somebody who joined nine days ago. They are not the same problem. The
  five-year regular is having a bad week. The new joiner is *leaving*, and the
  window to do anything about it is small.
- **Rhythm-break detection (FR-09)** is explicitly blind here. It needs about
  three months of check-ins before it can describe anyone. It says nothing at
  all about a member in their first 90 days — by design, and that is the gap
  this document fills.

Between them, these three features cover the whole member lifecycle:

| Feature | Watches | Question it asks |
|---|---|---|
| **FR-10 (this)** | First 90 days | Did they ever get started? |
| **FR-09** | Established members | Have they lost their routine? |
| **FR-01** | Everyone else | Have they stopped coming? |

---

## 1. Who is in the programme

Any member whose **join date** is within the last **90 days**, and whose
membership is still active.

**Join date, not membership start date.** These differ: when a member renews,
their start date moves forward to the new cycle. Somebody who joined two years
ago and renewed last week has a start date of last week — but they are not a
new member and must never appear here. The join date is the one that doesn't
move.

**Frozen members are skipped** while they're frozen. Somebody who froze their
membership for a medical reason hasn't failed to activate, and calling them
about it would be insulting. Their 90-day clock is *not* extended to compensate
— see §6 for why that's a deliberate simplification rather than an oversight.

Expired and terminated members are not in the programme either. They've already
gone; that's a different conversation.

---

## 2. The three things that go wrong

Each is a distinct problem with a distinct phone call. They are separate alerts
on purpose — telling staff "this new member needs attention" without saying
*which* of these it is would waste the call.

### Never started — `activation_no_first_visit`

**Fires when:** they joined **3 or more days ago** and have **never checked in**,
not once.

**Severity:** High. Always.

This is the highest-leverage call in the entire product. They have paid. They
have not walked in. Every day that passes makes the doorway harder to cross,
and there is no habit to repair yet — you're just getting them through the door
the first time.

Three days rather than one, because somebody who signs up on Saturday and
starts Monday is completely normal and should not be chased.

**Closes by itself when:** they check in. Nothing else needed.

### Not enough to stick — `activation_slow_start`

**Fires when:** they're **7 or more days** into the programme, have checked in
at least once, and are averaging **fewer than 1.5 visits a week** since joining.

**Severity:** Medium.

Coming once a fortnight never becomes a habit. It stays an effort, and efforts
stop. Roughly twice a week is the floor for something turning automatic; 1.5 is
set just below that so a member having one slow week isn't chased.

Not fired before day 7, because a rate calculated over three days is meaningless.

**Closes by itself when:** their rate climbs back above 1.5 a week.

### Started, then went quiet — `activation_going_quiet`

**Fires when:** they've checked in **at least 3 times**, and haven't checked in
for **10 days or more**.

**Severity:** High.

This one had it and lost it. For an established member a ten-day gap is a
holiday. For somebody eight weeks into their membership, it is usually the end
— they never built enough habit for the gym to pull them back on its own.

Ten days rather than seven, because a new member's pattern is naturally erratic
and a week off is common. Ten is where it stops being noise.

**Closes by itself when:** they check in.

---

## 3. Only one alert per member at a time

A member can hold **at most one** open activation alert.

The three problems are stages of the same story, and a member sliding from one
to the next must not accumulate rows. When a member's situation changes, the
scan closes the alert that no longer applies and raises the one that does.

Priority, when more than one could technically apply: **never started** beats
**went quiet** beats **slow start**. The more urgent problem wins the row.

---

## 4. The generic inactivity alerts stand down

While a member is in their first 90 days, the existing `inactive_1_week` and
`inactive_2_weeks` alerts **do not fire for them**.

Without this rule, a new member who stops coming gets listed two or three
times, the At Risk list fills with duplicates, and — worse — the generic alert
tells staff the wrong story. "Inactive 1 week" suggests a lapse from a routine.
A new member has no routine to lapse from. The activation alert says what's
actually happening and suggests a different conversation.

This is the same discipline FR-09 §3 applies: **one member, one problem, one
row, one call.**

---

## 5. The activation funnel

Alerts tell the front desk who to ring today. The funnel tells the **owner**
whether onboarding is working at all, which is the more valuable number and the
one no gym currently has.

For members who joined in a given month, what fraction:

1. checked in **at least once**
2. reached **4 visits within their first 14 days**
3. reached **12 visits within their first 30 days**
4. were **still checking in during days 60–90**

Shown per join-month, so the trend is visible. If January's cohort reached 12
visits at 60% and April's at 35%, something changed — new staff, a new
timetable, a broken induction process — and the owner can go and find out.

**No target is set for any of these.** A number GymCRM invented would be worse
than no number: the owner would manage to a figure that came from nowhere. The
comparison that matters is this gym against itself, month over month.

---

## 6. What this deliberately does not do

- **It does not extend the 90-day clock for frozen members.** A member who
  froze for six weeks arguably deserves those six weeks back. Handling that
  properly means tracking freeze periods per member and doing date arithmetic
  around them, and the payoff is a slightly different date for a small number
  of people. Skipping them while frozen gets almost all the benefit for almost
  none of the complexity. Worth revisiting if it turns out gyms freeze new
  members often — which I doubt, but I don't know.

- **It does not automate any outreach.** Same rule as everywhere else in
  GymCRM: it raises a flag for a human. *Record, don't automate.*

- **It does not score members out of 100 or predict a churn date.** The three
  states are things you can verify by looking at the member's check-in list. A
  score would imply a validation exercise nobody has done.

- **It does not judge onboarding quality.** It counts visits. Whether the
  induction was any good, whether the trainer was welcoming, whether the
  equipment was free — none of that is in the data, and the funnel should be
  read as "something is wrong here, go and look", not as a diagnosis.

- **It sets no benchmark against other gyms.** GymCRM has one gym's data. Any
  industry comparison would be invented.

- **It does not run automatically on a schedule yet.** It runs with the other
  scans, from the Run scan button.

---

## 7. What the software exposes

| Action | What it does |
|---|---|
| **Run scan** | Evaluates everyone in their first 90 days, raises the right alert, closes the ones that no longer apply. Reports how many are in the programme and how many are in each state. |
| **List activation alerts** | The open ones, with days since joining, visit count and last visit date. |
| **Activation funnel** | The cohort table from §5, by join month. |

Alerts are closed through the same "mark handled" action as every other alert,
with the same note and the same staff attribution. Everything is restricted to
the branch you're logged into.

---

## 8. Decisions that are yours, not mine

Every number below I chose by reasoning, not from your data. Each is a single
constant.

- **3 days before "never started" fires.** Shorter is more urgent but chases
  weekend sign-ups. Longer wastes the best days you have.

- **1.5 visits a week as the "will not stick" line.** This comes from the
  general idea that roughly twice a week is where a behaviour turns automatic.
  It is not derived from your members, because you don't have real ones yet.
  **Recalculate this from your first pilot gym's data** — compare the visit
  rate of members who renewed against those who didn't, and the honest number
  will be sitting right there.

- **10 days of silence before "went quiet".** Balanced against the generic
  7-day alert that this replaces. If gyms find it too slow, 7 works too.

- **90 days as the length of the programme.** Chosen so it hands over cleanly to
  rhythm-break detection, which needs about three months of history to say
  anything. The two are deliberately adjacent with no gap between them.

- **The funnel's four steps (1 visit, 4 in 14 days, 12 in 30 days, active at
  60–90).** These are reasonable-sounding milestones, and that is all they are
  until a real gym's renewal data tells us which ones actually predict a
  renewal.
