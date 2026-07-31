package auth

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"fmt"
	"strings"
	"time"

	"golang.org/x/crypto/bcrypt"

	"gymcrm/internal/gyms"
	"gymcrm/internal/middleware"
	"gymcrm/internal/users"
)

const (
	bcryptCost        = 12 // strong enough; ~250ms on a low-end VPS
	refreshTokenBytes = 32 // 256 bits of entropy
)

// Service contains all auth business logic.
// Handlers call Service. Service calls Repository. Nothing else crosses that boundary.
type Service struct {
	repo      *Repository
	jwtSecret string
}

func NewService(repo *Repository, jwtSecret string) *Service {
	return &Service{repo: repo, jwtSecret: jwtSecret}
}

// ─── Register ─────────────────────────────────────────────────────────────────

// RegisterGym creates a gym tenant and its first owner atomically.
// On success, returns tokens — owner is immediately logged in.
func (s *Service) RegisterGym(ctx context.Context, req RegisterGymRequest) (*RegisterResponse, error) {
	// Guard: gym phone must be globally unique
	exists, err := s.repo.GymPhoneExists(ctx, req.Phone)
	if err != nil {
		return nil, fmt.Errorf("register: %w", err)
	}
	if exists {
		return nil, ErrGymPhoneAlreadyRegistered
	}

	// Hash password before touching the DB
	hash, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcryptCost)
	if err != nil {
		return nil, fmt.Errorf("register: hash password: %w", err)
	}

	gym := &gyms.Gym{
		Name:      req.GymName,
		OwnerName: req.OwnerName,
		Phone:     req.Phone,
		Email:     toNullableString(req.Email),
		Address:   req.Address,
		City:      req.City,
		State:     req.State,
		Status:    gyms.GymStatusActive,
	}
	if err := s.repo.CreateGym(ctx, gym); err != nil {
		return nil, fmt.Errorf("register: create gym: %w", err)
	}

	owner := &users.User{
		GymID:        gym.ID,
		Name:         req.OwnerName,
		Phone:        req.Phone,
		Email:        req.Email,
		PasswordHash: string(hash),
		Role:         users.RoleOwner,
		Status:       users.UserStatusActive,
	}
	if err := s.repo.CreateUser(ctx, owner); err != nil {
		return nil, fmt.Errorf("register: create owner: %w", err)
	}

	pair, err := s.issueTokenPair(ctx, owner)
	if err != nil {
		return nil, fmt.Errorf("register: issue tokens: %w", err)
	}

	return &RegisterResponse{
		Gym:          toGymDTO(gym),
		User:         toUserDTO(owner),
		AccessToken:  pair.accessToken,
		RefreshToken: pair.refreshToken,
		TokenType:    "Bearer",
		ExpiresIn:    int(middleware.AccessTokenTTL.Seconds()),
	}, nil
}

// ─── Login ────────────────────────────────────────────────────────────────────

// Login validates credentials and returns a fresh token pair.
// Old refresh tokens for this user are revoked on successful login.
func (s *Service) Login(ctx context.Context, req LoginRequest) (*AuthResponse, error) {
	user, err := s.repo.FindUserByPhone(ctx, req.Phone)
	if err != nil {
		return nil, fmt.Errorf("login: %w", err)
	}
	// Same error for "not found" and "wrong password" — prevents user enumeration
	if user == nil {
		return nil, ErrInvalidCredentials
	}
	if user.Status != users.UserStatusActive {
		return nil, ErrUserInactive
	}

	// bcrypt.CompareHashAndPassword is constant-time
	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(req.Password)); err != nil {
		return nil, ErrInvalidCredentials
	}

	gym, err := s.repo.FindGymByID(ctx, user.GymID)
	if err != nil {
		return nil, fmt.Errorf("login: check gym: %w", err)
	}
	if gym == nil || gym.Status != gyms.GymStatusActive {
		return nil, ErrGymInactive
	}

	// Revoke all old tokens — only one session active at a time per user
	if err := s.repo.RevokeAllUserTokens(ctx, user.ID); err != nil {
		return nil, fmt.Errorf("login: revoke old tokens: %w", err)
	}

	pair, err := s.issueTokenPair(ctx, user)
	if err != nil {
		return nil, fmt.Errorf("login: issue tokens: %w", err)
	}

	return &AuthResponse{
		AccessToken:  pair.accessToken,
		RefreshToken: pair.refreshToken,
		TokenType:    "Bearer",
		ExpiresIn:    int(middleware.AccessTokenTTL.Seconds()),
		User:         toUserDTO(user),
	}, nil
}

// ─── Refresh ──────────────────────────────────────────────────────────────────

