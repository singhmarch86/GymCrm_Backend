package staffwork

import (
	"context"
	"fmt"
	"time"
)

// Analytics assembles the staff work analytics for a span.
func (s *Service) Analytics(
	ctx context.Context, rng Range,
) (*StaffAnalytics, error) {
	byWeek := rng.Days() > TrendByWeek

	// The comparison window: the same number of days, ending the day before
	// this span starts. Equal length matters — comparing a 31-day month
	// against a 28-day one produces a "drop" that is just February.
	days := rng.Days()
	prevTo := rng.From.AddDate(0, 0, -1)
	prevFrom := prevTo.AddDate(0, 0, -(days - 1))

	trend, err := s.repo.Trend(ctx, rng, byWeek)
	if err != nil {
		return nil, fmt.Errorf("staffwork: trend: %w", err)
	}
	cats, err := s.repo.CategoryTotals(ctx, rng)
	if err != nil {
		return nil, fmt.Errorf("staffwork: categories: %w", err)
	}
	people, err := s.repo.PersonTotals(ctx, rng,
		prevFrom.Format("2006-01-02"), prevTo.Format("2006-01-02"))
	if err != nil {
		return nil, fmt.Errorf("staffwork: people: %w", err)
	}

	out := &StaffAnalytics{
		From:       rng.FromString(),
		To:         rng.ToString(),
		Days:       days,
		TrendUnit:  "day",
		Trend:      fillTrend(rng, trend, byWeek),
		Categories: make([]CategoryTotal, 0, len(cats)),
		People:     make([]PersonTrend, 0, len(people)),
	}
	if byWeek {
		out.TrendUnit = "week"
	}

	for _, p := range out.Trend {
		out.TotalCount += p.Count
		out.TotalAmountInPaise += p.AmountInPaise
		if p.Quiet {
			out.QuietDays++
		}
	}

	for _, c := range cats {
		share := 0
		if out.TotalCount > 0 {
			share = c.Count * 100 / out.TotalCount
		}
		out.Categories = append(out.Categories, CategoryTotal{
			Category:      c.Category,
			Label:         Category(c.Category).Label(),
			Count:         c.Count,
			AmountInPaise: c.AmountInPaise,
			SharePct:      share,
		})
	}

	for _, p := range people {
		if p.UserID == nil {
			// Unattributed work is not a person and must never sit in a list
			// of people — it would read as somebody's output. Reported
			// separately as the data-quality figure it is.
			out.UnattributedCount += p.Count
			continue
		}
		out.People = append(out.People, PersonTrend{
			UserID:        p.UserID,
			Name:          p.Name,
			Role:          p.Role,
			Count:         p.Count,
			AmountInPaise: p.AmountInPaise,
			PreviousCount: p.PreviousCount,
			ChangePct:     changePct(p.PreviousCount, p.Count),
		})
	}

	if out.TotalCount > 0 {
		out.UnattributedPct = out.UnattributedCount * 100 / out.TotalCount
	}

	return out, nil
}

// changePct compares a person to themselves.
//
// Nil when there is nothing to compare against. A new joiner, or somebody
// whose first recorded work falls in this span, is not "down 100%" — and a
// screen that says so about a real person is worse than one that says nothing.
func changePct(previous, current int) *int {
	if previous == 0 {
		return nil
	}
	v := (current - previous) * 100 / previous
	return &v
}

// fillTrend turns the grouped rows into a gap-free series.
//
// A day nobody recorded anything is absent from a GROUP BY, and a chart that
// skips it draws a continuous line across a closed Sunday — hiding the one
// thing a rhythm chart is for.
func fillTrend(rng Range, found []trendRow, byWeek bool) []TrendPoint {
	byKey := make(map[string]trendRow, len(found))
	for _, r := range found {
		byKey[r.Key] = r
	}

	out := make([]TrendPoint, 0, len(found)+1)

	cur := time.Date(rng.From.Year(), rng.From.Month(), rng.From.Day(),
		0, 0, 0, 0, IST)
	end := time.Date(rng.To.Year(), rng.To.Month(), rng.To.Day(),
		0, 0, 0, 0, IST)

	if byWeek {
		// Postgres truncates weeks to Monday; match it or the first bucket
		// never lines up with a returned key.
		for cur.Weekday() != time.Monday {
			cur = cur.AddDate(0, 0, -1)
		}
	}

	for !cur.After(end) {
		key := cur.Format("2006-01-02")
		row := byKey[key]
		out = append(out, TrendPoint{
			Key:           key,
			Label:         trendLabel(cur, byWeek),
			Count:         row.Count,
			AmountInPaise: row.AmountInPaise,
			Quiet:         row.Count == 0,
		})
		if byWeek {
			cur = cur.AddDate(0, 0, 7)
		} else {
			cur = cur.AddDate(0, 0, 1)
		}
	}
	return out
}

func trendLabel(d time.Time, byWeek bool) string {
	if byWeek {
		return "w/c " + d.Format("2 Jan")
	}
	return d.Format("2 Jan")
}
