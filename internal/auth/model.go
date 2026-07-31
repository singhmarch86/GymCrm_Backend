package auth

import (
	"time"
)

// RefreshToken stores hashed refresh tokens.
// Plain token is never persisted — only bcrypt hash.
// One active token per user at a time (revoke old on reissue).
type RefreshToken struct {
	ID        int64     `gorm:"primaryKey;autoIncrement" json:"id"`
	UserID    int64     `gorm:"not null;index" json:"user_id"`
	GymID     int64     `gorm:"not null;index" json:"gym_id"` // denormalised for fast tenant checks
	TokenHash string    `gorm:"type:varchar(255);not null;uniqueIndex" json:"-"`
	ExpiresAt time.Time `gorm:"not null;index" json:"expires_at"`
	RevokedAt *time.Time `gorm:"index" json:"revoked_at,omitempty"`
	CreatedAt time.Time `gorm:"autoCreateTime" json:"created_at"`
}

// IsValid returns true if the token has not expired and not been revoked.
func (r *RefreshToken) IsValid() bool {
	return r.RevokedAt == nil && time.Now().Before(r.ExpiresAt)
}
