package counter

import (
	"context"
	"time"

	"gorm.io/gorm"

	"gymcrm/internal/database"
)

type Repository struct {
	db *gorm.DB
}

func NewRepository(db *gorm.DB) *Repository { return &Repository{db: db} }

type visitRow struct {
	TotalVisits int
	LastVisit   *time.Time
	PrevVisit   *time.Time
}

type alertRow struct {
	AlertType string
	Severity  string
	Message   string
}

type ptRow struct {
	TrainerName  string
	SessionsLeft int
}

type restockRow struct {
	ProductName   string
	Purchases     int
	DaysSinceLast int
	TypicalDays   int
}

type walletRow struct {
	BalanceInPaise int64
	TxCount        int
}

// LoadContext gathers everything the rules need for one member.
//
// Deliberately several small queries rather than one clever join: each is
// independently readable, and the whole thing runs at the front desk where a
// wrong answer is worse than a slow one.
func (r *Repository) LoadContext(ctx context.Context, memberID int64, now time.Time) (Context, error) {
	tc := database.MustGetTenant(ctx)
	gymID := tc.GymID()
	c := Context{RecentKinds: map[Kind]bool{}}

	// Visits. PrevVisit is the visit *before* today's, because by the time this
	// runs the member has usually just been checked in — measuring the gap
	// against their own new row would always say zero.
	var v []visitRow
	if err := r.db.WithContext(ctx).Raw(`
		SELECT COUNT(*) AS total_visits,
		       MAX(checked_in_date) AS last_visit,
		       MAX(checked_in_date) FILTER (WHERE checked_in_date < ?) AS prev_visit
		FROM attendance
		WHERE gym_id = ? AND member_id = ?
	`, now.Format("2006-01-02"), gymID, memberID).Scan(&v).Error; err != nil {
		return c, err
	}
	if len(v) > 0 {
		c.TotalVisits = v[0].TotalVisits
		c.DaysSinceLastVisit = -1
		if v[0].PrevVisit != nil {
			c.DaysSinceLastVisit = int(now.Sub(*v[0].PrevVisit).Hours() / 24)
		}
	}

	// Open alerts.
	var alerts []alertRow
	if err := r.db.WithContext(ctx).Raw(`
		SELECT alert_type, severity, message
		FROM retention_alerts
		WHERE gym_id = ? AND member_id = ? AND is_resolved = false
	`, gymID, memberID).Scan(&alerts).Error; err != nil {
		return c, err
	}
	for _, a := range alerts {
		c.OpenAlerts = append(c.OpenAlerts, OpenAlert(a))
	}

	// Personal training: the active package closest to running out.
	var pt []ptRow
	if err := r.db.WithContext(ctx).Raw(`
		SELECT COALESCE(NULLIF(TRIM(COALESCE(t.first_name,'') || ' ' || COALESCE(t.last_name,'')), ''),
		                'their trainer') AS trainer_name,
		       (p.total_sessions - p.sessions_used) AS sessions_left
		FROM pt_packages p
		LEFT JOIN trainers t ON t.id = p.trainer_id AND t.gym_id = p.gym_id
		WHERE p.gym_id = ? AND p.member_id = ?
		  AND p.status = 'active'
		  AND (p.expiry_date IS NULL OR p.expiry_date >= CURRENT_DATE)
		  AND p.total_sessions > p.sessions_used
		ORDER BY sessions_left ASC
		LIMIT 1
	`, gymID, memberID).Scan(&pt).Error; err != nil {
		return c, err
	}
	if len(pt) > 0 {
		c.PT = &PTPackage{TrainerName: pt[0].TrainerName, SessionsLeft: pt[0].SessionsLeft}
	}

	// Restock: the product they buy most regularly, with THEIR typical gap
	// rather than a fixed guess — somebody who buys monthly and somebody who
	// buys fortnightly should not be prompted on the same schedule.
	var rs []restockRow
	if err := r.db.WithContext(ctx).Raw(`
		SELECT si.product_name,
		       COUNT(*)::int AS purchases,
		       (CURRENT_DATE - MAX(s.created_at::date))::int AS days_since_last,
		       GREATEST(1, (
		           (MAX(s.created_at::date) - MIN(s.created_at::date))
		           / GREATEST(1, COUNT(*) - 1)
		       ))::int AS typical_days
		FROM sale_items si
		JOIN sales s ON s.id = si.sale_id AND s.gym_id = si.gym_id
		WHERE si.gym_id = ? AND s.member_id = ? AND s.is_refund = false
		GROUP BY si.product_name
		HAVING COUNT(*) >= 2
		ORDER BY (CURRENT_DATE - MAX(s.created_at::date)) DESC
		LIMIT 1
	`, gymID, memberID).Scan(&rs).Error; err != nil {
		return c, err
	}
	if len(rs) > 0 {
		c.Restock = &RestockCandidate{
			ProductName: rs[0].ProductName, Purchases: rs[0].Purchases,
			DaysSinceLast: rs[0].DaysSinceLast, TypicalDays: rs[0].TypicalDays,
		}
	}

	// Wallet. TxCount is what distinguishes "low balance" from "never used it".
	var w []walletRow
	if err := r.db.WithContext(ctx).Raw(`
		SELECT m.wallet_balance_in_paise AS balance_in_paise,
		       (SELECT COUNT(*) FROM wallet_transactions wt
		         WHERE wt.gym_id = m.gym_id AND wt.member_id = m.id)::int AS tx_count
		FROM members m
		WHERE m.gym_id = ? AND m.id = ?
	`, gymID, memberID).Scan(&w).Error; err != nil {
		return c, err
	}
	if len(w) > 0 {
		c.WalletBalanceInPaise = w[0].BalanceInPaise
		c.UsesWallet = w[0].TxCount > 0
	}

	// Which kinds are still inside their cooldown.
	var kinds []string
	if err := r.db.WithContext(ctx).Raw(`
		SELECT DISTINCT prompt_kind
		FROM counter_prompt_log
		WHERE gym_id = ? AND member_id = ? AND shown_at >= ?
	`, gymID, memberID, CooldownSince(now)).Scan(&kinds).Error; err != nil {
		return c, err
	}
	for _, k := range kinds {
		c.RecentKinds[Kind(k)] = true
	}

	return c, nil
}

