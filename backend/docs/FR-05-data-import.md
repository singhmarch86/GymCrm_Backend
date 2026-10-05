# FR-05 — Data Import

Status: draft for implementation
Depends on: `members`, `plans`, `payments`
Related: FR-04 (invoicing — imported payment history is money, not documents)

---

## 0. Why this exists

A gym switching from FitnessForce arrives with **years of data**: hundreds of members,
their plans, their expiry dates, their payment history. Without a way to bring that in,
feature parity is irrelevant — they physically cannot move. The parity spec calls this a
sales blocker rather than a feature, and that framing is correct.

The entire design follows from one observation: **the person doing the import is scared.**
They are moving their business's records into unfamiliar software, from a spreadsheet
they half-trust, and they cannot tell in advance what will go wrong. So the module's
first job is not importing — it's *showing them what would happen*, before anything
changes.

---

## 1. The two-phase rule

Nothing is ever written from a file in one step.

```
upload ──> validate ──> preview ──> commit
                 │
                 └──> discard (nothing written, ever)
```

1. **Upload + validate.** The file is parsed and every row checked. Nothing is written to
   the real tables. The batch and its parsed rows are stored separately so the preview
   survives a page refresh.
2. **Preview.** The user sees exactly what will happen: how many rows will be created,
   how many are duplicates, how many are broken and why — row by row, with the line
   number from their file.
3. **Commit.** Only then are records written, and only the rows that passed.
4. **Discard.** A batch can be thrown away at any point before commit, leaving no trace
   in the real data.

A committed batch is never re-committed. The batch record is kept as an audit trail of
what was imported, when, by whom, and from which file.

---

## 2. What can be imported

v1 covers the three entities that block a switch, in dependency order:

| Entity | Why it's needed | Depends on |
|---|---|---|
| **Plans** | Members reference them | — |
| **Members** | The core record | plans (by name) |
| **Payments** | Revenue history, dues | members (by phone) |

Attendance history, leads and classes are deliberately out of v1 — a gym can start fresh
on those without losing anything that matters commercially.

### 2.1 Column mapping

Nobody's spreadsheet matches our field names. The importer accepts a set of **aliases**
per field, matched case-insensitively and ignoring spaces/underscores, so
`First Name`, `first_name` and `FIRSTNAME` all land on the same field.

Members: `first_name` (also *first, fname, given name*), `last_name` (*last, surname,
lname*), `phone` (*mobile, contact, phone number*), `email`, `gender`, `date_of_birth`
(*dob, birthdate*), `address`, `plan` (*plan name, membership*), `start_date`
(*join date, joining date*), `expiry_date` (*end date, valid till, expires*), `status`,
`notes`.

Unrecognised columns are **ignored, not rejected** — a real export has a dozen columns
we don't care about, and failing the whole file over them would be hostile.

### 2.2 Dates

Indian exports are overwhelmingly `DD/MM/YYYY`, but `YYYY-MM-DD` and `DD-MM-YYYY` all
appear in practice. The parser accepts all three. It does **not** accept ambiguous
US-style `MM/DD/YYYY`: `03/04/2026` cannot be disambiguated from `DD/MM/YYYY`, and
silently guessing wrong shifts a member's expiry by months. Where a date is ambiguous the
row is flagged rather than guessed.

**POLICY** — default date interpretation is day-first. See open question 6.1.

### 2.3 Money

Accepted as rupees (`1200`, `1,200`, `₹1,200.00`, `1200.50`) and converted to paise on
the way in. Never stored as float. A value that cannot be parsed to a non-negative amount
fails its row.

---

## 3. Row outcomes

Every row lands in exactly one state, and the preview shows the counts:

| State | Meaning | On commit |
|---|---|---|
| `valid` | Parsed cleanly, no conflict | Created |
| `duplicate` | A record with this identity already exists | Depends on the duplicate policy (§4) |
| `invalid` | Failed validation | Skipped, with a reason |

`invalid` rows always carry a human-readable reason *and* the source line number, because
"row 47: phone number is missing" is actionable and "import failed" is not.

---

## 4. Duplicates

Identity is:

- **Member** → phone number, within the gym
- **Plan** → name (case-insensitive), within the gym
- **Payment** → no natural key; duplicates are not detected in v1 (see §7)

When a member's phone already exists, the user picks the policy **for the whole batch**,
at commit time:

- `skip` (default) — leave the existing record untouched, count it as skipped
- `update` — overwrite the existing record's fields from the file

There is no per-row choice in v1. A gym importing 800 members will not make 800
decisions, and a batch-level answer is the honest reflection of how the decision is
actually made.

`update` deliberately does **not** touch `status` or `expiry_date` unless those columns
are present in the file — a partial spreadsheet must not silently expire a live member.

---

## 5. Safety properties

These are the guarantees the module must hold, not implementation details:

1. **A validation pass never writes to real tables.** Ever.
2. **A commit is transactional per row**, not per batch: one bad row cannot roll back 700
   good ones, and a crash mid-commit leaves committed rows committed and the rest still
   pending, not a half-written mess.
3. **The original file content is retained** with the batch, so a disputed import can be
   re-examined against what was actually uploaded.
4. **Import never deletes.** There is no "replace all" mode. The only writes are inserts
   and — under an explicit `update` policy — field updates.
5. **Tenant isolation holds throughout**: a batch belongs to a gym, and every row it
   creates is scoped to that gym.

---

## 6. Open questions for you

1. **Date format.** Default is day-first (`03/04/2026` = 3 April). Confirm — this is the
   single most damaging thing to get wrong silently.
2. **Unknown plan names.** If a member's row names a plan that doesn't exist, should the
   importer (a) fail that row, (b) create the plan with a zero price for you to fix
   afterwards, or (c) import the member with no plan attached? v1 does **(c)** and flags
   it, since a member without a plan is recoverable and a fabricated plan is not.
3. **Excel files.** v1 accepts **CSV only** — every spreadsheet tool exports it, and it
   avoids a parsing dependency for the first version. Do gyms hand you `.xlsx` directly
   often enough to justify adding it?
4. **Who can import?** Bulk-creating records is significant. Owner/manager only, or any
   staff user?

---

## 7. What this deliberately does not do

- **No export.** This is import only. Export is a separate (and easier) piece of work.
- **No duplicate detection for payments.** They have no natural key, so re-uploading the
  same payments file twice *will* double the history. The preview says so plainly rather
  than pretending otherwise.
- **No attendance, leads, classes or PT import.** Out of v1 scope by choice.
- **No automatic scheduled/recurring imports.** A human uploads a file and confirms it.
- **No cross-field inference.** If `status` is missing it defaults to `active`; the
  importer does not derive status from expiry dates, because a gym's own rules for that
  are theirs, not ours.
- **No undo.** Once committed, records are normal records — corrections happen through
  the app's ordinary screens, not by rewinding an import.
