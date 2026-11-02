package platform

import (
	"context"
	"crypto/rand"
	"errors"
	"fmt"
	"math/big"
	"strings"
	"time"

	"golang.org/x/crypto/bcrypt"
	"gorm.io/gorm"

	"gymcrm/internal/middleware"
)

const (
	maxFailures = 5
	lockFor     = 15 * time.Minute
	issuer      = "MOKA CRM Platform"
)

var (
	ErrBadCredentials = errors.New("invalid email, password or code")
	ErrLocked         = errors.New("too many failed attempts; try again in 15 minutes")
	ErrNotFound       = errors.New("not found")
	ErrInvalid        = errors.New("invalid request")
	ErrConflict       = errors.New("conflict")
)

type Service struct {
	db     *gorm.DB
	secret string
}

func NewService(db *gorm.DB, secret string) *Service { return &Service{db: db, secret: secret} }

type Admin struct {
	ID              int64      `json:"id"`
	Email           string     `json:"email"`
	Name            string     `json:"name"`
	PasswordHash    string     `json:"-"`
	TOTPSecret      *string    `json:"-"`
	TOTPConfirmedAt *time.Time `json:"-"`
	TOTPLastStep    int64      `json:"-"`
	FailedAttempts  int        `json:"-"`
	LockedUntil     *time.Time `json:"-"`
	Status          string     `json:"status"`
	Enrolled        bool       `json:"enrolled" gorm:"-"`
	CreatedAt       time.Time  `json:"created_at"`
}

func (Admin) TableName() string { return "platform_admins" }

func (s *Service) adminByID(ctx context.Context, id int64) (*Admin, error) {
	var a Admin
	err := s.db.WithContext(ctx).Where("id = ?", id).First(&a).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, ErrNotFound
	}
	a.Enrolled = a.TOTPConfirmedAt != nil
	return &a, err
}

// ── Login & 2FA ──────────────────────────────────────────────────────────────

type LoginResult struct {
	TOTPRequired      bool       `json:"totp_required,omitempty"`
	EnrolmentRequired bool       `json:"enrolment_required,omitempty"`
	Token             string     `json:"token,omitempty"` // enrol-scope or session-scope
	ExpiresAt         *time.Time `json:"expires_at,omitempty"`
	Admin             *Admin     `json:"admin,omitempty"`
}

func (s *Service) Login(ctx context.Context, email, password, code, recovery string) (*LoginResult, error) {
	var a Admin
	err := s.db.WithContext(ctx).Where("LOWER(email) = ?", strings.ToLower(strings.TrimSpace(email))).First(&a).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		_ = bcrypt.CompareHashAndPassword([]byte("$2a$12$0000000000000000000000000000000000000000000000000000"), []byte(password)) // timing
		return nil, ErrBadCredentials
	} else if err != nil {
		return nil, err
	}
	if a.LockedUntil != nil && a.LockedUntil.After(time.Now()) {
		return nil, ErrLocked
	}
	if a.Status != "active" || bcrypt.CompareHashAndPassword([]byte(a.PasswordHash), []byte(password)) != nil {
		return nil, s.fail(ctx, &a)
	}
	a.Enrolled = a.TOTPConfirmedAt != nil

	if !a.Enrolled { // password alone only opens enrolment (§10)
		tok, exp, err := issue(s.secret, a.ID, ScopeEnroll, EnrollTTL)
		return &LoginResult{EnrolmentRequired: true, Token: tok, ExpiresAt: &exp, Admin: &a}, err
	}
	if strings.TrimSpace(code) == "" && strings.TrimSpace(recovery) == "" {
		return &LoginResult{TOTPRequired: true}, nil
	}
	if strings.TrimSpace(recovery) != "" {
		if !s.useRecoveryCode(ctx, a.ID, recovery) {
			return nil, s.fail(ctx, &a)
		}
	} else {
		step, ok := verifyTOTP(*a.TOTPSecret, code, time.Now(), a.TOTPLastStep)
		if !ok {
			return nil, s.fail(ctx, &a)
		}
		s.db.WithContext(ctx).Exec("UPDATE platform_admins SET totp_last_step = ? WHERE id = ?", step, a.ID)
	}
	s.db.WithContext(ctx).Exec("UPDATE platform_admins SET failed_attempts = 0, locked_until = NULL WHERE id = ?", a.ID)
	tok, exp, err := issue(s.secret, a.ID, ScopeSession, SessionTTL)
	return &LoginResult{Token: tok, ExpiresAt: &exp, Admin: &a}, err
}