// LogShown records a prompt that was actually put in front of somebody.
//
// Only called when the prompt is displayed, never on a lookup — otherwise
// browsing a member's record would burn their cooldown (FR-11 §7).
func (r *Repository) LogShown(ctx context.Context, memberID int64, p Prompt, userID int64) (int64, error) {
	tc := database.MustGetTenant(ctx)
	var id int64
	err := r.db.WithContext(ctx).Raw(`
		INSERT INTO counter_prompt_log
			(gym_id, member_id, prompt_kind, prompt_text, shown_by_user_id)
		VALUES (?,?,?,?,?)
		RETURNING id
	`, tc.GymID(), memberID, string(p.Kind), p.Text, userID).Scan(&id).Error
	return id, err
}

// MarkActed records that the staff member did something about it. Optional by
// design — mandatory logging at a busy counter gets clicked through
// meaninglessly, which is worse than no data (FR-11 §5).
func (r *Repository) MarkActed(ctx context.Context, promptID int64, note string) (int64, error) {
	tc := database.MustGetTenant(ctx)
	res := r.db.WithContext(ctx).Exec(`
		UPDATE counter_prompt_log
		SET acted = true, acted_at = NOW(), action_note = NULLIF(?, '')
		WHERE gym_id = ? AND id = ?
	`, note, tc.GymID(), promptID)
	return res.RowsAffected, res.Error
}

// EffectivenessRow is one prompt kind's record: how often it was shown and how
// often anyone acted.
type EffectivenessRow struct {
	PromptKind string  `json:"prompt_kind"`
	Shown      int     `json:"shown"`
	Acted      int     `json:"acted"`
	ActedShare float64 `json:"acted_share"`
}

// Effectiveness is the honest scoreboard: which prompts staff actually use.
// A kind nobody ever acts on is noise and should be switched off.
func (r *Repository) Effectiveness(ctx context.Context, days int) ([]EffectivenessRow, error) {
	tc := database.MustGetTenant(ctx)
	var rows []EffectivenessRow
	err := r.db.WithContext(ctx).Raw(`
		SELECT prompt_kind,
		       COUNT(*)::int AS shown,
		       COUNT(*) FILTER (WHERE acted)::int AS acted,
		       CASE WHEN COUNT(*) = 0 THEN 0
		            ELSE COUNT(*) FILTER (WHERE acted)::numeric / COUNT(*) END AS acted_share
		FROM counter_prompt_log
		WHERE gym_id = ? AND shown_at >= CURRENT_DATE - make_interval(days => ?)
		GROUP BY prompt_kind
		ORDER BY shown DESC
	`, tc.GymID(), days).Scan(&rows).Error
	return rows, err
}
