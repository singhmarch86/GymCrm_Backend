package reports

import (
	"context"
	"fmt"
	"time"

	"gorm.io/gorm"

	"gymcrm/internal/database"
)

// Repository runs all analytics queries.
//
// TENANT ISOLATION: every query uses database.ScopedDB or an explicit
// WHERE gym_id = ? — no cross-tenant leakage possible.
//
// FINANCIAL SOURCE OF TRUTH: revenue queries read from the `payments` table
// (status = 'paid'), not from renewals.amount_paid_in_paise. This is
// consistent with the Sprint 4 decision: payments own money, renewals own
// membership validity.
type Repository struct {
	db *gorm.DB
}

func NewRepository(db *gorm.DB) *Repository {
	return &Repository{db: db}
}

// ─── Revenue ──────────────────────────────────────────────────────────────────

func (r *Repository) GetRevenueReport(ctx context.Context) (*RevenueReport, error) {
	tc := database.MustGetTenant(ctx)
	gymID := tc.GymID()
	report := &RevenueReport{}

	type paise struct{ V int64 }

	scan := func(query string, dest *int64, args ...interface{}) error {
		var p paise
		err := r.db.WithContext(ctx).Raw(query, args...).Scan(&p).Error
		if err != nil {
			return err
		}
		*dest = p.V
		return nil
	}

	// Today
	if err := scan(
		`SELECT COALESCE(SUM(amount_in_paise),0) AS v FROM payments
		 WHERE gym_id = ? AND status = 'paid' AND paid_date = CURRENT_DATE`,
		&report.TodayInPaise, gymID,
	); err != nil {
		return nil, err
	}

	// Yesterday
	if err := scan(
		`SELECT COALESCE(SUM(amount_in_paise),0) AS v FROM payments
		 WHERE gym_id = ? AND status = 'paid' AND paid_date = CURRENT_DATE - INTERVAL '1 day'`,
		&report.YesterdayInPaise, gymID,
	); err != nil {
		return nil, err
	}

	// This week
	if err := scan(
		`SELECT COALESCE(SUM(amount_in_paise),0) AS v FROM payments
		 WHERE gym_id = ? AND status = 'paid'
		 AND paid_date >= DATE_TRUNC('week', CURRENT_DATE)`,
		&report.WeekInPaise, gymID,
	); err != nil {
		return nil, err
	}

	// This month
	if err := scan(
		`SELECT COALESCE(SUM(amount_in_paise),0) AS v FROM payments
		 WHERE gym_id = ? AND status = 'paid'
		 AND DATE_TRUNC('month', paid_date) = DATE_TRUNC('month', CURRENT_DATE)`,
		&report.MonthInPaise, gymID,
	); err != nil {
		return nil, err
	}

	// Last month
	if err := scan(
		`SELECT COALESCE(SUM(amount_in_paise),0) AS v FROM payments
		 WHERE gym_id = ? AND status = 'paid'
		 AND DATE_TRUNC('month', paid_date) = DATE_TRUNC('month', CURRENT_DATE - INTERVAL '1 month')`,
		&report.LastMonthInPaise, gymID,
	); err != nil {
		return nil, err
	}

	// Rupee conversions
	report.TodayInRupees = float64(report.TodayInPaise) / 100
	report.YesterdayInRupees = float64(report.YesterdayInPaise) / 100
	report.WeekInRupees = float64(report.WeekInPaise) / 100
	report.MonthInRupees = float64(report.MonthInPaise) / 100
	report.LastMonthInRupees = float64(report.LastMonthInPaise) / 100

	// 12-month trend
	type trendRow struct {
		Month   time.Time
		Revenue int64
	}
	var rows []trendRow
	err := r.db.WithContext(ctx).Raw(`
		SELECT DATE_TRUNC('month', paid_date) AS month,
		       COALESCE(SUM(amount_in_paise), 0) AS revenue
		FROM payments
		WHERE gym_id = ? AND status = 'paid'
		  AND paid_date >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '11 months'
		GROUP BY DATE_TRUNC('month', paid_date)
		ORDER BY month ASC
	`, gymID).Scan(&rows).Error
	if err != nil {
		return nil, err
	}

	report.Trend = make([]RevenueTrendPoint, 0, len(rows))
	for _, row := range rows {
		report.Trend = append(report.Trend, RevenueTrendPoint{
			Month:           row.Month.Format("Jan 2006"),
			RevenueInPaise:  row.Revenue,
			RevenueInRupees: float64(row.Revenue) / 100,
		})
	}

	return report, nil
}

