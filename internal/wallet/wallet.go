// Package wallet implements stored credit on a member's account.
// See docs/FR-08-member-wallet.md.
//
// One rule shapes everything: the balance is the running result of an
// insert-only ledger, never a number anyone edits. "Why is my balance ₹300?"
// must always have an answer — same discipline as stock movements (FR-07 §1)
// and membership events (FR-01).
package wallet

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	"encoding/json"
	stdlog "log"

	"gorm.io/gorm"
	"gorm.io/gorm/clause"

	"gymcrm/internal/database"
	"gymcrm/internal/shared/response"
)

// ─── Model ────────────────────────────────────────────────────────────────────

type Transaction struct {
	ID       int64 `gorm:"primaryKey;autoIncrement" json:"id"`
	GymID    int64 `gorm:"not null" json:"gym_id"`
	MemberID int64 `gorm:"not null" json:"member_id"`

	// Signed: positive adds credit, negative spends it.
	AmountInPaise   int64  `gorm:"not null" json:"amount_in_paise"`
	BalanceAfter    int64  `gorm:"not null" json:"balance_after"`
	TransactionType string `gorm:"type:varchar(20);not null" json:"transaction_type"`

	Reason    *string `gorm:"type:text" json:"reason,omitempty"`
	SaleID    *int64  `json:"sale_id,omitempty"`
	InvoiceID *int64  `json:"invoice_id,omitempty"`
	PaymentID *int64  `json:"payment_id,omitempty"`

	CreatedByUserID int64     `gorm:"not null" json:"created_by_user_id"`
	CreatedAt       time.Time `gorm:"autoCreateTime" json:"created_at"`
}

func (Transaction) TableName() string { return "wallet_transactions" }

const (
	TypeTopup      = "topup"
	TypeSpend      = "spend"
	TypeRefund     = "refund"
	TypeAdjustment = "adjustment"
	TypeExpiry     = "expiry"
)

var (
	ErrMemberNotFound   = errors.New("member not found")
	ErrAmountZero       = errors.New("amount must be greater than 0")
	ErrInsufficientFunds = errors.New("not enough balance in the wallet")
	ErrReasonRequired   = errors.New("a reason is required")
)

// ─── Repository ───────────────────────────────────────────────────────────────

type Repository struct{ db *gorm.DB }

func NewRepository(db *gorm.DB) *Repository { return &Repository{db: db} }

// Apply appends a ledger row and moves the cached balance, atomically, with the
// member row locked.
//
// CONCURRENCY: spending reads the balance, checks it, then writes a lower one —
// a check-then-act that races. Two staff spending the last ₹500 simultaneously
// would both succeed and leave the wallet negative. The member row is locked
// FOR UPDATE inside the same transaction, as with class capacity (FR-02), PT
// credits (FR-03) and stock (FR-07).
func (r *Repository) Apply(ctx context.Context, memberID int64, delta int64, txType, reason string, allowNegative bool) (*Transaction, error) {
	var out *Transaction
	err := r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		var err error
		out, err = ApplyTx(ctx, tx, memberID, delta, txType, reason, allowNegative, nil)
		return err
	})
	if err != nil {
		return nil, err
	}
	return out, nil
}

// ApplyTx is the same operation against a caller-supplied transaction, so
// another module can move a wallet balance as part of its own atomic unit.
//
// This exists for the POS counter: paying for a sale from stored credit must
// record the sale, move the stock and debit the wallet together, or do none of
// them. Two separate calls would leave a window where a member is charged for
// goods that were never sold, or given goods never charged for.
//
// saleID links the ledger row back to what the credit was spent on.
func ApplyTx(
	ctx context.Context,
	tx *gorm.DB,
	memberID int64,
	delta int64,
	txType, reason string,
	allowNegative bool,
	saleID *int64,
) (*Transaction, error) {
	tc := database.MustGetTenant(ctx)

	var current struct {
		ID      int64
		Balance int64
	}
	err := tx.Table("members").
		Clauses(clause.Locking{Strength: "UPDATE"}).
		Select("id, wallet_balance_in_paise AS balance").
		Where("id = ? AND gym_id = ? AND deleted_at IS NULL", memberID, tc.GymID()).
		Take(&current).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, ErrMemberNotFound
	}
	if err != nil {
		return nil, err
	}

	after := current.Balance + delta
	if after < 0 && !allowNegative {
		return nil, fmt.Errorf("%w: balance is %d, tried to spend %d",
			ErrInsufficientFunds, current.Balance, -delta)
	}

	if err := tx.Table("members").Where("id = ?", memberID).
		Updates(map[string]any{
			"wallet_balance_in_paise": after,
			"updated_at":              time.Now(),
		}).Error; err != nil {
		return nil, err
	}

	out := Transaction{
		GymID: tc.GymID(), MemberID: memberID,
		AmountInPaise: delta, BalanceAfter: after,
		TransactionType: txType, Reason: optional(reason),
		SaleID: saleID, CreatedByUserID: tc.UserID(),
	}
	if err := tx.Create(&out).Error; err != nil {
		return nil, err
	}
	return &out, nil
}

