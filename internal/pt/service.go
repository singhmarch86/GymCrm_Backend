package pt

import (
	"context"
	"fmt"
	"strings"
	"time"

	"gymcrm/internal/database"
)

// Service holds PT package and appointment logic. Rules are specified in
// docs/FR-03-trainers-pt-appointments.md.
type Service struct {
	repo *Repository
}

func NewService(repo *Repository) *Service { return &Service{repo: repo} }

// ─── Packages ─────────────────────────────────────────────────────────────────

func (s *Service) CreatePackage(ctx context.Context, req CreatePackageRequest) (*PackageResponse, error) {
	expiry, err := validateCreatePackage(req)
	if err != nil {
		return nil, err
	}
	tc := database.MustGetTenant(ctx)
	p := &Package{
		GymID: tc.GymID(), MemberID: req.MemberID, TrainerID: req.TrainerID,
		PackageName: strings.TrimSpace(req.PackageName), TotalSessions: req.TotalSessions,
		AmountInPaise: req.AmountInPaise, ExpiryDate: expiry, Status: PackageActive,
	}
	// The money is written with the sale, in one transaction. A package with
	// no payment row is exactly the state this prevents, so a failure on the
	// money side must take the sale with it rather than leave a half-written
	// one nobody knows to retry.
	money, err := resolvePayment(req)
	if err != nil {
		return nil, err
	}
	if err := s.repo.CreatePackageWithPayment(ctx, p, money); err != nil {
		return nil, fmt.Errorf("create package: %w", err)
	}
	return s.getPackage(ctx, p.ID)
}

func (s *Service) ListPackages(ctx context.Context, memberID, trainerID *int64) ([]PackageResponse, error) {
	rows, err := s.repo.ListPackages(ctx, memberID, trainerID)
	if err != nil {
		return nil, fmt.Errorf("list packages: %w", err)
	}
	out := make([]PackageResponse, 0, len(rows))
	for _, r := range rows {
		out = append(out, toPackageResponse(r))
	}
	return out, nil
}

func (s *Service) UpdatePackageStatus(ctx context.Context, id int64, req UpdatePackageStatusRequest) (*PackageResponse, error) {
	if err := validatePackageStatus(req.Status); err != nil {
		return nil, err
	}
	existing, err := s.repo.FindPackage(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("update package status: find: %w", err)
	}
	if existing == nil {
		return nil, ErrPackageNotFound
	}
	if err := s.repo.UpdatePackageStatus(ctx, id, req.Status); err != nil {
		return nil, fmt.Errorf("update package status: %w", err)
	}
	return s.getPackage(ctx, id)
}

func (s *Service) getPackage(ctx context.Context, id int64) (*PackageResponse, error) {
	row, err := s.repo.packageRowByID(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("get package: %w", err)
	}
	if row == nil {
		return nil, ErrPackageNotFound
	}
	resp := toPackageResponse(*row)
	return &resp, nil
}

// ─── Appointments ─────────────────────────────────────────────────────────────

// Book schedules a 1:1 session. Deliberately does NOT check or reserve a
// session credit — the guard is on completing it, not booking it. FR-03 §3.
func (s *Service) Book(ctx context.Context, req CreateAppointmentRequest) (*AppointmentResponse, error) {
	scheduledAt, duration, err := validateCreateAppointment(req)
	if err != nil {
		return nil, err
	}
	tc := database.MustGetTenant(ctx)

	pkg, err := s.repo.FindPackage(ctx, req.PTPackageID)
	if err != nil {
		return nil, fmt.Errorf("book: find package: %w", err)
	}
	if pkg == nil {
		return nil, ErrPackageNotFound
	}
	if pkg.Status != PackageActive {
		return nil, ErrPackageNotActive
	}

	a := &Appointment{
		GymID: tc.GymID(), PTPackageID: pkg.ID, TrainerID: pkg.TrainerID, MemberID: pkg.MemberID,
		ScheduledAt: scheduledAt, DurationMinutes: duration, Status: AppointmentScheduled,
		Notes: optionalText(req.Notes), CreatedByUserID: tc.UserID(),
	}
	if err := s.repo.CreateAppointment(ctx, a); err != nil {
		return nil, fmt.Errorf("book: %w", err)
	}
	return s.getAppointment(ctx, a.ID)
}

func (s *Service) ListAppointments(ctx context.Context, from, to time.Time, trainerID, memberID *int64) ([]AppointmentResponse, error) {
	rows, err := s.repo.ListAppointments(ctx, from, to, trainerID, memberID)
	if err != nil {
		return nil, fmt.Errorf("list appointments: %w", err)
	}
	out := make([]AppointmentResponse, 0, len(rows))
	for _, r := range rows {
		out = append(out, toAppointmentResponse(r))
	}
	return out, nil
}

// SetOutcome marks an appointment completed, cancelled, or no-show.
// Only 'completed' consumes a session credit — see FR-03 §3.
func (s *Service) SetOutcome(ctx context.Context, id int64, req MarkAttendanceRequest) (*AppointmentResponse, error) {
	if err := validateOutcome(req.Status); err != nil {
		return nil, err
	}
	existing, err := s.repo.FindAppointment(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("set outcome: find: %w", err)
	}
	if existing == nil {
		return nil, ErrAppointmentNotFound
	}
	if existing.Status != AppointmentScheduled {
		return nil, ErrAppointmentNotScheduled
	}

	if req.Status == AppointmentCompleted {
		if err := s.repo.CompleteAppointmentAndConsumeCredit(ctx, id, existing.PTPackageID); err != nil {
			return nil, fmt.Errorf("set outcome: %w", err)
		}
	} else {
		if err := s.repo.SetAppointmentStatus(ctx, id, req.Status); err != nil {
			return nil, fmt.Errorf("set outcome: %w", err)
		}
	}
	return s.getAppointment(ctx, id)
}

func (s *Service) getAppointment(ctx context.Context, id int64) (*AppointmentResponse, error) {
	row, err := s.repo.appointmentRowByID(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("get appointment: %w", err)
	}
	if row == nil {
		return nil, ErrAppointmentNotFound
	}
	resp := toAppointmentResponse(*row)
	return &resp, nil
}

// ─── mapping ──────────────────────────────────────────────────────────────────

func toPackageResponse(r packageRow) PackageResponse {
	return PackageResponse{
		ID: r.ID, MemberID: r.MemberID, MemberName: r.MemberName,
		TrainerID: r.TrainerID, TrainerName: r.TrainerName, PackageName: r.PackageName,
		TotalSessions: r.TotalSessions, SessionsUsed: r.SessionsUsed,
		SessionsRemaining: r.sessionsRemaining(),
		AmountInPaise:     r.AmountInPaise, AmountInRupees: paiseToRupees(r.AmountInPaise),
		ExpiryDate: r.ExpiryDate, Status: r.Status, CreatedAt: r.CreatedAt,
	}
}

func toAppointmentResponse(r appointmentRow) AppointmentResponse {
	return AppointmentResponse{
		ID: r.ID, PTPackageID: r.PTPackageID, TrainerID: r.TrainerID, TrainerName: r.TrainerName,
		MemberID: r.MemberID, MemberName: r.MemberName, ScheduledAt: r.ScheduledAt,
		DurationMinutes: r.DurationMinutes, Status: r.Status, Notes: r.Notes, CreatedAt: r.CreatedAt,
	}
}

func optionalText(s string) *string {
	if s == "" {
		return nil
	}
	return &s
}
