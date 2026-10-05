# FR-06 — Multi-location (branches)

Status: draft for implementation
Depends on: `gyms`, `users`, `auth`, `middleware`
Affects: every module (indirectly — see §1)

---

## 0. The decision that makes this cheap instead of expensive

A gym chain has several branches. The obvious modelling instinct is to add a
`branch_id` to every table — members, payments, classes, invoices, all of it —
and scope every query by it. That is the expensive path: it touches every query
in the system, every index, and every repository method, and any query missed
becomes a silent data leak between branches.

**We do not do that.** Instead:

> **A branch *is* a gym.** `gym_id` remains the one and only tenancy boundary.

Every existing table already carries `gym_id`, every repository already scopes
by it through `database.ScopedDB`, and the JWT already pins it. That machinery
is correct and battle-tested — a second parallel boundary would only give us two
things to keep in sync.

What is genuinely new is a level *above* the gym:

```
Organization  ("FitZone Group")
   ├── Gym / branch  ("FitZone Model Town")     ← gym_id: the tenancy boundary
   ├── Gym / branch  ("FitZone Sarabha Nagar")
   └── Gym / branch  ("FitZone Rajguru Nagar")
```

So the work is: an `organizations` table, a link from gyms to it, per-user access
to several branches, a way to switch between them, and consolidated reporting.
**No existing query changes.**

### 0.1 What this costs us

Honesty about the trade-off: because branches are separate tenants, data does
*not* implicitly flow between them. A member of the Model Town branch is not
automatically a member at Sarabha Nagar; plans are per-branch; a class booked at
one branch is invisible at another. For a chain that runs branches as separate
businesses (the norm in India — separate GSTINs are common) this is correct and
desirable. For a chain that wants one membership usable everywhere, it is not,
and that requires cross-branch member access as a deliberate later feature
(§5.2), not an accident of the schema.

---

## 1. Access model

```
users            — unchanged; a user still has a home gym_id
user_gym_access  — NEW: which branches a user may enter, and their role in each
organizations    — NEW: the chain a gym belongs to
gyms.organization_id — NEW: nullable link
```

Rules:

1. A user has **one home gym** (`users.gym_id`, unchanged) and **zero or more
   additional branch grants** in `user_gym_access`.
2. A grant carries its own **role**: someone can be a manager at one branch and
   ordinary staff at another. The role that applies is the role for the branch
   currently being acted in.
3. A user may only ever be granted access to branches **within their own
   organization**. Cross-organization access does not exist.
4. Every existing user is backfilled with a grant to their current gym at their
   current role, so behaviour is identical on day one.

### 1.1 The security rule

The JWT carries the *active* `gym_id`, exactly as it does today. What changes is
that a user can ask for a token for a **different** branch.

> The server must verify, on every switch, that the requesting user actually has
> a grant for the requested gym. A `gym_id` supplied by a client is a request,
> never a fact.

This is the single most security-sensitive rule in the module: get it wrong and
any authenticated user can read any gym's data by asking for a token for it.
Switching is therefore a **server-side endpoint that issues a new token**, never
a client-side change of a stored value.

Tokens stay short-lived and single-branch. There is deliberately no
"all branches" token: a token that grants everything is a token whose blast
radius is everything.

---

## 2. Consolidated reporting

An owner of a chain needs to see the whole chain, which is the one place we
legitimately read across branches.

- Implemented as **explicit org-scoped endpoints** (`/api/v1/org/...`) that
  aggregate over the gyms the user has grants for — never by relaxing
  `ScopedDB`.
- Available only to users with an **owner** role grant on at least one branch,
  and only across branches they hold a grant for. An owner of two branches in a
  five-branch chain sees two.
- Read-only. There is no cross-branch write. Every mutation still happens inside
  exactly one branch's tenancy.

---

## 3. What each branch owns independently

Because a branch is a tenant, each branch has its own: members, staff, plans,
payments, invoices **including its own gapless number series** (FR-04 §1 — this
falls out for free, and is correct: separate GSTINs need separate series),
classes, trainers, attendance, leads.

Shared across the organization: nothing, in v1. Not even plans. A chain that
wants a common plan catalogue can copy plans between branches (§5.1) — an
explicit action, rather than an ambiguous shared-vs-local rule that nobody can
predict.

---

## 4. Open questions for you

1. **Do your target chains run branches as one business or several?** Separate
   GSTINs and separate books (our model) vs one legal entity with locations. If
   the latter is common, consolidated *invoicing* becomes a requirement, not
   just consolidated reporting.
2. **Should a member be able to use any branch?** v1 says no — membership is per
   branch. Cross-branch check-in is a real feature (§5.2) but has revenue-sharing
   implications between branches that are a business decision, not a technical
   one.
3. **Who creates branches?** You as the vendor during onboarding, or a chain
   owner self-service? Self-service means a gym can inflate its own bill.

---

## 5. Deliberately out of v1

1. **No plan/catalogue sharing** across branches. Copying is a future
   convenience feature.
2. **No cross-branch membership or check-in.** See §4.2.
3. **No branch-to-branch transfers** of members or staff. The lifecycle transfer
   in FR-01 operates within one branch.
4. **No org-level user management UI.** Grants are set per user; a "manage all
   staff across the chain" screen comes later.
5. **No consolidated billing to the gym chain** (that's vendor billing, a
   separate concern from the gym's own invoicing).
