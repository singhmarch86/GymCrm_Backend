# FR-14 — The Tabbed Shell

**This is the specification** — every rule and why. Plain language, but
complete.

---

## Why this exists

Today the dashboard is a **menu**. Nineteen tiles, each of which pushes a
screen you then have to back out of before you can do anything else. Grouping
those tiles into sections (done) made the menu readable, but it did not change
what it is: a place you pass through on the way to the work, dozens of times a
day.

The pilot gym uses FitnessForce, where the sections are always present and each
one opens straight into the work. Leads is not a tile that leads to a board —
Leads **is** the board.

The difference matters most at the front desk, where the same four or five
screens are opened continuously for eight hours. Every push-and-pop is a lost
second and a lost scroll position. It matters again for the owner on a phone,
where "back, back, scroll, tap" is the entire interaction.

**This changes navigation only.** No new data, no new endpoints, no migration.
Every screen it hosts already exists and is unchanged behind it.

---

## 1. The sections are the shell, not a destination

Five sections are always reachable in one tap, from anywhere:

| Section | Opens on | Why it earns a permanent slot |
|---|---|---|
| **Today** | Overview, alerts, renewals, revenue | The owner's first question every morning |
| **Members** | Member list | The most-opened screen in any gym CRM |
| **Leads** | **The board**, not the list | Where the money comes from, and the board is the view that shows the whole funnel |
| **At Risk** | Retention worklist | The reason this product exists, and the one screen nobody remembers to open |
| **More** | The grouped sections | Everything else, one tap away |

## 2. Leads opens on the board

The list view still exists; it is simply not the default any more.

The board answers "where is the funnel blocked" at a glance, which is the
question a gym owner actually has. The list answers "find me this one person",
which is what search is for. A section that opens on the less useful of its own
views wastes the tap it just saved.

## 3. Switching sections never loses your place

Each section keeps its scroll position, its filters and its sub-tab while you
are away from it.

This is the whole point. A receptionist who scrolls to the bottom of the At Risk
list, takes a payment, and comes back to find themselves at the top has been
given a worse tool than they had before. State is preserved for the life of the
session.

## 4. The shell adapts; the screens do not

One set of screens, two arrangements:

- **Desk (≥900px)** — a vertical rail down the left, always visible, labels
  shown. Horizontal space is abundant and a rail costs nothing.
- **Phone (<900px)** — a bottom bar, thumb-reachable.

Screens themselves are not forked. A second implementation per screen is two
things to keep in sync and one of them is always broken.

## 5. Density is the point, not a side effect

A tab that has to be scrolled to be understood has not saved anybody a tap.

Concretely, inside the shell:

- **Today drops the tile grid entirely.** It moved to More. What remains is
  numbers and alerts — the things that change daily — so the morning question
  is answered without scrolling.
- **Section headers do not repeat what the tab already says.** The tab is
  labelled Members; a large "Members" title under it is a wasted row on every
  single screen.
- **Chrome shrinks.** Tighter page padding and a compact app bar inside the
  shell, because the rail or bottom bar is already telling the user where they
  are.

Every row of chrome removed is a row of member data gained, on a screen a
receptionist reads a hundred times a day. FitnessForce looks better arranged
largely because it spends its pixels on data rather than on labels.

## 6. Deep navigation still pushes

Opening a member, a lead, or an invoice still pushes a full screen over the
shell.

Sections are *places*; records are *things you open and close*. Making a record
detail replace a section would strand the user with no way back that matches
what they did.

## 7. Nothing is removed

Every screen reachable before is reachable now. **More** carries the full
grouped map of the product.

A navigation change that quietly drops a feature is how a gym discovers, three
weeks in, that the thing they bought it for is gone.

---

## What this deliberately does not do

- **No per-user customisation of the tabs.** Which five sections matter is a
  question for the pilot gym, not a preferences screen. Answer it with evidence
  first; a settings toggle is what you build when you refuse to decide.
- **No badges on every tab.** At Risk and Renewals already carry counts where
  they are useful. A number on all five is noise, and noise is what the old
  dashboard was.
- **No URL routing.** The app has never had it; adding it is a separate job.
- **No new screens.** This is a container. Everything inside it already shipped.
- **No change to permissions.** Staff see exactly what they saw before.

---

## Decisions that are yours

1. **The five sections.** This is my best guess from the data model, not from
   watching a desk work. The pilot gym will tell you in ten minutes, and this
   list is one constant to change.
2. **Whether Today should exist at all for staff.** A receptionist may want
   Attendance in that slot instead — they never look at revenue.
3. **Whether At Risk deserves a permanent slot** before the gym is actually
   using it. It is there because it is the differentiator, which is a
   product-strategy reason rather than a workflow one.
