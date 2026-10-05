package ptfeedback

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"gorm.io/gorm"

	"gymcrm/internal/database"
)

var (
	ErrBadAuthorRole  = errors.New("author_role must be 'member' or 'trainer'")
	ErrBlankNote      = errors.New("note cannot be blank")
	ErrMemberNotHere  = errors.New("that member is not at your branch")
	ErrTrainerNotHere = errors.New("that trainer is not at your branch")
)

type Service struct {
	repo *Repository
	db   *gorm.DB
}

func NewService(repo *Repository, db *gorm.DB) *Service {
	return &Service{repo: repo, db: db}
}

type CreateRequest struct {
	MemberID        int64  `json:"member_id"`
	AuthorRole      string `json:"author_role"`
	Note            string `json:"note"`
	TrainerID       *int64 `json:"trainer_id,omitempty"`
	PTPackageID     *int64 `json:"pt_package_id,omitempty"`
	PTAppointmentID *int64 `json:"pt_appointment_id,omitempty"`
}

// Create writes one feedback row. Member and trainer, when given, are
// checked against the caller's own gym — a bare foreign key would accept an
// id from any gym, and that is exactly the boundary tenant isolation exists
// to hold.
func (s *Service) Create(ctx context.Context, req CreateRequest) (*Row, error) {
	role := strings.TrimSpace(req.AuthorRole)
	if role != AuthorMember && role != AuthorTrainer {
		return nil, ErrBadAuthorRole
	}
	note := strings.TrimSpace(req.Note)
	if note == "" {
		return nil, ErrBlankNote
	}

	tc := database.MustGetTenant(ctx)

	if !s.existsInGym(ctx, "members", req.MemberID, tc.GymID()) {
		return nil, ErrMemberNotHere
	}
	if req.TrainerID != nil && !s.existsInGym(ctx, "trainers", *req.TrainerID, tc.GymID()) {
		return nil, ErrTrainerNotHere
	}

	f := &Feedback{
		GymID: tc.GymID(), MemberID: req.MemberID, AuthorRole: role,
		TrainerID: req.TrainerID, PTPackageID: req.PTPackageID, PTAppointmentID: req.PTAppointmentID,
		Note: note, CreatedByUserID: tc.UserID(),
	}
	if err := s.repo.Create(ctx, f); err != nil {
		return nil, fmt.Errorf("create feedback: %w", err)
	}

	rows, err := s.repo.ByMember(ctx, tc.GymID(), req.MemberID)
	if err != nil || len(rows) == 0 {
		return nil, fmt.Errorf("create feedback: reload: %w", err)
	}
	out := toRow(rows[0])
	return &out, nil
}

func (s *Service) existsInGym(ctx context.Context, table string, id, gymID int64) bool {
	var n int64
	s.db.WithContext(ctx).Table(table).
		Where("id = ? AND gym_id = ?", id, gymID).Count(&n)
	return n > 0
}

// ByMember is one member's feedback history, both roles, newest first.
func (s *Service) ByMember(ctx context.Context, memberID int64) ([]Row, error) {
	tc := database.MustGetTenant(ctx)
	rows, err := s.repo.ByMember(ctx, tc.GymID(), memberID)
	if err != nil {
		return nil, fmt.Errorf("member feedback: %w", err)
	}
	return toRows(rows), nil
}

// ByTrainer is the feedback one trainer has given, newest first.
func (s *Service) ByTrainer(ctx context.Context, trainerID int64) ([]Row, error) {
	tc := database.MustGetTenant(ctx)
	rows, err := s.repo.ByTrainer(ctx, tc.GymID(), trainerID)
	if err != nil {
		return nil, fmt.Errorf("trainer feedback: %w", err)
	}
	return toRows(rows), nil
}

func toRow(r row) Row {
	return Row{
		ID: r.ID, MemberID: r.MemberID, MemberName: r.MemberName,
		AuthorRole: r.AuthorRole, TrainerID: r.TrainerID, TrainerName: r.TrainerName,
		PTPackageID: r.PTPackageID, PTAppointmentID: r.PTAppointmentID,
		Note: r.Note, CreatedByName: r.CreatedByName, CreatedAt: r.CreatedAt,
	}
}

func toRows(rows []row) []Row {
	out := make([]Row, 0, len(rows))
	for _, r := range rows {
		out = append(out, toRow(r))
	}
	return out
}
