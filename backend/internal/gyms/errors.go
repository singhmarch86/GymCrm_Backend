package gyms

import "errors"

var (
	ErrOwnerOnly    = errors.New("gyms: only an owner can edit the public page")
	ErrSlugTaken    = errors.New("gyms: that page address is already taken")
	ErrSlugRequired = errors.New("gyms: set a page address before publishing")
	ErrGymNotFound  = errors.New("gyms: gym not found")
)