func (r *Repository) Balance(ctx context.Context, memberID int64) (int64, error) {
	tc := database.MustGetTenant(ctx)
	var balance *int64
	err := r.db.WithContext(ctx).Table("members").
		Select("wallet_balance_in_paise").
		Where("id = ? AND gym_id = ? AND deleted_at IS NULL", memberID, tc.GymID()).
		Limit(1).Scan(&balance).Error
	if err != nil || balance == nil {
		return 0, err
	}
	return *balance, nil
}

func (r *Repository) History(ctx context.Context, memberID int64, limit int) ([]Transaction, error) {
	q := database.ScopedDB(ctx, r.db).
		Where("member_id = ?", memberID).
		Order("created_at DESC")
	if limit > 0 {
		q = q.Limit(limit)
	}
	var out []Transaction
	err := q.Find(&out).Error
	return out, err
}

// ─── Service ──────────────────────────────────────────────────────────────────

type Service struct{ repo *Repository }

func NewService(repo *Repository) *Service { return &Service{repo: repo} }

// TopUp adds credit. Money coming in is recorded as a payment separately —
// this only records that the member now holds credit.
func (s *Service) TopUp(ctx context.Context, memberID, amountInPaise int64, reason string) (*Transaction, error) {
	if amountInPaise <= 0 {
		return nil, ErrAmountZero
	}
	return s.repo.Apply(ctx, memberID, amountInPaise, TypeTopup, reason, false)
}

// Spend deducts credit, refusing to go below zero. Overdraft is deliberately
// not a feature: a wallet that can go negative is an unsecured loan the gym
// never agreed to give.
func (s *Service) Spend(ctx context.Context, memberID, amountInPaise int64, reason string) (*Transaction, error) {
	if amountInPaise <= 0 {
		return nil, ErrAmountZero
	}
	return s.repo.Apply(ctx, memberID, -amountInPaise, TypeSpend, reason, false)
}

// Adjust is the manual correction path, and always needs a reason — an
// unexplained balance change is exactly what this ledger exists to prevent.
func (s *Service) Adjust(ctx context.Context, memberID, deltaInPaise int64, reason string) (*Transaction, error) {
	if deltaInPaise == 0 {
		return nil, ErrAmountZero
	}
	if strings.TrimSpace(reason) == "" {
		return nil, ErrReasonRequired
	}
	// A correction may legitimately take a balance to zero but never below.
	return s.repo.Apply(ctx, memberID, deltaInPaise, TypeAdjustment, reason, false)
}

type Summary struct {
	MemberID       int64         `json:"member_id"`
	BalanceInPaise int64         `json:"balance_in_paise"`
	BalanceInRupees float64      `json:"balance_in_rupees"`
	Transactions   []Transaction `json:"transactions"`
}

func (s *Service) Get(ctx context.Context, memberID int64) (*Summary, error) {
	balance, err := s.repo.Balance(ctx, memberID)
	if err != nil {
		return nil, fmt.Errorf("wallet: %w", err)
	}
	history, err := s.repo.History(ctx, memberID, 50)
	if err != nil {
		return nil, fmt.Errorf("wallet history: %w", err)
	}
	return &Summary{
		MemberID: memberID, BalanceInPaise: balance,
		BalanceInRupees: float64(balance) / 100, Transactions: history,
	}, nil
}

