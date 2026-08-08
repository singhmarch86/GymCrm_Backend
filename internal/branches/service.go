package branches

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"gymcrm/internal/database"
	"gymcrm/internal/middleware"
)

var (
	ErrNoAccess          = errors.New("you do not have access to that branch")
	ErrBranchNotFound    = errors.New("branch not found")
	ErrNotOwner          = errors.New("only an owner can do that")
	ErrNameRequired      = errors.New("branch name is required")
	ErrDifferentOrg      = errors.New("that branch belongs to a different organization")
	ErrUserDifferentOrg  = errors.New("that user belongs to a different organization")
	ErrCannotRevokeSelf  = errors.New("you cannot revoke your own access")
	ErrMemberNotInBranch  = errors.New("that member is not in this branch")
	ErrSameBranch         = errors.New("already in that branch")
	ErrUserNotFound       = errors.New("staff member not found")
	ErrTrainerNotInBranch = errors.New("that trainer is not in this branch")
)

// Service implements branch listing, switching and chain-level reporting.
// See docs/FR-06-multi-location.md.
type Service struct {
	repo      *Repository
	jwtSecret string
}

func NewService(repo *Repository, jwtSecret string) *Service {
	return &Service{repo: repo, jwtSecret: jwtSecret}
}

// MyBranches lists the branches the caller may act in.
func (s *Service) MyBranches(ctx context.Context) ([]Branch, error) {
	tc := database.MustGetTenant(ctx)
	list, err := s.repo.AccessibleBranches(ctx, tc.UserID())
	if err != nil {
		return nil, fmt.Errorf("my branches: %w", err)
	}
	return list, nil
}

// SwitchResult carries a token scoped to the newly selected branch.
type SwitchResult struct {
	AccessToken string `json:"access_token"`
	TokenType   string `json:"token_type"`
	ExpiresIn   int    `json:"expires_in"`
	GymID       int64  `json:"gym_id"`
	BranchName  string `json:"branch_name"`
	Role        string `json:"role"`
}

// Switch issues a new token scoped to another branch.
//
// SECURITY: this is the check that stands between an authenticated user and
// every other gym's data. The requested gym_id arrives from the client, so it
// is treated as a request and verified against the user's grants. A user with
// no grant gets ErrNoAccess and no token — never a token with a gym_id they
// merely asked for (FR-06 §1.1).
func (s *Service) Switch(ctx context.Context, targetGymID int64) (*SwitchResult, error) {
	tc := database.MustGetTenant(ctx)

	role, err := s.repo.RoleFor(ctx, tc.UserID(), targetGymID)
	if err != nil {
		return nil, fmt.Errorf("switch: access check: %w", err)
	}
	// An empty role means no grant row was found. This is the denial — it must
	// never fall through to a default.
	if role == "" {
		return nil, ErrNoAccess
	}

	branches, err := s.repo.AccessibleBranches(ctx, tc.UserID())
	if err != nil {
		return nil, fmt.Errorf("switch: %w", err)
	}
	name := ""
	for _, b := range branches {
		if b.ID == targetGymID {
			name = b.DisplayName()
			break
		}
	}

	// The new token carries the branch-specific role, so a manager at one
	// branch does not carry manager rights into another.
	token, err := middleware.GenerateAccessToken(tc.UserID(), targetGymID, role, s.jwtSecret)
	if err != nil {
		return nil, fmt.Errorf("switch: issue token: %w", err)
	}

	return &SwitchResult{
		AccessToken: token,
		TokenType:   "Bearer",
		ExpiresIn:   int(middleware.AccessTokenTTL.Seconds()),
		GymID:       targetGymID,
		BranchName:  name,
		Role:        role,
	}, nil
}

// CreateBranch adds a branch to the caller's own organization.
func (s *Service) CreateBranch(ctx context.Context, name, branchName, city, state, phone string) (*Branch, error) {
	tc := database.MustGetTenant(ctx)
	if !isOwnerish(tc.Role()) {
		return nil, ErrNotOwner
	}
	if strings.TrimSpace(name) == "" {
		return nil, ErrNameRequired
	}

	orgID, err := s.repo.OrganizationIDForGym(ctx, tc.GymID())
	if err != nil {
		return nil, fmt.Errorf("create branch: %w", err)
	}
	// A gym with no organization yet gets one created around it, so the first
	// added branch does not silently land in a different chain.
	if orgID == nil {
		newID, err := s.repo.CreateOrganization(ctx, name)
		if err != nil {
			return nil, fmt.Errorf("create branch: organization: %w", err)
		}
		if err := s.repo.UpdateBranch(ctx, tc.GymID(), map[string]any{"organization_id": newID}); err != nil {
			return nil, fmt.Errorf("create branch: link existing gym: %w", err)
		}
		orgID = &newID
	}

	gymID, err := s.repo.CreateBranch(ctx, *orgID, tc.UserID(), name, branchName, city, state, phone)
	if err != nil {
		return nil, fmt.Errorf("create branch: %w", err)
	}
	bn := branchName
	return &Branch{
		ID: gymID, Name: name, BranchName: &bn, City: city, State: state,
		Status: "active", OrganizationID: orgID, Role: RoleOwner,
	}, nil
}

