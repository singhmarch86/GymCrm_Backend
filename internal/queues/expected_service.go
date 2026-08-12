package queues

import (
	"context"
	"time"

	"gymcrm/internal/staffwork"
)

// Expected assembles the expected-payments view for a span.
func (s *Service) Expected(
	ctx context.Context, rng staffwork.Range,
) (*ExpectedPayments, error) {
	byMonth := rng.Days() > BucketByMonth

	totals, err := s.repo.ExpectedTotals(ctx, rng)
	if err != nil {
		return nil, err
	}
	rows, err := s.repo.ExpectedItems(ctx, rng)
	if err != nil {
		return nil, err
	}
	buckets, err := s.repo.ExpectedBuckets(ctx, rng, byMonth)
	if err != nil {
		return nil, err
	}

	out := &ExpectedPayments{
		From:        rng.FromString(),
		To:          rng.ToString(),
		Days:        rng.Days(),
		IsSingleDay: rng.IsSingleDay(),

		RaisedCount:     totals.RaisedCount,
		RaisedInPaise:   totals.RaisedInPaise,
		ExpiringCount:   totals.ExpiringCount,
		ExpiringInPaise: totals.ExpiringInPaise,

		BucketUnit: "day",
		Buckets:    fillBuckets(rng, buckets, byMonth),
		Items:      make([]ExpectedItem, 0, len(rows)),
	}
	if byMonth {
		out.BucketUnit = "month"
	}

	if len(rows) > ExpectedItemLimit {
		rows = rows[:ExpectedItemLimit]
		out.Truncated = true
	}

	for _, r := range rows {
		item := ExpectedItem{
			Kind:          r.Kind,
			MemberID:      r.MemberID,
			Member:        r.Member,
			Phone:         r.Phone,
			AmountInPaise: r.AmountInPaise,
			Estimated:     r.Kind == KindExpiring,
			Date:          r.Date,
			PaymentID:     r.PaymentID,
			PlanName:      r.PlanName,
			LastVisitAt:   r.LastVisitAt,
			OwedInPaise:   r.OwedInPaise,
		}
		out.Items = append(out.Items, item)
	}

	return out, nil
}

// fillBuckets turns the rows SQL returned into a gap-free series.
//
// A day with nothing due is absent from a GROUP BY, and a chart that simply
// skips it draws a continuous line over a quiet week — which is the one thing
// the shape of a span is supposed to reveal.
func fillBuckets(
	rng staffwork.Range, found []ExpectedBucket, byMonth bool,
) []ExpectedBucket {
	byKey := make(map[string]ExpectedBucket, len(found))
	for _, b := range found {
		byKey[b.Key] = b
	}

	out := make([]ExpectedBucket, 0, len(found)+1)

	cur := time.Date(rng.From.Year(), rng.From.Month(), rng.From.Day(),
		0, 0, 0, 0, staffwork.IST)
	end := time.Date(rng.To.Year(), rng.To.Month(), rng.To.Day(),
		0, 0, 0, 0, staffwork.IST)

	if byMonth {
		cur = time.Date(cur.Year(), cur.Month(), 1, 0, 0, 0, 0, staffwork.IST)
	}

	for !cur.After(end) {
		key := cur.Format("2006-01-02")
		b, ok := byKey[key]
		if !ok {
			b = ExpectedBucket{Key: key}
		}
		b.Label = bucketLabel(cur, byMonth)
		out = append(out, b)

		if byMonth {
			cur = cur.AddDate(0, 1, 0)
		} else {
			cur = cur.AddDate(0, 0, 1)
		}
	}
	return out
}

func bucketLabel(d time.Time, byMonth bool) string {
	if byMonth {
		return d.Format("Jan 2006")
	}
	return d.Format("2 Jan")
}