// fail counts a failed attempt and locks the account after five (§10).
func (s *Service) fail(ctx context.Context, a *Admin) error {
	n := a.FailedAttempts + 1
	if n >= maxFailures {
		s.db.WithContext(ctx).Exec("UPDATE platform_admins SET failed_attempts = 0, locked_until = ? WHERE id = ?", time.Now().Add(lockFor), a.ID)
		return ErrLocked
	}
	s.db.WithContext(ctx).Exec("UPDATE platform_admins SET failed_attempts = ? WHERE id = ?", n, a.ID)
	return ErrBadCredentials
}

func (s *Service) useRecoveryCode(ctx context.Context, adminID int64, code string) bool {
	var rows []struct {
		ID       int64
		CodeHash string
	}
	s.db.WithContext(ctx).Raw("SELECT id, code_hash FROM platform_recovery_codes WHERE admin_id = ? AND used_at IS NULL", adminID).Scan(&rows)
	code = strings.ToLower(strings.TrimSpace(code))
	for _, r := range rows {
		if bcrypt.CompareHashAndPassword([]byte(r.CodeHash), []byte(code)) == nil {
			res := s.db.WithContext(ctx).Exec("UPDATE platform_recovery_codes SET used_at = now() WHERE id = ? AND used_at IS NULL", r.ID)
			return res.RowsAffected == 1 // single use, race-safe
		}
	}
	return false
}

type Enrolment struct {
	Secret string `json:"secret"`
	URI    string `json:"otpauth_uri"`
}

// StartEnrolment generates (or regenerates, while unconfirmed) the secret.
func (s *Service) StartEnrolment(ctx context.Context, adminID int64) (*Enrolment, error) {
	a, err := s.adminByID(ctx, adminID)
	if err != nil {
		return nil, err
	}
	if a.Enrolled {
		return nil, fmt.Errorf("%w: already enrolled", ErrConflict)
	}
	sec, err := newTOTPSecret()
	if err != nil {
		return nil, err
	}
	if err := s.db.WithContext(ctx).Exec("UPDATE platform_admins SET totp_secret = ? WHERE id = ?", sec, adminID).Error; err != nil {
		return nil, err
	}
	return &Enrolment{Secret: sec, URI: otpauthURI(issuer, a.Email, sec)}, nil
}

type ConfirmResult struct {
	RecoveryCodes []string  `json:"recovery_codes"`
	Token         string    `json:"token"`
	ExpiresAt     time.Time `json:"expires_at"`
	Admin         *Admin    `json:"admin"`
}

