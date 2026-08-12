package queues

import "context"

// Leakage runs every check and groups the findings.
//
// Empty groups are kept. "No sessions given away this month" is one of the
// more useful sentences this screen can say, and a heading that disappears at
// zero denies the reader that — the same rule the other queues follow.
func (s *Service) Leakage(ctx context.Context) (*LeakageReport, error) {
	oversold, err := s.repo.OversoldPT(ctx)
	if err != nil {
		return nil, err
	}
	drift, err := s.repo.SessionDrift(ctx)
	if err != nil {
		return nil, err
	}
	expired, err := s.repo.TrainingAfterExpiry(ctx)
	if err != nil {
		return nil, err
	}
	unpaid, err := s.repo.UnpaidMemberships(ctx)
	if err != nil {
		return nil, err
	}
	invoices, err := s.repo.UncollectedInvoices(ctx)
	if err != nil {
		return nil, err
	}

	out := &LeakageReport{Groups: []LeakGroup{
		buildGroup(LeakOversoldPT,
			"Sessions given away",
			"Personal training delivered beyond what the package paid for. "+
				"Cancelled bookings are not counted. Valued at the rate this "+
				"member actually paid, not the list price.",
			"urgent", oversold, oversoldDetail),

		buildGroup(LeakTrainingExpired,
			"Training after expiry",
			"Members who kept checking in after their membership ran out. "+
				"Frozen memberships are excluded — those are paused on "+
				"purpose. Valued at their own plan's daily rate, which is "+
				"deliberately less than a walk-in would pay.",
			"urgent", expired, expiredDetail),

		buildGroup(LeakUnpaidMembership,
			"Members who never paid",
			"Active memberships with no payment recorded at all — not paid, "+
				"and not even raised as a due. A member with an unpaid due is "+
				"not here; that one is already being chased in Collect. These "+
				"are the ones nobody wrote down. Valued at their plan price.",
			"urgent", unpaid, unpaidDetail),

		buildGroup(LeakUncollectedInvoice,
			"Invoices with nothing against them",
			"Issued invoices carrying no payment row of any kind. Invoices "+
				"raised from a due are excluded on purpose — that due is "+
				"already counted in Collect, and listing it twice would "+
				"inflate the figure above.",
			"warn", invoices, invoiceDetail),

		buildGroup(LeakSessionDrift,
			"Counters that disagree",
			"A package's used-session count does not match its completed "+
				"bookings. Not a loss on its own — it is how one hides, "+
				"because the counter stops at the limit while sessions keep "+
				"being booked.",
			"warn", drift, driftDetail),
	}}

	for _, g := range out.Groups {
		out.TotalCount += len(g.Items)
		out.ValuedInPaise += g.ValueInPaise
		for _, i := range g.Items {
			if i.ValueInPaise == 0 {
				out.UnvaluedCount++
			}
		}
	}
	return out, nil
}

func buildGroup(
	kind, label, note, severity string,
	rows []leakRow,
	detail func(leakRow) (string, string),
) LeakGroup {
	g := LeakGroup{
		Kind:     kind,
		Label:    label,
		Note:     note,
		Severity: severity,
		Items:    make([]LeakItem, 0, len(rows)),
	}
	for _, row := range rows {
		text, basis := detail(row)
		g.Items = append(g.Items, LeakItem{
			Kind:         kind,
			MemberID:     row.MemberID,
			Member:       row.Member,
			Phone:        row.Phone,
			TrainerID:    row.TrainerID,
			Trainer:      row.Trainer,
			Detail:       text,
			Basis:        basis,
			ValueInPaise: row.ValueInPaise,
			Count:        row.Count,
			Since:        row.Since,
			PackageID:    row.PackageID,
		})
		g.ValueInPaise += row.ValueInPaise
	}
	return g
}

func oversoldDetail(r leakRow) (string, string) {
	n := plural(r.Count, "session")
	return r.Extra + " — " + itoa(r.Count) + " " + n + " past the limit",
		"the package's own per-session rate"
}

func expiredDetail(r leakRow) (string, string) {
	n := plural(r.Count, "visit")
	return itoa(r.Count) + " " + n + " after the membership expired",
		"their plan's daily rate"
}

func unpaidDetail(r leakRow) (string, string) {
	plan := r.Extra
	if plan == "" {
		plan = "No plan on record"
	}
	return plan + " — nothing ever recorded", "their plan price"
}

func invoiceDetail(r leakRow) (string, string) {
	if r.Extra == "" {
		return "Issued invoice, nothing collected", "the invoice total"
	}
	return "Invoice " + r.Extra + " — nothing collected", "the invoice total"
}

func driftDetail(r leakRow) (string, string) {
	return r.Extra + " — counter is out by " + itoa(r.Count), ""
}

func plural(n int, word string) string {
	if n == 1 {
		return word
	}
	return word + "s"
}

func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	neg := n < 0
	if neg {
		n = -n
	}
	var b []byte
	for n > 0 {
		b = append([]byte{byte('0' + n%10)}, b...)
		n /= 10
	}
	if neg {
		return "-" + string(b)
	}
	return string(b)
}
