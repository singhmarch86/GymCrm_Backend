package auth

// ─── Request DTOs ─────────────────────────────────────────────────────────────

// RegisterGymRequest is the payload for POST /api/v1/auth/register.
// This creates the gym (tenant) AND the first owner user atomically.
// @Description Gym registration payload. Creates gym and owner account in one step.
type RegisterGymRequest struct {
	// Gym details
	GymName string `json:"gym_name"  validate:"required,min=2,max=200"`
	City    string `json:"city"      validate:"required,min=2,max=100"`
	State   string `json:"state"     validate:"required,min=2,max=100"`
	Address string `json:"address"   validate:"max=500"`

	// Owner account
	OwnerName string `json:"owner_name" validate:"required,min=2,max=200"`
	Phone     string `json:"phone"      validate:"required,min=10,max=15"`
	Password  string `json:"password"   validate:"required,min=8,max=72"`
	Email     string `json:"email"      validate:"omitempty,email,max=200"`

	// InviteCode is required only when the deployment runs in invite mode.
	// Deliberately not validated by the struct rules — an empty code is a
	// permissions failure (403), not a malformed request (422).
	InviteCode string `json:"invite_code,omitempty"`
}

// LoginRequest is the payload for POST /api/v1/auth/login.
// Phone is the primary identifier — gym owners in Punjab don't reliably use email.
// @Description Login with phone + password. Returns access + refresh tokens.
type LoginRequest struct {
	Phone    string `json:"phone"    validate:"required,min=10,max=15"`
	Password string `json:"password" validate:"required,min=1,max=72"`
}

// RefreshRequest is the payload for POST /api/v1/auth/refresh.
// @Description Exchange a valid refresh token for a new access + refresh token pair.
type RefreshRequest struct {
	RefreshToken string `json:"refresh_token" validate:"required"`
}

// ─── Response DTOs ────────────────────────────────────────────────────────────

// AuthResponse is returned on successful login and refresh.
// @Description Successful authentication response with token pair.
type AuthResponse struct {
	AccessToken  string  `json:"access_token"`
	RefreshToken string  `json:"refresh_token"`
	TokenType    string  `json:"token_type"` // always "Bearer"
	ExpiresIn    int     `json:"expires_in"` // access token TTL in seconds
	User         UserDTO `json:"user"`
}

// RegisterResponse is returned after successful gym registration.
// @Description Gym registration success response.
type RegisterResponse struct {
	Gym  GymDTO  `json:"gym"`
	User UserDTO `json:"user"`
	// Tokens so the app is usable immediately after registration
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	TokenType    string `json:"token_type"`
	ExpiresIn    int    `json:"expires_in"`
}

// UserDTO is the safe user representation — no password, no sensitive fields.
// @Description Safe user object returned in auth responses.
type UserDTO struct {
	ID    int64  `json:"id"`
	GymID int64  `json:"gym_id"`
	Name  string `json:"name"`
	Phone string `json:"phone"`
	Email string `json:"email,omitempty"`
	Role  string `json:"role"`
}

// GymDTO is the safe gym representation.
// @Description Gym object returned in auth responses.
type GymDTO struct {
	ID     int64  `json:"id"`
	Name   string `json:"name"`
	City   string `json:"city"`
	State  string `json:"state"`
	Status string `json:"status"`
}

// MeResponse is returned by GET /api/v1/auth/me.
// Designed as a tenant-verification and session-check endpoint for Flutter.
// @Description Current authenticated user and their gym context.
type MeResponse struct {
	User UserDTO `json:"user"`
	Gym  GymDTO  `json:"gym"`
}
