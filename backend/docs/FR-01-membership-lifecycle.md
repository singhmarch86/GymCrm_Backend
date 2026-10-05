# FR-01 — Membership Lifecycle

Freeze · Unfreeze · Upgrade · Transfer · Terminate

**Status:** proposed — rules below are our own, not FitnessForce's.
FitnessForce documents these as features but publishes no business rules, so
everything here is derived from Indian gym operating norms. Every numeric limit
is a policy decision and is intended to be argued with; each is called out as
`POLICY` so it can be changed without touching logic.

---

## 0. Shared rules

### 0.1 Member status machine

```
                 ┌──────────┐
     join ──────▶│  active  │
                 └────┬─────┘
        freeze ───────┤
                      ▼
                 ┌──────────┐   unfreeze / auto-thaw
                 │  frozen  │──────────────┐
                 └────┬─────┘              │
                      │                    ▼
                      │              ┌──────────┐
                      │   expiry ───▶│ expired  │
                      │              └────┬─────┘
                      │                   │ renew
                      │                   ▼
                      │              ┌──────────┐
                      └─────────────▶│terminated│  (terminal)
                                     └──────────┘
```

- `terminated` is terminal. Restoring a terminated member requires a **new**
  membership, not a status flip. This keeps the financial audit honest.
- Only `active` and `expired` members may be upgraded or transferred.
- Only `active` members may be frozen. Freezing an already-expired membership is
  meaningless — there is nothing left to preserve.

### 0.2 Money

All amounts are **paise** (`int64`), matching `renewals.amount_paid_in_paise`.
Never float. Daily rate is computed as:

```
daily_rate_paise = plan.price_in_paise / plan.duration_days     (integer division)
```

Integer division truncates in the member's favour on charges and against them on
refunds by at most 1 paise/day. Accepted — the alternative is fractional paise.

### 0.3 Audit

Every operation writes exactly one immutable `membership_events` row (transfer
writes two — see §4). Events are never updated or deleted. The member row holds
current state; the event table holds how it got there.

### 0.4 Effective dating

- Operations may be **backdated up to 7 days** (`POLICY`) to let staff record
  something that happened over a weekend.
- Operations may be **future-dated up to 30 days** (`POLICY`) for freeze only.
- Backdating beyond the limit requires a manual expiry correction — deliberately
  awkward, because it distorts revenue reporting.

---

## 1. Freeze

Pause a membership so its remaining validity is preserved.

### Rules

| Rule | Value | |
|---|---|---|
| Minimum duration | 7 days | `POLICY` |
| Maximum single freeze | 90 days | `POLICY` |
| Maximum per membership year | 90 days total | `POLICY` |
| Membership year | rolls from `join_date` anniversary | |
| Freeze fee | optional, default 0 | `POLICY` |

- **Expiry extends 1:1** with days actually frozen. A 30-day freeze pushes expiry
  out 30 days. This is the core promise of a freeze.
- Status becomes `frozen`. `frozen_from` and `frozen_until` are set on the member.
- A frozen member **cannot check in**. Attendance must reject with a clear reason.
- A frozen member **is excluded from retention alerts** — they are not at risk,
  they are on hold. (Requires a change in `internal/retention`.)
- Cannot freeze if: already frozen, terminated, expired, or the requested window
  would exceed the annual allowance.

### Early unfreeze

Members often return early. On unfreeze before `frozen_until`:

- `actual_days = unfreeze_date − frozen_from`
- Expiry extension is **recalculated to `actual_days`**, not the originally
  requested duration. The member does not keep days they did not use.
- The annual allowance is debited by `actual_days`, not the requested duration.

### Auto-thaw

A member whose `frozen_until` has passed is `active` again. This is computed on
read rather than by a scheduled job, so it is correct even if nothing is running:
any member with `status = frozen AND frozen_until < today` is treated as active
and lazily corrected on next write.

---

## 2. Upgrade

Move a member to a different plan mid-term.

### Rules

- **Expiry date does not change.** The member keeps their existing end date; only
  the plan and the price change. This is the least surprising behaviour and the
  easiest to explain at a front desk. (`POLICY` — the alternative, recalculating
  expiry from the new plan's duration, is available but not the default.)
- Proration is charged for the **remaining days only**:

```
remaining_days = expiry_date − effective_date        (0 if already expired)
delta_paise    = (new_daily_rate − old_daily_rate) × remaining_days
```

- `delta_paise > 0` → an amount is **due**. The upgrade records the amount but
  does **not** collect it; collection goes through the existing payments module.
- `delta_paise < 0` → this is a **downgrade**. Default behaviour is to record the
  credit on the event and **not** refund it (`POLICY`). Refunding mid-term
  downgrades invites abuse; gyms typically apply credit at next renewal.
- `delta_paise = 0` → allowed, recorded, no financial effect.
- Cannot upgrade a `frozen` member — unfreeze first. Freezing and reprising at
  once produces proration maths nobody can explain to a customer.

---

## 3. Transfer

Move remaining membership validity from one member to another.

### Rules

- Both members must exist in the **same gym**.
- Source must be `active` or `expired` with remaining days > 0.
- Target must **not** have an active membership. Merging two live memberships is
  ambiguous and is rejected rather than guessed at.
- Target receives: source's `membership_plan_id`, `expiry_date`, and
  `start_date` = transfer effective date.
- Source becomes `terminated` with `reason = transferred`.
- Transfer fee optional, default 0 (`POLICY`).
- Writes **two** events: `transfer_out` on the source, `transfer_in` on the
  target, each carrying `related_member_id` pointing at the other.

Transfers are the most abuse-prone operation in gym software — one membership
resold repeatedly. The paired-event design means the full chain is always
reconstructable.

---

## 4. Terminate

End a membership permanently.

### Rules

- Sets `status = terminated`, `expiry_date = effective_date`.
- **Terminal.** No un-terminate. Restoring means selling a new membership.
- Refund is **calculated and recorded but never auto-paid**:

```
refund_paise = remaining_days × daily_rate − termination_fee_paise
```

- Negative result clamps to 0.
- Termination fee default 0 (`POLICY`).
- A `reason` is **required** — free text, but must be non-empty. Terminations
  without reasons make churn analysis worthless.
- Terminating a `frozen` member is allowed; unused frozen days are forfeit and
  the refund is computed from the pre-freeze expiry.

---

## 5. What this deliberately does not do

- **No automatic collection or refund.** Every operation records money owed or
  owed-back; moving actual money stays in the payments module. Lifecycle
  operations must never be the thing that charges a card.
- **No notification sending.** Events are written; a later phase reads them and
  decides what to send.
- **No approval workflow.** Any authenticated staff member may perform any
  operation. Role-gating is a later concern once the RBAC model is exercised.

---

## 6. Open questions for you

1. **Freeze fee** — do your target gyms charge for freezing? Common in metro
   chains, rare in independents. Default is 0.
2. **Downgrade credit** — record-only (default) or refundable?
3. **Upgrade expiry** — keep existing end date (default) or recalculate from the
   new plan's duration?
4. **Annual freeze allowance** — 90 days is generous. Some chains allow 30.
