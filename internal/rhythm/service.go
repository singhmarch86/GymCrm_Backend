package rhythm

import (
	"context"
	"errors"
	"time"
)

var ErrBadAsOf = errors.New("as_of must be a date in YYYY-MM-DD format")

type Service struct {
	repo *Repository
}

func NewService(repo *Repository) *Service { return &Service{repo: repo} }

// ScanResult is what the owner sees after running a scan.
type ScanResult struct {
	AsOf string `json:"as_of"`
	// Members with any check-in in the 12-week span.
	Evaluated int `json:"evaluated"`
	// Members who had an established rhythm to break at all (FR-09 §2).
	Eligible int `json:"eligible"`
	// Broken right now, including ones already flagged by an earlier scan.
	Broken int `json:"broken"`
	// New alerts actually written — repeats are discarded by the unique index.
	AlertsRaised int64 `json:"alerts_raised"`
	// Open alerts closed because the member is keeping their slot again.
	AlertsResolved int64 `json:"alerts_resolved"`
}

// Scan analyses every active member's check-in timestamps, stores a rhythm
// profile for each eligible member, raises alerts for broken rhythms, and
// closes alerts for members who have recovered.
func (s *Service) Scan(ctx context.Context, asOfParam string) (*ScanResult, error) {
	asOf := time.Now().In(istLocation)
	if asOfParam != "" {
		// Scanning against a past date is what makes the feature checkable
		// against historical data rather than only "whatever today is".
		parsed, err := time.ParseInLocation("2006-01-02", asOfParam, istLocation)
		if err != nil {
			return nil, ErrBadAsOf
		}
		asOf = parsed.Add(23*time.Hour + 59*time.Minute)
	}

	members, err := s.repo.LoadCheckIns(ctx, asOf)
	if err != nil {
		return nil, err
	}

	result := &ScanResult{AsOf: asOf.Format("2006-01-02"), Evaluated: len(members)}

	var profiles []*Profile
	var alerts []NewAlert
	var recovered []int64

	for _, m := range members {
		p := Analyse(m.MemberID, m.CheckIns, asOf)
		if !p.Eligible() {
			// Not describable as a rhythm, so nothing is stored and nothing is
			// claimed about them. The count-based retention alerts still apply.
			continue
		}
		result.Eligible++
		profiles = append(profiles, p)

		if p.IsBroken {
			result.Broken++
			alerts = append(alerts, NewAlert{
				MemberID: p.MemberID,
				Severity: p.Severity,
				Message:  p.Message(m.Name),
			})
			continue
		}
		if p.Recovered() {
			recovered = append(recovered, p.MemberID)
		}
	}

	if err := s.repo.UpsertProfiles(ctx, asOf, profiles); err != nil {
		return nil, err
	}
	if result.AlertsRaised, err = s.repo.RaiseAlerts(ctx, alerts); err != nil {
		return nil, err
	}
	if result.AlertsResolved, err = s.repo.ResolveRecovered(ctx, recovered); err != nil {
		return nil, err
	}
	return result, nil
}

func (s *Service) ListBreaks(ctx context.Context) ([]BreakRow, error) {
	rows, err := s.repo.ListBreaks(ctx)
	if err != nil {
		return nil, err
	}
	if rows == nil {
		rows = []BreakRow{}
	}

	// Re-render from the current profile, for the same reason activation does.
	//
	// Here the drift is worse than a day count: the profile is recomputed on
	// every scan, so the card's bars can say "5 of 27" while the sentence
	// underneath still says "3 of 21" from whenever the alert was first
	// raised. The stored message stays in the database as the record of what
	// staff were told at the time; this is what they read today.
	for i := range rows {
		p := Profile{
			AnchorMinute:   rows[i].AnchorMinute,
			BaselineVisits: rows[i].BaselineVisits,
			BaselineOnSlot: rows[i].BaselineOnSlot,
			BaselineRate:   rows[i].BaselineRate,
			RecentVisits:   rows[i].RecentVisits,
			RecentOnSlot:   rows[i].RecentOnSlot,
			RecentRate:     rows[i].RecentRate,
		}
		// A member with no stored profile yet keeps the original wording
		// rather than being described with zeroes.
		if rows[i].BaselineVisits > 0 {
			rows[i].Message = p.Message(rows[i].MemberName)
		}
	}
	return rows, nil
}

func (s *Service) GetProfile(ctx context.Context, memberID int64) (*ProfileRow, error) {
	return s.repo.GetProfile(ctx, memberID)
}
