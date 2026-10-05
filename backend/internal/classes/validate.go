package classes

import (
	"fmt"
	"strings"
	"time"
)

const dateLayout = "2006-01-02"

func today() time.Time {
	n := time.Now().UTC()
	return time.Date(n.Year(), n.Month(), n.Day(), 0, 0, 0, 0, time.UTC)
}

func truncateDay(t time.Time) time.Time {
	return time.Date(t.Year(), t.Month(), t.Day(), 0, 0, 0, 0, time.UTC)
}

func parseDateOrToday(s string) (time.Time, error) {
	if strings.TrimSpace(s) == "" {
		return today(), nil
	}
	t, err := time.Parse(dateLayout, strings.TrimSpace(s))
	if err != nil {
		return time.Time{}, fmt.Errorf("invalid date %q: expected YYYY-MM-DD", s)
	}
	return truncateDay(t), nil
}

func parseDateOptional(s string) (*time.Time, error) {
	if strings.TrimSpace(s) == "" {
		return nil, nil
	}
	t, err := time.Parse(dateLayout, strings.TrimSpace(s))
	if err != nil {
		return nil, fmt.Errorf("invalid date %q: expected YYYY-MM-DD", s)
	}
	d := truncateDay(t)
	return &d, nil
}

func parseDateRequired(s, field string) (time.Time, error) {
	if strings.TrimSpace(s) == "" {
		return time.Time{}, fmt.Errorf("%s is required", field)
	}
	t, err := time.Parse(dateLayout, strings.TrimSpace(s))
	if err != nil {
		return time.Time{}, fmt.Errorf("invalid %s %q: expected YYYY-MM-DD", field, s)
	}
	return truncateDay(t), nil
}

// parseClockTime accepts "HH:MM" or "HH:MM:SS" and normalises to "HH:MM:SS"
// for storage, matching Postgres's `time` column.
func parseClockTime(s, field string) (string, error) {
	s = strings.TrimSpace(s)
	if s == "" {
		return "", fmt.Errorf("%s is required", field)
	}
	if t, err := time.Parse("15:04", s); err == nil {
		return t.Format("15:04:05"), nil
	}
	if t, err := time.Parse("15:04:05", s); err == nil {
		return t.Format("15:04:05"), nil
	}
	return "", fmt.Errorf("invalid %s %q: expected HH:MM", field, s)
}

func validateCreateClassType(req CreateClassTypeRequest) error {
	if strings.TrimSpace(req.Name) == "" {
		return fmt.Errorf("name is required")
	}
	if req.DurationMinutes <= 0 {
		return fmt.Errorf("duration_minutes must be greater than 0")
	}
	if req.DefaultCapacity <= 0 {
		return fmt.Errorf("default_capacity must be greater than 0")
	}
	return nil
}

// validateUpdateClassType only checks fields that were actually provided —
// unlike create, every field here is optional, so an absent field is not an
// error.
func validateUpdateClassType(req UpdateClassTypeRequest) error {
	if req.Name != nil && strings.TrimSpace(*req.Name) == "" {
		return fmt.Errorf("name cannot be empty")
	}
	if req.DurationMinutes != nil && *req.DurationMinutes <= 0 {
		return fmt.Errorf("duration_minutes must be greater than 0")
	}
	if req.DefaultCapacity != nil && *req.DefaultCapacity <= 0 {
		return fmt.Errorf("default_capacity must be greater than 0")
	}
	return nil
}

// validateCreateSchedule checks bounds that don't need a DB lookup. Defaults
// from the class type (duration/capacity) are resolved in the service, which
// has the class type loaded.
func validateCreateSchedule(req CreateScheduleRequest) (startTime string, from time.Time, until *time.Time, err error) {
	if req.ClassTypeID <= 0 {
		err = fmt.Errorf("class_type_id is required")
		return
	}
	if req.DayOfWeek < 0 || req.DayOfWeek > 6 {
		err = ErrInvalidDayOfWeek
		return
	}
	startTime, err = parseClockTime(req.StartTime, "start_time")
	if err != nil {
		return
	}
	from, err = parseDateOrToday(req.EffectiveFrom)
	if err != nil {
		return
	}
	until, err = parseDateOptional(req.EffectiveUntil)
	if err != nil {
		return
	}
	if until != nil && until.Before(from) {
		err = ErrInvalidDateRange
	}
	return
}

func validateAdHocSession(req CreateAdHocSessionRequest) (date time.Time, startTime string, err error) {
	if req.ClassTypeID <= 0 {
		err = fmt.Errorf("class_type_id is required")
		return
	}
	date, err = parseDateRequired(req.SessionDate, "session_date")
	if err != nil {
		return
	}
	startTime, err = parseClockTime(req.StartTime, "start_time")
	return
}
