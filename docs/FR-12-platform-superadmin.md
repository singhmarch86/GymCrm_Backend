# FR-12 — Platform Superadmin (Vendor Console)

**This is the specification** — every rule and why. Plain language, but
complete. Nothing here is built yet.

Read §3 and §6 before anything else. This feature deliberately punches a hole
through the one boundary that keeps every customer's data separate, and the
rules around that hole are the whole point of the document.

---

## Why this exists

GymCRM is sold to gyms. Today there is no way for **the vendor** — you — to see
that you have twelve customers, add a thirteenth, or stop serving one who has
not paid. Every account in the system belongs to exactly one gym, and every
query is scoped to it.

For one pilot gym that is fine: a gym is created with a SQL insert. Around the
third or fourth customer it stops being fine, and doing it by hand starts being
the thing that breaks.

## The distinction that matters

GymCRM already has **organizations** — a gym chain with several branches
(FR-06). That is a *customer* who owns more than one location. Their owner can
already switch between their own branches.

This document is about something different: **the vendor**, who is not a
customer at all, and who can see across customers that have nothing to do with
each other.

Confusing the two would be a serious mistake. A chain owner must never gain
vendor powers by virtue of having several branches.

---

## 1. A platform admin is not a user

Platform admins live in their own table, `platform_admins`. They are **not**
rows in `users`.

Two reasons, and the first is the important one:

1. **`users.gym_id` is NOT NULL.** Every user belongs to a gym. Making a
   platform admin a user would mean either putting them in some arbitrary gym
   or making that column nullable — and a nullable tenancy column is the kind
   of thing that later gets forgotten in a `WHERE` clause.

2. **A third value in the `role` CHECK would be one UPDATE away.** Today roles
   are `owner` and `staff`. If `superadmin` were simply a third option, then
   any bug, any careless admin query, or anyone who compromises a gym owner's
   account and can write to `users` is one column change from reading every
   customer's data. A separate table makes escalation require a separate,
   auditable act.

## 2. Vendor rights belong to platform admins and nobody else

The vendor capabilities — listing all gyms, creating one, suspending one,
seeing platform-wide usage — are available **only** to a platform admin.

No gym owner has them, at any tier, in any plan, ever. There is no "premium
owner" who can see other gyms. A chain owner sees their own branches and
nothing else.

This is not a permissions preference; it is the product's core promise. A gym
handing over its member list is trusting that no other gym can see it.

## 3. Platform tokens cannot reach gym endpoints

A platform admin logs in at a **separate endpoint** and receives a token of a
**different kind**. That token is accepted only on `/api/v1/platform/*` routes.

This is the single most important rule in the document.

Every existing handler in GymCRM trusts `gym_id` from the JWT and scopes its
query to it. That is safe precisely because a token always names exactly one
gym. If a platform token could be presented to `/api/v1/members`, then whatever
`gym_id` it happened to carry would be silently trusted by a hundred handlers
that were never written with a cross-tenant caller in mind.

So platform tokens carry no `gym_id` at all, and the gym middleware rejects
them outright. **The two token types never meet.**

## 4. Seeing a customer's data requires impersonation, on the record

There are two ways a platform admin can learn anything, and they are different
on purpose.

### Aggregates — always available, never personal

The console shows counts and health, across all gyms: how many members, when
the gym was last used, whether scans are being run, subscription status.

**No member names, phone numbers, email addresses or payment records appear in
any aggregate view.** A vendor does not need a customer's member list to know
that customer is healthy, and "I could see it" is the answer nobody wants to
give when a gym asks.

### Support access — explicit, time-limited, logged, visible

To actually look at a gym's screens — because the owner has reported a bug —
the platform admin **enters** that gym. That mints an ordinary gym token,
scoped to that one gym, and:

| Rule | Value | Why |
|---|---|---|
| A reason must be given | free text, required | An access with no stated reason is one nobody can review later |
| The token is short-lived | **30 minutes** | Support work is minutes; a day-long token is a standing key |
| It names one gym | single `gym_id` | No token ever spans customers |
| It is read-only | no writes | See §5 |
| It is logged | permanently | See §7 |
| **The gym owner can see it** | in their own app | See §6 |

Entering a gym is a deliberate, recorded act. It is not a side effect of
browsing the console.

## 5. The vendor does not edit customer data

Support access is **read-only**. A platform admin can look at a gym's members,
payments and reports; they cannot change them.

