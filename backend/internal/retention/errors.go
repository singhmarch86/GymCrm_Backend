package retention

import "errors"

var (
	ErrAlertNotFound   = errors.New("alert not found or already resolved")
	ErrInvalidSeverity = errors.New("severity must be one of: low, medium, high")
)

// IsValidSeverity reports whether s is an accepted filter value.
func IsValidSeverity(s string) bool {
	switch Severity(s) {
	case SeverityLow, SeverityMedium, SeverityHigh:
		return true
	}
	return false
}
