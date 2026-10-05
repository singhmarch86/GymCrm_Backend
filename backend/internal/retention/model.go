package retention

import (
	"time"
)

// RetentionAlert is created by the background retention job.
// It flags members who are at churn risk.
// Append-only — alerts are never modified once created.
// Resolved by the gym owner taking action (renewal recorded, reminder sent).
type RetentionAlert struct {
	ID         int64      `gorm:"primaryKey;autoIncrement" json:"id"`
	GymID      int64      `gorm:"not null;index:idx_alerts_gym" json:"gym_id"`
	MemberID   int64      `gorm:"not null;index:idx_alerts_gym" json:"member_id"`
	AlertType  AlertType  `gorm:"type:varchar(50);not null;index:idx_alerts_gym" json:"alert_type"`
	Severity   Severity   `gorm:"type:varchar(20);not null" json:"severity"`
	Message    string     `gorm:"type:text;not null" json:"message"` // human-readable, ready for WhatsApp
	IsResolved bool       `gorm:"not null;default:false;index:idx_alerts_gym" json:"is_resolved"`
	ResolvedAt *time.Time `json:"resolved_at,omitempty"`
	CreatedAt  time.Time  `gorm:"autoCreateTime" json:"created_at"`
}

// AlertType classifies why the alert was raised.
type AlertType string

const (
	// ExpiringIn3Days — renewal due in 3 days
	AlertExpiringIn3Days AlertType = "expiring_in_3_days"
	// ExpiringToday — renewal due today
	AlertExpiringToday AlertType = "expiring_today"
	// ExpiredNoRenewal — expired, no renewal recorded yet
	AlertExpiredNoRenewal AlertType = "expired_no_renewal"
	// InactiveOneWeek — no check-in in 7 days (but membership still active)
	AlertInactiveOneWeek AlertType = "inactive_1_week"
	// InactiveTwoWeeks — no check-in in 14 days — churn risk
	AlertInactiveTwoWeeks AlertType = "inactive_2_weeks"
)

// Severity drives UI priority and WhatsApp urgency.
type Severity string

const (
	SeverityLow    Severity = "low"
	SeverityMedium Severity = "medium"
	SeverityHigh   Severity = "high"
)
