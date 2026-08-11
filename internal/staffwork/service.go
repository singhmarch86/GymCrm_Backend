package staffwork

import (
	"context"
	"errors"
	"sort"
	"time"

	"gymcrm/internal/database"
)

var (
	ErrUnknownCategory = errors.New("staffwork: unknown category")
	ErrBadDate         = errors.New("staffwork: date must be YYYY-MM-DD")
)

type Service struct {
	repo *Repository
}

func NewService(repo *Repository) *Service {
	return &Service{repo: repo}
}

// ParseDay turns a YYYY-MM-DD query parameter into a day in IST. An empty
// string means today — in the gym's timezone, not the server's.
func ParseDay(s string) (time.Time, error) {
	if s == "" {
		return time.Now().In(IST), nil
	}
	d, err := time.ParseInLocation("2006-01-02", s, IST)
	if err != nil {
		return time.Time{}, ErrBadDate
	}
	return d, nil
}

// Day builds the whole screen for one date.
//
// Visibility is decided here from the caller's own token: an owner sees
// everyone, anybody else sees only themselves (FR-13 §7). Deliberately not a
// client-supplied user_id — a staff member editing a query parameter must not
// be able to read a colleague's day.
func (s *Service) Day(ctx context.Context, day time.Time) (*DayReport, error) {
	tc := database.MustGetTenant(ctx)

	var filter *int64
	if !tc.IsOwner() {
		uid := tc.UserID()
		filter = &uid
	}

	rows, err := s.repo.DayTallies(ctx, day, filter)
	if err != nil {
		return nil, err
	}

	report := &DayReport{Date: day.Format("2006-01-02"), Staff: []StaffDay{}}

	// Group by user. A nil user id is its own bucket: unattributed work is
	// shown rather than folded into whoever looks likeliest (FR-13 §2, §3).
	type key struct {
		id    int64
		isNil bool
	}
	byUser := map[key]*StaffDay{}

	for _, row := range rows {
		if row.Count == 0 {
			continue
		}

		k := key{isNil: row.UserID == nil}
		if row.UserID != nil {
			k.id = *row.UserID
		}

		sd, ok := byUser[k]
		if !ok {
			sd = &StaffDay{UserID: row.UserID, Name: "Unattributed"}
			if row.Name != nil && *row.Name != "" {
				sd.Name = *row.Name
			}
			sd.Role = row.Role
			byUser[k] = sd
		}

		cat := Category(row.Category)
		t := Tally{Category: cat, Label: cat.Label(), Count: row.Count}
		if cat.HasMoney() {
			amount := row.Amount
			t.AmountInPaise = &amount
			sd.TotalHandled += amount
		}
		sd.Tallies = append(sd.Tallies, t)
		sd.TotalActions += row.Count

		sd.FirstActionAt = earlier(sd.FirstActionAt, row.FirstAt)
		sd.LastActionAt = later(sd.LastActionAt, row.LastAt)
	}

	for _, sd := range byUser {
		// Categories in a fixed display order, so a person's card does not
		// rearrange itself between days.
		sort.Slice(sd.Tallies, func(i, j int) bool {
			return categoryRank(sd.Tallies[i].Category) < categoryRank(sd.Tallies[j].Category)
		})
		report.Staff = append(report.Staff, *sd)
		report.TotalActions += sd.TotalActions
		report.TotalHandled += sd.TotalHandled
	}

	// By name, never by count (FR-13 §9). Sorting by output would turn this
	// into a leaderboard on every load, which §1 exists to prevent.
	// Unattributed sits last because it is not a person.
	sort.Slice(report.Staff, func(i, j int) bool {
		a, b := report.Staff[i], report.Staff[j]
		if (a.UserID == nil) != (b.UserID == nil) {
			return b.UserID == nil
		}
		return a.Name < b.Name
	})

	return report, nil
}

// Items returns the rows behind one number, after the same visibility check.
func (s *Service) Items(ctx context.Context, day time.Time, userID *int64, cat Category) ([]Item, error) {
	tc := database.MustGetTenant(ctx)

	if !tc.IsOwner() {
		// A staff member may only ever drill into their own work, whatever
		// user_id they asked for.
		uid := tc.UserID()
		if userID == nil || *userID != uid {
			userID = &uid
		}
	}

	if !IsValidCategory(string(cat)) {
		return nil, ErrUnknownCategory
	}

	rows, err := s.repo.DayItems(ctx, day, userID, cat)
	if err != nil {
		return nil, err
	}

	items := make([]Item, 0, len(rows))
	for _, r := range rows {
		items = append(items, Item{
			Category:      Category(r.Category),
			At:            r.At,
			Who:           r.Who,
			What:          r.What,
			AmountInPaise: r.Amount,
		})
	}
	return items, nil
}

func categoryRank(c Category) int {
	for i, x := range AllCategories {
		if x == c {
			return i
		}
	}
	return len(AllCategories)
}

func earlier(a, b *time.Time) *time.Time {
	if b == nil {
		return a
	}
	if a == nil || b.Before(*a) {
		return b
	}
	return a
}

func later(a, b *time.Time) *time.Time {
	if b == nil {
		return a
	}
	if a == nil || b.After(*a) {
		return b
	}
	return a
}