// ConfirmEnrolment activates the secret only after a valid code proves the
// authenticator holds it, then issues the ten one-time recovery codes.
func (s *Service) ConfirmEnrolment(ctx context.Context, adminID int64, code string) (*ConfirmResult, error) {
	a, err := s.adminByID(ctx, adminID)
	if err != nil {
		return nil, err
	}
	if a.Enrolled || a.TOTPSecret == nil {
		return nil, fmt.Errorf("%w: nothing to confirm", ErrConflict)
	}
	step, ok := verifyTOTP(*a.TOTPSecret, code, time.Now(), 0)
	if !ok {
		return nil, s.fail(ctx, a)
	}
	codes, err := newRecoveryCodes(10)
	if err != nil {
		return nil, err
	}
	err = s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := tx.Exec("UPDATE platform_admins SET totp_confirmed_at = now(), totp_last_step = ?, failed_attempts = 0 WHERE id = ?", step, adminID).Error; err != nil {
			return err
		}
		if err := tx.Exec("DELETE FROM platform_recovery_codes WHERE admin_id = ?", adminID).Error; err != nil {
			return err
		}
		for _, c := range codes {
			h, err := bcrypt.GenerateFromPassword([]byte(c), 10)
			if err != nil {
				return err
			}
			if err := tx.Exec("INSERT INTO platform_recovery_codes (admin_id, code_hash) VALUES (?, ?)", adminID, string(h)).Error; err != nil {
				return err
			}
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	tok, exp, err := issue(s.secret, adminID, ScopeSession, SessionTTL)
	a.Enrolled = true
	return &ConfirmResult{RecoveryCodes: codes, Token: tok, ExpiresAt: exp, Admin: a}, err
}

// ── Admins ───────────────────────────────────────────────────────────────────

func randomPassword() (string, error) {
	const a = "abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	b := make([]byte, 16)
	for i := range b {
		n, err := rand.Int(rand.Reader, big.NewInt(int64(len(a))))
		if err != nil {
			return "", err
		}
		b[i] = a[n.Int64()]
	}
	return string(b), nil
}

// CreateAdmin makes an account that can only log in and enrol. Returns the
// one-time password, which the caller shows once. createdBy 0 = bootstrap CLI.
func (s *Service) CreateAdmin(ctx context.Context, createdBy int64, email, name string) (*Admin, string, error) {
	email = strings.ToLower(strings.TrimSpace(email))
	name = strings.TrimSpace(name)
	if !strings.Contains(email, "@") || name == "" {
		return nil, "", fmt.Errorf("%w: name and a valid email are required", ErrInvalid)
	}
	pw, err := randomPassword()
	if err != nil {
		return nil, "", err
	}
	h, err := bcrypt.GenerateFromPassword([]byte(pw), 12)
	if err != nil {
		return nil, "", err
	}
	var by interface{}
	if createdBy != 0 {
		by = createdBy
	}
	var a Admin
	err = s.db.WithContext(ctx).Raw(
		`INSERT INTO platform_admins (email, name, password_hash, created_by) VALUES (?, ?, ?, ?)
		 RETURNING id, email, name, status, created_at`, email, name, string(h), by).Scan(&a).Error
	if err != nil {
		if strings.Contains(err.Error(), "idx_platform_admins_email") {
			return nil, "", fmt.Errorf("%w: an admin with that email exists", ErrConflict)
		}
		return nil, "", err
	}
	if createdBy != 0 {
		s.logAction(ctx, createdBy, nil, "admin_created", email)
	}
	return &a, pw, nil
}

func (s *Service) ListAdmins(ctx context.Context) ([]Admin, error) {
	var out []Admin
	err := s.db.WithContext(ctx).Raw(`SELECT id, email, name, status, created_at,
		(totp_confirmed_at IS NOT NULL) AS enrolled FROM platform_admins ORDER BY id`).Scan(&out).Error
	return out, err
}

// ResetAdmin clears another admin's 2FA and password (lost phone AND codes,
// §10). The target gets a new one-time password and must re-enrol.
func (s *Service) ResetAdmin(ctx context.Context, by, target int64) (string, error) {
	if by == target {
		return "", fmt.Errorf("%w: another admin must reset your account", ErrInvalid)
	}
	t, err := s.adminByID(ctx, target)
	if err != nil {
		return "", err
	}
	pw, err := randomPassword()
	if err != nil {
		return "", err
	}
	h, _ := bcrypt.GenerateFromPassword([]byte(pw), 12)
	err = s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := tx.Exec(`UPDATE platform_admins SET password_hash = ?, totp_secret = NULL, totp_confirmed_at = NULL,
			totp_last_step = 0, failed_attempts = 0, locked_until = NULL WHERE id = ?`, string(h), target).Error; err != nil {
			return err
		}
		return tx.Exec("DELETE FROM platform_recovery_codes WHERE admin_id = ?", target).Error
	})
	if err == nil {
		s.logAction(ctx, by, nil, "admin_reset", t.Email)
	}
	return pw, err
}

// ── Audit ────────────────────────────────────────────────────────────────────

func (s *Service) logAction(ctx context.Context, adminID int64, gymID *int64, action, detail string) {
	if err := s.db.WithContext(ctx).Exec(
		"INSERT INTO platform_action_log (admin_id, gym_id, action, detail) VALUES (?, ?, ?, ?)",
		adminID, gymID, action, detail).Error; err != nil {
		fmt.Printf("ERROR platform audit log: %v\n", err)
	}
}

type AccessEntry struct {
	ID        int64     `json:"id"`
	AdminName string    `json:"admin_name"`
	GymID     int64     `json:"gym_id"`
	GymName   string    `json:"gym_name,omitempty"`
	Reason    string    `json:"reason"`
	StartedAt time.Time `json:"started_at"`
	ExpiresAt time.Time `json:"expires_at"`
}

type ActionEntry struct {
	ID        int64     `json:"id"`
	AdminName string    `json:"admin_name"`
	GymID     *int64    `json:"gym_id,omitempty"`
	GymName   string    `json:"gym_name,omitempty"`
	Action    string    `json:"action"`
	Detail    string    `json:"detail"`
	CreatedAt time.Time `json:"created_at"`
}

