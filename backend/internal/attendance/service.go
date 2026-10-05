package attendance

import (
	"context"
	"fmt"
	"time"

	"gymcrm/internal/database"
	"gymcrm/internal/shared/pagination"
)

// Service contains all attendance business logic.
type Service struct {
	repo *Repository
}

func NewService(repo *Repository) *Service {
	return &Service{repo: repo}
}

// ─── Check-in ─────────────────────────────────────────────────────────────────

// CheckIn records a member's attendance for today.
// Enforces: member exists in gym, not already checked in today.
// Server always sets the timestamp — client cannot manipulate it.
func (s *Service) CheckIn(ctx context.Context, req CheckInRequest) (*AttendanceResponse, error) {
	tc := database.MustGetTenant(ctx)

	// Validate member belongs to this gym
	exists, err := s.repo.MemberExists(ctx, req.MemberID)
	if err != nil {
		return nil, fmt.Errorf("checkin: check member: %w", err)
	}
	if !exists {
		return nil, ErrMemberNotFound
	}

	// Server-set timestamps — client has no influence over these
	now := time.Now().UTC()
	today := now.Truncate(24 * time.Hour)

	// Duplicate check — service layer (DB unique index is the backup)
	alreadyIn, err := s.repo.ExistsToday(ctx, req.MemberID, today)
	if err != nil {
		return nil, fmt.Errorf("checkin: check duplicate: %w", err)
	}
	if alreadyIn {
		return nil, ErrAlreadyCheckedIn
	}

	a := &Attendance{
		GymID:         tc.GymID(),
		MemberID:      req.MemberID,
		CheckedInAt:   now,
		CheckedInDate: today,
	}

	if err := s.repo.Create(ctx, a); err != nil {
		// Map unique constraint violation to domain error
		if isUniqueViolation(err) {
			return nil, ErrAlreadyCheckedIn
		}
		return nil, fmt.Errorf("checkin: insert: %w", err)
	}

	// Fetch with member name for response
	results, _, err := s.repo.FindByMember(ctx, req.MemberID, pagination.Params{Page: 1, PerPage: 1, Offset: 0})
	if err != nil || len(results) == 0 {
		// Fallback: return without member name rather than failing
		resp := AttendanceResponse{
			ID:            a.ID,
			GymID:         a.GymID,
			MemberID:      a.MemberID,
			CheckedInAt:   a.CheckedInAt,
			CheckedInDate: a.CheckedInDate,
			CreatedAt:     a.CreatedAt,
		}
		return &resp, nil
	}
	resp := results[0].ToResponse()
	return &resp, nil
}

// ─── Read ─────────────────────────────────────────────────────────────────────

func (s *Service) GetToday(ctx context.Context, p pagination.Params) ([]AttendanceResponse, int64, error) {
	records, total, err := s.repo.FindToday(ctx, p)
	if err != nil {
		return nil, 0, fmt.Errorf("attendance today: %w", err)
	}
	return ToResponseList(records), total, nil
}

func (s *Service) GetByDate(ctx context.Context, dateStr string, p pagination.Params) ([]AttendanceResponse, int64, error) {
	date, err := ParseDate(dateStr)
	if err != nil {
		return nil, 0, ErrInvalidDate
	}
	records, total, err := s.repo.FindByDate(ctx, date, p)
	if err != nil {
		return nil, 0, fmt.Errorf("attendance by date: %w", err)
	}
	return ToResponseList(records), total, nil
}

func (s *Service) GetMemberAttendance(ctx context.Context, memberID int64, p pagination.Params) ([]AttendanceResponse, int64, error) {
	// Validate member belongs to this gym
	exists, err := s.repo.MemberExists(ctx, memberID)
	if err != nil {
		return nil, 0, fmt.Errorf("member attendance: check member: %w", err)
	}
	if !exists {
		return nil, 0, ErrMemberNotFound
	}

	records, total, err := s.repo.FindByMember(ctx, memberID, p)
	if err != nil {
		return nil, 0, fmt.Errorf("member attendance: %w", err)
	}
	return ToResponseList(records), total, nil
}

func (s *Service) GetRecent(ctx context.Context, limit int) ([]AttendanceResponse, error) {
	if limit <= 0 {
		limit = 20
	}
	if limit > 100 {
		limit = 100
	}
	records, err := s.repo.FindRecent(ctx, limit)
	if err != nil {
		return nil, fmt.Errorf("recent attendance: %w", err)
	}
	return ToResponseList(records), nil
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

// isUniqueViolation detects PostgreSQL unique constraint errors.
// Used to map DB-level duplicate check-in to ErrAlreadyCheckedIn.
func isUniqueViolation(err error) bool {
	if err == nil {
		return false
	}
	return contains(err.Error(), "idx_attendance_unique_daily") ||
		contains(err.Error(), "unique constraint") ||
		contains(err.Error(), "SQLSTATE 23505")
}

func contains(s, substr string) bool {
	return len(s) >= len(substr) && (s == substr ||
		len(s) > 0 && containsStr(s, substr))
}

func containsStr(s, substr string) bool {
	for i := 0; i <= len(s)-len(substr); i++ {
		if s[i:i+len(substr)] == substr {
			return true
		}
	}
	return false
}
