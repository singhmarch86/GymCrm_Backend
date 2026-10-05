package payments

import (
	"context"
	"errors"
	"time"

	"gorm.io/gorm"
	"gorm.io/gorm/clause"

	"gymcrm/internal/database"
	"gymcrm/internal/renewals"
	"gymcrm/internal/shared/pagination"
)

// Repository handles all payments DB operations, plus the one atomic
// "collect payment" transaction that also writes a renewals row and
// updates the member's expiry_date.
//
// TENANT ISOLATION:
//  1. Single-table reads use database.ScopedDB(ctx, r.db)
//  2. Joined queries qualify gym_id as "payments.gym_id" — members and
//     membership_plans also have a gym_id column, so an unqualified
//     WHERE gym_id = ? after a JOIN is ambiguous in Postgres (same class
//     of bug already fixed in renewals/repository.go and
//     members/repository.go's FindDueForRenewal).
//
// WHY THIS PACKAGE WRITES DIRECTLY TO THE renewals TABLE INSTEAD OF CALLING
// renewals.Repository / renewals.Service:
// Every method on renewals.Repository opens its query via
// database.ScopedDB(ctx, r.db), which always runs against that repository's
// own r.db handle — never a transaction handle passed in per-call. There is
// no way to make renewals.Repository.Create() participate in *this*
// package's gorm.DB.Transaction(...) without modifying renewals itself,
// which the project's current instructions explicitly forbid ("do not
// modify existing Renewals architecture"). So CollectPayment below
// duplicates the small, well-understood expiry-calculation logic from
// renewals.Service.CreateRenewal and writes the renewals row directly,
// using renewals.Renewal as the model (imported, not reimplemented) so the
// schema/table stays single-sourced even though the write path is separate.
type Repository struct {
	db *gorm.DB
}

func NewRepository(db *gorm.DB) *Repository {
	return &Repository{db: db}
}

// scopedPaymentsDB qualifies gym_id with the payments table name.
// Required for any query that JOINs members or membership_plans.
func (r *Repository) scopedPaymentsDB(ctx context.Context) *gorm.DB {
	tc := database.MustGetTenant(ctx)
	return r.db.WithContext(ctx).Where("payments.gym_id = ?", tc.GymID())
}

// ─── Collect payment — the one-click transaction ─────────────────────────────

// CollectPaymentInput carries everything needed to run the transaction.
type CollectPaymentInput struct {
	MemberID        int64
	PlanID          int64
	AmountInPaise   int64
	PaymentMode     PaymentMode
	PaidDate        time.Time
	ReferenceNumber string
	Notes           string
}

// CollectPaymentResult is what the transaction produces, handed back to the
// service layer for response mapping.
type CollectPaymentResult struct {
	Payment Payment
	Renewal renewals.Renewal
}