func (s *Service) AccessLog(ctx context.Context, gymID, adminID int64) ([]AccessEntry, []ActionEntry, error) {
	acc := []AccessEntry{}
	act := []ActionEntry{}
	err := s.db.WithContext(ctx).Raw(`SELECT l.id, a.name AS admin_name, l.gym_id, g.name AS gym_name, l.reason, l.started_at, l.expires_at
		FROM platform_access_log l JOIN platform_admins a ON a.id = l.admin_id JOIN gyms g ON g.id = l.gym_id
		WHERE (? = 0 OR l.gym_id = ?) AND (? = 0 OR l.admin_id = ?) ORDER BY l.started_at DESC LIMIT 200`,
		gymID, gymID, adminID, adminID).Scan(&acc).Error
	if err != nil {
		return nil, nil, err
	}
	err = s.db.WithContext(ctx).Raw(`SELECT l.id, a.name AS admin_name, l.gym_id, g.name AS gym_name, l.action, l.detail, l.created_at
		FROM platform_action_log l JOIN platform_admins a ON a.id = l.admin_id LEFT JOIN gyms g ON g.id = l.gym_id
		WHERE (? = 0 OR l.gym_id = ?) AND (? = 0 OR l.admin_id = ?) ORDER BY l.created_at DESC LIMIT 200`,
		gymID, gymID, adminID, adminID).Scan(&act).Error
	return acc, act, err
}

// GymSupportHistory is what a gym owner sees about vendor access to their own
// account (§6): which admin, when, for how long, and the stated reason.
func (s *Service) GymSupportHistory(ctx context.Context, gymID int64) ([]AccessEntry, error) {
	out := []AccessEntry{}
	err := s.db.WithContext(ctx).Raw(`SELECT l.id, a.name AS admin_name, l.gym_id, l.reason, l.started_at, l.expires_at
		FROM platform_access_log l JOIN platform_admins a ON a.id = l.admin_id
		WHERE l.gym_id = ? ORDER BY l.started_at DESC LIMIT 100`, gymID).Scan(&out).Error
	return out, err
}

// ── Gyms ─────────────────────────────────────────────────────────────────────

// GymRow is aggregate-only: counts and dates, never a name or a phone (§4).
type GymRow struct {
	ID                 int64      `json:"id"`
	Name               string     `json:"name"`
	City               string     `json:"city"`
	Status             string     `json:"status"`
	PlanTier           string     `json:"plan_tier"`
	SubscriptionStatus string     `json:"subscription_status"`
	SuspendedReason    *string    `json:"suspended_reason,omitempty"`
	CreatedAt          time.Time  `json:"created_at"`
	Members            int        `json:"members"`
	LastLogin          *time.Time `json:"last_login,omitempty"`
	LastCheckIn        *time.Time `json:"last_check_in,omitempty"`
}

const gymSelect = `SELECT g.id, g.name, g.city, g.status, g.plan_tier, g.subscription_status, g.suspended_reason, g.created_at,
	(SELECT count(*) FROM members m WHERE m.gym_id = g.id AND m.deleted_at IS NULL) AS members,
	(SELECT max(t.created_at) FROM refresh_tokens t WHERE t.gym_id = g.id) AS last_login,
	(SELECT max(a.checked_in_at) FROM attendance a WHERE a.gym_id = g.id) AS last_check_in
	FROM gyms g`

func (s *Service) ListGyms(ctx context.Context) ([]GymRow, error) {
	out := []GymRow{}
	err := s.db.WithContext(ctx).Raw(gymSelect + " ORDER BY g.id").Scan(&out).Error
	return out, err
}

type GymSummary struct {
	GymRow
	ActiveMembers   int `json:"active_members"`
	Staff           int `json:"staff"`
	Payments30Days  int `json:"payments_30_days"`
	CheckIns30Days  int `json:"check_ins_30_days"`
	SupportAccesses int `json:"support_accesses"`
}

func (s *Service) GymSummary(ctx context.Context, id int64) (*GymSummary, error) {
	var out GymSummary
	err := s.db.WithContext(ctx).Raw(`SELECT * FROM (`+gymSelect+` WHERE g.id = ?) x`, id).Scan(&out.GymRow).Error
	if err != nil {
		return nil, err
	}
	if out.ID == 0 {
		return nil, ErrNotFound
	}
	s.db.WithContext(ctx).Raw(`SELECT
		(SELECT count(*) FROM members WHERE gym_id = ? AND deleted_at IS NULL AND status = 'active'),
		(SELECT count(*) FROM users WHERE gym_id = ? AND status = 'active'),
		(SELECT count(*) FROM payments WHERE gym_id = ? AND created_at > now() - interval '30 days'),
		(SELECT count(*) FROM attendance WHERE gym_id = ? AND checked_in_at > now() - interval '30 days'),
		(SELECT count(*) FROM platform_access_log WHERE gym_id = ?)`, id, id, id, id, id).Row().Scan(
		&out.ActiveMembers, &out.Staff, &out.Payments30Days, &out.CheckIns30Days, &out.SupportAccesses)
	return &out, nil
}

