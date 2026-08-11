package leads

import "time"

// ─── Activity ─────────────────────────────────────────────────────────────────

// AddActivityRequest is the payload for POST /api/v1/leads/{id}/activities.
// Only client-loggable types are accepted (call, note, follow_up_set,
// trial_scheduled) — pipeline history is written by the server.
type AddActivityRequest struct {
	Type string `json:"type"` // required
	Note string `json:"note"` // optional
	// Date is only meaningful for follow_up_set / trial_scheduled, where it
	// also updates the matching column on the lead. Format: YYYY-MM-DD.
	Date string `json:"date"`
	// Outcome is what came of it (FR-16). Optional: a note has none, and a
	// staff member mid-shift must never be blocked by a dropdown.
	Outcome string `json:"outcome"`
}

// ActivityListResponse wraps a lead's timeline.
type ActivityListResponse struct {
	Activities []LeadActivity `json:"activities"`
}

// ─── Assignment ───────────────────────────────────────────────────────────────

// AssignRequest is the payload for PATCH /api/v1/leads/{id}/assign.
// A null assigned_user_id clears the assignment.
type AssignRequest struct {
	AssignedUserID *int64 `json:"assigned_user_id"`
}

type AssigneeListResponse struct {
	Assignees []Assignee `json:"assignees"`
}

// ─── Follow-up queue ──────────────────────────────────────────────────────────

type FollowUpCounts struct {
	Overdue  int `json:"overdue"`
	Today    int `json:"today"`
	Upcoming int `json:"upcoming"`
	Trials   int `json:"trials"`
}

// FollowUpResponse backs GET /api/v1/leads/followups — the daily action queue.
type FollowUpResponse struct {
	Overdue     []LeadResponse `json:"overdue"`
	Today       []LeadResponse `json:"today"`
	Upcoming    []LeadResponse `json:"upcoming"`
	Trials      []LeadResponse `json:"trials"`
	Counts      FollowUpCounts `json:"counts"`
	GeneratedAt time.Time      `json:"generated_at"`

	// What the last week of calling produced (FR-16 §6). Always all six
	// outcomes, zeros included, so the row keeps its shape between refreshes.
	OutcomeCounts []OutcomeCount `json:"outcome_counts"`
	OutcomeDays   int            `json:"outcome_days"`
}

// ─── Analytics ────────────────────────────────────────────────────────────────

// FunnelStageResponse is one step of the conversion funnel.
//
// Count is cumulative: how many leads have *reached at least* this stage, so
// the funnel decreases monotonically. StepConversion is the pass-through rate
// from the previous stage (where the drop-off actually happens);
// OverallConversion is relative to the top of the funnel.
type FunnelStageResponse struct {
	Status            string  `json:"status"`
	Label             string  `json:"label"`
	Count             int64   `json:"count"`
	StepConversion    float64 `json:"step_conversion"`    // % of previous stage
	OverallConversion float64 `json:"overall_conversion"` // % of first stage
	AvgDays           float64 `json:"avg_days"`           // avg time spent in this stage
}

type SourcePerformanceResponse struct {
	Source         string  `json:"source"`
	Label          string  `json:"label"`
	Total          int64   `json:"total"`
	Joined         int64   `json:"joined"`
	Lost           int64   `json:"lost"`
	ConversionRate float64 `json:"conversion_rate"`
}

type LostReasonResponse struct {
	Reason string `json:"reason"`
	Count  int64  `json:"count"`
}

// AnalyticsResponse backs GET /api/v1/leads/analytics.
type AnalyticsResponse struct {
	Funnel      []FunnelStageResponse       `json:"funnel"`
	LostCount   int64                       `json:"lost_count"`
	BySource    []SourcePerformanceResponse `json:"by_source"`
	LostReasons []LostReasonResponse        `json:"lost_reasons"`
}