// RefreshTokens validates the incoming refresh token and issues a new pair.
// The old token is revoked immediately (token rotation).
// Token format: "<userID>:<plainToken>" — the userID prefix enables O(1) DB lookup.
func (s *Service) RefreshTokens(ctx context.Context, req RefreshRequest) (*AuthResponse, error) {
	userID, plainToken, err := splitRefreshToken(req.RefreshToken)
	if err != nil {
		return nil, ErrRefreshTokenInvalid
	}

	// Find and verify in one call — bcrypt compare happens inside the repo
	stored, err := s.repo.FindAndVerifyRefreshToken(ctx, userID, plainToken)
	if err != nil {
		return nil, fmt.Errorf("refresh: verify token: %w", err)
	}
	if stored == nil {
		return nil, ErrRefreshTokenInvalid
	}

	// Revoke the token that was just used (rotation)
	if err := s.repo.RevokeToken(ctx, stored.ID); err != nil {
		return nil, fmt.Errorf("refresh: revoke token: %w", err)
	}

	user, err := s.repo.FindUserByID(ctx, stored.UserID, stored.GymID)
	if err != nil {
		return nil, fmt.Errorf("refresh: find user: %w", err)
	}
	if user == nil || user.Status != users.UserStatusActive {
		return nil, ErrUserInactive
	}

	pair, err := s.issueTokenPair(ctx, user)
	if err != nil {
		return nil, fmt.Errorf("refresh: issue tokens: %w", err)
	}

	return &AuthResponse{
		AccessToken:  pair.accessToken,
		RefreshToken: pair.refreshToken,
		TokenType:    "Bearer",
		ExpiresIn:    int(middleware.AccessTokenTTL.Seconds()),
		User:         toUserDTO(user),
	}, nil
}

// ─── Logout ───────────────────────────────────────────────────────────────────

// Logout revokes all refresh tokens for the current user.
// Access tokens expire naturally (15 min). Acceptable for V1.
func (s *Service) Logout(ctx context.Context, userID int64) error {
	return s.repo.RevokeAllUserTokens(ctx, userID)
}

// ─── Me ───────────────────────────────────────────────────────────────────────

// GetMe returns the current user + gym. Requires a valid JWT (tenant context set).
func (s *Service) GetMe(ctx context.Context, userID, gymID int64) (*MeResponse, error) {
	user, err := s.repo.FindUserByID(ctx, userID, gymID)
	if err != nil {
		return nil, fmt.Errorf("me: %w", err)
	}
	if user == nil {
		return nil, ErrInvalidCredentials
	}

	gym, err := s.repo.FindGymByID(ctx, gymID)
	if err != nil {
		return nil, fmt.Errorf("me: find gym: %w", err)
	}
	if gym == nil {
		return nil, ErrGymInactive
	}

	return &MeResponse{
		User: toUserDTO(user),
		Gym:  toGymDTO(gym),
	}, nil
}

// ─── Token machinery ──────────────────────────────────────────────────────────

type tokenPair struct {
	accessToken  string
	refreshToken string // "<userID>:<plainToken>" — opaque to the client, parsed server-side
}

func (s *Service) issueTokenPair(ctx context.Context, user *users.User) (*tokenPair, error) {
	// JWT access token
	accessToken, err := middleware.GenerateAccessToken(
		user.ID, user.GymID, string(user.Role), s.jwtSecret,
	)
	if err != nil {
		return nil, fmt.Errorf("generate access token: %w", err)
	}

	// Opaque refresh token: random bytes, bcrypt-hashed for storage
	plainToken, hashStr, err := generateRefreshToken()
	if err != nil {
		return nil, err
	}

	dbToken := &RefreshToken{
		UserID:    user.ID,
		GymID:     user.GymID,
		TokenHash: hashStr,
		ExpiresAt: time.Now().Add(middleware.RefreshTokenTTL),
	}
	if err := s.repo.CreateRefreshToken(ctx, dbToken); err != nil {
		return nil, fmt.Errorf("persist refresh token: %w", err)
	}

	// Encode as "<userID>:<plainToken>" so we can find the right DB record without
	// scanning all tokens. The userID prefix is not secret — it just enables O(1) lookup.
	encodedRefresh := fmt.Sprintf("%d:%s", user.ID, plainToken)

	return &tokenPair{
		accessToken:  accessToken,
		refreshToken: encodedRefresh,
	}, nil
}

// generateRefreshToken produces a cryptographically random token and its bcrypt hash.
func generateRefreshToken() (plain, hash string, err error) {
	b := make([]byte, refreshTokenBytes)
	if _, err = rand.Read(b); err != nil {
		return "", "", fmt.Errorf("generate random bytes: %w", err)
	}
	plain = base64.URLEncoding.EncodeToString(b)

	hashBytes, err := bcrypt.GenerateFromPassword([]byte(plain), bcryptCost)
	if err != nil {
		return "", "", fmt.Errorf("hash refresh token: %w", err)
	}
	return plain, string(hashBytes), nil
}


// toNullableString converts empty string to nil pointer.
// Used for optional fields with unique indexes — prevents "" colliding across rows.
func toNullableString(s string) *string {
	if s == "" {
		return nil
	}
	return &s
}
// splitRefreshToken parses "<userID>:<plainToken>" into its components.
func splitRefreshToken(token string) (userID int64, plain string, err error) {
	idx := strings.IndexByte(token, ':')
	if idx <= 0 {
		return 0, "", fmt.Errorf("invalid token format")
	}
	var id int64
	if _, err := fmt.Sscanf(token[:idx], "%d", &id); err != nil {
		return 0, "", fmt.Errorf("invalid token user prefix")
	}
	return id, token[idx+1:], nil
}

// ─── DTO mappers ──────────────────────────────────────────────────────────────

func toUserDTO(u *users.User) UserDTO {
	return UserDTO{
		ID:    u.ID,
		GymID: u.GymID,
		Name:  u.Name,
		Phone: u.Phone,
		Email: u.Email,
		Role:  string(u.Role),
	}
}

func toGymDTO(g *gyms.Gym) GymDTO {
	return GymDTO{
		ID:     g.ID,
		Name:   g.Name,
		City:   g.City,
		State:  g.State,
		Status: string(g.Status),
	}
}