type CreateGymInput struct {
	GymName   string `json:"gym_name"`
	OwnerName string `json:"owner_name"`
	Phone     string `json:"phone"`
	Email     string `json:"email"`
	City      string `json:"city"`
	State     string `json:"state"`
	Password  string `json:"password"`
	PlanTier  string `json:"plan_tier"`
}

// CreateGym adds a customer and its first owner (§12). The owner's phone is
// also the gym's phone, matching self-registration.
func (s *Service) CreateGym(ctx context.Context, adminID int64, in CreateGymInput) (*GymRow, error) {
	in.GymName, in.OwnerName, in.Phone = strings.TrimSpace(in.GymName), strings.TrimSpace(in.OwnerName), strings.TrimSpace(in.Phone)
	if in.GymName == "" || in.OwnerName == "" || len(in.Phone) < 10 || len(in.Password) < 8 {
		return nil, fmt.Errorf("%w: gym name, owner name, 10-digit phone and an 8+ character password are required", ErrInvalid)
	}
	if in.PlanTier == "" {
		in.PlanTier = "normal"
	}
	if !validTier(in.PlanTier) {
		return nil, fmt.Errorf("%w: plan must be normal, medium or premium", ErrInvalid)
	}
	if in.City == "" {
		in.City = "Ludhiana"
	}
	if in.State == "" {
		in.State = "Punjab"
	}
	h, err := bcrypt.GenerateFromPassword([]byte(in.Password), 12)
	if err != nil {
		return nil, err
	}
	var gymID int64
	err = s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		var email interface{}
		if strings.TrimSpace(in.Email) != "" {
			email = strings.TrimSpace(in.Email)
		}
		if err := tx.Raw(`INSERT INTO gyms (name, owner_name, phone, email, city, state, plan_tier, subscription_status)
			VALUES (?, ?, ?, ?, ?, ?, ?, 'trial') RETURNING id`,
			in.GymName, in.OwnerName, in.Phone, email, in.City, in.State, in.PlanTier).Row().Scan(&gymID); err != nil {
			return err
		}
		return tx.Exec(`INSERT INTO users (gym_id, name, phone, email, password_hash, role, status)
			VALUES (?, ?, ?, ?, ?, 'owner', 'active')`, gymID, in.OwnerName, in.Phone, strings.TrimSpace(in.Email), string(h)).Error
	})
	if err != nil {
		if strings.Contains(err.Error(), "duplicate key") {
			return nil, fmt.Errorf("%w: a gym or user with that phone already exists", ErrConflict)
		}
		return nil, err
	}
	s.logAction(ctx, adminID, &gymID, "gym_created", in.GymName+" ("+in.PlanTier+")")
	var row GymRow
	s.db.WithContext(ctx).Raw(gymSelect+" WHERE g.id = ?", gymID).Scan(&row)
	return &row, nil
}

func validTier(t string) bool { return t == "normal" || t == "medium" || t == "premium" }

// SetPlan changes the pricing tier — the field internal/entitlements enforces.
func (s *Service) SetPlan(ctx context.Context, adminID, gymID int64, tier string) error {
	if !validTier(tier) {
		return fmt.Errorf("%w: plan must be normal, medium or premium", ErrInvalid)
	}
	var old string
	if err := s.db.WithContext(ctx).Raw("SELECT plan_tier FROM gyms WHERE id = ?", gymID).Row().Scan(&old); err != nil {
		return ErrNotFound
	}
	if err := s.db.WithContext(ctx).Exec("UPDATE gyms SET plan_tier = ?, updated_at = now() WHERE id = ?", tier, gymID).Error; err != nil {
		return err
	}
	s.logAction(ctx, adminID, &gymID, "plan_changed", old+" -> "+tier)
	return nil
}

