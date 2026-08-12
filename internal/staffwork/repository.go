package staffwork

import (
	"context"
	"fmt"
	"time"

	"gorm.io/gorm"

	"gymcrm/internal/database"
)

// ItemLimit caps a drill-down list. Kept small deliberately: this is a list a
// person reads, not an export.
const ItemLimit = 200

type Repository struct {
	db *gorm.DB
}

func NewRepository(db *gorm.DB) *Repository {
	return &Repository{db: db}
}

// IST is the gym's day boundary. Fixed offset rather than a tzdata lookup so
// the binary keeps working in a scratch container with no zoneinfo — the same
// choice the rhythm detector makes, and for the same reason.
var IST = time.FixedZone("IST", 5*60*60+30*60)

// tallyRow is one (user, category) pair straight out of the union.
type tallyRow struct {
	UserID   *int64
	Name     *string
	Role     *string
	Category string
	Count    int64
	Amount   int64
	FirstAt  *time.Time
	LastAt   *time.Time
}

// eventSources is the union that the whole feature rests on.
//
// Each SELECT contributes one ledger, normalised to (user, category, when,
// amount). Written once here rather than as eight separate queries: the
// dashboard needs them grouped together, and eight round trips to build one
// screen is how a dashboard ends up too slow to open.
//
// The timestamp column differs per ledger on purpose — a payment belongs to
// the day it was *paid*, not the day the row happened to be written, and an
// alert belongs to the day it was *resolved*. Using created_at everywhere
// would be simpler and wrong.
const eventSources = `
	SELECT collected_by_user_id AS user_id, 'payments' AS category,
	       COALESCE(paid_date, created_at) AS at, amount_in_paise AS amount
	  FROM payments
	 WHERE gym_id = @gym AND status = 'paid'

	UNION ALL
	SELECT renewed_by_user_id, 'renewals',
	       COALESCE(renewal_date, created_at), amount_paid_in_paise
	  FROM renewals WHERE gym_id = @gym

	UNION ALL
	SELECT created_by_user_id, 'sales', created_at, total_in_paise
	  FROM sales WHERE gym_id = @gym AND is_refund = false

	UNION ALL
	SELECT created_by_user_id, 'invoices', COALESCE(invoice_date, created_at), total_in_paise
	  FROM invoices WHERE gym_id = @gym AND status <> 'cancelled'

	UNION ALL
	SELECT resolved_by, 'retention', resolved_at, 0
	  FROM retention_alerts WHERE gym_id = @gym AND is_resolved = true AND resolved_at IS NOT NULL

	UNION ALL
	SELECT user_id, 'leads', created_at, 0
	  FROM lead_activities WHERE gym_id = @gym

	UNION ALL
	SELECT performed_by_user_id, 'lifecycle', created_at, 0
	  FROM membership_events WHERE gym_id = @gym

	UNION ALL
	SELECT created_by_user_id, 'wallet', created_at, amount_in_paise
	  FROM wallet_transactions WHERE gym_id = @gym AND transaction_type = 'topup'
`

// RangeTallies returns per-user, per-category counts over an inclusive span of
// gym-local days (FR-18 §9). One day is the one-day range.
//
// If userID is non-nil the result is restricted to that person — used to
// enforce FR-13 §7 server-side, never by trusting a client-supplied id.
func (r *Repository) RangeTallies(ctx context.Context, rng Range, userID *int64) ([]tallyRow, error) {
	tc := database.MustGetTenant(ctx)

	// The day filter converts each timestamp into IST before taking its date,
	// so an 11pm sale lands on the day the gym would call it (FR-13 §4).
	// Comparing raw UTC timestamps puts every evening transaction on tomorrow.
	// BETWEEN is inclusive at both ends — what an owner means by "the 1st to
	// the 31st" includes the 31st.
	sql := `
		WITH events AS (` + eventSources + `)
		SELECT e.user_id, u.name, u.role, e.category,
		       COUNT(*)      AS count,
		       COALESCE(SUM(e.amount), 0) AS amount,
		       MIN(e.at)     AS first_at,
		       MAX(e.at)     AS last_at
		  FROM events e
		  LEFT JOIN users u ON u.id = e.user_id
		 WHERE e.at IS NOT NULL
		   AND (e.at AT TIME ZONE 'Asia/Kolkata')::date BETWEEN CAST(@from AS date) AND CAST(@to AS date)
		   AND (CAST(@filter_user AS bigint) IS NULL OR e.user_id = @filter_user)
		 GROUP BY e.user_id, u.name, u.role, e.category`

	var rows []tallyRow
	err := r.db.WithContext(ctx).Raw(sql,
		map[string]interface{}{
			"gym":         tc.GymID(),
			"from":        rng.FromString(),
			"to":          rng.ToString(),
			"filter_user": userID,
		}).Scan(&rows).Error

	return rows, err
}

// itemRow is one drill-down line.
type itemRow struct {
	Category string
	At       time.Time
	Who      string
	What     string
	Amount   *int64
}

