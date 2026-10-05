package branches

import "time"

// Organization is a gym chain. See docs/FR-06-multi-location.md.
//
// A standalone gym is simply an organization with one branch — there is no
// separate "no chain" mode to reason about.
type Organization struct {
	ID        int64     `gorm:"primaryKey;autoIncrement" json:"id"`
	Name      string    `gorm:"type:varchar(200);not null" json:"name"`
	CreatedAt time.Time `gorm:"autoCreateTime" json:"created_at"`
	UpdatedAt time.Time `gorm:"autoUpdateTime" json:"updated_at"`
}

func (Organization) TableName() string { return "organizations" }

// UserGymAccess is a grant: this user may act in this branch, with this role.
//
// This table is the authority on branch access. A gym_id arriving from a
// client is a request to be checked against these rows, never a fact to be
// trusted (FR-06 §1.1).
type UserGymAccess struct {
	ID        int64     `gorm:"primaryKey;autoIncrement" json:"id"`
	UserID    int64     `gorm:"not null" json:"user_id"`
	GymID     int64     `gorm:"not null" json:"gym_id"`
	Role      string    `gorm:"type:varchar(20);not null;default:'staff'" json:"role"`
	CreatedAt time.Time `gorm:"autoCreateTime" json:"created_at"`
}

func (UserGymAccess) TableName() string { return "user_gym_access" }

// Roles a grant can carry. Deliberately per-branch: a manager at one branch may
// be ordinary staff at another (FR-06 §1.2).
const (
	RoleOwner   = "owner"
	RoleManager = "manager"
	RoleStaff   = "staff"
)

// Branch is a gym seen as a location within an organization.
type Branch struct {
	ID             int64   `json:"id"`
	Name           string  `json:"name"`
	BranchName     *string `json:"branch_name,omitempty"`
	City           string  `json:"city"`
	State          string  `json:"state"`
	Status         string  `json:"status"`
	OrganizationID *int64  `json:"organization_id,omitempty"`

	/// The requesting user's role in this branch — only set when listing the
	/// branches a user can access.
	Role string `json:"role,omitempty"`
}

// DisplayName prefers the short branch label ("Model Town") over the gym's full
// name ("FitZone Model Town"), which reads better in a switcher.
func (b Branch) DisplayName() string {
	if b.BranchName != nil && *b.BranchName != "" {
		return *b.BranchName
	}
	return b.Name
}
