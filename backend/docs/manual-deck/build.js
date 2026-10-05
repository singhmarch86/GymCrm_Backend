const pptxgen = require("pptxgenjs");
const { iconPng } = require("./icons");

// ─── Palette ────────────────────────────────────────────────────────────────
const NAVY = "12203D"; // dominant — dark slides, headers, icon circles
const STEEL = "3D5A80"; // secondary — supporting text, category labels
const CORAL = "FF5A4E"; // accent — icons, highlights, small emphasis
const CARD = "F2F4F8"; // light card tint
const INK = "1C2536"; // body text on light bg
const MUTED = "6B7280"; // muted/caption text
const WHITE = "FFFFFF";
const DANGER = "C0392B";
const GOOD = "1E8E5A";

const W = 13.333,
  H = 7.5;
const MARGIN = 0.6;
const CONTENT_W = W - MARGIN * 2;

async function main() {
  const pres = new pptxgen();
  pres.layout = "LAYOUT_WIDE";
  pres.author = "GymCRM";
  pres.title = "Regulars — Complete Software Manual";

  // ── Pre-render icons ────────────────────────────────────────────────────
  const iconNames = [
    "FiLogIn",
    "FiGrid",
    "FiUsers",
    "FiUserPlus",
    "FiRefreshCw",
    "FiAlertTriangle",
    "FiCreditCard",
    "FiShoppingCart",
    "FiFileText",
    "FiCheckSquare",
    "FiCalendar",
    "FiClipboard",
    "FiBarChart2",
    "FiUserCheck",
    "FiShare2",
    "FiMapPin",
    "FiUpload",
    "FiAward",
    "FiActivity",
    "FiStar",
    "FiMessageCircle",
    "FiTarget",
    "FiShield",
    "FiHeart",
    "FiSlash",
    "FiCompass",
    "FiEyeOff",
    "FiTrendingDown",
    "FiDollarSign",
    "FiList",
  ];
  const icon = {};
  for (const name of iconNames) {
    icon[name] = await iconPng(name, { size: 256, color: "FFFFFF" });
  }
  const iconDark = {};
  for (const name of ["FiAlertTriangle", "FiHeart", "FiCompass"]) {
    iconDark[name] = await iconPng(name, { size: 256, color: NAVY });
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  function bgSlide(color = WHITE) {
    const s = pres.addSlide();
    s.background = { color };
    return s;
  }

  function pageFooter(s, label, pageNum) {
    s.addText(label.toUpperCase(), {
      x: MARGIN,
      y: H - 0.45,
      w: 6,
      h: 0.3,
      fontFace: "Calibri",
      fontSize: 9,
      color: MUTED,
      charSpacing: 1,
      isTextBox: true,
      margin: 0,
    });
    s.addText(String(pageNum), {
      x: W - MARGIN - 1,
      y: H - 0.45,
      w: 1,
      h: 0.3,
      align: "right",
      fontFace: "Calibri",
      fontSize: 9,
      color: MUTED,
      isTextBox: true,
      margin: 0,
    });
  }

  function iconCircle(s, iconKey, { x, y, d = 0.9, fill = NAVY } = {}) {
    s.addShape(pres.ShapeType.ellipse, { x, y, w: d, h: d, fill: { color: fill }, line: { type: "none" } });
    const pad = d * 0.24;
    s.addImage({ data: "image/png;base64," + icon[iconKey], x: x + pad, y: y + pad, w: d - pad * 2, h: d - pad * 2 });
  }

  // Standard content-slide header: eyebrow, title, one-liner, icon at top-right.
  function moduleHeader(s, { eyebrow, title, what, iconKey }) {
    s.addText(eyebrow.toUpperCase(), {
      x: MARGIN,
      y: 0.42,
      w: 10,
      h: 0.3,
      fontFace: "Calibri",
      fontSize: 12,
      bold: true,
      color: CORAL,
      charSpacing: 1.5,
      isTextBox: true,
      margin: 0,
    });
    s.addText(title, {
      x: MARGIN,
      y: 0.72,
      w: 10.8,
      h: 0.65,
      fontFace: "Cambria",
      fontSize: 30,
      bold: true,
      color: NAVY,
      isTextBox: true,
      margin: 0,
    });
    s.addText(what, {
      x: MARGIN,
      y: 1.4,
      w: 11.5,
      h: 0.5,
      fontFace: "Calibri",
      fontSize: 14.5,
      color: MUTED,
      italic: true,
      isTextBox: true,
      margin: 0,
    });
    iconCircle(s, iconKey, { x: W - MARGIN - 0.9, y: 0.5, d: 0.9 });
  }

  // A tinted rounded-rect card with a heading and a bulleted/numbered list.
  function card(s, { x, y, w, h, heading, items, numbered = false, headingColor = NAVY }) {
    s.addShape(pres.ShapeType.roundRect, {
      x,
      y,
      w,
      h,
      rectRadius: 0.08,
      fill: { color: CARD },
      line: { type: "none" },
    });
    const padX = 0.32,
      padY = 0.26;
    s.addText(heading, {
      x: x + padX,
      y: y + padY,
      w: w - padX * 2,
      h: 0.35,
      fontFace: "Calibri",
      fontSize: 14,
      bold: true,
      color: headingColor,
      isTextBox: true,
      margin: 0,
    });
    const bodyItems = [];
    items.forEach((it, i) => {
      const [head, rest] = Array.isArray(it) ? it : [null, it];
      const isLast = i === items.length - 1;
      const bulletOpt = numbered ? { type: "number", startAt: i + 1 } : { code: "2022", indent: 14 };
      if (head) {
        bodyItems.push({
          text: `${head} `,
          options: { bold: true, color: NAVY, fontSize: 12.5, bullet: bulletOpt, paraSpaceAfter: 8 },
        });
        bodyItems.push({
          text: rest,
          options: { color: INK, fontSize: 12.5, breakLine: !isLast, paraSpaceAfter: 8 },
        });
      } else {
        bodyItems.push({
          text: rest,
          options: {
            color: INK,
            fontSize: 12.5,
            bullet: bulletOpt,
            breakLine: !isLast,
            paraSpaceAfter: 8,
          },
        });
      }
    });
    s.addText(bodyItems, {
      x: x + padX,
      y: y + padY + 0.42,
      w: w - padX * 2,
      h: h - padY * 2 - 0.42,
      fontFace: "Calibri",
      isTextBox: true,
      margin: 0,
      valign: "top",
    });
  }

  function moduleSlide({ eyebrow, title, what, iconKey, blocks, pageNum }) {
    const s = bgSlide(WHITE);
    moduleHeader(s, { eyebrow, title, what, iconKey });
    const top = 2.05,
      bottom = 6.85;
    const gap = 0.4;
    const totalW = CONTENT_W;
    const bw = blocks.length === 1 ? totalW : (totalW - gap * (blocks.length - 1)) / blocks.length;
    blocks.forEach((b, i) => {
      card(s, { x: MARGIN + i * (bw + gap), y: top, w: bw, h: bottom - top, ...b });
    });
    pageFooter(s, eyebrow, pageNum);
    return s;
  }

  function dividerSlide({ label, subtitle, pageNum }) {
    const s = bgSlide(NAVY);
    s.addShape(pres.ShapeType.rect, { x: 0, y: 0, w: W, h: H, fill: { color: NAVY }, line: { type: "none" } });
    s.addText(label.toUpperCase(), {
      x: MARGIN,
      y: H / 2 - 0.9,
      w: W - MARGIN * 2,
      h: 1.3,
      fontFace: "Cambria",
      fontSize: 46,
      bold: true,
      color: WHITE,
      charSpacing: 1,
      isTextBox: true,
      margin: 0,
    });
    s.addText(subtitle, {
      x: MARGIN,
      y: H / 2 + 0.35,
      w: W - MARGIN * 2 - 2,
      h: 0.6,
      fontFace: "Calibri",
      fontSize: 16,
      color: "CADCFC",
      isTextBox: true,
      margin: 0,
    });
    pageFooter(s, "", pageNum);
    // fix footer color on dark bg
    return s;
  }

  // ══════════════════════════════════════════════════════════════════════
  // 1. TITLE
  // ══════════════════════════════════════════════════════════════════════
  {
    const s = bgSlide(NAVY);
    s.addShape(pres.ShapeType.ellipse, {
      x: W - 3.6,
      y: -1.6,
      w: 5.2,
      h: 5.2,
      fill: { color: "1B2C50" },
      line: { type: "none" },
    });
    s.addShape(pres.ShapeType.ellipse, {
      x: W - 2.1,
      y: 3.6,
      w: 3.2,
      h: 3.2,
      fill: { color: CORAL, transparency: 88 },
      line: { type: "none" },
    });
    s.addText("REGULARS", {
      x: MARGIN,
      y: 2.55,
      w: 10,
      h: 0.5,
      fontFace: "Calibri",
      fontSize: 15,
      bold: true,
      color: CORAL,
      charSpacing: 3,
      isTextBox: true,
      margin: 0,
    });
    s.addText("Complete Software Manual", {
      x: MARGIN,
      y: 2.95,
      w: 10.5,
      h: 1.3,
      fontFace: "Cambria",
      fontSize: 46,
      bold: true,
      color: WHITE,
      isTextBox: true,
      margin: 0,
    });
    s.addText("Gym management software that tells you when your regulars stop being regular.", {
      x: MARGIN,
      y: 4.05,
      w: 9.5,
      h: 0.6,
      fontFace: "Calibri",
      fontSize: 16,
      color: "CADCFC",
      isTextBox: true,
      margin: 0,
    });
    s.addText("Every screen, every action, every retention signal — in one reference.", {
      x: MARGIN,
      y: 4.55,
      w: 9.5,
      h: 0.5,
      fontFace: "Calibri",
      fontSize: 13,
      italic: true,
      color: "8FA6D6",
      isTextBox: true,
      margin: 0,
    });
  }

  // ══════════════════════════════════════════════════════════════════════
  // 2. OVERVIEW — three pillars
  // ══════════════════════════════════════════════════════════════════════
  {
    const s = bgSlide(WHITE);
    s.addText("WHAT THIS SOFTWARE IS", {
      x: MARGIN,
      y: 0.5,
      w: 10,
      h: 0.3,
      fontFace: "Calibri",
      fontSize: 12,
      bold: true,
      color: CORAL,
      charSpacing: 1.5,
      isTextBox: true,
      margin: 0,
    });
    s.addText("Three jobs, one system", {
      x: MARGIN,
      y: 0.8,
      w: 10.8,
      h: 0.65,
      fontFace: "Cambria",
      fontSize: 30,
      bold: true,
      color: NAVY,
      isTextBox: true,
      margin: 0,
    });
    const pillars = [
      {
        icon: "FiUsers",
        title: "Run the front desk",
        body: "Members, leads, renewals, payments, invoices, the shop counter, and attendance — the daily work of the desk, in one place.",
      },
      {
        icon: "FiAlertTriangle",
        title: "Watch for churn before it happens",
        body: "Nine alerts and six counter prompts, all arithmetic on real visit records — no scores, no predictions, every flag traceable back to actual data.",
      },
      {
        icon: "FiMapPin",
        title: "Run more than one location",
        body: "Branches, staff and trainer transfers, chain-wide stock and revenue views — for gyms that have outgrown a single site.",
      },
    ];
    const top = 2.05,
      bh = 4.6,
      gap = 0.4;
    const bw = (CONTENT_W - gap * 2) / 3;
    pillars.forEach((p, i) => {
      const x = MARGIN + i * (bw + gap);
      s.addShape(pres.ShapeType.roundRect, {
        x,
        y: top,
        w: bw,
        h: bh,
        rectRadius: 0.1,
        fill: { color: CARD },
        line: { type: "none" },
      });
      iconCircle(s, p.icon, { x: x + 0.35, y: top + 0.35, d: 0.75 });
      s.addText(p.title, {
        x: x + 0.35,
        y: top + 1.3,
        w: bw - 0.7,
        h: 0.8,
        fontFace: "Cambria",
        fontSize: 18,
        bold: true,
        color: NAVY,
        isTextBox: true,
        margin: 0,
      });
      s.addText(p.body, {
        x: x + 0.35,
        y: top + 2.15,
        w: bw - 0.7,
        h: bh - 2.5,
        fontFace: "Calibri",
        fontSize: 13,
        color: INK,
        isTextBox: true,
        margin: 0,
        valign: "top",
      });
    });
    pageFooter(s, "Overview", 2);
  }

  // ══════════════════════════════════════════════════════════════════════
  // Section dividers + module slides, in manual order
  // ══════════════════════════════════════════════════════════════════════
  let n = 3;

  dividerSlide({ label: "Getting In", subtitle: "The front door, and the first screen after it.", pageNum: n++ });

  moduleSlide({
    eyebrow: "Getting in",
    title: "Login",
    what: "The front door — works in any browser on laptop, tablet or phone. Nothing to install.",
    iconKey: "FiLogIn",
    pageNum: n++,
    blocks: [
      {
        heading: "On the screen",
        items: ["Phone number, password, and a Login button."],
      },
      {
        heading: "Two kinds of account",
        items: [
          ["Owner", "everything — staff, plans, pricing, reports."],
          ["Staff", "members, check-ins, payments, shop, At Risk."],
        ],
      },
    ],
  });

  moduleSlide({
    eyebrow: "Getting in",
    title: "Dashboard",
    what: "The first screen after login. It answers “what needs attention today.”",
    iconKey: "FiGrid",
    pageNum: n++,
    blocks: [
      {
        heading: "On the screen, top to bottom",
        items: [
          "Your name and greeting, with sign-out",
          "Alert bar — inactive 30+ days, renewals due within 7 days",
          "Today's Overview — members, expiring soon, revenue this month",
          "Renewals card — due today / this week / overdue",
          "Revenue card — this month / today / pending",
          "Quick Actions — the way into every screen ahead",
        ],
      },
    ],
  });

  dividerSlide({ label: "Every Day", subtitle: "The screens staff and owners live in, day to day.", pageNum: n++ });

  moduleSlide({
    eyebrow: "1 · Every day",
    title: "Members",
    what: "Every member of the gym. The screen used most.",
    iconKey: "FiUsers",
    pageNum: n++,
    blocks: [
      {
        heading: "Add a member",
        numbered: true,
        items: ["Tap Add Member", "Fill in name, phone, plan, start date", "Save — expiry is worked out from the plan"],
      },
      {
        heading: "The member's page",
        items: [
          "Plan, expiry, check-ins, payments, invoices",
          "PT packages, feedback and recognition",
          "Shop purchases, wallet balance",
          "Full history of every change",
          ["Actions:", "Renew, Freeze, Change plan, Transfer, Terminate — all recorded with date and who did it"],
          ["Freeze:", "up to 90 days at a time, expiry extends day-for-day — return early and only the days actually frozen count"],
        ],
      },
    ],
  });

  moduleSlide({
    eyebrow: "2 · Every day",
    title: "Leads (CRM)",
    what: "Enquiries who are not members yet — five fixed stages, and never left without a next step.",
    iconKey: "FiUserPlus",
    pageNum: n++,
    blocks: [
      {
        heading: "The pipeline — five stages, each with a default next step",
        items: [
          ["New Lead →", "make first contact, same day"],
          ["Contacted →", "book a trial, within 2 days"],
          ["Trial Scheduled →", "confirm they're coming, the day before"],
          ["Trial Completed →", "counselling — sit down, discuss plans"],
          ["Joined / Lost —", "the workflow ends here"],
        ],
      },
      {
        heading: "On the screen",
        items: [
          "Pipeline board, one column per stage — drag a lead as it progresses",
          "Every lead shows how long it's been in its current stage — stuck is visible, not hidden",
          "Follow-up queue, activity timeline, Assign to a staff member",
          "Analytics — where leads come from, how they convert, why they're lost",
          "Convert: one tap turns a lead into a member, nothing retyped",
        ],
      },
    ],
  });

  moduleSlide({
    eyebrow: "3 · Every day",
    title: "Renewals",
    what: "Everyone whose membership is expiring, so nobody lapses unnoticed.",
    iconKey: "FiRefreshCw",
    pageNum: n++,
    blocks: [
      {
        heading: "Two tabs: Due, and All",
        items: [
          "Due — everyone expiring soon, worst first",
          ["Lapsed — still worth a call —", "expired in the last 30 days and not renewed; the window where somebody usually still comes back"],
          "All — the full list, not just what's due",
        ],
      },
      {
        heading: "To use it",
        items: ["Tap a member to renew, or to call first.", "Renewing records the payment and moves the expiry date forward."],
      },
    ],
  });

  moduleSlide({
    eyebrow: "4 · Every day",
    title: "At Risk",
    what: "The retention worklist — a worklist, not a report. Every row is a member and a phone call.",
    iconKey: "FiAlertTriangle",
    pageNum: n++,
    blocks: [
      {
        heading: "First 90 days — most churn happens here",
        items: [
          ["Paid, never walked in", "joined, zero check-ins — the easiest save on the list"],
          ["Started, then stopped", "came a few times, then went quiet"],
          ["Coming too rarely", "under ~1.5 visits/week, never becomes a habit"],
        ],
      },
      {
        heading: "Routine has broken — the one early-warning signal",
        items: [
          "Still coming just as often, but no longer at their usual time",
          "Every other signal fires when somebody stops coming — this fires while attendance is still normal",
          "Don't say “we miss you” — ask if their schedule changed",
          "Tap the tick to mark handled — the note is recorded against your name",
        ],
      },
    ],
  });

  // ── Retention signal reference table ────────────────────────────────────
  {
    const s = bgSlide(WHITE);
    moduleHeader(s, {
      eyebrow: "4 · Every day",
      title: "Every Retention Signal",
      what: "Nine alerts and six counter prompts — every one is arithmetic on your own records. No scores, no predictions.",
      iconKey: "FiShield",
    });
    const rows = [
      [
        { text: "Stage", options: { bold: true, color: WHITE, fill: { color: NAVY } } },
        { text: "Signal", options: { bold: true, color: WHITE, fill: { color: NAVY } } },
        { text: "Fires when", options: { bold: true, color: WHITE, fill: { color: NAVY } } },
      ],
      ["First 90 days", "Paid, never walked in", "3+ days since joining, zero check-ins"],
      ["First 90 days", "Coming too rarely", "Day 7+, under 1.5 visits a week"],
      ["First 90 days", "Started, then quiet", "3+ visits, then 10 days silent"],
      ["Established", "Routine has broken", "Kept a slot 8 weeks, now <40% — while still visiting as often"],
      ["Established", "Inactive 1 / 2+ weeks", "7–13 days light nudge; 14+ days strongest churn signal"],
      ["Ending", "Expiring / expired", "3 days out, expires today, or lapsed unrenewed"],
    ].map((r) =>
      Array.isArray(r)
        ? r.map((c) => (typeof c === "string" ? { text: c, options: { color: INK, fontSize: 11.5 } } : c))
        : r
    );
    s.addTable(rows, {
      x: MARGIN,
      y: 2.05,
      w: CONTENT_W,
      colW: [2.6, 3.4, CONTENT_W - 6],
      fontFace: "Calibri",
      fontSize: 11.5,
      border: { type: "solid", color: "E2E6ED", pt: 0.75 },
      autoPage: false,
      valign: "middle",
      rowH: 0.55,
    });
    s.addText(
      "At the counter — six prompts, one at a time: First ever visit · Back after a break · Needs attention · PT running out · Due a restock · Wallet low. Most check-ins show none.",
      {
        x: MARGIN,
        y: 6.15,
        w: CONTENT_W,
        h: 0.7,
        fontFace: "Calibri",
        fontSize: 12.5,
        italic: true,
        color: MUTED,
        isTextBox: true,
        margin: 0,
      }
    );
    pageFooter(s, "4 · Every day", n++);
  }

  moduleSlide({
    eyebrow: "5 · Every day",
    title: "Payments",
    what: "Money taken, and the Collections tab — everything outstanding, worst first.",
    iconKey: "FiCreditCard",
    pageNum: n++,
    blocks: [
      {
        heading: "Collections — grouped worst first, not oldest first",
        items: [
          ["Nobody has chased these —", "overdue, no contact recorded since the due date — the group that justifies the tab"],
          ["Chased, no outcome —", "somebody called, the money hasn't arrived"],
          ["Promised to pay —", "sorted by the date agreed"],
        ],
      },
      {
        heading: "Collect a payment",
        numbered: true,
        items: [
          "Collect payment, or open the member and collect there",
          "Choose amount and method — cash, UPI, card, bank transfer",
          "Save — recorded against whoever is logged in",
        ],
      },
    ],
  });

  moduleSlide({
    eyebrow: "6 · Every day",
    title: "Money Leaks",
    what: "Value the gym handed over without ever billing it. Not a debtors list — nobody wrote these down in the first place.",
    iconKey: "FiTrendingDown",
    pageNum: n++,
    blocks: [
      {
        heading: "Five findings, valued honestly",
        items: [
          ["Sessions given away —", "PT delivered beyond what the package paid for"],
          ["Training after expiry —", "checked in after the membership ran out (frozen members excluded)"],
          ["Members who never paid —", "active membership, zero payment — not even raised as a due"],
          ["Invoices with nothing against them —", "issued, but no payment row of any kind"],
          ["Counters that disagree —", "a package's used-session count doesn't match its completed bookings"],
        ],
      },
      {
        heading: "Every finding, never an accusation",
        items: [
          "Zero-valued where a figure can't be reached honestly — a drifted counter costs nothing by itself",
          "The total is a floor, not the total — some findings carry no figure at all",
          "This is not Collections — a due already being chased there is never double-counted here",
          "Not this screen: Collections (Payments), Renewals due (Renewals), Low stock (Shop → Restock) — each already its own worklist",
        ],
      },
    ],
  });

  moduleSlide({
    eyebrow: "7 · Every day",
    title: "Digital Wallet",
    what: "Stored credit against a member's account — an insert-only ledger, never a number anyone can just type over.",
    iconKey: "FiDollarSign",
    pageNum: n++,
    blocks: [
      {
        heading: "How it's used",
        items: [
          "Top up a member's wallet, or spend it as part of a sale",
          "Every change is one ledger row — top-up, spend, refund, adjustment, or expiry",
          "The balance is always the sum of that ledger, so “why is my balance ₹300” always has an answer",
        ],
      },
      {
        heading: "Where it shows up",
        items: [
          "Shop → Sell: wallet sits alongside cash and UPI as a payment method",
          "The member's page: current balance and full transaction history",
          "Counter prompt: “Wallet low” appears at check-in once the balance drops under ₹200",
        ],
      },
    ],
  });

  moduleSlide({
    eyebrow: "8 · Every day",
    title: "Shop (POS)",
    what: "Four tabs — Sell, Restock, Stock, Sales — the counter and everything behind it.",
    iconKey: "FiShoppingCart",
    pageNum: n++,
    blocks: [
      {
        heading: "Sell",
        items: [
          "Build a basket, optionally pick a member, take payment",
          "Cash, UPI, or the member's wallet balance",
          "Wallet payments come out as part of the sale — if the sale fails, nothing is deducted",
        ],
      },
      {
        heading: "Restock, Stock & Sales",
        items: [
          ["Restock —", "the low-stock queue itself: products at or below their reorder level, worst first"],
          "Stock is driven by recorded movements, never typed in — a sale that would take it negative is refused",
          "Sales tab: full history, including refunds",
          "“What the shop is doing”: days of cover per product — reorder now / dead / overstocked / healthy",
        ],
      },
    ],
  });

  moduleSlide({
    eyebrow: "9 · Every day",
    title: "Invoices",
    what: "GST invoices with proper sequential numbering — two tabs: Invoices and Discounts.",
    iconKey: "FiFileText",
    pageNum: n++,
    blocks: [
      {
        heading: "On the screen",
        items: [
          "Filter by All, Drafts, Issued, Cancelled",
          "Every invoice with its status — draft, unpaid, partly paid, paid",
          "Discounts tab: the discount codes/rules invoices can apply, managed separately",
        ],
      },
      {
        heading: "Two things worth understanding",
        items: [
          ["Gapless numbering.", "Assigned when issued, not drafted — never a hole in the sequence."],
          ["Issued cannot be edited.", "Cancel and re-issue instead — that's what makes the books defensible."],
          "Prices are tax-inclusive by default; discounts apply per line.",
        ],
      },
    ],
  });

  moduleSlide({
    eyebrow: "10 · Every day",
    title: "Attendance",
    what: "Check-ins, and the front desk's home screen.",
    iconKey: "FiCheckSquare",
    pageNum: n++,
    blocks: [
      {
        heading: "Check somebody in",
        numbered: true,
        items: ["Tap Check in", "Search by name or phone", "Tap the member — twice never creates a second visit"],
      },
      {
        heading: "The counter prompt",
        items: [
          "A short note appears sometimes — for you, not the member",
          "“Back after a break,” “Due a restock,” “First ever visit”",
          "Most check-ins show nothing — deliberately",
          "Never anything about money owed here — that's a private conversation",
        ],
      },
    ],
  });

  dividerSlide({ label: "Setting Up & Running", subtitle: "Configuration, reporting, and multi-branch operations.", pageNum: n++ });

  moduleSlide({
    eyebrow: "11 · Setting up",
    title: "Classes",
    what: "The group timetable.",
    iconKey: "FiCalendar",
    pageNum: n++,
    blocks: [
      {
        heading: "To set up",
        items: [
          "Create a class type (Yoga, HIIT)",
          "Then a schedule — day, time, capacity, trainer",
          "Schedules generate individual sessions",
        ],
      },
      {
        heading: "On a session",
        items: [
          "Who's booked, who's waitlisted, attendance marking",
          "A full session moves waitlisted members up automatically on a cancellation",
          "Classes are included in membership — no per-class charging",
        ],
      },
    ],
  });

  moduleSlide({
    eyebrow: "12 · Setting up",
    title: "Plans",
    what: "Membership types and prices. Owner only.",
    iconKey: "FiClipboard",
    pageNum: n++,
    blocks: [
      {
        heading: "On the screen",
        items: [
          "Each plan with duration and price",
          "Create with a name, length in days, and price",
          "Plans drive expiry dates and renewal amounts everywhere else",
          "Changing a price never rewrites past invoices",
        ],
      },
    ],
  });

  moduleSlide({
    eyebrow: "13 · Setting up",
    title: "Analytics",
    what: "Everything the software already computes, gathered under one heading instead of scattered across four screens. No new metric — an information-architecture change.",
    iconKey: "FiBarChart2",
    pageNum: n++,
    blocks: [
      {
        heading: "Four views, one section",
        items: [
          ["Business —", "5 charts: Revenue trend, Member growth, Renewal trend, Payment distribution, Plan distribution"],
          ["Leads —", "funnel, sources, lost reasons, conversion (also lives inside Leads)"],
          ["Retention —", "alerts by severity and type, what the scan is finding"],
          ["Staff —", "who did what, per day (Staff Work, kept reachable from More too)"],
        ],
      },
      {
        heading: "Why one section",
        items: [
          "Everything here already existed on other screens — this just gathers it",
          "Use At Risk for today's work; use Analytics → Business for last month's answer",
          "If a fifth view appears later, it belongs here too, not a new corner",
          ["Also findable as “Reports” under More —", "same Business charts, plus a per-plan Members/Revenue/Sold table"],
        ],
      },
    ],
  });

  moduleSlide({
    eyebrow: "14 · Setting up",
    title: "Staff Accounts",
    what: "Who can log in. Owner only — separate from Staff Work, which is what they did.",
    iconKey: "FiUserCheck",
    pageNum: n++,
    blocks: [
      {
        heading: "On the screen",
        items: [
          "Add a staff member: name, phone, role (owner or staff)",
          "They log in with that phone and the password you set",
          "Deactivate rather than delete when somebody leaves — their record of what they did stays intact",
        ],
      },
    ],
  });

  // ── Staff Work — read-only, deliberately not a leaderboard ─────────────
  {
    const s = bgSlide(WHITE);
    moduleHeader(s, {
      eyebrow: "15 · Setting up",
      title: "Staff Work",
      what: "Five tabs — a record of what happened, plus the day's actual worklists in one place.",
      iconKey: "FiList",
    });
    const top = 2.05,
      bottom = 6.85;
    const gap = 0.4;
    const bw = (CONTENT_W - gap) / 2;
    card(s, {
      x: MARGIN,
      y: top,
      w: bw,
      h: bottom - top,
      heading: "Five tabs",
      items: [
        ["Money & work —", "payments collected, renewals closed, shop sales, invoices raised, per person"],
        ["Expected —", "already-raised dues vs. the renewal ceiling, day by day"],
        ["Collect —", "the same Collections queue, worst first"],
        ["Leads / Follow up —", "lead activity and the same unattended-follow-up queue from Leads"],
        "Every count opens the rows behind it — which member, which amount, what time",
      ],
    });
    card(s, {
      x: MARGIN + bw + gap,
      y: top,
      w: bw,
      h: bottom - top,
      heading: "The discipline",
      items: [
        "Money shown is money handled, not earned — labelled “collected,” never “achieved”",
        "Ordered by name, never by count — sorting by count turns it into a leaderboard on every load",
        "Staff see only their own row; an owner sees everyone",
        "Nothing is inferred — every category is one existing ledger, not a guess",
      ],
    });
    pageFooter(s, "15 · Setting up", n++);
  }

  moduleSlide({
    eyebrow: "16 · Setting up",
    title: "Visitors & Referrals",
    what: "Everyone who came in but isn't a member yet — and the members who brought them.",
    iconKey: "FiShare2",
    pageNum: n++,
    blocks: [
      {
        heading: "Visitors",
        items: [
          "Walk-ins, trial sessions and tours",
          "Record who came, why, and what happened",
          "A visitor can convert into a member or a lead",
        ],
      },
      {
        heading: "Referrals",
        items: [
          "Record who referred whom, and whether it converted",
          "See which members are worth thanking",
          "See how much of your growth is word of mouth",
        ],
      },
    ],
  });

  moduleSlide({
    eyebrow: "17 · Setting up",
    title: "Branches",
    what: "For gyms with more than one location. Skip it if you have one.",
    iconKey: "FiMapPin",
    pageNum: n++,
    blocks: [
      {
        heading: "Each branch",
        items: ["Its own members, staff and takings.", "Switch between branches here."],
      },
      {
        heading: "Also here",
        items: [
          "Transfer members, staff and trainers between branches",
          "Targets — monthly revenue and member targets per branch",
          "Chain overview — branches compared, side by side",
          "Stock chain — what's in stock at every branch, and what could move instead of being bought",
        ],
      },
    ],
  });

  moduleSlide({
    eyebrow: "18 · Setting up",
    title: "Import Data",
    what: "Bringing members, plans and payments from a spreadsheet or your previous software.",
    iconKey: "FiUpload",
    pageNum: n++,
    blocks: [
      {
        heading: "Two stages — and this matters",
        numbered: true,
        items: [
          "Check — the file is read, every row judged, nothing saved",
          "Import — only the rows that passed are saved",
        ],
      },
      {
        heading: "Worth knowing",
        items: [
          "Dates must be day-first (31/01/2026) — month-first dates are rejected, not guessed",
          "Column headings match flexibly — “Phone,” “Mobile,” “Contact No” all understood",
        ],
      },
    ],
  });

  moduleSlide({
    eyebrow: "19 · Setting up",
    title: "Trainers",
    what: "Your training staff, their specialisations, and their own profile page.",
    iconKey: "FiAward",
    pageNum: n++,
    blocks: [
      {
        heading: "The roster",
        items: ["Add a trainer with name, phone and specialisation.", "Trainers attach to classes and to PT packages."],
      },
      {
        heading: "A trainer's page",
        items: [
          "Sessions delivered, feedback given or received",
          "Who they currently work with, what they were last paid",
          "Edit and Move to another branch live here, not on the list",
          "Members are always listed by name — never ranked or scored",
        ],
      },
    ],
  });

  moduleSlide({
    eyebrow: "20 · Setting up",
    title: "Trainer Payouts",
    what: "The mirror of collections — money the gym owes the people who work in it, not money owed to it.",
    iconKey: "FiDollarSign",
    pageNum: n++,
    blocks: [
      {
        heading: "Three schemes, any combination",
        items: [
          ["Salary —", "a fixed amount for a whole calendar month"],
          ["Commission —", "a percentage of PT the gym has actually been paid for, never on packages merely sold"],
          ["Session —", "a rate per session actually delivered"],
        ],
      },
      {
        heading: "On the screen",
        items: [
          "One payout per trainer, per period — salary, commission and session kept apart so “why is this less than last month” has an answer",
          "Adjustments (signed — an advance recovered is negative), with a reason",
          "Mark paid: payment mode and reference number recorded",
          "A trainer's own payout history lives on their profile page too",
        ],
      },
    ],
  });

  moduleSlide({
    eyebrow: "21 · Setting up",
    title: "Personal Training",
    what: "One-to-one training: packages and appointments.",
    iconKey: "FiActivity",
    pageNum: n++,
    blocks: [
      {
        heading: "Sell a package",
        items: ["Member, trainer, number of sessions, price.", "An invoice can be raised from it in one tap."],
      },
      {
        heading: "Book an appointment",
        items: [
          "Member, trainer, date and time",
          "Sessions deduct as they're used; remaining balance is always visible",
          "Down to the last couple of sessions? The front desk sees a note at check-in",
        ],
      },
    ],
  });

  // ── PT Feedback / Reports / Recognition — feature highlight ────────────
  {
    const s = bgSlide(WHITE);
    moduleHeader(s, {
      eyebrow: "22 · Setting up",
      title: "Feedback, Reports & Recognition",
      what: "What was said, what it adds up to, and a private word for the ones going above and beyond.",
      iconKey: "FiStar",
    });
    const items = [
      {
        icon: "FiMessageCircle",
        title: "Feedback",
        body: "One running note of what a member said and what a trainer observed. Trainers don't log in, so both directions are written by staff.",
      },
      {
        icon: "FiBarChart2",
        title: "Reports",
        body: "The same records, read back on both the member's page and the trainer's page: sessions used, feedback, and recent attendance consistency.",
      },
      {
        icon: "FiStar",
        title: "Recognition",
        body: "A private note when a member deserves a shout-out. Written reason required; citing a signal is optional. Staff-only, never shown to the member.",
      },
    ];
    const top = 2.05,
      bh = 4.5,
      gap = 0.4;
    const bw = (CONTENT_W - gap * 2) / 3;
    items.forEach((p, i) => {
      const x = MARGIN + i * (bw + gap);
      s.addShape(pres.ShapeType.roundRect, {
        x,
        y: top,
        w: bw,
        h: bh,
        rectRadius: 0.1,
        fill: { color: CARD },
        line: { type: "none" },
      });
      iconCircle(s, p.icon, { x: x + 0.35, y: top + 0.35, d: 0.75, fill: CORAL });
      s.addText(p.title, {
        x: x + 0.35,
        y: top + 1.3,
        w: bw - 0.7,
        h: 0.5,
        fontFace: "Cambria",
        fontSize: 18,
        bold: true,
        color: NAVY,
        isTextBox: true,
        margin: 0,
      });
      s.addText(p.body, {
        x: x + 0.35,
        y: top + 1.85,
        w: bw - 0.7,
        h: bh - 2.2,
        fontFace: "Calibri",
        fontSize: 12.5,
        color: INK,
        isTextBox: true,
        margin: 0,
        valign: "top",
      });
    });
    s.addText("Not a leaderboard. No score, no ranking, no member ever sees it — the same discipline the retention screens hold to.", {
      x: MARGIN,
      y: top + bh + 0.2,
      w: CONTENT_W,
      h: 0.4,
      fontFace: "Calibri",
      fontSize: 12.5,
      italic: true,
      color: MUTED,
      isTextBox: true,
      margin: 0,
    });
    pageFooter(s, "22 · Setting up", n++);
  }

  // ══════════════════════════════════════════════════════════════════════
  // WHAT IT DOES NOT DO
  // ══════════════════════════════════════════════════════════════════════
  {
    const s = bgSlide(NAVY);
    s.addText("BEING STRAIGHT ABOUT THIS", {
      x: MARGIN,
      y: 0.5,
      w: 10,
      h: 0.3,
      fontFace: "Calibri",
      fontSize: 12,
      bold: true,
      color: CORAL,
      charSpacing: 1.5,
      isTextBox: true,
      margin: 0,
    });
    s.addText("What This Software Does Not Do", {
      x: MARGIN,
      y: 0.8,
      w: 11.5,
      h: 0.7,
      fontFace: "Cambria",
      fontSize: 30,
      bold: true,
      color: WHITE,
      isTextBox: true,
      margin: 0,
    });
    s.addText("Matters more than a longer feature list.", {
      x: MARGIN,
      y: 1.45,
      w: 11,
      h: 0.4,
      fontFace: "Calibri",
      fontSize: 14,
      italic: true,
      color: "8FA6D6",
      isTextBox: true,
      margin: 0,
    });
    const dont = [
      "It does not send messages — no automatic SMS, WhatsApp or email. It tells a human who to contact.",
      "It does not charge for classes — classes are included in membership.",
      "It does not connect to a biometric or turnstile device — check-ins are recorded in the app.",
      "It does not take online payments from members — it records payments already taken.",
      "There is no member-facing app — members don't log in, staff do.",
      "It does not predict who will quit or score members — every flag traces back to real visits.",
      "It does not rank or score members, staff, or trainers — recognition is a private reason, never a leaderboard.",
    ];
    const top = 2.15;
    const rowH = 0.62;
    dont.forEach((t, i) => {
      const y = top + i * rowH;
      iconCircle(s, "FiSlash", { x: MARGIN, y: y - 0.02, d: 0.42, fill: "24345C" });
      s.addText(t, {
        x: MARGIN + 0.62,
        y: y - 0.08,
        w: CONTENT_W - 0.7,
        h: rowH,
        fontFace: "Calibri",
        fontSize: 13,
        color: "E6ECFA",
        isTextBox: true,
        margin: 0,
        valign: "top",
      });
    });
    pageFooter(s, "Also read", n++);
  }

  // ══════════════════════════════════════════════════════════════════════
  // FULL FEATURE LIST — one-page checklist
  // ══════════════════════════════════════════════════════════════════════
  {
    const s = bgSlide(WHITE);
    moduleHeader(s, {
      eyebrow: "Also read",
      title: "The Complete Feature List",
      what: "Every module in this manual, one page — nothing here that isn't a real, working screen.",
      iconKey: "FiCheckSquare",
    });

    const left = [
      "Membership lifecycle — plans, freeze, transfer, terminate",
      "Renewals — Due & Lapsed, before anyone lapses unnoticed",
      "GST invoicing — sequential numbers, a Discounts tab",
      "Payments & Collections — worst-first, not oldest-first",
      "Money Leaks — audits value given away, not just what's owed",
      "Digital Wallet — balance, top-up, spend",
      "Shop (POS) — Sell, Restock, Stock and Sales, four tabs",
      "Stock analytics — reorder now / dead / overstocked, by product",
      "Attendance & check-in",
      "Classes & schedule",
      "Personal Training — packages and appointments",
      "PT Feedback, Reports & Recognition",
    ];
    const right = [
      "Trainer payouts — computed, never silent",
      "Leads CRM — five-stage pipeline, a default next step for each",
      "Lead workflow & follow-ups — nothing goes quiet unnoticed",
      "Visitors — walk-ins, trials, tours",
      "Referral tracking — who brought whom, and whether it converted",
      "At Risk — real visits behind every flag, never a guess",
      "Analytics — Business, Leads, Retention and Staff in one section",
      "Staff Work — a record of the day, never a leaderboard",
      "Staff accounts — role-based login, deactivate rather than delete",
      "Multi-branch — chain overview, targets, stock transfer",
      "Data import — bring in an old member list safely, in two stages",
      "Every membership change recorded — who did it, and when",
    ];

    const top = 2.05,
      colGap = 0.5,
      colW = (CONTENT_W - colGap) / 2;

    function checklist(items, x) {
      const runs = [];
      items.forEach((t) => {
        runs.push({ text: "✓  ", options: { bold: true, color: GOOD, fontSize: 12.5 } });
        runs.push({ text: t, options: { color: INK, fontSize: 12.5, breakLine: true, paraSpaceAfter: 11 } });
      });
      s.addText(runs, {
        x,
        y: top,
        w: colW,
        h: H - top - 0.6,
        fontFace: "Calibri",
        isTextBox: true,
        margin: 0,
        valign: "top",
      });
    }
    checklist(left, MARGIN);
    checklist(right, MARGIN + colW + colGap);
    s.addShape(pres.ShapeType.line, {
      x: MARGIN + colW + colGap / 2,
      y: top,
      w: 0,
      h: H - top - 0.65,
      line: { color: "E2E6ED", width: 1 },
    });
    pageFooter(s, "Also read", n++);
  }

  // ══════════════════════════════════════════════════════════════════════
  // QUICK REFERENCE
  // ══════════════════════════════════════════════════════════════════════
  {
    const s = bgSlide(WHITE);
    moduleHeader(s, {
      eyebrow: "Also read",
      title: "Quick Reference",
      what: "The fastest way from “I want to…” to the right screen.",
      iconKey: "FiCompass",
    });
    const rows = [
      ["Check somebody in", "Attendance → Check in"],
      ["Add a new member", "Members → Add Member"],
      ["Take a payment", "Payments → Collect, or the member's page"],
      ["Renew a membership", "Renewals, or member → Renew"],
      ["Raise a GST invoice", "Invoices → New, or from a payment"],
      ["See who needs a call today", "At Risk → Run scan"],
      ["Sell a protein tub", "Shop → Sell"],
      ["Book a PT session", "Personal Training → Book appointment"],
      ["Log PT feedback", "Session → Log feedback, or Member → Add feedback"],
      ["Recognize a member", "Member → Recognize member"],
      ["See a trainer's report", "Trainers → tap the trainer"],
      ["Bring in my old member list", "Import data"],
      ["Chase overdue payments", "Payments → Collections"],
      ["Find PT or billing given away unbilled", "Money Leaks"],
      ["Top up or spend a member's wallet", "Member's page → Wallet"],
      ["See who did what today", "Analytics → Staff"],
      ["See revenue and other charts", "Analytics → Business"],
    ];
    const header = [
      { text: "I want to…", options: { bold: true, color: WHITE, fill: { color: NAVY } } },
      { text: "Go to", options: { bold: true, color: WHITE, fill: { color: NAVY } } },
    ];
    const body = rows.map(([a, b]) => [
      { text: a, options: { color: INK, fontSize: 10.5 } },
      { text: b, options: { color: STEEL, fontSize: 10.5, bold: true } },
    ]);
    s.addTable([header, ...body], {
      x: MARGIN,
      y: 1.9,
      w: CONTENT_W,
      colW: [5.6, CONTENT_W - 5.6],
      fontFace: "Calibri",
      border: { type: "solid", color: "E2E6ED", pt: 0.75 },
      autoPage: false,
      valign: "middle",
      rowH: 0.27,
    });
    pageFooter(s, "Also read", n++);
  }

  // ══════════════════════════════════════════════════════════════════════
  // CLOSING
  // ══════════════════════════════════════════════════════════════════════
  {
    const s = bgSlide(NAVY);
    s.addShape(pres.ShapeType.ellipse, {
      x: -2,
      y: 3.5,
      w: 6,
      h: 6,
      fill: { color: "1B2C50" },
      line: { type: "none" },
    });
    iconCircle(s, "FiHeart", { x: MARGIN, y: 1.9, d: 0.9, fill: CORAL });
    s.addText("People leave a gym when the habit breaks, not when they decide to quit — and the habit breaks weeks earlier.", {
      x: MARGIN,
      y: 3.0,
      w: 10.6,
      h: 1.6,
      fontFace: "Cambria",
      fontSize: 28,
      bold: true,
      color: WHITE,
      isTextBox: true,
      margin: 0,
    });
    s.addText(
      "That's what First 90 Days and Routine Has Broken are looking for — both arithmetic on your own check-in records: nothing invented, nothing guessed, every flag traceable to real visits.",
      {
        x: MARGIN,
        y: 4.75,
        w: 9.8,
        h: 0.9,
        fontFace: "Calibri",
        fontSize: 14,
        color: "CADCFC",
        isTextBox: true,
        margin: 0,
      }
    );
    s.addText("The one thing the software cannot do is make the phone call.", {
      x: MARGIN,
      y: 5.75,
      w: 9.8,
      h: 0.5,
      fontFace: "Calibri",
      fontSize: 14,
      italic: true,
      color: CORAL,
      isTextBox: true,
      margin: 0,
    });
  }

  await pres.writeFile({ fileName: "regulars-manual.pptx" });
  console.log("wrote regulars-manual.pptx");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