// GrantAccess lets an owner give a colleague access to a branch. Both the user
// and the branch must be inside the caller's own organization.
func (s *Service) GrantAccess(ctx context.Context, userID, gymID int64, role string) error {
	tc := database.MustGetTenant(ctx)
	if !isOwnerish(tc.Role()) {
		return ErrNotOwner
	}
	if role != RoleOwner && role != RoleManager && role != RoleStaff {
		role = RoleStaff
	}

	orgID, err := s.repo.OrganizationIDForGym(ctx, tc.GymID())
	if err != nil {
		return fmt.Errorf("grant: %w", err)
	}
	if orgID == nil {
		return ErrDifferentOrg
	}

	okGym, err := s.repo.GymBelongsToOrganization(ctx, gymID, *orgID)
	if err != nil {
		return fmt.Errorf("grant: %w", err)
	}
	if !okGym {
		return ErrDifferentOrg
	}

	okUser, err := s.repo.UserBelongsToOrganization(ctx, userID, *orgID)
	if err != nil {
		return fmt.Errorf("grant: %w", err)
	}
	if !okUser {
		return ErrUserDifferentOrg
	}

	if err := s.repo.GrantAccess(ctx, userID, gymID, role); err != nil {
		return fmt.Errorf("grant: %w", err)
	}
	return nil
}

func (s *Service) RevokeAccess(ctx context.Context, userID, gymID int64) error {
	tc := database.MustGetTenant(ctx)
	if !isOwnerish(tc.Role()) {
		return ErrNotOwner
	}
	// Removing your own last grant would lock you out of the branch you are
	// standing in, with no way back.
	if userID == tc.UserID() {
		return ErrCannotRevokeSelf
	}
	if err := s.repo.RevokeAccess(ctx, userID, gymID); err != nil {
		return fmt.Errorf("revoke: %w", err)
	}
	return nil
}

// ChainSummary aggregates across the branches the caller can access — and only
// those. An owner of two branches in a five-branch chain sees two (FR-06 §2).
func (s *Service) ChainSummary(ctx context.Context) ([]BranchSummary, error) {
	tc := database.MustGetTenant(ctx)
	branches, err := s.repo.AccessibleBranches(ctx, tc.UserID())
	if err != nil {
		return nil, fmt.Errorf("chain summary: %w", err)
	}

	ids := make([]int64, 0, len(branches))
	for _, b := range branches {
		// Consolidated figures are an ownership view, so only branches where
		// the user is an owner contribute.
		if b.Role == RoleOwner {
			ids = append(ids, b.ID)
		}
	}
	if len(ids) == 0 {
		return nil, ErrNotOwner
	}

	out, err := s.repo.SummaryForBranches(ctx, ids)
	if err != nil {
		return nil, fmt.Errorf("chain summary: %w", err)
	}
	return out, nil
}

// PeriodReport is the branch league table over a chosen date range, with
// membership and retail revenue split out and each branch ranked.
func (s *Service) PeriodReport(ctx context.Context, from, to time.Time) ([]BranchPeriodReport, error) {
	tc := database.MustGetTenant(ctx)
	branches, err := s.repo.AccessibleBranches(ctx, tc.UserID())
	if err != nil {
		return nil, fmt.Errorf("period report: %w", err)
	}
	ids := make([]int64, 0, len(branches))
	for _, b := range branches {
		if b.Role == RoleOwner {
			ids = append(ids, b.ID)
		}
	}
	if len(ids) == 0 {
		return nil, ErrNotOwner
	}
	out, err := s.repo.PeriodReport(ctx, ids, from, to)
	if err != nil {
		return nil, fmt.Errorf("period report: %w", err)
	}
	return out, nil
}

// SetTargets records what a branch should achieve this month. Targets are what
// turn a league table from "who is biggest" into "who is performing".
func (s *Service) SetTargets(ctx context.Context, gymID int64, revenueTargetInPaise int64, memberTarget int) error {
	tc := database.MustGetTenant(ctx)
	if !isOwnerish(tc.Role()) {
		return ErrNotOwner
	}
	// You may only set targets for a branch you actually hold.
	role, err := s.repo.RoleFor(ctx, tc.UserID(), gymID)
	if err != nil {
		return fmt.Errorf("set targets: %w", err)
	}
	if role != RoleOwner {
		return ErrNoAccess
	}
	if revenueTargetInPaise < 0 || memberTarget < 0 {
		return fmt.Errorf("targets cannot be negative")
	}
	if err := s.repo.SetTargets(ctx, gymID, revenueTargetInPaise, memberTarget); err != nil {
		return fmt.Errorf("set targets: %w", err)
	}
	return nil
}

