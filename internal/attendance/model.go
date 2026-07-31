package attendance

import "time"

// Attendance is an immutable check-in record.
// Append-only — no updates, no deletes, no soft delete.
// One record per member per day per gym — enforced by unique index and service layer.
//
// checked_in_at: full UTC timestamp — exact moment of check-in
// checked_in_date: date-only — set by server at insert time, never independently
// Both columns always set together. checked_in_date exists purely for query performance.
type Attendance struct {
	ID            int64     `gorm:"primaryKey;autoIncrement" json:"id"`
	GymID         int64     `gorm:"not null"                 json:"gym_id"`
	MemberID      int64     `gorm:"not null"                 json:"member_id"`
	CheckedInAt   time.Time `gorm:"not null"                 json:"checked_in_at"`
	CheckedInDate time.Time `gorm:"type:date;not null"       json:"checked_in_date"`
	CreatedAt     time.Time `gorm:"autoCreateTime"           json:"created_at"`
}

func (Attendance) TableName() string { return "attendance" }
