package leads

import (
	"context"
	"fmt"
	"time"
)

// IST is the gym's day. Fixed offset rather than a tzdata lookup, matching
// staffwork and the rhythm detector — the binary must keep working in a
// scratch container with no zoneinfo.
var workflowIST = time.FixedZone("IST", 5*60*60+30*60)

// WorkflowItem is one lead in the queue, with everything the desk needs to act
// without opening it.
type WorkflowItem struct {
	LeadID     int64  `json:"lead_id"`
	Name       string `json:"name"`
	Phone      string `json:"phone"`
	Status     string `json:"status"`
	StageLabel string `json:"stage_label"`

	// How long it has been in this stage. Stuck is not a status (FR-18 §5).
	StageDays int `json:"stage_days"`

	NextStep      *string    `json:"next_step,omitempty"`
	NextStepLabel *string    `json:"next_step_label,omitempty"`
	NextStepDue   *time.Time `json:"next_step_due,omitempty"`

	OwnerID   *int64  `json:"owner_id,omitempty"`
	OwnerName *string `json:"owner_name,omitempty"`

	// Why this lead is where it is, so the UI never has to re-derive it and
	// cannot disagree with the server about who is overdue.
	State       string `json:"state"`
	DaysOverdue int    `json:"days_overdue,omitempty"`
}

// WorkflowGroup is one bucket of the queue.
type WorkflowGroup struct {
	State string         `json:"state"`
	Label string         `json:"label"`
	Count int            `json:"count"`
	Items []WorkflowItem `json:"items"`
}

// WorkflowResponse backs GET /api/v1/leads/workflow.
type WorkflowResponse struct {
	Groups []WorkflowGroup `json:"groups"`

	// Headline numbers, computed here so every client shows the same ones.
	TotalOpen  int `json:"total_open"`
	Unattended int `json:"unattended"`
	Overdue    int `json:"overdue"`
	DueToday   int `json:"due_today"`

	GeneratedAt time.Time `json:"generated_at"`
}

// groupOrder is urgency order, and Unattended leads it deliberately: a lead
// nobody has picked up is a worse failure than one being chased late.
var groupOrder = []WorkflowState{
	StateUnattended, StateOverdue, StateToday, StateUpcoming,
}

// GetWorkflow builds the queue.
func (s *Service) GetWorkflow(ctx context.Context, assignedTo string) (*WorkflowResponse, error) {
	rows, err := s.repo.WorkflowLeads(ctx, assignedTo)
	if err != nil {
		return nil, fmt.Errorf("workflow: %w", err)
	}

	now := time.Now().In(workflowIST)
	buckets := map[WorkflowState][]WorkflowItem{}

	for i := range rows {
		row := rows[i]
		state := StateOf(&row.Lead, now)

		item := WorkflowItem{
			LeadID:      row.ID,
			Name:        row.Name,
			Phone:       row.Phone,
			Status:      string(row.Status),
			StageLabel:  stageLabel(row.Status),
			StageDays:   row.StageDays,
			NextStep:    row.NextStep,
			NextStepDue: row.NextStepDue,
			OwnerID:     row.AssignedUserID,
			State:       string(state),
		}
		if row.NextStep != nil && *row.NextStep != "" {
			label := NextStep(*row.NextStep).Label()
			item.NextStepLabel = &label
		}
		if row.AssignedUserName != nil && *row.AssignedUserName != "" {
			item.OwnerName = row.AssignedUserName
		}
		if state == StateOverdue && row.NextStepDue != nil {
			due := row.NextStepDue.In(workflowIST)
			item.DaysOverdue = int(now.Sub(due).Hours() / 24)
		}

		buckets[state] = append(buckets[state], item)
	}

	out := &WorkflowResponse{Groups: []WorkflowGroup{}, GeneratedAt: time.Now().UTC()}
	for _, st := range groupOrder {
		items := buckets[st]
		// Every group is returned, including empty ones. "0 unattended" is the
		// single most useful thing this screen can say, and a group that
		// vanishes when it hits zero denies the reader that sentence.
		out.Groups = append(out.Groups, WorkflowGroup{
			State: string(st),
			Label: st.Label(),
			Count: len(items),
			Items: items,
		})
		out.TotalOpen += len(items)
	}

	out.Unattended = len(buckets[StateUnattended])
	out.Overdue = len(buckets[StateOverdue])
	out.DueToday = len(buckets[StateToday])

	return out, nil
}

// SetNextStep records what happens next for one lead.
//
// Clearing is allowed (both fields empty) but partial is not: a step with no
// date is invisible to every queue, so accepting one would quietly create the
// exact failure FR-18 exists to remove.
func (s *Service) SetNextStep(
	ctx context.Context, leadID int64, step string, dueStr string,
) (*LeadResponse, error) {
	lead, err := s.repo.FindByID(ctx, leadID)
	if err != nil {
		return nil, fmt.Errorf("set next step: %w", err)
	}
	if lead == nil {
		return nil, ErrLeadNotFound
	}

	// A closed lead carries no next step (FR-18 §6). Refusing here rather than
	// silently ignoring it: a client trying this has a bug worth surfacing.
	if lead.Status == LeadStatusJoined || lead.Status == LeadStatusLost {
		return nil, ErrLeadClosed
	}

	if step == "" && dueStr == "" {
		if err := s.repo.SetNextStep(ctx, leadID, nil, nil); err != nil {
			return nil, fmt.Errorf("set next step: %w", err)
		}
		return s.GetLead(ctx, leadID)
	}

	if !IsValidNextStep(step) {
		return nil, ErrInvalidNextStep
	}
	due := parseDate(dueStr)
	if due == nil {
		return nil, ErrNextStepDueRequired
	}

	if err := s.repo.SetNextStep(ctx, leadID, &step, due); err != nil {
		return nil, fmt.Errorf("set next step: %w", err)
	}
	return s.GetLead(ctx, leadID)
}

// SuggestForOutcome returns the step that usually follows an outcome, so the
// client can offer it pre-filled. Advisory only — nothing is written until the
// staff member confirms (FR-18 §3).
func (s *Service) SuggestForOutcome(outcome string, callBack *time.Time) (*Suggestion, bool) {
	if !IsValidOutcome(outcome) {
		return nil, false
	}
	sug, ok := SuggestNext(ActivityOutcome(outcome), time.Now().In(workflowIST), callBack)
	if !ok {
		return nil, false
	}
	return &sug, true
}

func stageLabel(s LeadStatus) string {
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
