package activation

import (
	"context"
	"time"
)

type Service struct {
	repo *Repository
}

func NewService(repo *Repository) *Service { return &Service{repo: repo} }

// ScanResult is what the owner sees after a scan.
type ScanResult struct {
	// Members inside their first 90 days.
	InProgramme int `json:"in_programme"`
	OnTrack     int `json:"on_track"`
	Frozen      int `json:"frozen"`

	NeverStarted int `json:"never_started"`
	SlowStart    int `json:"slow_start"`
	GoingQuiet   int `json:"going_quiet"`

	AlertsRaised   int64 `json:"alerts_raised"`
	AlertsResolved int64 `json:"alerts_resolved"`
}

// Scan evaluates everyone in their first 90 days, raises the one alert each
// member needs, and closes the ones that no longer describe them.
func (s *Service) Scan(ctx context.Context) (*ScanResult, error) {
	today := time.Now()

	members, err := s.repo.LoadCohort(ctx, today)
	if err != nil {
		return nil, err
	}

	result := &ScanResult{InProgramme: len(members)}

	var alerts []NewAlert
	var stale []StaleAlert

	for _, m := range members {
		a := Evaluate(m, today)

		switch a.State {
		case StateFrozen:
			result.Frozen++
			// Frozen members keep no open activation alert — whatever was
			// raised before the freeze is no longer a fair thing to chase.
			stale = append(stale, StaleAlert{MemberID: m.ID})
			continue
		case StateOnTrack:
			result.OnTrack++
			stale = append(stale, StaleAlert{MemberID: m.ID})
			continue
		case StateNoFirstVisit:
			result.NeverStarted++
		case StateSlowStart:
			result.SlowStart++
		case StateGoingQuiet:
			result.GoingQuiet++
		default:
			continue
		}

		alerts = append(alerts, NewAlert{
			MemberID: m.ID,
			Type:     a.State,
			Severity: a.State.Severity(),
			Message:  a.Message(m.Name),
		})
		// Close any other activation alert this member holds, so a member
		// moving between states never occupies two rows (FR-10 §3).
		stale = append(stale, StaleAlert{MemberID: m.ID, Except: a.State})
	}

	// Resolve before raising: if a member moved from slow start to going
	// quiet, the old row must close in the same scan the new one opens.
	resolvedStale, err := s.repo.ResolveStale(ctx, stale)
	if err != nil {
		return nil, err
	}
	// Members who aged out or left are no longer loaded at all, so their old
	// alerts have to be closed separately or they would sit open forever.
	resolvedGrad, err := s.repo.ResolveGraduated(ctx, today)
	if err != nil {
		return nil, err
	}
	// Generic inactivity alerts held by members in this programme are stale by
	// definition — the activation alert tells the same member's story better
	// (FR-10 §4).
	resolvedGeneric, err := s.repo.ResolveSupersededInactivity(ctx, today)
	if err != nil {
		return nil, err
	}
	result.AlertsResolved = resolvedStale + resolvedGrad + resolvedGeneric

	if result.AlertsRaised, err = s.repo.RaiseAlerts(ctx, alerts); err != nil {
		return nil, err
	}
	return result, nil
}

func (s *Service) ListAlerts(ctx context.Context) ([]AlertRow, error) {
	rows, err := s.repo.ListAlerts(ctx)
	if err != nil {
		return nil, err
	}
	if rows == nil {
		rows = []AlertRow{}
	}
	return rows, nil
}

func (s *Service) Funnel(ctx context.Context, months int) ([]CohortRow, error) {
	if months <= 0 || months > 24 {
		months = 6
	}
	rows, err := s.repo.Funnel(ctx, months)
	if err != nil {
		return nil, err
	}
	if rows == nil {
		rows = []CohortRow{}
	}
	return rows, nil
}
