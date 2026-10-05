package devseed

import "gymcrm/internal/plans"

// planSeed is the static catalogue requested by the PRD. Prices are in
// paise (₹1 = 100 paise), matching plans.MembershipPlan.PriceInPaise.
type planSeed struct {
	name         string
	description  string
	durationDays int
	priceInPaise int64
}

var planCatalogue = []planSeed{
	{"Monthly", "Pay-as-you-go monthly membership.", 30, 150000},
	{"Quarterly", "3-month membership at a discounted monthly rate.", 90, 400000},
	{"Half Yearly", "6-month membership — better value than quarterly.", 180, 750000},
	{"Annual", "Full-year membership, best value per month.", 365, 1300000},
	{"PT Package", "Personal training add-on package, 30-day cycle.", 30, 500000},
}

func (s *seeder) seedPlans() error {
	for _, p := range planCatalogue {
		plan := plans.MembershipPlan{
			GymID:        s.gymID,
			Name:         p.name,
			Description:  strPtr(p.description),
			DurationDays: p.durationDays,
			PriceInPaise: p.priceInPaise,
			IsActive:     true,
		}
		if err := s.tx.Create(&plan).Error; err != nil {
			return err
		}
		s.plans = append(s.plans, plan)
	}
	return nil
}
