package visitors

import "strings"

var validPurposes = map[string]bool{
	PurposeTrial: true, PurposeGuest: true, PurposeTour: true, PurposeOther: true,
}

func validateCheckIn(req CheckInRequest) (purpose string, err error) {
	if strings.TrimSpace(req.Name) == "" {
		return "", ErrNameRequired
	}
	purpose = strings.TrimSpace(req.Purpose)
	if purpose == "" {
		purpose = PurposeTrial
	}
	if !validPurposes[purpose] {
		return "", ErrInvalidPurpose
	}
	return purpose, nil
}
