package devseed

import (
	"golang.org/x/crypto/bcrypt"

	"gymcrm/internal/gyms"
	"gymcrm/internal/users"
)

// bcryptCost matches internal/auth/service.go's bcryptCost — same strength
// used for real logins, so the seeded owner account behaves identically.
const bcryptCost = 12

const (
	ownerPhone    = "9876543210"
	ownerPassword = "secure123"
)

func (s *seeder) seedGymAndOwner() error {
	gym := &gyms.Gym{
		Name:      "Demo Fitness Gym",
		OwnerName: "Amanpreet Singh",
		Phone:     ownerPhone,
		Email:     strPtr("owner@demofitnessgym.dev"),
		Address:   "SCO 42, Model Town Extension",
		City:      "Ludhiana",
		State:     "Punjab",
		Status:    gyms.GymStatusActive,
	}
	if err := s.tx.Create(gym).Error; err != nil {
		return err
	}
	s.gymID = gym.ID

	hash, err := bcrypt.GenerateFromPassword([]byte(ownerPassword), bcryptCost)
	if err != nil {
		return err
	}

	owner := &users.User{
		GymID:        s.gymID,
		Name:         gym.OwnerName,
		Phone:        ownerPhone,
		Email:        "owner@demofitnessgym.dev",
		PasswordHash: string(hash),
		Role:         users.RoleOwner,
		Status:       users.UserStatusActive,
	}
	if err := s.tx.Create(owner).Error; err != nil {
		return err
	}
	s.ownerUserID = owner.ID

	return nil
}
