package visitors

import "time"

// Purpose of visit. Mirrors chk_visitors_purpose in migration 014.
const (
	PurposeTrial = "trial"
	PurposeGuest = "guest"
	PurposeTour  = "tour"
	PurposeOther = "other"
)

// Visitor is a single walk-in visit — distinct from a Lead (an enquiry,
// which may never set foot in the gym) and a Member (a paying signup).
// Converting a visit into a Lead is an explicit staff action, never automatic.
type Visitor struct {
	ID    int64 `gorm:"primaryKey;autoIncrement" json:"id"`
	GymID int64 `gorm:"not null"                 json:"gym_id"`

	Name    string  `gorm:"not null" json:"name"`
	Phone   *string `json:"phone,omitempty"`
	Purpose string  `gorm:"type:varchar(20);not null;default:'trial'" json:"purpose"`

	CheckedInAt     time.Time  `gorm:"autoCreateTime" json:"checked_in_at"`
	CheckedOutAt    *time.Time `json:"checked_out_at,omitempty"`
	HostStaffUserID *int64     `json:"host_staff_user_id,omitempty"`

	ConvertedLeadID *int64 `json:"converted_lead_id,omitempty"`

	Notes     *string   `json:"notes,omitempty"`
	CreatedAt time.Time `gorm:"autoCreateTime" json:"created_at"`
	UpdatedAt time.Time `gorm:"autoUpdateTime" json:"updated_at"`
}

func (Visitor) TableName() string { return "visitors" }

func (v Visitor) isCheckedOut() bool { return v.CheckedOutAt != nil }
