package staffwork

import (
	"context"
	"sort"
	"time"

	"gymcrm/internal/database"
)

// The per-person lead workflow (FR-18 §7).
//
// Deliberately not the same screen as the Leads workflow queue. That one is a
// worklist — "what do I do next" — and belongs beside the board where the work
// happens. This one answers a different question asked by a different person:
// "is Simran coping?" Moving the queue here would make a receptionist walk
// through a screen about staff to reach their own work.
//
// Two halves, and the distinction matters:
//
//   - What they are CARRYING is a fact about now. It ignores the date filter,
//     because a lead nobody has picked up is unattended today regardless of
//     which day you are looking at.
//   - What they WORKED is scoped to the chosen day. It is a record of activity,
//     and activity has a date.
//
// Mixing the two would produce a number that means neither.

// LeadWorkload is what one person is carrying right now.
type LeadWorkload struct {
	OpenLeads  int `json:"open_leads"`
	Unattended int `json:"unattended"`
	Overdue    int `json:"overdue"`
	DueToday   int `json:"due_today"`

	// The single most useful line on the card: who to call next, and when it
	// was due. Nil when they are carrying nothing scheduled.
	NextLeadID   *int64     `json:"next_lead_id,omitempty"`
	NextLeadName *string    `json:"next_lead_name,omitempty"`
	NextDue      *time.Time `json:"next_due,omitempty"`
}

// LeadFunnel is what one person did on the chosen day.
//
// Not a conversion rate. Rates over one person's single day are noise —
// three trials and one joiner is not "33%", it is three trials and one
// joiner — and a rate invites ranking, which FR-13 §1 exists to prevent.
type LeadFunnel struct {
	Calls        int `json:"calls"`
	Reached      int `json:"reached"`
	Counselling  int `json:"counselling"`
	TrialsBooked int `json:"trials_booked"`
	Joined       int `json:"joined"`
	NotesLogged  int `json:"notes_logged"`
}

// StaffLeadWork is one person's card.
type StaffLeadWork struct {
	UserID *int64  `json:"user_id,omitempty"`
	Name   string  `json:"name"`
	Role   *string `json:"role,omitempty"`

	Carrying LeadWorkload `json:"carrying"`
	Worked   LeadFunnel   `json:"worked"`
}

// LeadWorkReport backs GET /api/v1/staff-work/leads.
type LeadWorkReport struct {
	Date  string          `json:"date"`
	Staff []StaffLeadWork `json:"staff"`

	// Gym-wide, so the owner has the denominator for every card below.
	TotalOpen       int `json:"total_open"`
	TotalUnattended int `json:"total_unattended"`
	TotalOverdue    int `json:"total_overdue"`
}

type workloadRow struct {
	UserID       *int64
	Name         *string
	Role         *string
	OpenLeads    int
	Unattended   int
	Overdue      int
	DueToday     int
	NextLeadID   *int64
	NextLeadName *string
	NextDue      *time.Time
}

// LeadWorkloads returns what each person is carrying, as of now.
func (r *Repository) LeadWorkloads(ctx context.Context, userID *int64) ([]workloadRow, error) {
	tc := database.MustGetTenant(ctx)

	// A lead is unattended when any part of the invariant is missing — step,
	// date or owner (FR-18 §1). The owner check is implicit here: rows with a
	// NULL assigned_user_id group under the nil user, which is exactly where
	// they belong on this screen.
	sql := `
		SELECT l.assigned_user_id AS user_id, u.name, u.role,
		       COUNT(*) AS open_leads,
		       COUNT(*) FILTER (
		           WHERE l.next_step IS NULL OR l.next_step_due IS NULL
		                 OR l.assigned_user_id IS NULL
		       ) AS unattended,
		       COUNT(*) FILTER (
		           WHERE l.next_step_due IS NOT NULL
		                 AND l.next_step_due < CAST(@today AS date)
		       ) AS overdue,
		       COUNT(*) FILTER (
		           WHERE l.next_step_due = CAST(@today AS date)
		       ) AS due_today,
		       nx.id AS next_lead_id, nx.name AS next_lead_name, nx.next_step_due AS next_due
		  FROM leads l
		  LEFT JOIN users u ON u.id = l.assigned_user_id
		  -- Soonest scheduled lead for this owner. LATERAL over the group key
		  -- rather than a window function: one index seek per staff member,
		  -- and there are two of them, not two thousand.
		  LEFT JOIN LATERAL (
		      SELECT id, name, next_step_due
		        FROM leads n
		       WHERE n.gym_id = l.gym_id
		         AND n.deleted_at IS NULL
		         AND n.status NOT IN ('joined', 'lost')
		         AND n.next_step_due IS NOT NULL
		         AND n.assigned_user_id IS NOT DISTINCT FROM l.assigned_user_id
		       ORDER BY n.next_step_due ASC
		       LIMIT 1
		  ) nx ON true
		 WHERE l.gym_id = @gym
		   AND l.deleted_at IS NULL
		   AND l.status NOT IN ('joined', 'lost')
		   AND (CAST(@filter_user AS bigint) IS NULL
		        OR l.assigned_user_id = @filter_user)
		 GROUP BY l.assigned_user_id, u.name, u.role,
		          nx.id, nx.name, nx.next_step_due`

	var rows []workloadRow
	err := r.db.WithContext(ctx).Raw(sql, map[string]interface{}{
		"gym":         tc.GymID(),
		"today":       time.Now().In(IST).Format("2006-01-02"),
		"filter_user": userID,
	}).Scan(&rows).Error
	return rows, err
}

