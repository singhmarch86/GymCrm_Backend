package users

// CreateStaffRequest is the payload for POST /api/v1/users.
// @Description Add a staff member (or co-owner) to the gym.
type CreateStaffRequest struct {
	Name     string `json:"name"`     // required
	Phone    string `json:"phone"`    // required, unique — this is the login identity
	Email    string `json:"email"`    // optional
	Role     string `json:"role"`     // owner | staff (defaults to staff)
	Password string `json:"password"` // required, min 8 chars incl. a digit
}

// UpdateStaffRequest is the payload for PUT /api/v1/users/{id}.
// Nil fields are left unchanged. Password is deliberately absent — a reset is a
// separate, explicit operation rather than a side effect of editing a profile.
type UpdateStaffRequest struct {
	Name  *string `json:"name,omitempty"`
	Phone *string `json:"phone,omitempty"`
	Email *string `json:"email,omitempty"`
	Role  *string `json:"role,omitempty"`
}

// UpdateStatusRequest is the payload for PATCH /api/v1/users/{id}/status.
type UpdateStatusRequest struct {
	Status string `json:"status"` // active | inactive
}

// ResetPasswordRequest is the payload for PATCH /api/v1/users/{id}/password.
type ResetPasswordRequest struct {
	Password string `json:"password"`
}

type StaffListResponse struct {
	Staff []StaffRow `json:"staff"`
}