// ─── Members ──────────────────────────────────────────────────────────────────

func (r *Repository) GetMemberReport(ctx context.Context) (*MemberReport, error) {
	tc := database.MustGetTenant(ctx)
	gymID := tc.GymID()
	report := &MemberReport{}

	type countRow struct{ V int64 }

	count := func(query string, dest *int64, args ...interface{}) error {
		var c countRow
		if err := r.db.WithContext(ctx).Raw(query, args...).Scan(&c).Error; err != nil {
			return err
		}
		// The assignment this closure exists for. Without it every caller got
		// back its zero value while the queries themselves ran perfectly — so
		// the screen reported 0 members against a database holding 809, and
		// nothing errored anywhere to say otherwise.
		*dest = c.V
		return nil
	}

	if err := count(
		`SELECT COUNT(*) AS v FROM members WHERE gym_id = ? AND deleted_at IS NULL`,
		&report.Total, gymID,
	); err != nil {
		return nil, err
	}

	if err := count(
		`SELECT COUNT(*) AS v FROM members WHERE gym_id = ? AND deleted_at IS NULL AND status = 'active'`,
		&report.Active, gymID,
	); err != nil {
		return nil, err
	}

	if err := count(
		`SELECT COUNT(*) AS v FROM members WHERE gym_id = ? AND deleted_at IS NULL AND status = 'expired'`,
		&report.Expired, gymID,
	); err != nil {
		return nil, err
	}

	if err := count(
		`SELECT COUNT(*) AS v FROM members
		 WHERE gym_id = ? AND deleted_at IS NULL
		 AND DATE_TRUNC('month', created_at) = DATE_TRUNC('month', CURRENT_DATE)`,
		&report.NewThisMonth, gymID,
	); err != nil {
		return nil, err
	}

	// Growth % vs last month
	var lastMonthNew int64
	if err := count(
		`SELECT COUNT(*) AS v FROM members
		 WHERE gym_id = ? AND deleted_at IS NULL
		 AND DATE_TRUNC('month', created_at) = DATE_TRUNC('month', CURRENT_DATE - INTERVAL '1 month')`,
		&lastMonthNew, gymID,
	); err != nil {
		return nil, err
	}
	if lastMonthNew > 0 {
		report.GrowthPct = float64(report.NewThisMonth-lastMonthNew) / float64(lastMonthNew) * 100
	}

	// 12-month growth chart
	type growthRow struct {
		Month  time.Time
		Joined int64
	}
	var joinRows []growthRow
	if err := r.db.WithContext(ctx).Raw(`
		SELECT DATE_TRUNC('month', created_at) AS month, COUNT(*) AS joined
		FROM members
		WHERE gym_id = ? AND deleted_at IS NULL
		  AND created_at >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '11 months'
		GROUP BY DATE_TRUNC('month', created_at)
		ORDER BY month ASC
	`, gymID).Scan(&joinRows).Error; err != nil {
		return nil, err
	}

	type expireRow struct {
		Month   time.Time
		Expired int64
	}
	var expireRows []expireRow
	if err := r.db.WithContext(ctx).Raw(`
		SELECT DATE_TRUNC('month', expiry_date) AS month, COUNT(*) AS expired
		FROM members
		WHERE gym_id = ? AND deleted_at IS NULL AND expiry_date IS NOT NULL
		  AND expiry_date >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '11 months'
		GROUP BY DATE_TRUNC('month', expiry_date)
		ORDER BY month ASC
	`, gymID).Scan(&expireRows).Error; err != nil {
		return nil, err
	}

	// Merge into a map keyed by month label
	type combined struct {
		joined  int64
		expired int64
	}
	merged := make(map[string]*combined)
	for _, r := range joinRows {
		key := r.Month.Format("Jan 2006")
		if merged[key] == nil {
			merged[key] = &combined{}
		}
		merged[key].joined = r.Joined
	}
	for _, r := range expireRows {
		key := r.Month.Format("Jan 2006")
		if merged[key] == nil {
			merged[key] = &combined{}
		}
		merged[key].expired = r.Expired
	}

	// Build ordered slice (last 12 months)
	now := time.Now()
	report.Growth = make([]MemberGrowthPoint, 0, 12)
	for i := 11; i >= 0; i-- {
		m := now.AddDate(0, -i, 0)
		key := fmt.Sprintf("%s %d", m.Month().String()[:3], m.Year())
		c := merged[key]
		pt := MemberGrowthPoint{Month: key}
		if c != nil {
			pt.Joined = c.joined
			pt.Expired = c.expired
		}
		report.Growth = append(report.Growth, pt)
	}

	return report, nil
}

