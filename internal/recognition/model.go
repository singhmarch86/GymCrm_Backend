package recognition

import "time"

// Private, owner-curated member recognition (migration 035).
//
// Deliberately not a score and not rankable: no points column, no ordering
// field, one row per act of recognition with a mandatory human reason. This
// module reads member_rhythm_profiles and member_feedback only as inert
// citations the caller already fetched and is pointing at by id — it never
// imports rhythm's or ptfeedback's logic, so "never automatic" is a
// structural fact here, not just a UI convention. Same anti-ranking spirit
// as staff work (FR-13 §1: "no productivity score, no ranking").

const (
	SignalRhythm   = "rhythm"
	SignalFeedback = "feedback"
)

type Recognition struct {
	ID       int64 `gorm:"primaryKey;autoIncrement" json:"id"`
	GymID    int64 `gorm:"not null"                 json:"gym_id"`
	MemberID int64 `gorm:"not null"                 json:"member_id"`

	Reason string `gorm:"type:text;not null" json:"reason"`

	// What the owner leaned on, if anything — never computed here, only
	// cited. NULL means pure judgment call.
	SignalType *string `json:"signal_type,omitempty"`
	SignalID   *int64  `json:"signal_id,omitempty"`

	CreatedByUserID int64     `gorm:"not null" json:"created_by_user_id"`
	CreatedAt       time.Time `gorm:"autoCreateTime" json:"created_at"`
}

func (Recognition) TableName() string { return "member_recognitions" }

// Row is a recognition as the history list shows it.
type Row struct {
	ID            int64     `json:"id"`
	MemberID      int64     `json:"member_id"`
	Reason        string    `json:"reason"`
	SignalType    *string   `json:"signal_type,omitempty"`
	SignalID      *int64    `json:"signal_id,omitempty"`
	CreatedByName string    `json:"created_by_name"`
	CreatedAt     time.Time `json:"created_at"`
}
