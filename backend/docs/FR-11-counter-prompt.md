# FR-11 — The Counter Prompt

**This is the specification** — every rule and why. Plain language, but
complete.

---

## Why this exists

GymCRM now knows a great deal about who needs attention: renewals due, members
who went quiet, members whose routine broke, new members who never started. All
of it lives on the At Risk screen — **a screen somebody has to remember to
open.**

Meanwhile the member physically walks past the front desk. That is the highest-
contact moment in the entire business, it happens hundreds of times a week, and
right now nothing happens at it.

The counter prompt puts one line of context on the screen at the moment the
member is standing there. It turns retention from a task somebody schedules
into something that happens while they're already talking.

This is not a new signal. **It is a new place to show the signals that already
exist**, at the only moment when acting on them costs nobody any extra effort.

---

## 1. One prompt. Never a list.

At most **one** prompt per check-in.

The desk has about five seconds while the member is at the counter. Three
prompts means they read none of them, and a list is something to scroll past
rather than say out loud. Whatever is most worth saying wins; everything else
waits.

## 2. Silence is the normal answer

Most check-ins produce **no prompt at all**, and that is the point.

If something appears every time, staff stop reading it within a week and the
feature is dead. A prompt appearing is meant to be unusual enough that it gets
read. Any change that makes prompts more frequent should be treated as making
the feature worse, not richer.

## 3. The prompts, in priority order

The first one that applies wins.

### 1. First ever visit — `first_visit`

Their very first check-in, ever.

> *"First visit. Make sure someone shows them round and books their next
> session."*

The single most important moment in a member's life at the gym, and the one
nobody currently marks. Everything FR-10 tries to fix downstream starts here.

### 2. Back after a long gap — `welcome_back`

They're checking in after **10 or more days** away.

> *"First time back in 24 days. Say welcome back — don't ask where they've
> been."*

**This deliberately outranks their own "went quiet" alert.** That alert says
*chase this person* — but they're standing at the counter, so chasing is over
and the script is completely different. Getting this wrong would have staff
interrogating somebody who just did the hard thing and came back.

### 3. An open alert — `alert`

Any unresolved alert for this member: expiring membership, broken routine,
never started, and so on. The alert's own message is used, so the wording stays
consistent with the At Risk screen.

Highest severity first. **Inactivity alerts are excluded** — rule 2 already
covers that member better.

### 4. Personal training nearly used up — `pt_low`

**2 or fewer sessions** left on an active package.

> *"2 PT sessions left with Rahul. Good moment to ask about the next block."*

An honest upsell at the only moment the member is thinking about training.

### 5. Time to restock — `restock`

They have bought the same consumable **at least twice**, and enough days have
passed since the last one that they are probably running out.

> *"Last bought Whey Protein 1kg 31 days ago — they buy about every 30."*

If they run out, they buy it elsewhere and often don't come back to your
counter. Estimated from their **own** purchase interval, not a fixed guess:
somebody who buys monthly and somebody who buys fortnightly get different
timing.

Needs at least two purchases of the same product — one purchase tells you
nothing about an interval.

### 6. Wallet running low — `wallet_low`

They pay from their wallet and the balance has dropped below **₹200**.

> *"Wallet balance ₹150. Top up?"*

Only for members who actually use the wallet — a zero balance on somebody who
has never used it is not news.

### 7. Nothing

By far the most common outcome. Say nothing.

---

## 4. Never the same prompt twice in a week

The same **kind** of prompt is not shown for the same member more than once
every **7 days**.

Without this, somebody who trains daily gets told about their protein tub six
days running, which is how staff learn to ignore the panel. The cooldown is per
member *and* per kind, so a genuinely new situation still gets through.

The cooldown applies to **every** kind, including `first_visit` and
`welcome_back`. A 10-day absence looks like a natural limit on its own, but it
is not: a staff member who taps check-in twice would log the moment twice,
which quietly corrupts the only measurement that can ever say whether these
prompts work.

---

## 5. It records what it showed

Every prompt shown is written down: which member, which kind, when, and which
staff member was at the desk.

Two reasons, and the second matters more:

1. It's what makes the cooldown in §4 possible.
2. It's the only way to ever answer **"does this work?"** — do members who got a
   restock prompt buy more, do members who got a welcome-back prompt stay
   longer. Nobody can answer that today, and without the log nobody ever could.

Staff can optionally mark a prompt as **acted on**. Optional on purpose:
mandatory logging at a busy counter gets clicked through meaninglessly, which
is worse than no data because it looks like data.

---

## 6. What this deliberately does not do

- **It shows nothing that embarrasses the member.** Outstanding dues are
  deliberately **not** a counter prompt. There are usually other people within
  earshot, and "you owe us ₹1,500" said out loud is how a gym loses a member
  permanently. Money conversations belong somewhere private. This is a
  judgement about dignity, not a technical limitation.

- **It doesn't tell the member anything.** It's a note to the staff member. It
  is never shown on a member-facing screen, and its wording assumes a human
  will decide whether to say it at all.

- **It doesn't automate the conversation.** No pre-written speech, no script to
  read out. One line of context; the human does the rest.

- **It doesn't score or rank members.** The priority order is a fixed list of
  rules in this document, not a model. Any staff member can be told why a
  prompt appeared.

- **It doesn't create new signals.** Everything shown comes from an existing
  alert, purchase history, PT package or wallet balance. If the At Risk screen
  doesn't know it, neither does the counter.

---

## 7. What the software exposes

| Action | What it does |
|---|---|
| **Check in** | The existing check-in response now also carries the prompt, if there is one. One call, no extra round trip at a busy desk. |
| **Look up a prompt** | The same prompt for a member without checking them in — for when staff pull a member up on screen. Does not count as "shown". |
| **Mark acted** | Records that the staff member did something about it. Optional. |

Everything is scoped to the branch you're logged into.

---

## 8. Decisions that are yours, not mine

- **10 days for "back after a gap".** Matches the FR-10 going-quiet threshold on
  purpose, so the two never disagree about the same member.
- **2 or fewer PT sessions.** Enough warning to sell the next block without
  nagging from session five.
- **₹200 wallet floor.** A guess. Should be roughly one counter purchase.
- **7-day cooldown.** The single most important number here. If staff start
  ignoring the panel, this is the first thing to raise.
- **Should dues ever appear?** I've said no on dignity grounds. A gym owner may
  disagree, and it is their business. If it's ever added it should be worded as
  a private prompt — "check their account with them" — never an amount.
