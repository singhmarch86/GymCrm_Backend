package leads

import (
	"context"
	"fmt"
	"strings"
	"time"
)

// ─── Timeline ─────────────────────────────────────────────────────────────────

func (s *Service) ListActivities(
	ctx context.Context, leadID int64, activityType, outcome string,
) ([]LeadActivity, error) {
	lead, err := s.repo.FindByID(ctx, leadID)
	if err != nil {
		return nil, fmt.Errorf("list activities: %w", err)
	}
	if lead == nil {
		return nil, ErrLeadNotFound
	}

	// Reject an unknown filter rather than returning an empty timeline. A
	// typo'd value silently matching nothing looks identical to "this lead has
	// no history", which is the wrong thing to conclude about a lead.
	if activityType != "" && !IsValidActivityType(activityType) {
		return nil, ErrInvalidActivityType
	}
	if outcome != "" && !IsValidOutcome(outcome) {
		return nil, ErrInvalidOutcome
	}

	out, err := s.repo.ListActivities(ctx, leadID, activityType, outcome)
	if err != nil {
		return nil, fmt.Errorf("list activities: %w", err)
	}
	return out, nil
}

// AddActivity records a manual timeline entry (a logged call, a note, a
// rescheduled follow-up). Entries that represent pipeline history —
// stage changes, creation, conversion — are written by the server and cannot
// be submitted here; see IsValidActivityType.
//
// When the entry carries a date (follow_up_set / trial_scheduled) the
// corresponding column on the lead is updated too, so the follow-up queue and
// the timeline never drift apart.
func (s *Service) AddActivity(ctx context.Context, leadID int64, req AddActivityRequest) (*LeadActivity, error) {
	lead, err := s.repo.FindByID(ctx, leadID)
	if err != nil {
		return nil, fmt.Errorf("add activity: %w", err)
	}
	if lead == nil {
		return nil, ErrLeadNotFound
	}

	if !IsValidActivityType(req.Type) {
		return nil, ErrInvalidActivityType
	}

	activity := &LeadActivity{
		LeadID: leadID,
		Type:   ActivityType(req.Type),
		Note:   strPtrOrNil(strings.TrimSpace(req.Note)),
	}

	// Outcome is optional (FR-16 §3) but never invented: absent stays absent
	// rather than becoming a default that would misreport work nobody did.
	if raw := strings.TrimSpace(req.Outcome); raw != "" {
		if !IsValidOutcome(raw) {
			return nil, ErrInvalidOutcome
		}
		if !ActivityType(req.Type).AcceptsOutcome() {
			return nil, ErrOutcomeNotAllowed
		}
		o := ActivityOutcome(raw)
		activity.Outcome = &o
	}

	if err := s.repo.LogActivity(ctx, activity); err != nil {
		return nil, fmt.Errorf("add activity: %w", err)
	}

	// Keep the lead's own date columns in step with the entry just logged.
	updates := map[string]interface{}{}
	switch ActivityType(req.Type) {
	case ActivityFollowUpSet:
		if d := parseDate(req.Date); d != nil {
			updates["follow_up_date"] = *d
		}
	case ActivityTrialScheduled:
		if d := parseDate(req.Date); d != nil {
			updates["trial_date"] = *d
		}
	}
	if len(updates) > 0 {
		if err := s.repo.Update(ctx, leadID, updates); err != nil {
			return nil, fmt.Errorf("add activity: sync lead dates: %w", err)
		}
	}

	return activity, nil
}

// ─── Assignees ────────────────────────────────────────────────────────────────

func (s *Service) ListAssignees(ctx context.Context) ([]Assignee, error) {
	out, err := s.repo.ListAssignees(ctx)
	if err != nil {
		return nil, fmt.Errorf("list assignees: %w", err)
	}
	return out, nil
}

// AssignLead sets (or clears, when userID is nil) a lead's owner and records
// it on the timeline so reassignments are auditable.
func (s *Service) AssignLead(ctx context.Context, leadID int64, userID *int64) (*LeadResponse, error) {
	lead, err := s.repo.FindByID(ctx, leadID)
	if err != nil {
		return nil, fmt.Errorf("assign lead: %w", err)
	}
	if lead == nil {
		return nil, ErrLeadNotFound
	}

	if err := s.repo.Update(ctx, leadID, map[string]interface{}{
		"assigned_user_id": userID,
	}); err != nil {
		return nil, fmt.Errorf("assign lead: save: %w", err)
	}

	updated, err := s.repo.FindByID(ctx, leadID)
	if err != nil || updated == nil {
		return nil, fmt.Errorf("assign lead: re-fetch: %w", err)
	}

	note := "Unassigned"
	if updated.AssignedUserName != "" {
		note = "Assigned to " + updated.AssignedUserName
	}
	_ = s.repo.LogActivity(ctx, &LeadActivity{
		LeadID: leadID,
		Type:   ActivityNote,
		Note:   &note,
	})

	resp := toLeadResponse(updated)
	return &resp, nil
}

// ─── Follow-up queue ──────────────────────────────────────────────────────────

