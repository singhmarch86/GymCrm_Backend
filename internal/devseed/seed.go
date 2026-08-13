// Package devseed populates a freshly created development database with a
// realistic demo dataset: one gym, an owner login, membership plans, 150
// members across active/expiring/expired states, 90 days of attendance,
// renewal + payment history, and a lead pipeline.
//
// It is gated by two things, enforced at two different layers on purpose:
//   - the caller (cmd/server/main.go) only invokes Run when APP_ENV=development
//   - Run itself refuses to do anything unless the users table is empty
//
// The second gate is what makes this idempotent: every run either seeds a
// gym+owner+users (making later runs a no-op) or seeds nothing at all. The
// whole seed happens inside one transaction, so a crash partway through
// leaves users empty and the next boot retries cleanly instead of leaving a
// half-seeded gym behind with duplicate-prone data.
package devseed

import (
	"context"
	"fmt"
	"log"
	"math/rand"
	"time"

	"gorm.io/gorm"

	"gymcrm/internal/plans"
	"gymcrm/internal/users"
)

// seeder carries shared state across the seed phases (gym.go, plans.go,
// members.go, attendance.go, billing.go, leads.go). A fixed RNG seed keeps
// a from-scratch reseed reproducible for debugging.
type seeder struct {
	tx  *gorm.DB
	rng *rand.Rand
	now time.Time // today, truncated to midnight UTC

	gymID       int64
	ownerUserID int64
	staffUserID int64

	// The chain. Both are zero until seedSecondBranch runs, which is last —
	// everything before it is written as a single-branch gym, because that
	// is what the gym is until a second location exists.
	orgID       int64
	branchGymID int64

	plans    []plans.MembershipPlan
	members  []seedMember
	trainers []seedTrainer
	products []seedProduct

	// counts for the closing summary log
	memberCount     int
	attendanceCount int
	renewalCount    int
	paymentCount    int
	leadCount       int
	trainerCount    int
	ptPackageCount  int
	ptSessionCount  int
	productCount    int
	saleCount       int
	transferCount   int
	retentionAlerts int64
	rhythmAlerts    int64
}

// Run seeds the database if it looks fresh. Safe to call on every startup —
// it is a no-op once the users table has any row in it.
func Run(ctx context.Context, db *gorm.DB) error {
	var userCount int64
	if err := db.WithContext(ctx).Model(&users.User{}).Count(&userCount).Error; err != nil {
		return fmt.Errorf("devseed: count users: %w", err)
	}
	if userCount > 0 {
		log.Println("devseed: users table is not empty, skipping (already seeded)")
		return nil
	}

	s := &seeder{
		rng: rand.New(rand.NewSource(42)),
		now: time.Now().UTC().Truncate(24 * time.Hour),
	}

	err := db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		s.tx = tx

		if err := s.seedGymAndOwner(); err != nil {
			return fmt.Errorf("gym+owner: %w", err)
		}
		if err := s.seedPlans(); err != nil {
			return fmt.Errorf("plans: %w", err)
		}
		if err := s.seedMembers(); err != nil {
			return fmt.Errorf("members: %w", err)
		}
		if err := s.seedAttendance(); err != nil {
			return fmt.Errorf("attendance: %w", err)
		}
		if err := s.seedBilling(); err != nil {
			return fmt.Errorf("billing: %w", err)
		}
		if err := s.seedLeads(); err != nil {
			return fmt.Errorf("leads: %w", err)
		}
		// Trainers before packages: a package needs somebody to deliver it.
		if err := s.seedTrainers(); err != nil {
			return fmt.Errorf("trainers: %w", err)
		}
		if err := s.seedPTPackages(); err != nil {
			return fmt.Errorf("pt packages: %w", err)
		}
		if err := s.seedProducts(); err != nil {
			return fmt.Errorf("products: %w", err)
		}
		// Sales draw stock down through the movements ledger, so they must
		// follow the opening purchases that put it there.
		if err := s.seedSales(); err != nil {
			return fmt.Errorf("sales: %w", err)
		}
		// Last, and on purpose. It backfills the main gym with an
		// organization and a branch name, and the opening transfer draws on
		// stock levels that sales have already moved — so it has to see the
		// finished shop rather than the opening one.
		if err := s.seedSecondBranch(); err != nil {
			return fmt.Errorf("second branch: %w", err)
		}
		return nil
	})
	if err != nil {
		return fmt.Errorf("devseed: %w", err)
	}

	// After the commit, never inside it. Both scanners read the seeded history
	// through their own repositories and write their own rows; running them
	// against an uncommitted transaction would show them a database that does
	// not exist yet.
	//
	// A scan failure is logged, not returned. The seed itself has already
	// committed and is sound — losing the derived alerts is worth a warning,
	// but refusing to boot over it would be a poor trade.
	if err := s.runScans(ctx, db); err != nil {
		log.Printf("devseed: warning: %v (At Risk will be empty until a scan runs)", err)
	}

	log.Printf("devseed: seeded demo gym %q — owner login phone=9876543210 password=secure123", "Demo Fitness Gym")
	log.Printf("devseed: %d members, %d attendance records, %d renewals, %d payments, %d leads",
		s.memberCount, s.attendanceCount, s.renewalCount, s.paymentCount, s.leadCount)
	log.Printf("devseed: %d trainers, %d PT packages, %d sessions, %d products, %d counter sales",
		len(s.trainers), s.ptPackageCount, s.ptSessionCount, s.productCount, s.saleCount)
	log.Printf("devseed: 2 branches (%s, %s) under one organization, %d stock transfer(s)",
		mainBranchName, secondBranchName, s.transferCount)
	log.Printf("devseed: %d inactivity alerts, %d rhythm breaks — raised by the real scanners",
		s.retentionAlerts, s.rhythmAlerts)
	return nil
}

// ─── Small shared helpers ──────────────────────────────────────────────────

// deskUser spreads counter work across the two people who work the desk.
//
// A third to the owner, the rest to reception. Only payments route through
// here — renewals, lifecycle changes and the rest stay with the owner — so the
// gym-wide split lands nearer 70/30 than 33/67. That is a fair picture of a
// small gym where the owner does most things and reception takes money at the
// counter, and it is enough for the per-person views to have something to
// show. Attributing everything to the owner made every staff screen a
// single-row list.
func (s *seeder) deskUser() int64 {
	if s.staffUserID == 0 || s.rng.Intn(3) == 0 {
		return s.ownerUserID
	}
	return s.staffUserID
}

func strPtr(s string) *string        { return &s }
func timePtr(t time.Time) *time.Time { return &t }
func int64Ptr(v int64) *int64        { return &v }

// pick returns a random element of a non-empty slice.
func pick[T any](rng *rand.Rand, items []T) T {
	return items[rng.Intn(len(items))]
}

// weightedIndex returns an index into weights chosen proportionally to the
// weight values (which need not sum to 1).
func weightedIndex(rng *rand.Rand, weights []float64) int {
	total := 0.0
	for _, w := range weights {
		total += w
	}
	r := rng.Float64() * total
	for i, w := range weights {
		if r < w {
			return i
		}
		r -= w
	}
	return len(weights) - 1
}

// min returns the smaller of two ints (local helper — avoids depending on
// Go 1.21's builtin min in case the toolchain here predates it).
func minInt(a, b int) int {
	if a < b {
		return a
	}
	return b
}
