package devseed

import "time"

// Trainers and personal training.
//
// The three trainers are on deliberately different pay schemes, because the
// payout screen has to be judged against all three at once and a gym where
// everybody is paid the same way proves nothing:
//
//	Rohit    commission AND per-session — the mixed case the gym confirmed
//	Simran   a flat monthly salary
//	Vikram   per session only
//
// Packages are seeded the way a real gym's books look: mostly paid, a couple
// still owed, one that over-delivered. A demo of a leak-detection screen that
// always reports zero cannot be evaluated — but nothing here is invented drama
// either. These are the ordinary imperfections of a gym that is running.

type seedTrainer struct {
	id                int64
	name              string
	salaryInPaise     *int64
	commissionPct     *float64
	perSessionInPaise *int64
}

func (s *seeder) seedTrainers() error {
	pct := func(v float64) *float64 { return &v }

	defs := []struct {
		first, last, phone, spec string
		salary                   *int64
		commission               *float64
		perSession               *int64
	}{
		{"Rohit", "Verma", "9811100001", "Strength & conditioning",
			nil, pct(20), int64Ptr(30000)},
		{"Simran", "Kaur", "9811100002", "Yoga & mobility",
			int64Ptr(2500000), nil, nil},
		{"Vikram", "Singh", "9811100003", "Boxing & HIIT",
			nil, nil, int64Ptr(40000)},
	}

	for _, d := range defs {
		var id int64
		err := s.tx.Raw(`
			INSERT INTO trainers
			    (gym_id, first_name, last_name, phone, specialization, status,
			     salary_in_paise, commission_pct, per_session_in_paise)
			VALUES (?, ?, ?, ?, ?, 'active', ?, ?, ?)
			RETURNING id`,
			s.gymID, d.first, d.last, d.phone, d.spec,
			d.salary, d.commission, d.perSession).Scan(&id).Error
		if err != nil {
			return err
		}
		s.trainers = append(s.trainers, seedTrainer{
			id: id, name: d.first + " " + d.last,
			salaryInPaise: d.salary, commissionPct: d.commission,
			perSessionInPaise: d.perSession,
		})
	}
	return nil
}

type ptPlan struct {
	name     string
	sessions int
	price    int64
}

var ptPlans = []ptPlan{
	{"PT Starter — 8 sessions", 8, 800000},
	{"PT Regular — 12 sessions", 12, 1100000},
	{"PT Intensive — 24 sessions", 24, 2000000},
}

// seedPTPackages sells packages to a slice of the membership and books the
// sessions that were actually delivered against them.
//
// Every package writes its money, exactly as the live sale path now does: a
// paid payment, or a pending due carrying pt_package_id. Seeding a package
// with no payment row would recreate the leak that path was built to close,
// and the leakage screen would then report the seeder's own shortcut as a
// finding.
func (s *seeder) seedPTPackages() error {
	if len(s.trainers) == 0 || len(s.members) == 0 {
		return nil
	}

	const packageCount = 22

	for i := 0; i < packageCount; i++ {
		trainer := s.trainers[i%len(s.trainers)]
		member := s.members[s.rng.Intn(len(s.members))]
		plan := ptPlans[s.rng.Intn(len(ptPlans))]

		// Sold somewhere in the last ten weeks, so commission lands across
		// several months and a monthly payout has something to show.
		soldAgo := 7 + s.rng.Intn(63)
		soldOn := s.now.AddDate(0, 0, -soldAgo)

		// Two of every nine are still owed. Ordinary for a gym, and it gives
		// the collections queue and the "uncollected PT" note on the payout
		// screen something real to point at.
		unpaid := i%9 == 3 || i%9 == 7

		var packageID int64
		err := s.tx.Raw(`
			INSERT INTO pt_packages
			    (gym_id, member_id, trainer_id, package_name, total_sessions,
			     sessions_used, amount_in_paise, expiry_date, status, created_at)
			VALUES (?, ?, ?, ?, ?, 0, ?, ?, 'active', ?)
			RETURNING id`,
			s.gymID, member.ID, trainer.id, plan.name, plan.sessions,
			plan.price, soldOn.AddDate(0, 6, 0), soldOn).Scan(&packageID).Error
		if err != nil {
			return err
		}

		if unpaid {
			err = s.tx.Exec(`
				INSERT INTO payments
				    (gym_id, member_id, pt_package_id, amount_in_paise, status,
				     due_date, notes, created_at)
				VALUES (?, ?, ?, ?, 'pending', ?, ?, ?)`,
				s.gymID, member.ID, packageID, plan.price,
				soldOn, plan.name, soldOn).Error
		} else {
			err = s.tx.Exec(`
				INSERT INTO payments
				    (gym_id, member_id, pt_package_id, amount_in_paise, status,
				     payment_mode, paid_date, notes, collected_by_user_id,
				     created_at)
				VALUES (?, ?, ?, ?, 'paid', ?, ?, ?, ?, ?)`,
				s.gymID, member.ID, packageID, plan.price,
				pick(s.rng, []string{"cash", "upi", "upi", "bank_transfer"}),
				soldOn, plan.name, s.ownerUserID, soldOn).Error
		}
		if err != nil {
			return err
		}
		s.paymentCount++
		s.ptPackageCount++

		// Sessions delivered so far. Most packages are partway through.
		delivered := s.rng.Intn(plan.sessions/2 + 1)

		// One package in the whole gym has over-delivered — somebody kept
		// booking after the sessions ran out. Exactly one, because this is
		// meant to be a finding the owner can investigate, not a pattern.
		if i == 5 {
			delivered = plan.sessions + 2
		}

		for k := 0; k < delivered; k++ {
			at := soldOn.AddDate(0, 0, k*3+1)
			if at.After(s.now) {
				break
			}
			if err := s.tx.Exec(`
				INSERT INTO pt_appointments
				    (gym_id, pt_package_id, trainer_id, member_id, scheduled_at,
				     duration_minutes, status, created_by_user_id, created_at)
				VALUES (?, ?, ?, ?, ?, 60, 'completed', ?, ?)`,
				s.gymID, packageID, trainer.id, member.ID,
				at.Add(18*time.Hour), s.ownerUserID, at).Error; err != nil {
				return err
			}
			s.ptSessionCount++
		}

		// The package's own counter is kept honest. Letting it drift here
		// would fire the "counters that disagree" check on every seed and
		// train whoever reads that screen to ignore it.
		if err := s.tx.Exec(`
			UPDATE pt_packages SET sessions_used = ? WHERE id = ?`,
			minInt(delivered, plan.sessions), packageID).Error; err != nil {
			return err
		}
	}

	return nil
}