func (s *Service) GetFollowUps(ctx context.Context) (*FollowUpResponse, error) {
	buckets, err := s.repo.GetFollowUps(ctx)
	if err != nil {
		return nil, fmt.Errorf("follow-ups: %w", err)
	}

	// A week: long enough that a quiet Tuesday does not read as a collapse,
	// short enough to still describe how the phone work is going now.
	const outcomeWindowDays = 7
	outcomes, err := s.repo.OutcomeCounts(ctx, outcomeWindowDays)
	if err != nil {
		return nil, fmt.Errorf("follow-ups: outcome counts: %w", err)
	}

	return &FollowUpResponse{
		Overdue:  toLeadResponseList(buckets.Overdue),
		Today:    toLeadResponseList(buckets.Today),
		Upcoming: toLeadResponseList(buckets.Upcoming),
		Trials:   toLeadResponseList(buckets.Trials),
		Counts: FollowUpCounts{
			Overdue:  len(buckets.Overdue),
			Today:    len(buckets.Today),
			Upcoming: len(buckets.Upcoming),
			Trials:   len(buckets.Trials),
		},
		GeneratedAt:   time.Now().UTC(),
		OutcomeCounts: outcomes,
		OutcomeDays:   outcomeWindowDays,
	}, nil
}

// ─── Analytics ────────────────────────────────────────────────────────────────

func (s *Service) GetAnalytics(ctx context.Context) (*AnalyticsResponse, error) {
	data, err := s.repo.GetAnalytics(ctx)
	if err != nil {
		return nil, fmt.Errorf("lead analytics: %w", err)
	}

	// Index the raw per-status counts so the funnel can be emitted in
	// PipelineOrder with zero-filled gaps — the client should never have to
	// know the stage ordering or handle a missing stage.
	counts := make(map[string]int64, len(data.Funnel))
	for _, f := range data.Funnel {
		counts[f.Status] = f.Count
	}
	durations := make(map[string]float64, len(data.StageDuration))
	for _, d := range data.StageDuration {
		durations[d.Status] = d.AvgDays
	}

	// The funnel is cumulative-by-progression: a lead now sitting at "joined"
	// necessarily passed through every earlier stage, so each stage's reach is
	// itself plus everything downstream of it. Counting only leads *currently*
	// in a stage would make the funnel widen and narrow arbitrarily instead of
	// decreasing monotonically. "lost" is excluded from the chain — it is an
	// exit, not a step forward — and reported separately.
	progression := []LeadStatus{
		LeadStatusNew,
		LeadStatusContacted,
		LeadStatusTrialScheduled,
		LeadStatusTrialCompleted,
		LeadStatusJoined,
	}

	funnel := make([]FunnelStageResponse, 0, len(progression))
	var firstStageTotal int64
	for i, status := range progression {
		var reached int64
		for _, downstream := range progression[i:] {
			reached += counts[string(downstream)]
		}
		if i == 0 {
			firstStageTotal = reached
		}

		stage := FunnelStageResponse{
			Status:  string(status),
			Label:   labelForStatus(status),
			Count:   reached,
			AvgDays: durations[string(status)],
		}

		// Conversion from the previous stage — the drop-off the gym can act on.
		if i > 0 {
			var prevReached int64
			for _, downstream := range progression[i-1:] {
				prevReached += counts[string(downstream)]
			}
			if prevReached > 0 {
				stage.StepConversion = round1(100 * float64(reached) / float64(prevReached))
			}
		}
		// Conversion from the top of the funnel.
		if firstStageTotal > 0 {
			stage.OverallConversion = round1(100 * float64(reached) / float64(firstStageTotal))
		}

		funnel = append(funnel, stage)
	}

	resp := &AnalyticsResponse{
		Funnel:      funnel,
		LostCount:   counts[string(LeadStatusLost)],
		BySource:    make([]SourcePerformanceResponse, 0, len(data.BySource)),
		LostReasons: make([]LostReasonResponse, 0, len(data.LostReasons)),
	}

	for _, src := range data.BySource {
		resp.BySource = append(resp.BySource, SourcePerformanceResponse{
			Source:         src.Source,
			Label:          labelForSource(LeadSource(src.Source)),
			Total:          src.Total,
			Joined:         src.Joined,
			Lost:           src.Lost,
			ConversionRate: round1(src.ConvRate),
		})
	}

	for _, lr := range data.LostReasons {
		resp.LostReasons = append(resp.LostReasons, LostReasonResponse{
			Reason: lr.Reason,
			Count:  lr.Count,
		})
	}

	return resp, nil
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

func round1(v float64) float64 {
	return float64(int64(v*10+0.5)) / 10
}

func strPtrOrNil(s string) *string {
	if strings.TrimSpace(s) == "" {
		return nil
	}
	return &s
}

func labelForStatus(s LeadStatus) string {
	switch s {
	case LeadStatusNew:
		return "New Lead"
	case LeadStatusContacted:
		return "Contacted"
	case LeadStatusTrialScheduled:
		return "Trial Scheduled"
	case LeadStatusTrialCompleted:
		return "Trial Completed"
	case LeadStatusJoined:
		return "Joined"
	case LeadStatusLost:
		return "Lost"
	}
	return string(s)
}

func labelForSource(s LeadSource) string {
	switch s {
	case LeadSourceWalkIn:
		return "Walk-in"
	case LeadSourceReferral:
		return "Referral"
	case LeadSourceInstagram:
		return "Instagram"
	case LeadSourceFacebook:
		return "Facebook"
	case LeadSourceGoogle:
		return "Google"
	case LeadSourceWhatsApp:
		return "WhatsApp"
	case LeadSourceWebsite:
		return "Website"
	case LeadSourceOther:
		return "Other"
	}
	return string(s)
}