type funnelRow struct {
	UserID  *int64
	Type    string
	Outcome *string
	Count   int
}

// LeadActivityFunnel returns what each person logged on one local day.
func (r *Repository) LeadActivityFunnel(
	ctx context.Context, day time.Time, userID *int64,
) ([]funnelRow, error) {
	tc := database.MustGetTenant(ctx)

	sql := `
		SELECT la.user_id, la.type, la.outcome, COUNT(*) AS count
		  FROM lead_activities la
		 WHERE la.gym_id = @gym
		   AND (la.created_at AT TIME ZONE 'Asia/Kolkata')::date = CAST(@date AS date)
		   AND (CAST(@filter_user AS bigint) IS NULL OR la.user_id = @filter_user)
		 GROUP BY la.user_id, la.type, la.outcome`

	var rows []funnelRow
	err := r.db.WithContext(ctx).Raw(sql, map[string]interface{}{
		"gym":         tc.GymID(),
		"date":        day.Format("2006-01-02"),
		"filter_user": userID,
	}).Scan(&rows).Error
	return rows, err
}

// LeadWork builds the per-person view.
func (s *Service) LeadWork(ctx context.Context, day time.Time) (*LeadWorkReport, error) {
	tc := database.MustGetTenant(ctx)

	// Same visibility rule as the rest of Staff work (FR-13 §7): decided from
	// the caller's own token, never from a query parameter.
	var filter *int64
	if !tc.IsOwner() {
		uid := tc.UserID()
		filter = &uid
	}

	loads, err := s.repo.LeadWorkloads(ctx, filter)
	if err != nil {
		return nil, err
	}
	acts, err := s.repo.LeadActivityFunnel(ctx, day, filter)
	if err != nil {
		return nil, err
	}

	type key struct {
		id    int64
		isNil bool
	}
	byUser := map[key]*StaffLeadWork{}

	get := func(uid *int64, name *string, role *string) *StaffLeadWork {
		k := key{isNil: uid == nil}
		if uid != nil {
			k.id = *uid
		}
		if existing, ok := byUser[k]; ok {
			return existing
		}
		// Leads with no owner are "Nobody" rather than folded into a person —
		// the same rule as unattributed work elsewhere in Staff work.
		entry := &StaffLeadWork{UserID: uid, Name: "Nobody assigned"}
		if name != nil && *name != "" {
			entry.Name = *name
		}
		entry.Role = role
		byUser[k] = entry
		return entry
	}

	report := &LeadWorkReport{Date: day.Format("2006-01-02"), Staff: []StaffLeadWork{}}

	for _, row := range loads {
		e := get(row.UserID, row.Name, row.Role)
		e.Carrying = LeadWorkload{
			OpenLeads:    row.OpenLeads,
			Unattended:   row.Unattended,
			Overdue:      row.Overdue,
			DueToday:     row.DueToday,
			NextLeadID:   row.NextLeadID,
			NextLeadName: row.NextLeadName,
			NextDue:      row.NextDue,
		}
		report.TotalOpen += row.OpenLeads
		report.TotalUnattended += row.Unattended
		report.TotalOverdue += row.Overdue
	}

	for _, row := range acts {
		e := get(row.UserID, nil, nil)
		switch row.Type {
		case "call":
			e.Worked.Calls += row.Count
			// Reached means somebody actually spoke to them. A call that rang
			// out is work done and worth counting, but it is not contact, and
			// conflating the two would make a bad day look like a good one.
			if row.Outcome != nil &&
				(*row.Outcome == "answered" || *row.Outcome == "interested") {
				e.Worked.Reached += row.Count
			}
		case "counselling":
			e.Worked.Counselling += row.Count
		case "trial_scheduled":
			e.Worked.TrialsBooked += row.Count
		case "converted":
			e.Worked.Joined += row.Count
		case "note":
			e.Worked.NotesLogged += row.Count
		}
	}

	for _, e := range byUser {
		report.Staff = append(report.Staff, *e)
	}

	// By name, never by output (FR-13 §9). Sorting by conversions would turn
	// this into a leaderboard on every load, and this is the screen where that
	// risk is highest — it is the one an owner reads about people.
	sort.Slice(report.Staff, func(i, j int) bool {
		a, b := report.Staff[i], report.Staff[j]
		if (a.UserID == nil) != (b.UserID == nil) {
			return b.UserID == nil
		}
		return a.Name < b.Name
	})

	return report, nil
}