// RangeItems returns the individual rows behind one (user, category) number.
//
// Written as one query per category rather than a union: each ledger names its
// counterparty differently (a member, a lead, an invoice number), and forcing
// them into one shape would mean either a lowest-common-denominator label or
// eight CASE branches nobody can read.
func (r *Repository) RangeItems(ctx context.Context, rng Range, userID *int64, cat Category) ([]itemRow, error) {
	tc := database.MustGetTenant(ctx)

	memberName := `TRIM(m.first_name || ' ' || COALESCE(m.last_name, ''))`

	var sql string
	switch cat {
	case CatPayments:
		sql = `SELECT 'payments' AS category, COALESCE(p.paid_date, p.created_at) AS at,
		              ` + memberName + ` AS who,
		              'Payment · ' || p.payment_mode AS what, p.amount_in_paise AS amount
		         FROM payments p JOIN members m ON m.id = p.member_id
		        WHERE p.gym_id = @gym AND p.status = 'paid'
		          AND (COALESCE(p.paid_date, p.created_at) AT TIME ZONE 'Asia/Kolkata')::date BETWEEN CAST(@from AS date) AND CAST(@to AS date)
		          AND p.collected_by_user_id IS NOT DISTINCT FROM @user`

	case CatRenewals:
		sql = `SELECT 'renewals' AS category, COALESCE(r.renewal_date, r.created_at) AS at,
		              ` + memberName + ` AS who,
		              'Renewed to ' || r.new_expiry_date::text AS what, r.amount_paid_in_paise AS amount
		         FROM renewals r JOIN members m ON m.id = r.member_id
		        WHERE r.gym_id = @gym
		          AND (COALESCE(r.renewal_date, r.created_at) AT TIME ZONE 'Asia/Kolkata')::date BETWEEN CAST(@from AS date) AND CAST(@to AS date)
		          AND r.renewed_by_user_id IS NOT DISTINCT FROM @user`

	case CatSales:
		sql = `SELECT 'sales' AS category, s.created_at AS at,
		              COALESCE(` + memberName + `, 'Walk-in') AS who,
		              'Shop sale · ' || s.payment_mode AS what, s.total_in_paise AS amount
		         FROM sales s LEFT JOIN members m ON m.id = s.member_id
		        WHERE s.gym_id = @gym AND s.is_refund = false
		          AND (s.created_at AT TIME ZONE 'Asia/Kolkata')::date BETWEEN CAST(@from AS date) AND CAST(@to AS date)
		          AND s.created_by_user_id IS NOT DISTINCT FROM @user`

	case CatInvoices:
		sql = `SELECT 'invoices' AS category, COALESCE(i.invoice_date, i.created_at) AS at,
		              ` + memberName + ` AS who,
		              'Invoice ' || i.invoice_number AS what, i.total_in_paise AS amount
		         FROM invoices i JOIN members m ON m.id = i.member_id
		        WHERE i.gym_id = @gym AND i.status <> 'cancelled'
		          AND (COALESCE(i.invoice_date, i.created_at) AT TIME ZONE 'Asia/Kolkata')::date BETWEEN CAST(@from AS date) AND CAST(@to AS date)
		          AND i.created_by_user_id IS NOT DISTINCT FROM @user`

	case CatRetention:
		sql = `SELECT 'retention' AS category, a.resolved_at AS at,
		              ` + memberName + ` AS who,
		              COALESCE(a.action_note, a.alert_type) AS what, NULL AS amount
		         FROM retention_alerts a JOIN members m ON m.id = a.member_id
		        WHERE a.gym_id = @gym AND a.is_resolved = true
		          AND (a.resolved_at AT TIME ZONE 'Asia/Kolkata')::date BETWEEN CAST(@from AS date) AND CAST(@to AS date)
		          AND a.resolved_by IS NOT DISTINCT FROM @user`

	case CatLeads:
		sql = `SELECT 'leads' AS category, la.created_at AS at, l.name AS who,
		              la.type || COALESCE(' · ' || la.note, '') AS what, NULL AS amount
		         FROM lead_activities la JOIN leads l ON l.id = la.lead_id
		        WHERE la.gym_id = @gym
		          AND (la.created_at AT TIME ZONE 'Asia/Kolkata')::date BETWEEN CAST(@from AS date) AND CAST(@to AS date)
		          AND la.user_id IS NOT DISTINCT FROM @user`

	case CatLifecycle:
		sql = `SELECT 'lifecycle' AS category, e.created_at AS at, ` + memberName + ` AS who,
		              e.event_type || COALESCE(' · ' || e.reason, '') AS what, NULL AS amount
		         FROM membership_events e JOIN members m ON m.id = e.member_id
		        WHERE e.gym_id = @gym
		          AND (e.created_at AT TIME ZONE 'Asia/Kolkata')::date BETWEEN CAST(@from AS date) AND CAST(@to AS date)
		          AND e.performed_by_user_id IS NOT DISTINCT FROM @user`

	case CatWallet:
		sql = `SELECT 'wallet' AS category, w.created_at AS at, ` + memberName + ` AS who,
		              COALESCE(w.reason, 'Wallet top-up') AS what, w.amount_in_paise AS amount
		         FROM wallet_transactions w JOIN members m ON m.id = w.member_id
		        WHERE w.gym_id = @gym AND w.transaction_type = 'topup'
		          AND (w.created_at AT TIME ZONE 'Asia/Kolkata')::date BETWEEN CAST(@from AS date) AND CAST(@to AS date)
		          AND w.created_by_user_id IS NOT DISTINCT FROM @user`

	default:
		return nil, ErrUnknownCategory
	}

	// One row over the cap, so the caller can tell "exactly 200 things happened"
	// apart from "there were more and you are not seeing them". A day rarely
	// reached the cap; a month will, and a silently truncated list is a lie the
	// reader has no way to detect.
	var rows []itemRow
	err := r.db.WithContext(ctx).Raw(
		fmt.Sprintf("%s ORDER BY 2 DESC LIMIT %d", sql, ItemLimit+1),
		map[string]interface{}{
			"gym":  tc.GymID(),
			"from": rng.FromString(),
			"to":   rng.ToString(),
			// IS NOT DISTINCT FROM, so a nil user matches the unattributed
			// rows rather than matching nothing the way `= NULL` would.
			"user": userID,
		}).Scan(&rows).Error

	return rows, err
}