// TransferMember moves a member to another branch in the same organization.
//
// The caller must hold the branch they are moving the member OUT of (they are
// acting in it) and have a grant for the branch they are moving them INTO —
// otherwise a user could push members into branches they have no relationship
// with.
func (s *Service) TransferMember(ctx context.Context, memberID, toGymID int64, reason string) error {
	tc := database.MustGetTenant(ctx)

	// Shared with staff and trainer transfers: destination must be a branch the
	// caller holds, in their own organization, and not where they already are.
	if err := s.checkTransferTarget(ctx, toGymID); err != nil {
		return err
	}

	inBranch, err := s.repo.MemberInBranch(ctx, memberID, tc.GymID())
	if err != nil {
		return fmt.Errorf("transfer: %w", err)
	}
	if !inBranch {
		return ErrMemberNotInBranch
	}

	if err := s.repo.TransferMember(ctx, memberID, tc.GymID(), toGymID, tc.UserID(), reason); err != nil {
		if errors.Is(err, ErrMemberNotInBranch) {
			return err
		}
		return fmt.Errorf("transfer: %w", err)
	}
	return nil
}

// checkTransferTarget runs the checks every transfer shares: the destination
// must be a branch the caller holds, in the caller's own organization, and not
// the branch they are already in.
func (s *Service) checkTransferTarget(ctx context.Context, toGymID int64) error {
	tc := database.MustGetTenant(ctx)
	if toGymID == tc.GymID() {
		return ErrSameBranch
	}
	role, err := s.repo.RoleFor(ctx, tc.UserID(), toGymID)
	if err != nil {
		return fmt.Errorf("transfer: access check: %w", err)
	}
	if role == "" {
		return ErrNoAccess
	}
	orgID, err := s.repo.OrganizationIDForGym(ctx, tc.GymID())
	if err != nil {
		return fmt.Errorf("transfer: %w", err)
	}
	if orgID == nil {
		return ErrDifferentOrg
	}
	sameOrg, err := s.repo.GymBelongsToOrganization(ctx, toGymID, *orgID)
	if err != nil {
		return fmt.Errorf("transfer: %w", err)
	}
	if !sameOrg {
		return ErrDifferentOrg
	}
	return nil
}

// TransferStaff moves a colleague's home branch. Owners only — moving staff
// between locations is a management action, not a front-desk one.
func (s *Service) TransferStaff(ctx context.Context, userID, toGymID int64, role string) error {
	tc := database.MustGetTenant(ctx)
	if !isOwnerish(tc.Role()) {
		return ErrNotOwner
	}
	if err := s.checkTransferTarget(ctx, toGymID); err != nil {
		return err
	}
	if role != RoleOwner && role != RoleManager && role != RoleStaff {
		role = RoleStaff
	}

	orgID, err := s.repo.OrganizationIDForGym(ctx, tc.GymID())
	if err != nil {
		return fmt.Errorf("transfer staff: %w", err)
	}
	inOrg, err := s.repo.UserInOrganization(ctx, userID, *orgID)
	if err != nil {
		return fmt.Errorf("transfer staff: %w", err)
	}
	if !inOrg {
		return ErrUserDifferentOrg
	}

	if err := s.repo.TransferStaff(ctx, userID, toGymID, role); err != nil {
		if errors.Is(err, ErrUserNotFound) {
			return err
		}
		return fmt.Errorf("transfer staff: %w", err)
	}
	return nil
}

// TransferTrainer moves a trainer to another branch. Packages already sold stay
// with the branch that sold them; only new business follows the trainer.
func (s *Service) TransferTrainer(ctx context.Context, trainerID, toGymID int64) error {
	tc := database.MustGetTenant(ctx)
	if !isOwnerish(tc.Role()) {
		return ErrNotOwner
	}
	if err := s.checkTransferTarget(ctx, toGymID); err != nil {
		return err
	}
	if err := s.repo.TransferTrainer(ctx, trainerID, tc.GymID(), toGymID); err != nil {
		if errors.Is(err, ErrTrainerNotInBranch) {
			return err
		}
		return fmt.Errorf("transfer trainer: %w", err)
	}
	return nil
}

// isOwnerish — 'manager' exists as a branch-level role but branch and access
// administration stays with owners.
func isOwnerish(role string) bool { return role == RoleOwner }
