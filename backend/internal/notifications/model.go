package notifications

import (
	"time"
)

// Notification is a log of every reminder sent (or queued) for a member.
// Append-only — we never modify a sent notification.
// WhatsApp integration is V2; V1 just stores the record and renders the template.
type Notification struct {
	ID         int64        `gorm:"primaryKey;autoIncrement" json:"id"`
	GymID      int64        `gorm:"not null;index:idx_notif_gym" json:"gym_id"`
	MemberID   int64        `gorm:"not null;index:idx_notif_gym" json:"member_id"`
	AlertID    *int64       `gorm:"index" json:"alert_id,omitempty"` // optional link to retention alert
	Channel    NotifChannel `gorm:"type:varchar(20);not null;default:'whatsapp'" json:"channel"`
	TemplateID string       `gorm:"type:varchar(100);not null" json:"template_id"` // e.g. "renewal_reminder_3d"
	Message    string       `gorm:"type:text;not null" json:"message"`             // rendered message body
	Status     NotifStatus  `gorm:"type:varchar(20);not null;default:'pending';index:idx_notif_gym" json:"status"`
	SentAt     *time.Time   `json:"sent_at,omitempty"`
	CreatedBy  int64        `gorm:"not null" json:"created_by"` // user_id
	CreatedAt  time.Time    `gorm:"autoCreateTime" json:"created_at"`
}

type NotifChannel string

const (
	ChannelWhatsApp NotifChannel = "whatsapp"
	ChannelSMS      NotifChannel = "sms" // future
)

type NotifStatus string

const (
	NotifStatusPending NotifStatus = "pending" // queued, not yet sent
	NotifStatusSent    NotifStatus = "sent"    // dispatched (V2: actual delivery)
	NotifStatusFailed  NotifStatus = "failed"
)

// NotificationTemplate stores reusable WhatsApp message templates.
// Templates use {{.MemberName}}, {{.ExpiryDate}}, {{.GymName}} placeholders.
type NotificationTemplate struct {
	ID         int64     `gorm:"primaryKey;autoIncrement" json:"id"`
	GymID      int64     `gorm:"not null;index" json:"gym_id"`
	TemplateID string    `gorm:"type:varchar(100);not null" json:"template_id"` // unique per gym
	Name       string    `gorm:"type:varchar(200);not null" json:"name"`
	Body       string    `gorm:"type:text;not null" json:"body"` // Go template syntax
	IsDefault  bool      `gorm:"not null;default:false" json:"is_default"`
	CreatedAt  time.Time `gorm:"autoCreateTime" json:"created_at"`
	UpdatedAt  time.Time `gorm:"autoUpdateTime" json:"updated_at"`
}
