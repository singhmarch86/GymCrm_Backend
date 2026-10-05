package members

import (
	"time"

	"gorm.io/gorm"
)

type Member struct {
	ID               int64      `gorm:"primaryKey;autoIncrement"                          json:"id"`
	GymID            int64      `gorm:"not null;index:idx_members_gym"                    json:"gym_id"`
	FirstName        string     `gorm:"type:varchar(100);not null"                        json:"first_name"`
	LastName         string     `gorm:"type:varchar(100);not null"                        json:"last_name"`
	Phone            string     `gorm:"type:varchar(20);not null"                         json:"phone"`
	Email            *string    `gorm:"type:varchar(200)"                                 json:"email,omitempty"`
	Gender           *string    `gorm:"type:varchar(10)"                                  json:"gender,omitempty"`
	DateOfBirth      *time.Time `gorm:"type:date"                                         json:"date_of_birth,omitempty"`
	Address          *string    `gorm:"type:text"                                         json:"address,omitempty"`
	MembershipPlanID *int64     `gorm:"index"                                             json:"membership_plan_id,omitempty"`
	StartDate        *time.Time `gorm:"type:date"                                         json:"start_date,omitempty"`
	ExpiryDate       *time.Time `gorm:"type:date;index:idx_members_gym"                   json:"expiry_date,omitempty"`

	// When this person first joined, as opposed to when their current term
	// began. StartDate moves forward on every renewal; JoinDate never moves,
	// which is why tenure questions read this one.
	//
	// The column has existed since the first migration with a default of
	// CURRENT_DATE, but nothing mapped it — so every member, however created,
	// was stamped with the date of the insert. That made a gym of four-year
	// veterans look like it opened this morning, and it silently emptied At
	// Risk: the inactivity alerts skip anyone inside their first 90 days
	// (FR-10 §4), and by this column everybody always was.
	//
	// Keeps the database default, so callers that do not set it still get
	// today — right for somebody joining at the counter now, the common case.
	JoinDate time.Time `gorm:"type:date;not null;default:CURRENT_DATE" json:"join_date"`

	Status MemberStatus `gorm:"type:varchar(20);not null;default:'active';index:idx_members_gym" json:"status"`
	Notes  *string      `gorm:"type:text"                                         json:"notes,omitempty"`

	// Somebody to call. The only field on this record that exists for the
	// member's sake rather than the gym's.
	EmergencyContactName  *string        `gorm:"type:varchar(200)" json:"emergency_contact_name,omitempty"`
	EmergencyContactPhone *string        `gorm:"type:varchar(20)"  json:"emergency_contact_phone,omitempty"`
	CreatedAt             time.Time      `gorm:"autoCreateTime"                                    json:"created_at"`
	UpdatedAt             time.Time      `gorm:"autoUpdateTime"                                    json:"updated_at"`
	DeletedAt             gorm.DeletedAt `gorm:"index"                                             json:"-"`
}

func (Member) TableName() string { return "members" }

func (m *Member) FullName() string { return m.FirstName + " " + m.LastName }

type MemberStatus string

const (
	MemberStatusActive   MemberStatus = "active"
	MemberStatusExpired  MemberStatus = "expired"
	MemberStatusInactive MemberStatus = "inactive"
	MemberStatusChurned  MemberStatus = "churned"
)
