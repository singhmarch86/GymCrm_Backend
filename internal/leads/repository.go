package leads

import (
	"context"
	"errors"
	"strconv"
	"strings"
	"time"

	"gorm.io/gorm"
	"gorm.io/gorm/clause"

	"gymcrm/internal/database"
	"gymcrm/internal/shared/pagination"
)

type Repository struct {
	db *gorm.DB
}

func NewRepository(db *gorm.DB) *Repository {
	return &Repository{db: db}
}

// ─── Create ───────────────────────────────────────────────────────────────────

func (r *Repository) Create(ctx context.Context, lead *Lead) error {
	return database.ScopedDB(ctx, r.db).Create(lead).Error
}

// ─── Read ─────────────────────────────────────────────────────────────────────

func (r *Repository) FindByID(ctx context.Context, id int64) (*Lead, error) {
	tc := database.MustGetTenant(ctx)
	var lead Lead
	err := r.db.WithContext(ctx).
		Table("leads").
		Select(`leads.*, COALESCE(users.name, '') AS assigned_user_name`).
		Joins("LEFT JOIN users ON users.id = leads.assigned_user_id").
		Where("leads.gym_id = ? AND leads.id = ? AND leads.deleted_at IS NULL", tc.GymID(), id).
		First(&lead).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, nil
	}
	return &lead, err
}

// ListRequest holds query params for GET /api/v1/leads.
type ListRequest struct {
	Page     int
	PerPage  int
	Status   string // "" means all
	Source   string // "" means all
	Search   string // name or phone

	// AssignedTo filters by owner: a numeric user id, the literal
	// "unassigned" for leads nobody owns, or "" for no filter.
	AssignedTo string
}

func (r *Repository) List(ctx context.Context, req ListRequest) ([]Lead, int64, error) {
	p := pagination.Params{
		Page:    req.Page,
		PerPage: req.PerPage,
		Offset:  (req.Page - 1) * req.PerPage,
	}

	tc := database.MustGetTenant(ctx)
	q := r.db.WithContext(ctx).
		Table("leads").
		Select(`leads.*, COALESCE(users.name, '') AS assigned_user_name`).
		Joins("LEFT JOIN users ON users.id = leads.assigned_user_id").
		Where("leads.gym_id = ? AND leads.deleted_at IS NULL", tc.GymID())

	if req.Status != "" {
		q = q.Where("leads.status = ?", req.Status)
	}
	if req.Source != "" {
		q = q.Where("leads.source = ?", req.Source)
	}
	if req.Search != "" {
		term := "%" + strings.ToLower(req.Search) + "%"
		q = q.Where("LOWER(leads.name) LIKE ? OR leads.phone LIKE ?", term, term)
	}
	if req.AssignedTo == "unassigned" {
		q = q.Where("leads.assigned_user_id IS NULL")
	} else if req.AssignedTo != "" {
		if uid, err := strconv.ParseInt(req.AssignedTo, 10, 64); err == nil {
			q = q.Where("leads.assigned_user_id = ?", uid)
		}
	}

	var total int64
	if err := q.Count(&total).Error; err != nil {
		return nil, 0, err
	}

	var leads []Lead
	err := q.Order("leads.created_at DESC").
		Limit(p.PerPage).
		Offset(p.Offset).
		Scan(&leads).Error

	return leads, total, err
}

// FindPendingFollowUps returns leads whose follow_up_date is today or in the past.
func (r *Repository) FindPendingFollowUps(ctx context.Context) ([]Lead, error) {
	var leads []Lead
	err := database.ScopedDB(ctx, r.db).
		Where("deleted_at IS NULL AND follow_up_date <= CURRENT_DATE AND status NOT IN (?, ?)",
			LeadStatusJoined, LeadStatusLost).
		Order("follow_up_date ASC").
		Find(&leads).Error
	return leads, err
}

// ─── Update ───────────────────────────────────────────────────────────────────

func (r *Repository) Update(ctx context.Context, id int64, updates map[string]interface{}) error {
	return database.ScopedDB(ctx, r.db).
		Model(&Lead{}).
		Where("id = ? AND deleted_at IS NULL", id).
		Updates(updates).Error
}

// ─── Delete ───────────────────────────────────────────────────────────────────

func (r *Repository) SoftDelete(ctx context.Context, id int64) error {
	return database.ScopedDB(ctx, r.db).
		Where("id = ? AND deleted_at IS NULL", id).
		Delete(&Lead{}).Error
}

// ─── Conversion ──────────────────────────────────────────────────────────────

