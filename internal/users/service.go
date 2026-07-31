package users

import (
	"context"
	"fmt"
	"strings"
	"unicode"

	"golang.org/x/crypto/bcrypt"

	"gymcrm/internal/database"
)

// bcryptCost must match auth's cost so staff and owner credentials are hashed
// identically. It is duplicated rather than imported because auth imports this
// package — importing back would be a cycle. A drift here would not break
// verification (bcrypt embeds the cost in every hash) but would make new
// passwords inconsistent with existing ones, so keep the two in step.
const bcryptCost = 12

type Service struct {
	repo *Repository
}

func NewService(repo *Repository) *Service {
	return &Service{repo: repo}
}

func (s *Service) ListStaff(ctx context.Context) ([]StaffRow, error) {
	out, err := s.repo.List(ctx)
	if err != nil {
		return nil, fmt.Errorf("list staff: %w", err)
	}
	return out, nil
}

func (s *Service) CreateStaff(ctx context.Context, req CreateStaffRequest) (*StaffRow, error) {
	req.Name = strings.TrimSpace(req.Name)
	req.Phone = strings.TrimSpace(req.Phone)
	req.Email = strings.TrimSpace(req.Email)

	if req.Name == "" {
		return nil, ErrNameRequired
	}
	if req.Phone == "" {
		return nil, ErrPhoneRequired
	}
	if err := validatePassword(req.Password); err != nil {
		return nil, err
	}

	role := RoleStaff
	if req.Role != "" {
		parsed, err := parseRole(req.Role)
		if err != nil {
			return nil, err
		}
		role = parsed
	}

	// Phone is the login identity and login resolves it table-wide, so it must
	// be globally unique — not merely unique within this gym.
	taken, err := s.repo.PhoneExistsAnywhere(ctx, req.Phone, 0)
	if err != nil {
		return nil, fmt.Errorf("create staff: %w", err)
	}
	if taken {
		return nil, ErrPhoneTaken
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcryptCost)
	if err != nil {
		return nil, fmt.Errorf("create staff: hash password: %w", err)
	}

	user := &User{
		Name:         req.Name,
		Phone:        req.Phone,
		Email:        req.Email,
		PasswordHash: string(hash),
		Role:         role,
		Status:       UserStatusActive,
	}
	if err := s.repo.Create(ctx, user); err != nil {
		return nil, fmt.Errorf("create staff: %w", err)
	}

	return s.findRow(ctx, user.ID)
}

func (s *Service) UpdateStaff(ctx context.Context, id int64, req UpdateStaffRequest) (*StaffRow, error) {
	existing, err := s.repo.FindByID(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("update staff: %w", err)
	}
	if existing == nil {
		return nil, ErrUserNotFound
	}

	tc := database.MustGetTenant(ctx)
	updates := map[string]interface{}{}

	if req.Name != nil {
		name := strings.TrimSpace(*req.Name)
		if name == "" {
			return nil, ErrNameRequired
		}
		updates["name"] = name
	}

	if req.Phone != nil {
		phone := strings.TrimSpace(*req.Phone)
		if phone == "" {
			return nil, ErrPhoneRequired
		}
		taken, err := s.repo.PhoneExistsAnywhere(ctx, phone, id)
		if err != nil {
			return nil, fmt.Errorf("update staff: %w", err)
		}
		if taken {
			return nil, ErrPhoneTaken
		}
		updates["phone"] = phone
	}

	if req.Email != nil {
		updates["email"] = strings.TrimSpace(*req.Email)
	}

	if req.Role != nil {
		role, err := parseRole(*req.Role)
		if err != nil {
			return nil, err
		}
		// Changing your own role could strip your own admin access mid-session.
		if id == tc.UserID() && role != existing.Role {
			return nil, ErrCannotDemoteSelf
		}
		// Demoting the last active owner would leave the gym unadministrable.
		if existing.Role == RoleOwner && role != RoleOwner {
			others, err := s.repo.CountActiveOwners(ctx, id)
			if err != nil {
				return nil, fmt.Errorf("update staff: %w", err)
			}
			if others == 0 {
				return nil, ErrLastActiveOwner
			}
		}
		updates["role"] = role
	}

	if len(updates) == 0 {
		return s.findRow(ctx, id)
	}

	if err := s.repo.Update(ctx, id, updates); err != nil {
		return nil, fmt.Errorf("update staff: save: %w", err)
	}
	return s.findRow(ctx, id)
}

