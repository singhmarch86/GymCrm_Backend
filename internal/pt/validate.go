package pt

import (
	"fmt"
	"strings"
	"time"
)

func truncateDay(t time.Time) time.Time {
	return time.Date(t.Year(), t.Month(), t.Day(), 0, 0, 0, 0, time.UTC)
}

func validateCreatePackage(req CreatePackageRequest) (expiry *time.Time, err error) {
	if req.MemberID <= 0 {
		return nil, ErrMemberNotFound
	}
	if req.TrainerID <= 0 {
		return nil, ErrTrainerNotFound
	}
	if strings.TrimSpace(req.PackageName) == "" {
		return nil, ErrPackageNameRequired
	}
	if req.TotalSessions <= 0 {
		return nil, ErrTotalSessionsRequired
	}
	if req.AmountInPaise < 0 {
		return nil, ErrAmountNegative
	}
	if strings.TrimSpace(req.ExpiryDate) != "" {
		t, perr := time.Parse("2006-01-02", strings.TrimSpace(req.ExpiryDate))
		if perr != nil {
			return nil, fmt.Errorf("invalid expiry_date %q: expected YYYY-MM-DD", req.ExpiryDate)
		}
		d := truncateDay(t)
		expiry = &d
	}
	return expiry, nil
}

var validPackageStatuses = map[string]bool{PackageActive: true, PackageExpired: true, PackageCancelled: true}

func validatePackageStatus(status string) error {
	if !validPackageStatuses[status] {
		return fmt.Errorf("status must be one of: active, expired, cancelled")
	}
	return nil
}

func validateCreateAppointment(req CreateAppointmentRequest) (scheduledAt time.Time, duration int, err error) {
	if req.PTPackageID <= 0 {
		return time.Time{}, 0, ErrPackageNotFound
	}
	if strings.TrimSpace(req.ScheduledAt) == "" {
		return time.Time{}, 0, ErrScheduledAtRequired
	}
	scheduledAt, err = time.Parse(time.RFC3339, strings.TrimSpace(req.ScheduledAt))
	if err != nil {
		return time.Time{}, 0, fmt.Errorf("invalid scheduled_at %q: expected RFC3339", req.ScheduledAt)
	}
	duration = req.DurationMinutes
	if duration <= 0 {
		duration = 60
	}
	return scheduledAt, duration, nil
}

var validOutcomes = map[string]bool{AppointmentCompleted: true, AppointmentCancelled: true, AppointmentNoShow: true}

func validateOutcome(status string) error {
	if !validOutcomes[status] {
		return fmt.Errorf("status must be one of: completed, cancelled, no_show")
	}
	return nil
}
