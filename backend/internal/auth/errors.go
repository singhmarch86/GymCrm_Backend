package auth

import "errors"

// Sentinel errors for the auth domain.
// These are matched in the handler to produce correct HTTP status codes.
// Never expose these messages directly to the client — handler maps them.
var (
	// ErrInvalidCredentials — wrong phone or password.
	// Deliberately vague: don't reveal which field was wrong.
	ErrInvalidCredentials = errors.New("invalid phone or password")

	// ErrPhoneAlreadyRegistered — phone exists in this gym's user table.
	ErrPhoneAlreadyRegistered = errors.New("phone number already registered")

	// ErrGymPhoneAlreadyRegistered — phone exists as a gym registration.
	ErrGymPhoneAlreadyRegistered = errors.New("a gym with this phone already exists")

	// ErrUserInactive — account exists but has been deactivated.
	ErrUserInactive = errors.New("account is inactive")

	// ErrGymInactive — gym has been suspended or deactivated.
	ErrGymInactive = errors.New("gym account is inactive")

	// ErrGymSuspended — the vendor suspended this gym (FR-12 §8). Carried as a
	// type so the login response can say plainly why, not just "inactive".
	// Nothing is deleted; the gym is restored by resuming it.

	// ErrRefreshTokenInvalid — token not found, expired, or revoked.
	ErrRefreshTokenInvalid = errors.New("refresh token is invalid or expired")

	// ErrRefreshTokenRevoked — token was explicitly revoked.
	ErrRefreshTokenRevoked = errors.New("refresh token has been revoked")
)

// GymSuspendedError is ErrGymInactive plus the reason the vendor recorded.
type GymSuspendedError struct{ Reason string }

func (e *GymSuspendedError) Error() string        { return ErrGymInactive.Error() }
func (e *GymSuspendedError) Is(target error) bool { return target == ErrGymInactive }