// ConversionInput carries everything the transaction needs.
type ConversionInput struct {
	LeadID          int64
	FirstName       string
	LastName        string
	Phone           string
	Email           string
	Gender          string
	PlanID          int64
	AmountInPaise   int64
	PaymentMode     string
	ReferenceNumber string
	Notes           string
}

// ConvertToMember runs a single atomic transaction:
//  1. Lock and validate the lead
//  2. Create member row
//  3. Create payment + renewal + update member expiry
//     (replicates payments.Repository.CollectPayment logic inline so
//      everything runs inside THIS transaction, not a nested one)
//  4. Set lead.converted_member_id and lead.status = joined
//
// Why inline rather than calling payments.Repository.CollectPayment?
// payments.Repository.CollectPayment opens its OWN gorm.Transaction.
// Nested transactions aren't supported by Postgres in this way — the inner
// COMMIT would commit independently of the outer one. We need one
// transaction that covers all four writes atomically.
func (r *Repository) ConvertToMember(ctx context.Context, in ConversionInput) (int64, error) {
	tc := database.MustGetTenant(ctx)
	var memberID int64

	err := r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		// Step 1: lock and validate the lead
		var lead Lead
		if err := tx.Table("leads").
			Clauses(clause.Locking{Strength: "UPDATE"}).
			Where("id = ? AND gym_id = ? AND deleted_at IS NULL", in.LeadID, tc.GymID()).
			First(&lead).Error; err != nil {
			if errors.Is(err, gorm.ErrRecordNotFound) {
				return ErrLeadNotFound
			}
			return err
		}
		if lead.ConvertedMemberID != nil {
			return ErrAlreadyConverted
		}
		if lead.Status != LeadStatusTrialCompleted && lead.Status != LeadStatusJoined {
			return ErrInvalidLeadForConversion
		}

		// Step 2: create member
		type memberRow struct {
			ID int64
		}
		var newMember struct {
			ID int64
		}

		insertMember := map[string]interface{}{
			"gym_id":     tc.GymID(),
			"first_name": in.FirstName,
			"last_name":  in.LastName,
			"phone":      in.Phone,
			"status":     "active",
		}
		if in.Email != "" {
			insertMember["email"] = in.Email
		}
		if in.Gender != "" {
			insertMember["gender"] = in.Gender
		}

		if err := tx.Table("members").
			Clauses(clause.Returning{Columns: []clause.Column{{Name: "id"}}}).
			Create(insertMember).
			Scan(&newMember).Error; err != nil {
			return err
		}
		memberID = newMember.ID

		// Step 3a: validate plan
		type planRow struct {
			ID           int64
			DurationDays int
			IsActive     bool
		}
		var plan planRow
		if err := tx.Table("membership_plans").
			Select("id, duration_days, is_active").
			Where("id = ? AND gym_id = ? AND deleted_at IS NULL", in.PlanID, tc.GymID()).
			First(&plan).Error; err != nil {
			return err
		}
		if !plan.IsActive {
			return errors.New("plan is inactive")
		}

		// Step 3b: compute expiry (new member, no prior expiry → base = today)
		today := time.Now().UTC().Truncate(24 * time.Hour)
		newExpiry := today.AddDate(0, 0, plan.DurationDays)

		// Step 3c: insert payment
		userID := tc.UserID()
		paidDate := today
		paymentData := map[string]interface{}{
			"gym_id":                tc.GymID(),
			"member_id":             memberID,
			"plan_id":               in.PlanID,
			"amount_in_paise":       in.AmountInPaise,
			"status":                "paid",
			"payment_mode":          in.PaymentMode,
			"paid_date":             paidDate,
			"collected_by_user_id":  userID,
		}
		if in.ReferenceNumber != "" {
			paymentData["reference_number"] = in.ReferenceNumber
		}
		if in.Notes != "" {
			paymentData["notes"] = in.Notes
		}

		var newPayment struct{ ID int64 }
		if err := tx.Table("payments").
			Clauses(clause.Returning{Columns: []clause.Column{{Name: "id"}}}).
			Create(paymentData).
			Scan(&newPayment).Error; err != nil {
			return err
		}

		// Step 3d: insert renewal
		renewalData := map[string]interface{}{
			"gym_id":              tc.GymID(),
			"member_id":           memberID,
			"plan_id":             in.PlanID,
			"amount_paid_in_paise": in.AmountInPaise,
			"new_expiry_date":     newExpiry,
			"renewal_date":        today,
			"renewed_by_user_id":  userID,
		}
		var newRenewal struct{ ID int64 }
		if err := tx.Table("renewals").
			Clauses(clause.Returning{Columns: []clause.Column{{Name: "id"}}}).
			Create(renewalData).
			Scan(&newRenewal).Error; err != nil {
			return err
		}
		// Link renewal → payment
		if err := tx.Table("renewals").
			Where("id = ?", newRenewal.ID).
			Update("payment_id", newPayment.ID).Error; err != nil {
			return err
		}

		// Step 3e: update member plan + expiry
		if err := tx.Table("members").
			Where("id = ?", memberID).
			Updates(map[string]interface{}{
				"membership_plan_id": in.PlanID,
				"expiry_date":        newExpiry,
				"status":             "active",
			}).Error; err != nil {
			return err
		}

		// Step 4: update lead
		if err := tx.Table("leads").
			Where("id = ?", in.LeadID).
			Updates(map[string]interface{}{
				"status":               string(LeadStatusJoined),
				"converted_member_id":  memberID,
			}).Error; err != nil {
			return err
		}

		return nil
	})

	if err != nil {
		return 0, err
	}
	return memberID, nil
}

