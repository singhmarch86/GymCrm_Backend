package reports

// ─── Date range ───────────────────────────────────────────────────────────────

// DateRange is used internally by the repository; every endpoint accepts
// optional ?from=YYYY-MM-DD&to=YYYY-MM-DD query params. If omitted, the
// service defaults to the current calendar month.
type DateRange struct {
	From string // YYYY-MM-DD
	To   string // YYYY-MM-DD
}

// ─── Revenue ──────────────────────────────────────────────────────────────────

// RevenueTrendPoint is a single month's collected revenue in the trend chart.
type RevenueTrendPoint struct {
	Month            string  `json:"month"`              // e.g. "Jan 2026"
	RevenueInPaise   int64   `json:"revenue_in_paise"`
	RevenueInRupees  float64 `json:"revenue_in_rupees"`
}

// RevenueReport backs GET /api/v1/reports/revenue.
type RevenueReport struct {
	// KPIs
	TodayInPaise     int64   `json:"today_in_paise"`
	TodayInRupees    float64 `json:"today_in_rupees"`
	YesterdayInPaise int64   `json:"yesterday_in_paise"`
	YesterdayInRupees float64 `json:"yesterday_in_rupees"`
	WeekInPaise      int64   `json:"week_in_paise"`
	WeekInRupees     float64 `json:"week_in_rupees"`
	MonthInPaise     int64   `json:"month_in_paise"`
	MonthInRupees    float64 `json:"month_in_rupees"`
	LastMonthInPaise int64   `json:"last_month_in_paise"`
	LastMonthInRupees float64 `json:"last_month_in_rupees"`
	// Trend — last 12 months, newest last (for chart x-axis)
	Trend []RevenueTrendPoint `json:"trend"`
}

// ─── Members ──────────────────────────────────────────────────────────────────

// MemberGrowthPoint is a single month in the bar chart.
type MemberGrowthPoint struct {
	Month   string `json:"month"`    // e.g. "Jan 2026"
	Joined  int64  `json:"joined"`
	Expired int64  `json:"expired"`
}

// MemberReport backs GET /api/v1/reports/members.
type MemberReport struct {
	Total    int64   `json:"total"`
	Active   int64   `json:"active"`
	Expired  int64   `json:"expired"`
	NewThisMonth int64 `json:"new_this_month"`
	GrowthPct float64 `json:"growth_pct"` // vs last month
	// Last 12 months joined vs expired
	Growth []MemberGrowthPoint `json:"growth"`
}

// ─── Payments ─────────────────────────────────────────────────────────────────

// PaymentModeBreakdown is a single slice of the payment-mode pie chart.
type PaymentModeBreakdown struct {
	Mode       string  `json:"mode"`        // cash | upi | credit_card | ...
	Label      string  `json:"label"`       // display-friendly label
	AmountInPaise  int64   `json:"amount_in_paise"`
	AmountInRupees float64 `json:"amount_in_rupees"`
	Count      int64   `json:"count"`
}

// PaymentReport backs GET /api/v1/reports/payments.
type PaymentReport struct {
	CollectedInPaise  int64   `json:"collected_in_paise"`
	CollectedInRupees float64 `json:"collected_in_rupees"`
	PendingInPaise    int64   `json:"pending_in_paise"`
	PendingInRupees   float64 `json:"pending_in_rupees"`
	OverdueInPaise    int64   `json:"overdue_in_paise"`
	OverdueInRupees   float64 `json:"overdue_in_rupees"`
	CollectedCount    int64   `json:"collected_count"`
	PendingCount      int64   `json:"pending_count"`
	// Pie chart slices — only includes modes with at least one payment
	ModeBreakdown []PaymentModeBreakdown `json:"mode_breakdown"`
}

// ─── Renewals ─────────────────────────────────────────────────────────────────

// RenewalTrendPoint is a single month in the renewals bar chart.
type RenewalTrendPoint struct {
	Month string `json:"month"`
	Count int64  `json:"count"`
}

// RenewalReport backs GET /api/v1/reports/renewals.
type RenewalReport struct {
	DueToday      int64   `json:"due_today"`
	CompletedThisMonth int64 `json:"completed_this_month"`
	// Success rate = completed / (completed + due but not renewed) * 100
	// Simplified for V1: completed this month / members expiring this month * 100
	SuccessRate   float64 `json:"success_rate"`
	Trend []RenewalTrendPoint `json:"trend"` // last 12 months
}

// ─── Plans ────────────────────────────────────────────────────────────────────

// PlanStat is a single plan's performance stats.
type PlanStat struct {
	PlanID          int64   `json:"plan_id"`
	PlanName        string  `json:"plan_name"`
	ActiveMembers   int64   `json:"active_members"`
	RevenueInPaise  int64   `json:"revenue_in_paise"`
	RevenueInRupees float64 `json:"revenue_in_rupees"`
	CountSold       int64   `json:"count_sold"` // total renewals using this plan
}

// PlanReport backs GET /api/v1/reports/plans.
type PlanReport struct {
	Plans []PlanStat `json:"plans"`
}