If a customer needs data changed, they change it, or they ask and you talk them
through it. The moment the vendor can silently edit a gym's payment records,
every dispute about those records becomes unanswerable — including in your
favour. Read-only protects you as much as them.

The narrow exceptions are vendor-level fields that are not the gym's data at
all: subscription status, plan, and suspension (§8).

## 6. The customer can see when you looked

Every support access is visible to the gym owner, in their own app, listing
which vendor admin entered, when, for how long, and the reason given.

**Silent impersonation is how software vendors lose customer trust
permanently** — not when they use it, but when a customer finds out later that
it existed and was invisible. Building the visibility in from the start costs
almost nothing. Retrofitting it after a customer asks "can you see my data?" is
a much worse conversation.

This is also the honest answer to that question: *"Yes, with your data I can
enter your account for support — and you can see every time anyone did."*

## 7. Everything cross-tenant is logged, permanently

`platform_access_log` records every support access: which admin, which gym,
when it started, the reason, and when the token expired.

The log is **insert-only**. No endpoint deletes or edits it, including for
platform admins. A log the accused can edit is not a log.

Aggregate console views are not logged individually — they contain no personal
data (§4), and logging every page view would bury the accesses that matter.

## 8. Suspending a customer

A gym has a status. `gyms.status` already exists and is the right place.

Suspending a gym for non-payment means **its users cannot log in**, and they
are told plainly why, with a way to contact you. It does **not** mean:

- deleting anything
- hiding their data from them permanently
- stopping backups

A gym that pays after a lapse is un-suspended and everything is exactly where
they left it. **Never destroy a customer's data over an invoice.** Beyond
being wrong, a gym's member list is often the only copy that exists.

Suspension is reversible, logged, and requires a reason.

## 9. Creating the first platform admin

There is a bootstrap problem: only a platform admin can create a platform
admin, and at the start there are none.

The first one is created by a **command run on the server**, with database
access — never by an HTTP endpoint. A public "create the first superadmin"
route is a permanent backdoor the moment anyone gets the timing or the
condition wrong.

After that, existing platform admins create others, and every creation is
logged.

The bootstrapped account is not usable until it has enrolled in two-factor
(§10), and you should create a **second** platform admin immediately — §10
explains why one is a way to lock yourself out permanently.

## 10. Two-factor authentication is required

Every platform admin logs in with a password **and** a six-digit TOTP code from
an authenticator app. This is a rule, not a setting.

**TOTP** — Time-based One-Time Password — is the six-digit number that changes
every 30 seconds in Google Authenticator, Microsoft Authenticator or Authy. It
is the same thing your bank or GitHub asks for.

It works by sharing one secret between the server and the phone at setup time.
After that both sides independently compute a code from that secret plus the
current time, and they match. **Nothing is sent to the phone** — no SMS, no
network, no cost, and it works on a plane. That is also why it beats SMS codes,
which can be intercepted by someone convincing a mobile operator to move a
number to a new SIM.

The practical effect: stealing the password is no longer enough. Someone would
need the password *and* the physical phone.

This is the account that can reach every customer's data. A password alone is
the wrong protection for it — passwords get reused, phished, and typed into the
wrong window, and the blast radius here is not one gym, it is all of them.

### It cannot be turned off

There is no per-account toggle. An optional second factor means the least
careful admin decides the security of the whole platform, and "I'll enable it
later" is a state that persists.

### A new admin cannot do anything until they have enrolled

Creating a platform admin creates an account that can do exactly one thing: log
in and complete enrolment. Until a TOTP secret is confirmed, every other
platform endpoint refuses it.

Otherwise there is a window — sometimes days — where a fully-powered account is
protected by a password that was very likely sent over WhatsApp.

**This includes the bootstrap admin from §9.** The command creates the account;
the first login forces enrolment. There is no exception for the first one,
because "just this one, temporarily" is how permanent exceptions are born.

### Enrolment

1. The server generates a secret and shows it once, as a QR code and as text.
2. The admin must enter a valid code from their app to confirm it. An
   unconfirmed secret is never activated — this catches the case where the QR
   was scanned into the wrong app, or not at all.
3. Ten single-use **recovery codes** are shown once and stored hashed, the same
   way a password is. They are never displayed again.

### Losing the phone

Recovery codes are the intended path: one code, used once, gets you in.