// CollectPayment runs ONE atomic database transaction:
//  1. Validate member exists in this gym (locked for update — avoids a race
//     where two simultaneous renewals for the same member compute the same
//     base expiry date)
//  2. Validate plan exists, is active, in this gym
//  3. Compute new expiry: max(member.expiry_date, today) + plan.duration_days
//     (identical formula to renewals.Service.CreateRenewal — kept in sync
//     manually since the two packages can't share the call without
//     modifying renewals)
//  4. Insert payments row (status='paid') — created first so its ID exists
//     for step 5
//  5. Insert renewals row, then set renewals.payment_id to the row from
//     step 4 (renewal points at payment, not the reverse — see model.go)
//  6. Update members.expiry_date + status='active'
//
// If ANY step fails, the entire transaction rolls back — no orphaned
// renewal, no orphaned payment, no partial expiry update.
func (r *Repository) CollectPayment(ctx context.Context, in CollectPaymentInput) (*CollectPaymentResult, error) {
	tc := database.MustGetTenant(ctx)
	var result CollectPaymentResult

	err := r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		// Step 1: lock and validate member within this gym.
		// "FOR UPDATE" prevents a concurrent collect-payment call for the
		// same member from reading a stale expiry_date before this
		// transaction commits its update.
		type memberRow struct {
			ID         int64
			ExpiryDate *time.Time
		}
		var member memberRow
		err := tx.Table("members").
			Select("id, expiry_date").
			Clauses(clause.Locking{Strength: "UPDATE"}).
			Where("id = ? AND gym_id = ? AND deleted_at IS NULL", in.MemberID, tc.GymID()).
			First(&member).Error
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return ErrMemberNotFound
		}
		if err != nil {
			return err
		}

		// Step 2: validate plan within this gym, must be active.
		type planRow struct {
			ID           int64
			DurationDays int
			IsActive     bool
		}
		var plan planRow
		err = tx.Table("membership_plans").
			Select("id, duration_days, is_active").
			Where("id = ? AND gym_id = ? AND deleted_at IS NULL", in.PlanID, tc.GymID()).
			First(&plan).Error
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return ErrPlanNotFound
		}
		if err != nil {
			return err
		}
		if !plan.IsActive {
			return ErrPlanInactive
		}

		// Step 3: expiry calculation — mirrors renewals.Service.CreateRenewal.
		today := time.Now().UTC().Truncate(24 * time.Hour)
		baseDate := today
		if member.ExpiryDate != nil && !member.ExpiryDate.Before(today) {
			baseDate = *member.ExpiryDate
		}
		newExpiry := baseDate.AddDate(0, 0, plan.DurationDays)

		// Step 4: insert payment row FIRST — its ID is needed by the renewal
		// row created in step 5 (renewals.payment_id points at payments.id,
		// not the other way around — see model.go's doc comment).
		userID := tc.UserID()
		mode := in.PaymentMode
		paidDate := in.PaidDate
		payment := Payment{
			GymID:             tc.GymID(),
			MemberID:          in.MemberID,
			PlanID:            &in.PlanID,
			AmountInPaise:     in.AmountInPaise,
			Status:            PaymentStatusPaid,
			PaymentMode:       &mode,
			PaidDate:          &paidDate,
			CollectedByUserID: &userID,
		}
		if in.ReferenceNumber != "" {
			payment.ReferenceNumber = &in.ReferenceNumber
		}
		if in.Notes != "" {
			payment.Notes = &in.Notes
		}
		if err := tx.Create(&payment).Error; err != nil {
			return err
		}

		// Step 5: insert renewal row, linked to the payment just created.
		//
		// renewals.Renewal (internal/renewals/model.go) has no PaymentID
		// field — that Go struct is intentionally left unmodified per
		// Sprint 4 instructions. So we insert via tx.Create using the
		// existing struct (which populates every column except payment_id),
		// then set payment_id with a direct, scoped column update against
		// the row we just inserted. This keeps internal/renewals/*.go at
		// zero changes while still populating the new schema column.
		renewal := renewals.Renewal{
			GymID:             tc.GymID(),
			MemberID:          in.MemberID,
			PlanID:            in.PlanID,
			AmountPaidInPaise: in.AmountInPaise,
			OldExpiryDate:     member.ExpiryDate,
			NewExpiryDate:     newExpiry,
			RenewalDate:       in.PaidDate,
			RenewedByUserID:   tc.UserID(),
		}
		if in.Notes != "" {
			renewal.Notes = &in.Notes
		}
		if err := tx.Create(&renewal).Error; err != nil {
			return err
		}
		if err := tx.Table("renewals").
			Where("id = ? AND gym_id = ?", renewal.ID, tc.GymID()).
			Update("payment_id", payment.ID).Error; err != nil {
			return err
		}

		// Step 6: update member expiry + status.
		if err := tx.Table("members").
			Where("id = ? AND gym_id = ?", in.MemberID, tc.GymID()).
			Updates(map[string]interface{}{
				"expiry_date": newExpiry,
				"status":      "active",
			}).Error; err != nil {
			return err
		}

		result = CollectPaymentResult{Payment: payment, Renewal: renewal}
		return nil
	})

	if err != nil {
		return nil, err
	}
	return &result, nil
}

// ─── Read ─────────────────────────────────────────────────────────────────────

// PaymentWithContext carries a payment plus resolved member/plan names from
// joins — same denormalisation pattern as renewals.RenewalWithContext.
type PaymentWithContext struct {
	Payment
	MemberFirstName string
	MemberLastName  string
	MemberPhone     string
	PlanName        *string
}

func (r *Repository) FindByID(ctx context.Context, id int64) (*PaymentWithContext, error) {
	var result PaymentWithContext
	err := r.scopedPaymentsDB(ctx).
		Table("payments").
		Select(`payments.*,
			members.first_name AS member_first_name,
			members.last_name  AS member_last_name,
			members.phone      AS member_phone,
			membership_plans.name AS plan_name`).
		Joins("JOIN members ON members.id = payments.member_id").
		Joins("LEFT JOIN membership_plans ON membership_plans.id = payments.plan_id").
		Where("payments.id = ?", id).
		First(&result).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, nil
	}
	return &result, err
}

