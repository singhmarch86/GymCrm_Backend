# FR-15 — One Analytics Section

**This is the specification** — every rule and why. Plain language, but
complete.

---

## Why this exists

The product already computes a great deal. It is simply scattered across four
places that nobody would think to connect:

| What exists today | Where it lives |
|---|---|
| Revenue, members, payments, renewals, plan performance | Reports screen |
| Funnel, sources, lost reasons, time-in-stage | A tab **inside** Leads |
| Churn risk, rhythm breaks, first-90-days activation | The At Risk worklist |
| Who did what, per day | Staff work |

FitnessForce does not necessarily compute more than this. It **feels** deeper
because there is one place called Analytics and everything is under it. An
owner comparing the two products sees one menu against four scattered screens
and concludes ours is the thinner product — while the numbers are already
there, unfindable.

**This adds no new metric.** It is an information-architecture change: gather
what exists under one heading, so the depth that was already built becomes
visible.

---

## 1. One section, four views

Analytics becomes a top-level section in the shell, with sub-tabs:

- **Business** — revenue, members, payments, renewals, plans *(the existing
  Reports screen)*
- **Leads** — funnel, sources, lost reasons, conversion *(the existing tab
  from inside Leads)*
- **Retention** — alerts by severity and type, what the scan is finding
- **Staff** — who did what, per day *(FR-13)*

Four is the whole product's analytics surface. If a fifth appears later it
belongs here too, not in a new corner.

## 2. Nothing moves out of where it already is

The Leads Analytics tab **stays** inside Leads. The Staff work screen stays
reachable from More. At Risk keeps its own summary.

Analytics is an additional door onto the same rooms, not a relocation. Somebody
who learned to find the funnel inside Leads must not discover one morning that
it has been taken away — that is how a UI change gets experienced as the
product breaking.

## 3. Views are reused, never reimplemented

Each sub-tab renders the **same widget** the standalone screen renders.

A second implementation of the funnel chart "for the analytics section" is two
things to keep in sync, and one of them is always the stale one. Where a view
needs data the section must fetch (the lead funnel), it calls the same service
method the original screen calls.

## 4. Each view loads only when first opened

Sub-tabs fetch on first visit, not on section entry.

Loading four analytics payloads — including a full funnel scan and a day of
staff ledgers — because somebody tapped Analytics would make the section slow
to open and would hammer the API for three views the user never looked at. Once
loaded, a view is kept alive for the session.

## 5. Analytics is read-only

Nothing in this section writes, resolves, edits, or triggers a scan.

An owner reading numbers is in a different mode from a receptionist working a
list. Mixing an action button into a reporting screen is how somebody resolves
an alert they meant to investigate. Acting on what you find happens on the
worklist screens, one tap away.

## 6. Empty is stated, not blank

A view with no data says what is missing and why, never an empty chart.

"No retention scan has been run yet" is useful. A chart with no bars looks
broken and gets reported as a bug.

---

## What this deliberately does not do

- **No new metrics.** Not one. This is grouping, and mixing new computation
  into a navigation change makes both impossible to review. Genuinely new
  analytics — cohort retention curves, LTV, trainer utilisation, class fill
  rates — is a separate FR with its own queries.
- **No date-range picker across all views.** Each view keeps the period it
  already uses. A shared range control implies every view honours it, and
  today none of them would.
- **No export.** Worth having, not part of this.
- **No cross-view drill-through.** Clicking a funnel stage does not filter the
  revenue chart. That is a data-model job, not a layout one.
- **No permissions change.** If a staff user could not see revenue before, they
  cannot now: the Business view is owner-only exactly as the Reports screen was.

---

## Decisions that are yours

1. **Whether Analytics deserves a permanent tab** or belongs inside More. It is
   a tab here because visibility is the entire point — but that is now six
   sections, and six is the most a bottom bar can carry.
2. **What genuinely new analytics matter.** Now that the existing set is
   visible in one place, the gaps against FitnessForce become obvious and
   specific — that comparison is much easier to make against this screen than
   against four scattered ones.
3. **Whether staff should see Analytics at all**, or only owners.