func (s *Service) SetSubscription(ctx context.Context, adminID, gymID int64, status string) error {
	switch status {
	case "trial", "active", "past_due", "cancelled":
	default:
		return fmt.Errorf("%w: subscription must be trial, active, past_due or cancelled", ErrInvalid)
	}
	res := s.db.WithContext(ctx).Exec("UPDATE gyms SET subscription_status = ?, updated_at = now() WHERE id = ?", status, gymID)
	if res.Error != nil {
		return res.Error
	}
	if res.RowsAffected == 0 {
		return ErrNotFound
	}
	s.logAction(ctx, adminID, &gymID, "subscription_changed", status)
	return nil
}

// Suspend stops the gym's users logging in. It deletes and hides nothing (§8),
// and revokes refresh tokens so open sessions end within one access-token TTL.
func (s *Service) Suspend(ctx context.Context, adminID, gymID int64, reason string) error {
	reason = strings.TrimSpace(reason)
	if reason == "" {
		return fmt.Errorf("%w: a reason is required", ErrInvalid)
	}
	err := s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		res := tx.Exec("UPDATE gyms SET status = 'suspended', suspended_reason = ?, updated_at = now() WHERE id = ?", reason, gymID)
		if res.Error != nil {
			return res.Error
		}
		if res.RowsAffected == 0 {
			return ErrNotFound
		}
		return tx.Exec("UPDATE refresh_tokens SET revoked_at = now() WHERE gym_id = ? AND revoked_at IS NULL", gymID).Error
	})
	if err == nil {
		s.logAction(ctx, adminID, &gymID, "suspended", reason)
	}
	return err
}

func (s *Service) Resume(ctx context.Context, adminID, gymID int64, reason string) error {
	reason = strings.TrimSpace(reason)
	if reason == "" {
		return fmt.Errorf("%w: a reason is required", ErrInvalid)
	}
	res := s.db.WithContext(ctx).Exec("UPDATE gyms SET status = 'active', suspended_reason = NULL, updated_at = now() WHERE id = ?", gymID)
	if res.Error != nil {
		return res.Error
	}
	if res.RowsAffected == 0 {
		return ErrNotFound
	}
	s.logAction(ctx, adminID, &gymID, "resumed", reason)
	return nil
}

// ── Support access ───────────────────────────────────────────────────────────

type SupportSession struct {
	AccessToken string    `json:"access_token"`
	ExpiresAt   time.Time `json:"expires_at"`
	User        any       `json:"user"`
	Gym         any       `json:"gym"`
}

// EnterGym mints the 30-minute, read-only gym token. The log row is written
// BEFORE the token is returned, so no access can exist unrecorded (§7).
func (s *Service) EnterGym(ctx context.Context, adminID, gymID int64, reason, gymSecret string) (*SupportSession, error) {
	reason = strings.TrimSpace(reason)
	if len(reason) < 5 {
		return nil, fmt.Errorf("%w: a reason is required (say why you are looking at this gym)", ErrInvalid)
	}
	var owner struct {
		ID    int64
		Name  string
		Phone string
	}
	var gym struct {
		ID       int64  `json:"id"`
		Name     string `json:"name"`
		City     string `json:"city"`
		State    string `json:"state"`
		Status   string `json:"status"`
		PlanTier string `json:"plan_tier"`
	}
	if err := s.db.WithContext(ctx).Raw("SELECT id, name, city, state, status, plan_tier FROM gyms WHERE id = ?", gymID).Scan(&gym).Error; err != nil {
		return nil, err
	}
	if gym.ID == 0 {
		return nil, ErrNotFound
	}
	if err := s.db.WithContext(ctx).Raw(
		"SELECT id, name, phone FROM users WHERE gym_id = ? AND role = 'owner' AND status = 'active' ORDER BY id LIMIT 1", gymID).Scan(&owner).Error; err != nil || owner.ID == 0 {
		return nil, fmt.Errorf("%w: this gym has no active owner to view as", ErrInvalid)
	}
	tok, exp, err := middleware.GenerateSupportToken(owner.ID, gymID, adminID, gymSecret)
	if err != nil {
		return nil, err
	}
	if err := s.db.WithContext(ctx).Exec(
		"INSERT INTO platform_access_log (admin_id, gym_id, reason, expires_at) VALUES (?, ?, ?, ?)",
		adminID, gymID, reason, exp).Error; err != nil {
		return nil, err
	}
	return &SupportSession{
		AccessToken: tok, ExpiresAt: exp, Gym: gym,
		User: map[string]any{"id": owner.ID, "gym_id": gymID, "name": owner.Name, "phone": owner.Phone, "role": "owner"},
	}, nil
}