// List returns paginated payments with optional filters.
// status: "" means all statuses (overdue is computed in Go, not stored —
// see Service.applyOverdueStatus — so a literal "overdue" filter is also
// applied in Go after fetching "pending" rows past their due date).
func (r *Repository) List(ctx context.Context, req ListPaymentsRequest) ([]PaymentWithContext, int64, error) {
	p := pagination.Params{
		Page:    req.Page,
		PerPage: req.PerPage,
		Offset:  (req.Page - 1) * req.PerPage,
	}

	q := r.scopedPaymentsDB(ctx).
		Table("payments").
		Select(`payments.*,
			members.first_name AS member_first_name,
			members.last_name  AS member_last_name,
			members.phone      AS member_phone,
			membership_plans.name AS plan_name`).
		Joins("JOIN members ON members.id = payments.member_id").
		Joins("LEFT JOIN membership_plans ON membership_plans.id = payments.plan_id")

	if req.Status != "" && req.Status != "overdue" {
		q = q.Where("payments.status = ?", req.Status)
	}
	if req.Search != "" {
		term := "%" + req.Search + "%"
		q = q.Where("members.first_name ILIKE ? OR members.last_name ILIKE ? OR members.phone LIKE ?", term, term, term)
	}
	if req.DateFrom != nil {
		q = q.Where("COALESCE(payments.paid_date, payments.due_date) >= ?", *req.DateFrom)
	}
	if req.DateTo != nil {
		q = q.Where("COALESCE(payments.paid_date, payments.due_date) <= ?", *req.DateTo)
	}

	var total int64
	if err := q.Count(&total).Error; err != nil {
		return nil, 0, err
	}

	var results []PaymentWithContext
	err := q.
		Order("COALESCE(payments.paid_date, payments.due_date) DESC, payments.id DESC").
		Limit(p.PerPage).
		Offset(p.Offset).
		Scan(&results).Error

	return results, total, err
}

func (r *Repository) FindByMember(ctx context.Context, memberID int64, p pagination.Params) ([]PaymentWithContext, int64, error) {
	q := r.scopedPaymentsDB(ctx).
		Table("payments").
		Select(`payments.*,
			members.first_name AS member_first_name,
			members.last_name  AS member_last_name,
			members.phone      AS member_phone,
			membership_plans.name AS plan_name`).
		Joins("JOIN members ON members.id = payments.member_id").
		Joins("LEFT JOIN membership_plans ON membership_plans.id = payments.plan_id").
		Where("payments.member_id = ?", memberID)

	var total int64
	if err := q.Count(&total).Error; err != nil {
		return nil, 0, err
	}

	var results []PaymentWithContext
	err := q.
		Order("COALESCE(payments.paid_date, payments.due_date) DESC").
		Limit(p.PerPage).
		Offset(p.Offset).
		Scan(&results).Error

	return results, total, err
}

func (r *Repository) MemberExists(ctx context.Context, memberID int64) (bool, error) {
	var count int64
	err := database.ScopedDB(ctx, r.db).
		Table("members").
		Where("id = ? AND deleted_at IS NULL", memberID).
		Count(&count).Error
	return count > 0, err
}

// ─── Revenue aggregation (used by the payments dashboard summary) ───────────

// RevenueSummary aggregates today's and this month's collected revenue,
// plus the count of pending dues. Backs GET /api/v1/payments/summary and
// is the data dashboard.Repository should call once it adopts these fields
// (see Sprint 4 dashboard DTO note — wiring into the existing dashboard
// module is intentionally left for a follow-up so this sprint doesn't touch
// the dashboard module's files, per the same "don't modify existing
// architecture" instruction).
type RevenueSummary struct {
	TodayRevenueInPaise int64
	MonthRevenueInPaise int64
	PendingPayments     int64
	CollectedCount      int64
}

func (r *Repository) GetRevenueSummary(ctx context.Context) (*RevenueSummary, error) {
	tc := database.MustGetTenant(ctx)
	var s RevenueSummary

	if err := r.db.WithContext(ctx).
		Table("payments").
		Select("COALESCE(SUM(amount_in_paise), 0)").
		Where("gym_id = ? AND status = 'paid' AND paid_date = CURRENT_DATE", tc.GymID()).
		Scan(&s.TodayRevenueInPaise).Error; err != nil {
		return nil, err
	}

	if err := r.db.WithContext(ctx).
		Table("payments").
		Select("COALESCE(SUM(amount_in_paise), 0)").
		Where("gym_id = ? AND status = 'paid' AND DATE_TRUNC('month', paid_date) = DATE_TRUNC('month', CURRENT_DATE)", tc.GymID()).
		Scan(&s.MonthRevenueInPaise).Error; err != nil {
		return nil, err
	}

	if err := r.db.WithContext(ctx).
		Table("payments").
		Where("gym_id = ? AND status = 'pending'", tc.GymID()).
		Count(&s.PendingPayments).Error; err != nil {
		return nil, err
	}

	if err := r.db.WithContext(ctx).
		Table("payments").
		Where("gym_id = ? AND status = 'paid'", tc.GymID()).
		Count(&s.CollectedCount).Error; err != nil {
		return nil, err
	}

	return &s, nil
}