// ─── Summary (dashboard KPIs) ─────────────────────────────────────────────────

type SummaryData struct {
	TotalLeads       int64
	TodayLeads       int64
	PendingFollowUps int64
	TrialsScheduled  int64
	JoinedCount      int64
	LostCount        int64
	ByStatus         map[string]int64
	BySource         map[string]int64
}

func (r *Repository) GetSummary(ctx context.Context) (*SummaryData, error) {
	tc := database.MustGetTenant(ctx)
	gymID := tc.GymID()
	s := &SummaryData{
		ByStatus: make(map[string]int64),
		BySource: make(map[string]int64),
	}

	type countRow struct{ V int64 }

	count := func(query string, dest *int64, args ...interface{}) error {
		var c countRow
		if err := r.db.WithContext(ctx).Raw(query, args...).Scan(&c).Error; err != nil {
			return err
		}
		// Same omission as the reports repository had: scanning into a local
		// and never assigning it left every lead count at zero, with the
		// queries running fine and no error raised anywhere.
		*dest = c.V
		return nil
	}

	if err := count(`SELECT COUNT(*) AS v FROM leads WHERE gym_id = ? AND deleted_at IS NULL`, &s.TotalLeads, gymID); err != nil {
		return nil, err
	}
	if err := count(`SELECT COUNT(*) AS v FROM leads WHERE gym_id = ? AND deleted_at IS NULL AND DATE(created_at) = CURRENT_DATE`, &s.TodayLeads, gymID); err != nil {
		return nil, err
	}
	if err := count(`SELECT COUNT(*) AS v FROM leads WHERE gym_id = ? AND deleted_at IS NULL AND follow_up_date <= CURRENT_DATE AND status NOT IN ('joined','lost')`, &s.PendingFollowUps, gymID); err != nil {
		return nil, err
	}
	if err := count(`SELECT COUNT(*) AS v FROM leads WHERE gym_id = ? AND deleted_at IS NULL AND status = 'trial_scheduled'`, &s.TrialsScheduled, gymID); err != nil {
		return nil, err
	}
	if err := count(`SELECT COUNT(*) AS v FROM leads WHERE gym_id = ? AND deleted_at IS NULL AND status = 'joined'`, &s.JoinedCount, gymID); err != nil {
		return nil, err
	}
	if err := count(`SELECT COUNT(*) AS v FROM leads WHERE gym_id = ? AND deleted_at IS NULL AND status = 'lost'`, &s.LostCount, gymID); err != nil {
		return nil, err
	}

	// By status
	type groupRow struct {
		Status string
		Count  int64
	}
	var statusRows []groupRow
	if err := r.db.WithContext(ctx).Raw(`
		SELECT status, COUNT(*) AS count FROM leads
		WHERE gym_id = ? AND deleted_at IS NULL
		GROUP BY status
	`, gymID).Scan(&statusRows).Error; err != nil {
		return nil, err
	}
	for _, row := range statusRows {
		s.ByStatus[row.Status] = row.Count
	}

	// By source
	var sourceRows []groupRow
	if err := r.db.WithContext(ctx).Raw(`
		SELECT source AS status, COUNT(*) AS count FROM leads
		WHERE gym_id = ? AND deleted_at IS NULL
		GROUP BY source
	`, gymID).Scan(&sourceRows).Error; err != nil {
		return nil, err
	}
	for _, row := range sourceRows {
		s.BySource[row.Status] = row.Count
	}

	return s, nil
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

func parseDate(s string) *time.Time {
	if s == "" {
		return nil
	}
	t, err := time.Parse(dateLayout, s)
	if err != nil {
		return nil
	}
	return &t
}