// ─── Payments ─────────────────────────────────────────────────────────────────

func (r *Repository) GetPaymentReport(ctx context.Context) (*PaymentReport, error) {
	tc := database.MustGetTenant(ctx)
	gymID := tc.GymID()
	report := &PaymentReport{}

	type sumRow struct {
		Amount int64
		Cnt    int64
	}

	var collected sumRow
	if err := r.db.WithContext(ctx).Raw(`
		SELECT COALESCE(SUM(amount_in_paise),0) AS amount, COUNT(*) AS cnt
		FROM payments WHERE gym_id = ? AND status = 'paid'
	`, gymID).Scan(&collected).Error; err != nil {
		return nil, err
	}
	report.CollectedInPaise = collected.Amount
	report.CollectedInRupees = float64(collected.Amount) / 100
	report.CollectedCount = collected.Cnt

	var pending sumRow
	if err := r.db.WithContext(ctx).Raw(`
		SELECT COALESCE(SUM(amount_in_paise),0) AS amount, COUNT(*) AS cnt
		FROM payments WHERE gym_id = ? AND status = 'pending'
	`, gymID).Scan(&pending).Error; err != nil {
		return nil, err
	}
	report.PendingInPaise = pending.Amount
	report.PendingInRupees = float64(pending.Amount) / 100
	report.PendingCount = pending.Cnt

	var overdue sumRow
	if err := r.db.WithContext(ctx).Raw(`
		SELECT COALESCE(SUM(amount_in_paise),0) AS amount, COUNT(*) AS cnt
		FROM payments WHERE gym_id = ? AND status = 'overdue'
	`, gymID).Scan(&overdue).Error; err != nil {
		return nil, err
	}
	report.OverdueInPaise = overdue.Amount
	report.OverdueInRupees = float64(overdue.Amount) / 100

	// Payment mode breakdown
	type modeRow struct {
		PaymentMode string
		Amount      int64
		Cnt         int64
	}
	var modes []modeRow
	if err := r.db.WithContext(ctx).Raw(`
		SELECT payment_mode, COALESCE(SUM(amount_in_paise),0) AS amount, COUNT(*) AS cnt
		FROM payments
		WHERE gym_id = ? AND status = 'paid' AND payment_mode IS NOT NULL
		GROUP BY payment_mode
		ORDER BY amount DESC
	`, gymID).Scan(&modes).Error; err != nil {
		return nil, err
	}

	modeLabels := map[string]string{
		"cash":          "Cash",
		"upi":           "UPI",
		"credit_card":   "Credit Card",
		"debit_card":    "Debit Card",
		"bank_transfer": "Bank Transfer",
	}
	report.ModeBreakdown = make([]PaymentModeBreakdown, 0, len(modes))
	for _, m := range modes {
		label := modeLabels[m.PaymentMode]
		if label == "" {
			label = m.PaymentMode
		}
		report.ModeBreakdown = append(report.ModeBreakdown, PaymentModeBreakdown{
			Mode:           m.PaymentMode,
			Label:          label,
			AmountInPaise:  m.Amount,
			AmountInRupees: float64(m.Amount) / 100,
			Count:          m.Cnt,
		})
	}

	return report, nil
}

// ─── Renewals ─────────────────────────────────────────────────────────────────

