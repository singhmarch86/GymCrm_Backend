package devseed

import (
	"fmt"
	"strings"

	"gymcrm/internal/leads"
)

const leadCountTarget = 50

var leadSources = []leads.LeadSource{
	leads.LeadSourceWalkIn,
	leads.LeadSourceInstagram,
	leads.LeadSourceFacebook,
	leads.LeadSourceWhatsApp,
	leads.LeadSourceReferral,
}

var leadGoals = []leads.LeadGoal{
	leads.LeadGoalWeightLoss,
	leads.LeadGoalMuscleGain,
	leads.LeadGoalFitness,
	leads.LeadGoalSports,
}

var lostReasons = []string{
	"Chose a different gym closer to home",
	"Price was too high for their budget",
	"Went cold after the trial session",
	"No longer interested in joining",
}

// leadStatusCounts maps the PRD's 5 pipeline statuses (New, Contacted,
// Trial, Converted, Lost) onto leads.LeadStatus. "Trial" is split across
// the model's two trial sub-stages so both get demo coverage.
var leadStatusCounts = []struct {
	status leads.LeadStatus
	count  int
}{
	{leads.LeadStatusNew, 15},
	{leads.LeadStatusContacted, 12},
	{leads.LeadStatusTrialScheduled, 5},
	{leads.LeadStatusTrialCompleted, 5},
	{leads.LeadStatusJoined, 8},
	{leads.LeadStatusLost, 5},
}

func (s *seeder) seedLeads() error {
	var statuses []leads.LeadStatus
	for _, sc := range leadStatusCounts {
		for i := 0; i < sc.count; i++ {
			statuses = append(statuses, sc.status)
		}
	}
	s.rng.Shuffle(len(statuses), func(i, j int) { statuses[i], statuses[j] = statuses[j], statuses[i] })

	var rows []leads.Lead
	for i := 0; i < leadCountTarget && i < len(statuses); i++ {
		isFemale := s.rng.Intn(2) == 0
		var first, gender string
		if isFemale {
			first, gender = pick(s.rng, femaleFirstNames), "female"
		} else {
			first, gender = pick(s.rng, maleFirstNames), "male"
		}
		last := pick(s.rng, lastNames)

		status := statuses[i]
		source := pick(s.rng, leadSources)
		createdAt := s.now.AddDate(0, 0, -s.rng.Intn(60))

		lead := leads.Lead{
			GymID:     s.gymID,
			Name:      fmt.Sprintf("%s %s", first, last),
			Phone:     fmt.Sprintf("91%08d", 2000000+i),
			Email:     strPtr(fmt.Sprintf("%s.%s.lead%d@gmail.com", strings.ToLower(first), strings.ToLower(last), i)),
			Gender:    strPtr(gender),
			Source:    source,
			Goal:      goalPtr(pick(s.rng, leadGoals)),
			Status:    status,
			CreatedAt: createdAt,
			UpdatedAt: createdAt,
		}

		if s.rng.Intn(10) > 2 { // ~70% assigned to the owner, rest unassigned
			lead.AssignedUserID = int64Ptr(s.ownerUserID)
		}

		switch status {
		case leads.LeadStatusTrialScheduled:
			lead.TrialDate = timePtr(s.now.AddDate(0, 0, 1+s.rng.Intn(7)))
			lead.FollowUpDate = timePtr(s.now.AddDate(0, 0, 1+s.rng.Intn(7)))
		case leads.LeadStatusTrialCompleted:
			lead.TrialDate = timePtr(createdAt.AddDate(0, 0, 1+s.rng.Intn(5)))
			lead.FollowUpDate = timePtr(s.now.AddDate(0, 0, s.rng.Intn(5)))
		case leads.LeadStatusNew, leads.LeadStatusContacted:
			lead.FollowUpDate = timePtr(s.now.AddDate(0, 0, s.rng.Intn(10)))
		case leads.LeadStatusLost:
			lead.LostReason = strPtr(pick(s.rng, lostReasons))
		case leads.LeadStatusJoined:
			lead.FollowUpDate = timePtr(createdAt.AddDate(0, 0, 3))
		}

		rows = append(rows, lead)
	}

	if len(rows) == 0 {
		return nil
	}
	if err := s.tx.CreateInBatches(rows, 50).Error; err != nil {
		return err
	}
	s.leadCount = len(rows)
	return nil
}

func goalPtr(g leads.LeadGoal) *leads.LeadGoal { return &g }