If both the phone and the codes are gone, another platform admin resets the
account. That reset is logged like any other cross-tenant act (§7).

**Therefore: always have at least two platform admins.** With one, a lost phone
and a lost recovery sheet means nobody can ever reach the vendor console again
— not you, not anyone — and the only remaining route is editing the database on
the server by hand. This is a real way to lock yourself out of your own
business, and the fix costs nothing: create the second admin on day one.

### Details that are easy to get wrong

| Rule | Value | Why |
|---|---|---|
| Clock drift tolerance | ±1 step (±30s) | Phones drift. Any wider and you are meaningfully extending each code's life. |
| A code cannot be reused | last accepted step is stored | Without this, a code shoulder-surfed or captured from a screen share stays valid for its whole window. This is the detail most implementations miss. |
| Failed attempts | lock the account after 5, for 15 minutes | Six digits is 1,000,000 combinations — trivial to brute force at machine speed if nothing stops it. |
| Recovery codes | single use, hashed at rest | A reusable recovery code is a second password. A plaintext one is worse. |
| Platform session | **2 hours** | Shorter than a gym session on purpose. TOTP at login is worth little if the session then lasts all day on an unlocked laptop. |

TOTP is checked **at login only**, not per request. The short session is what
limits exposure after that.

---

## 11. What this deliberately does not do

- **No billing.** The console records which plan a gym is on and whether it is
  paid, because suspension needs to know. It does not take payments, issue
  invoices to gyms, or integrate a payment gateway. That is a real system and
  deserves its own document.

- **No cross-customer analytics.** "Gyms like yours retain 62%" would require
  mining every customer's data for the benefit of other customers. Even
  aggregated, it is not something to do without asking them, and it is not
  worth the trust cost early.

- **No writing into gym data** (§5), beyond the vendor-level fields in §8.

- **No shared vendor accounts.** One platform admin per human. A shared login
  makes the audit log useless, which makes §6 and §7 theatre.

- **No permanent deletion of a gym.** Suspend, always. If a customer genuinely
  wants their data destroyed, that is a deliberate operation done by hand with
  a backup taken first.

- **It does not replace organizations.** Chains keep working exactly as they do
  now (FR-06). Nothing about this document changes what a customer sees.

---

## 12. What the software exposes

All under `/api/v1/platform/*`, all requiring a platform token.

| Action | What it does |
|---|---|
| Log in | Separate endpoint, separate token type. Rejected by every gym route. |
| List gyms | All customers: name, city, status, member count, last activity. No member details. |
| Gym summary | One customer's health — counts, subscription, last scan. Still no personal data. |
| Create gym | Adds a customer and its first owner account. |
| Suspend / resume | Requires a reason. Logged. Never deletes. |
| Enter gym | Mints a 30-minute read-only token for one gym. Requires a reason. Logged. Visible to the owner. |
| Access history | The audit log, filterable by gym or admin. Read-only for everyone. |

And one gym-side addition:

| Action | What it does |
|---|---|
| Support access history | Lets a gym owner see every time the vendor entered their account (§6). |

---

## 13. Decisions that are yours, not mine

- **Should entering a gym require the code again?** §10 checks TOTP at login
  only, and relies on a 2-hour session to limit what a walked-away laptop is
  worth. Asking again at the moment of crossing into a customer's data is
  stronger and is what banks do for transfers. It is also the most annoying
  possible place to put it, during support work, when you are already
  irritated. I have left it out; it is a fair thing to add later if the
  console is ever used from shared machines.

- **How long should the platform session last?** Two hours is my number, not a
  derived one. Shorter is safer and more irritating.

- **30 minutes for a support token.** Long enough to investigate, short enough
  that a forgotten browser tab is not a standing key. Raise it and you weaken
  §4; lower it and support gets annoying.

- **Should the gym owner be *notified* of support access, or only able to look
  it up?** The spec requires visibility, not notification. A notification is
  stronger and more honest; it is also noisier and may alarm customers during
  routine work. My instinct is: visible always, notified for anything outside
  a support ticket they raised.

- **Should read-only support access ever have a write escape hatch?** I have
  said no. There will come a day when a customer begs you to fix one row and
  the honest answer is a SQL statement on the server, taken with a backup and
  written down. That friction is a feature.

- **Restricting the console by IP.** Cheap, and meaningful if you always work
  from a known network. Annoying the first time you need it from a phone.
