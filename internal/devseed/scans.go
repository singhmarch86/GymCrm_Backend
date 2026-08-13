package devseed

import (
	"context"
	"fmt"

	"gorm.io/gorm"

	"gymcrm/internal/database"
	"gymcrm/internal/retention"
	"gymcrm/internal/rhythm"
	"gymcrm/internal/users"
)

// The scans that turn seeded history into the alerts At Risk reads.
//
// Attendance is data; "this member has stopped coming" is a conclusion, and
// nothing draws it until a scan runs. A freshly seeded database therefore had
// 800 members, four years of attendance, and an empty At Risk screen —
// technically correct and useless as a demo, since the one screen most worth
// looking at was the one showing nothing.
//
// Deliberately runs the real scanners rather than inserting alert rows
// directly. A seed that wrote its own alerts would be asserting what the
// scanners ought to produce instead of showing what they do, and the two would
// drift the first time a threshold moved. Anything on the screen after seeding
// is something the production code actually decided.
func (s *seeder) runScans(ctx context.Context, db *gorm.DB) error {
	// Both scans are tenant-scoped, so they need the context the JWT
	// middleware would normally build. This is the only other place that
	// constructs one, and it is legitimate for the same reason the middleware
	// is: the caller has already established who is acting. Here that is the
	// seeder itself, acting as the owner it just created.
	tc := database.NewTenantContext(s.gymID, s.ownerUserID, string(users.RoleOwner))
	ctx = database.WithTenant(ctx, tc)

	retentionSvc := retention.NewService(retention.NewRepository(db))
	res, err := retentionSvc.Scan(ctx)
	if err != nil {
		return fmt.Errorf("retention scan: %w", err)
	}
	s.retentionAlerts = res.Raised

	// Empty as-of means today, the same default the endpoint uses.
	rhythmSvc := rhythm.NewService(rhythm.NewRepository(db))
	rres, err := rhythmSvc.Scan(ctx, "")
	if err != nil {
		return fmt.Errorf("rhythm scan: %w", err)
	}
	s.rhythmAlerts = rres.AlertsRaised

	return nil
}
