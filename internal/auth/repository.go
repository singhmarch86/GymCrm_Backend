package auth

import (
	"context"
	"errors"
	"time"

	"golang.org/x/crypto/bcrypt"
	"gorm.io/gorm"

	"gymcrm/internal/gyms"
	"gymcrm/internal/users"
)

// Repository handles all DB operations for the auth domain.
// Auth is the ONE module that deliberately does NOT use ScopedDB.
// Reason: auth operates before a tenant context exists (login, register).
// Every method explicitly declares its query scope in its WHERE clause.
type Repository struct {
	db *gorm.DB
}

func NewRepository(db *gorm.DB) *Repository {
	return &Repository{db: db}
}

// ─── Gym queries ──────────────────────────────────────────────────────────────

func (r *Repository) CreateGym(ctx context.Context, gym *gyms.Gym) error {
	return r.db.WithContext(ctx).Create(gym).Error
}

func (r *Repository) FindGymByID(ctx context.Context, gymID int64) (*gyms.Gym, error) {
	var gym gyms.Gym
	err := r.db.WithContext(ctx).
		Where("id = ?", gymID).
		First(&gym).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, nil
	}
	return &gym, err
}

func (r *Repository) GymPhoneExists(ctx context.Context, phone string) (bool, error) {
	var count int64
	err := r.db.WithContext(ctx).
		Model(&gyms.Gym{}).
		Where("phone = ?", phone).
		Count(&count).Error
	return count > 0, err
}

// ─── User queries ─────────────────────────────────────────────────────────────

func (r *Repository) CreateUser(ctx context.Context, user *users.User) error {
	return r.db.WithContext(ctx).Create(user).Error
}

// FindUserByPhone finds an active user by phone number.
// Phone is globally unique across gyms for V1 (one gym per phone).
func (r *Repository) FindUserByPhone(ctx context.Context, phone string) (*users.User, error) {
	var user users.User
	err := r.db.WithContext(ctx).
		Where("phone = ? AND status = ?", phone, users.UserStatusActive).
		First(&user).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, nil
	}
	return &user, err
}

// FindUserByID finds a user scoped to a specific gym.
// gym_id is passed explicitly — not from context — because this is called
// both pre-auth (during refresh) and post-auth (during /me).
func (r *Repository) FindUserByID(ctx context.Context, userID, gymID int64) (*users.User, error) {
	var user users.User
	err := r.db.WithContext(ctx).
		Where("id = ? AND gym_id = ? AND status = ?", userID, gymID, users.UserStatusActive).
		First(&user).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, nil
	}
	return &user, err
}

func (r *Repository) UserPhoneExistsInGym(ctx context.Context, phone string, gymID int64) (bool, error) {
	var count int64
	err := r.db.WithContext(ctx).
		Model(&users.User{}).
		Where("phone = ? AND gym_id = ?", phone, gymID).
		Count(&count).Error
	return count > 0, err
}

// ─── Refresh token queries ────────────────────────────────────────────────────

func (r *Repository) CreateRefreshToken(ctx context.Context, token *RefreshToken) error {
	return r.db.WithContext(ctx).Create(token).Error
}

// FindAndVerifyRefreshToken finds the active token for a user and verifies
// the plain token against the stored bcrypt hash.
//
// Design: We store bcrypt(token) in DB. To look it up, we fetch the user's
// single active token and do a bcrypt.Compare. Since we revoke-on-login,
// each user has at most one active token — the compare is O(1) in practice.
//
// This avoids storing a fast-hash (SHA-256) lookup key, keeping the model simple for V1.
func (r *Repository) FindAndVerifyRefreshToken(ctx context.Context, userID int64, plainToken string) (*RefreshToken, error) {
	// Fetch the most recently created non-revoked token for this user
	var token RefreshToken
	err := r.db.WithContext(ctx).
		Where("user_id = ? AND revoked_at IS NULL AND expires_at > ?", userID, time.Now()).
		Order("created_at DESC").
		First(&token).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}

	// Constant-time comparison — prevents timing attacks
	if err := bcrypt.CompareHashAndPassword([]byte(token.TokenHash), []byte(plainToken)); err != nil {
		return nil, nil // hash mismatch — treat as not found
	}

	return &token, nil
}

func (r *Repository) RevokeToken(ctx context.Context, tokenID int64) error {
	now := time.Now()
	return r.db.WithContext(ctx).
		Model(&RefreshToken{}).
		Where("id = ?", tokenID).
		Update("revoked_at", now).Error
}

func (r *Repository) RevokeAllUserTokens(ctx context.Context, userID int64) error {
	now := time.Now()
	return r.db.WithContext(ctx).
		Model(&RefreshToken{}).
		Where("user_id = ? AND revoked_at IS NULL", userID).
		Update("revoked_at", now).Error
}

func (r *Repository) DeleteExpiredTokens(ctx context.Context) error {
	cutoff := time.Now().Add(-7 * 24 * time.Hour)
	return r.db.WithContext(ctx).
		Where("expires_at < ?", cutoff).
		Delete(&RefreshToken{}).Error
}