// SetStatus activates or deactivates an account.
//
// Deactivating deliberately does NOT unassign the user's leads. Silently
// reassigning or orphaning work when someone goes inactive loses information;
// the lists keep showing them as the owner, flagged inactive, so a human can
// decide where that work should go.
func (s *Service) SetStatus(ctx context.Context, id int64, req UpdateStatusRequest) (*StaffRow, error) {
	existing, err := s.repo.FindByID(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("set status: %w", err)
	}
	if existing == nil {
		return nil, ErrUserNotFound
	}

	status, err := parseStatus(req.Status)
	if err != nil {
		return nil, err
	}

	tc := database.MustGetTenant(ctx)
	if status == UserStatusInactive {
		if id == tc.UserID() {
			return nil, ErrCannotDeactivateSelf
		}
		if existing.Role == RoleOwner {
			others, err := s.repo.CountActiveOwners(ctx, id)
			if err != nil {
				return nil, fmt.Errorf("set status: %w", err)
			}
			if others == 0 {
				return nil, ErrLastActiveOwner
			}
		}
	}

	if err := s.repo.Update(ctx, id, map[string]interface{}{"status": status}); err != nil {
		return nil, fmt.Errorf("set status: save: %w", err)
	}
	return s.findRow(ctx, id)
}

func (s *Service) ResetPassword(ctx context.Context, id int64, req ResetPasswordRequest) error {
	existing, err := s.repo.FindByID(ctx, id)
	if err != nil {
		return fmt.Errorf("reset password: %w", err)
	}
	if existing == nil {
		return ErrUserNotFound
	}
	if err := validatePassword(req.Password); err != nil {
		return err
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcryptCost)
	if err != nil {
		return fmt.Errorf("reset password: hash: %w", err)
	}
	if err := s.repo.Update(ctx, id, map[string]interface{}{
		"password_hash": string(hash),
	}); err != nil {
		return fmt.Errorf("reset password: save: %w", err)
	}
	return nil
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

// findRow re-reads through the list query so the response carries the same
// shape (including lead_count) as GET /api/v1/users.
func (s *Service) findRow(ctx context.Context, id int64) (*StaffRow, error) {
	rows, err := s.repo.List(ctx)
	if err != nil {
		return nil, fmt.Errorf("load staff: %w", err)
	}
	for i := range rows {
		if rows[i].ID == id {
			return &rows[i], nil
		}
	}
	return nil, ErrUserNotFound
}

func parseRole(s string) (UserRole, error) {
	switch UserRole(strings.ToLower(strings.TrimSpace(s))) {
	case RoleOwner:
		return RoleOwner, nil
	case RoleStaff:
		return RoleStaff, nil
	}
	return "", ErrInvalidRole
}

func parseStatus(s string) (UserStatus, error) {
	switch UserStatus(strings.ToLower(strings.TrimSpace(s))) {
	case UserStatusActive:
		return UserStatusActive, nil
	case UserStatusInactive:
		return UserStatusInactive, nil
	}
	return "", ErrInvalidStatus
}

// validatePassword mirrors auth's rules so staff credentials are held to the
// same standard as the owner's.
func validatePassword(p string) error {
	if len(p) < 8 {
		return ErrWeakPassword
	}
	if len(p) > 72 {
		// bcrypt silently truncates past 72 bytes — reject rather than accept a
		// password whose tail is ignored.
		return ErrLongPassword
	}
	for _, r := range p {
		if unicode.IsDigit(r) {
			return nil
		}
	}
	return ErrWeakPassword
}