// ─── Handler ──────────────────────────────────────────────────────────────────

type Handler struct{ svc *Service }

func NewHandler(svc *Service) *Handler { return &Handler{svc: svc} }

type amountRequest struct {
	AmountInPaise int64  `json:"amount_in_paise"`
	Reason        string `json:"reason"`
}

// Get godoc
// @Summary      A member's wallet balance and history
// @Tags         wallet
// @Produce      json
// @Security     BearerAuth
// @Param        member_id  path      int  true  "Member ID"
// @Success      200        {object}  Summary
// @Router       /api/v1/members/{member_id}/wallet [get]
func (h *Handler) Get(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	res, err := h.svc.Get(r.Context(), id)
	if err != nil {
		writeErr(w, err, "get wallet")
		return
	}
	response.OK(w, res)
}

// TopUp godoc
// @Summary      Add credit to a member's wallet
// @Tags         wallet
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        member_id  path      int            true  "Member ID"
// @Param        body       body      amountRequest  true  "Amount"
// @Success      201        {object}  Transaction
// @Router       /api/v1/members/{member_id}/wallet/topup [post]
func (h *Handler) TopUp(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	var req amountRequest
	if !decode(w, r, &req) {
		return
	}
	res, err := h.svc.TopUp(r.Context(), id, req.AmountInPaise, req.Reason)
	if err != nil {
		writeErr(w, err, "wallet topup")
		return
	}
	response.Created(w, res)
}

// Spend godoc
// @Summary      Spend from a member's wallet
// @Description  Refused if the balance is short — the wallet never goes negative.
// @Tags         wallet
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        member_id  path      int            true  "Member ID"
// @Param        body       body      amountRequest  true  "Amount"
// @Success      201        {object}  Transaction
// @Failure      409        {object}  response.Envelope  "Not enough balance"
// @Router       /api/v1/members/{member_id}/wallet/spend [post]
func (h *Handler) Spend(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	var req amountRequest
	if !decode(w, r, &req) {
		return
	}
	res, err := h.svc.Spend(r.Context(), id, req.AmountInPaise, req.Reason)
	if err != nil {
		writeErr(w, err, "wallet spend")
		return
	}
	response.Created(w, res)
}

// Adjust godoc
// @Summary      Correct a wallet balance
// @Description  Signed amount. A reason is mandatory.
// @Tags         wallet
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        member_id  path      int            true  "Member ID"
// @Param        body       body      amountRequest  true  "Signed amount and reason"
// @Success      201        {object}  Transaction
// @Router       /api/v1/members/{member_id}/wallet/adjust [post]
func (h *Handler) Adjust(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	var req amountRequest
	if !decode(w, r, &req) {
		return
	}
	res, err := h.svc.Adjust(r.Context(), id, req.AmountInPaise, req.Reason)
	if err != nil {
		writeErr(w, err, "wallet adjust")
		return
	}
	response.Created(w, res)
}

// ─── helpers ──────────────────────────────────────────────────────────────────

func pathID(w http.ResponseWriter, r *http.Request) (int64, bool) {
	id, err := strconv.ParseInt(r.PathValue("member_id"), 10, 64)
	if err != nil || id <= 0 {
		response.BadRequest(w, "invalid member_id")
		return 0, false
	}
	return id, true
}

func decode(w http.ResponseWriter, r *http.Request, dst any) bool {
	if r.Body == nil || r.ContentLength == 0 {
		return true
	}
	if err := json.NewDecoder(r.Body).Decode(dst); err != nil {
		response.BadRequest(w, "invalid request body")
		return false
	}
	return true
}

func writeErr(w http.ResponseWriter, err error, op string) {
	switch {
	case errors.Is(err, ErrMemberNotFound):
		response.NotFound(w, err.Error())
	case errors.Is(err, ErrInsufficientFunds):
		response.Conflict(w, err.Error())
	case errors.Is(err, ErrAmountZero), errors.Is(err, ErrReasonRequired):
		response.UnprocessableEntity(w, err.Error())
	default:
		stdlog.Printf("wallet %s: %v", op, err)
		response.InternalServerError(w)
	}
}

func optional(s string) *string {
	s = strings.TrimSpace(s)
	if s == "" {
		return nil
	}
	return &s
}
