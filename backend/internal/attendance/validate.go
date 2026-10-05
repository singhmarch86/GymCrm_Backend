package attendance

import (
	"fmt"
	"time"
)

const dateLayout = "2006-01-02"

// ValidateCheckInRequest validates the check-in payload.
func ValidateCheckInRequest(req *CheckInRequest) error {
	if req.MemberID <= 0 {
		return fmt.Errorf("member_id is required")
	}
	return nil
}

// ParseDate parses a YYYY-MM-DD string into a time.Time.
// Returns ErrInvalidDate if the format is wrong.
func ParseDate(s string) (time.Time, error) {
	t, err := time.Parse(dateLayout, s)
	if err != nil {
		return time.Time{}, ErrInvalidDate
	}
	return t, nil
}
