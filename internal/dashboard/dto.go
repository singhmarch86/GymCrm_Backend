package dashboard

type DashboardResponse struct {
	TotalMembers      int64 `json:"total_members"`
	ActiveMembers     int64 `json:"active_members"`
	ExpiredMembers    int64 `json:"expired_members"`

	Expiring7Days     int64 `json:"expiring_7_days"`
	Expiring30Days    int64 `json:"expiring_30_days"`

	RenewalsToday     int64 `json:"renewals_today"`
	RenewalsThisMonth int64 `json:"renewals_this_month"`

	RevenueThisMonth  int64 `json:"revenue_this_month"`

	AttendanceToday   int64 `json:"attendance_today"`

	Inactive7Days     int64 `json:"inactive_7_days"`
	Inactive14Days    int64 `json:"inactive_14_days"`
	Inactive30Days    int64 `json:"inactive_30_days"`
}