func (r *Repository) GetRenewalReport(ctx context.Context) (*RenewalReport, error) {
	tc := database.MustGetTenant(ctx)
	gymID := tc.GymID()
	report := &RenewalReport{}

	type countRow struct{ V int64 }

	if err := r.db.WithContext(ctx).Raw(`
		SELECT COUNT(*) AS v FROM members
		WHERE gym_id = ? AND deleted_at IS NULL
		AND expiry_date::date = CURRENT_DATE
	`, gymID).Scan(&countRow{}).Error; err != nil {
		return nil, err
	}

	// Due today (members expiring today)
	var dueToday countRow
	if err := r.db.WithContext(ctx).Raw(`
		SELECT COUNT(*) AS v FROM members
		WHERE gym_id = ? AND deleted_at IS NULL AND expiry_date::date = CURRENT_DATE
	`, gymID).Scan(&dueToday).Error; err != nil {
		return nil, err
	}
	report.DueToday = dueToday.V

	// Completed this month (renewals)
	var completed countRow
	if err := r.db.WithContext(ctx).Raw(`
		SELECT COUNT(*) AS v FROM renewals
		WHERE gym_id = ?
		AND DATE_TRUNC('month', renewal_date) = DATE_TRUNC('month', CURRENT_DATE)
	`, gymID).Scan(&completed).Error; err != nil {
		return nil, err
	}
	report.CompletedThisMonth = completed.V

	// Success rate: completed / expiring this month (simplified)
	var expiringThisMonth countRow
	if err := r.db.WithContext(ctx).Raw(`
		SELECT COUNT(*) AS v FROM members
		WHERE gym_id = ? AND deleted_at IS NULL
		AND DATE_TRUNC('month', expiry_date) = DATE_TRUNC('month', CURRENT_DATE)
	`, gymID).Scan(&expiringThisMonth).Error; err != nil {
		return nil, err
	}
	if expiringThisMonth.V > 0 {
		report.SuccessRate = float64(report.CompletedThisMonth) / float64(expiringThisMonth.V) * 100
		if report.SuccessRate > 100 {
			report.SuccessRate = 100
		}
	}

	// 12-month trend
	type trendRow struct {
		Month time.Time
		Count int64
	}
	var rows []trendRow
	if err := r.db.WithContext(ctx).Raw(`
		SELECT DATE_TRUNC('month', renewal_date) AS month, COUNT(*) AS count
		FROM renewals
		WHERE gym_id = ?
		  AND renewal_date >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '11 months'
		GROUP BY DATE_TRUNC('month', renewal_date)
		ORDER BY month ASC
	`, gymID).Scan(&rows).Error; err != nil {
		return nil, err
	}

	report.Trend = make([]RenewalTrendPoint, 0, len(rows))
	for _, row := range rows {
		report.Trend = append(report.Trend, RenewalTrendPoint{
			Month: row.Month.Format("Jan 2006"),
			Count: row.Count,
		})
	}

	return report, nil
}

// ─── Plans ────────────────────────────────────────────────────────────────────

func (r *Repository) GetPlanReport(ctx context.Context) (*PlanReport, error) {
	tc := database.MustGetTenant(ctx)
	gymID := tc.GymID()

	type planRow struct {
		PlanID   int64
		PlanName string
		Active   int64
		Revenue  int64
		Sold     int64
	}
	var rows []planRow

	if err := r.db.WithContext(ctx).Raw(`
		SELECT
			p.id                                        AS plan_id,
			p.name                                      AS plan_name,
			COUNT(DISTINCT CASE WHEN m.status = 'active' THEN m.id END) AS active,
			COALESCE(SUM(pay.amount_in_paise), 0)       AS revenue,
			COUNT(pay.id)                               AS sold
		FROM membership_plans p
		LEFT JOIN members m
			ON m.membership_plan_id = p.id
			AND m.gym_id = ?
			AND m.deleted_at IS NULL
		LEFT JOIN payments pay
			ON pay.plan_id = p.id
			AND pay.gym_id = ?
			AND pay.status = 'paid'
		WHERE p.gym_id = ? AND p.deleted_at IS NULL
		GROUP BY p.id, p.name
		ORDER BY revenue DESC
	`, gymID, gymID, gymID).Scan(&rows).Error; err != nil {
		return nil, err
	}

	stats := make([]PlanStat, 0, len(rows))
	for _, row := range rows {
		stats = append(stats, PlanStat{
			PlanID:          row.PlanID,
			PlanName:        row.PlanName,
			ActiveMembers:   row.Active,
			RevenueInPaise:  row.Revenue,
			RevenueInRupees: float64(row.Revenue) / 100,
			CountSold:       row.Sold,
		})
	}
	return &PlanReport{Plans: stats}, nil
}
