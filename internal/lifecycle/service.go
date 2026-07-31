package lifecycle

import (
	"context"
	"fmt"
	"time"

	"gymcrm/internal/database"
)

// Service holds all membership lifecycle business logic.
// Rules are specified in docs/FR-01-membership-lifecycle.md; this file is the
// implementation of that document and the two should be changed together.
//
// Invariant: every operation writes exactly one immutable membership_events row
// (transfer writes two) and mutates the member inside the same DB transaction.
//
// Invariant: no operation ever moves money. Amounts owed or owed-back are
// recorded on the event; collection and refund go through the payments module.
// See FR-01 §5.
type Service struct {
	repo *Repository
}

func NewService(repo *Repository) *Service { return &Service{repo: repo} }

// ─── Freeze ───────────────────────────────────────────────────────────────────

// Freeze pauses a membership, extending expiry 1:1 with the frozen duration.
//
// The annual allowance is debited by the FULL requested duration here, and
// credited back on early unfreeze. Doing it this way — rather than debiting on
// unfreeze — keeps the allowance correct even if nothing ever unfreezes the
// member, because auto-thaw is a lazy read-time concept with no job behind it.
// The end state matches FR-01 §1 either way: actual days used are what count.
func (s *Service) Freeze(ctx context.Context, memberID int64, req FreezeRequest) (*MemberLifecycleResponse, error) {
	tc := database.MustGetTenant(ctx)

	start, end, err := validateFreeze(req)
	if err != nil {
		return nil, err
	}

	m, err := s.repo.FindMember(ctx, memberID)
	if err != nil {
		return nil, fmt.Errorf("freeze: find member: %w", err)
	}
	if m == nil {
		return nil, ErrMemberNotFound
	}

	if err := s.assertFreezable(*m); err != nil {
		return nil, err
	}

	days := daysBetween(start, end)
	yearStart, used := s.currentFreezeAllowance(*m)
	if used+days > MaxFreezeDaysPerYear {
		return nil, ErrFreezeAllowanceHit
	}

	// Expiry extends 1:1 — the core promise of a freeze.
	var newExpiry *time.Time
	if m.ExpiryDate != nil {
		e := m.ExpiryDate.AddDate(0, 0, days)
		newExpiry = &e
	}

	ev := &MembershipEvent{
		GymID:             tc.GymID(),
		MemberID:          m.ID,
		EventType:         EventFreeze,
		EffectiveDate:     start,
		OldExpiryDate:     m.ExpiryDate,
		NewExpiryDate:     newExpiry,
		OldStatus:         ptr(m.Status),
		NewStatus:         ptr(StatusFrozen),
		FreezeStart:       &start,
		FreezeEnd:         &end,
		FreezeDays:        &days,
		FeeInPaise:        req.FeeInPaise,
		AmountDueInPaise:  req.FeeInPaise, // a freeze fee is money owed
		PerformedByUserID: tc.UserID(),
		Reason:            optionalText(req.Reason),
		Notes:             optionalText(req.Notes),
	}

	mut := memberMutation{
		"status":               StatusFrozen,
		"frozen_from":          start,
		"frozen_until":         end,
		"freeze_year_start":    yearStart,
		"freeze_days_used_ytd": used + days,
	}
	if newExpiry != nil {
		mut["expiry_date"] = *newExpiry
	}

	if err := s.repo.ApplyEvent(ctx, ev, m.ID, mut); err != nil {
		return nil, fmt.Errorf("freeze: apply: %w", err)
	}
	return s.reload(ctx, m.ID, ev)
}

// Unfreeze ends a freeze, possibly early.
//
// Ending early gives back the unused days: expiry is pulled back and the annual
// allowance is credited, so a member who freezes 60 days and returns after 20
// has used 20 — not 60.
func (s *Service) Unfreeze(ctx context.Context, memberID int64, req UnfreezeRequest) (*MemberLifecycleResponse, error) {
	tc := database.MustGetTenant(ctx)

	effective, err := validateUnfreeze(req)
	if err != nil {
		return nil, err
	}

	m, err := s.repo.FindMember(ctx, memberID)
	if err != nil {
		return nil, fmt.Errorf("unfreeze: find member: %w", err)
	}
	if m == nil {
		return nil, ErrMemberNotFound
	}
	if m.Status != StatusFrozen || m.FrozenFrom == nil || m.FrozenUntil == nil {
		return nil, ErrNotFrozen
	}

	requested := daysBetween(*m.FrozenFrom, *m.FrozenUntil)
	actual := daysBetween(*m.FrozenFrom, effective)
	if actual < 0 {
		actual = 0
	}
	if actual > requested {
		actual = requested // unfreezing after the window is just a normal thaw
	}
	unused := requested - actual

	// Pull expiry back by the days not used.
	var newExpiry *time.Time
	if m.ExpiryDate != nil {
		e := m.ExpiryDate.AddDate(0, 0, -unused)
		newExpiry = &e
	}

	used := m.FreezeDaysUsedYTD - unused
	if used < 0 {
		used = 0
	}

	ev := &MembershipEvent{
		GymID:             tc.GymID(),
		MemberID:          m.ID,
		EventType:         EventUnfreeze,
		EffectiveDate:     effective,
		OldExpiryDate:     m.ExpiryDate,
		NewExpiryDate:     newExpiry,
		OldStatus:         ptr(StatusFrozen),
		NewStatus:         ptr(StatusActive),
		FreezeStart:       m.FrozenFrom,
		FreezeEnd:         &effective,
		FreezeDays:        &actual,
		PerformedByUserID: tc.UserID(),
		Notes:             optionalText(req.Notes),
	}

	mut := memberMutation{
		"status":               StatusActive,
		"frozen_from":          nil,
		"frozen_until":         nil,
		"freeze_days_used_ytd": used,
	}
	if newExpiry != nil {
		mut["expiry_date"] = *newExpiry
	}

	if err := s.repo.ApplyEvent(ctx, ev, m.ID, mut); err != nil {
		return nil, fmt.Errorf("unfreeze: apply: %w", err)
	}
	return s.reload(ctx, m.ID, ev)
}

// FreezeEligibility answers "can this member be frozen, and for how long?"
// so the UI can show the bounds up front instead of rejecting a filled-in form.
func (s *Service) FreezeEligibility(ctx context.Context, memberID int64) (*FreezeEligibilityResponse, error) {
	m, err := s.repo.FindMember(ctx, memberID)
	if err != nil {
		return nil, fmt.Errorf("freeze eligibility: %w", err)
	}
	if m == nil {
		return nil, ErrMemberNotFound
	}

	_, used := s.currentFreezeAllowance(*m)
	left := MaxFreezeDaysPerYear - used
	if left < 0 {
		left = 0
	}

	resp := &FreezeEligibilityResponse{
		MinDays:           MinFreezeDays,
		FreezeDaysUsedYTD: used,
		FreezeDaysLeftYTD: left,
		CurrentlyFrozen:   m.isEffectivelyFrozen(today()),
	}

	maxDays := MaxFreezeDaysPerFreeze
	if left < maxDays {
		maxDays = left
	}
	resp.MaxDays = maxDays

	if err := s.assertFreezable(*m); err != nil {
		resp.Eligible = false
		resp.Reason = err.Error()
		return resp, nil
	}
	if left < MinFreezeDays {
		resp.Eligible = false
		resp.Reason = ErrFreezeAllowanceHit.Error()
		return resp, nil
	}

	resp.Eligible = true
	return resp, nil
}

// ─── Upgrade ──────────────────────────────────────────────────────────────────

// Upgrade moves a member to a different plan, keeping their existing expiry and
// charging (or crediting) the prorated difference for the days remaining.
func (s *Service) Upgrade(ctx context.Context, memberID int64, req UpgradeRequest) (*MemberLifecycleResponse, error) {
	tc := database.MustGetTenant(ctx)

	effective, err := validateUpgrade(req)
	if err != nil {
		return nil, err
	}

	m, plan, quote, err := s.buildUpgradeQuote(ctx, memberID, req.NewPlanID, effective)
	if err != nil {
		return nil, err
	}

	ev := &MembershipEvent{
		GymID:               tc.GymID(),
		MemberID:            m.ID,
		EventType:           EventUpgrade,
		EffectiveDate:       effective,
		OldPlanID:           m.MembershipPlanID,
		NewPlanID:           &plan.ID,
		OldExpiryDate:       m.ExpiryDate,
		NewExpiryDate:       m.ExpiryDate, // expiry deliberately unchanged — FR-01 §2
		OldStatus:           ptr(m.Status),
		NewStatus:           ptr(m.Status),
		AmountDueInPaise:    quote.AmountDueInPaise,
		AmountCreditInPaise: quote.AmountCreditInPaise,
		PerformedByUserID:   tc.UserID(),
		Reason:              optionalText(req.Reason),
		Notes:               optionalText(req.Notes),
	}

	mut := memberMutation{"membership_plan_id": plan.ID}

	if err := s.repo.ApplyEvent(ctx, ev, m.ID, mut); err != nil {
		return nil, fmt.Errorf("upgrade: apply: %w", err)
	}
	return s.reload(ctx, m.ID, ev)
}

// UpgradeQuote previews the proration without committing it.
func (s *Service) UpgradeQuote(ctx context.Context, memberID, newPlanID int64) (*UpgradeQuoteResponse, error) {
	_, _, quote, err := s.buildUpgradeQuote(ctx, memberID, newPlanID, today())
	return quote, err
}

// buildUpgradeQuote is the shared proration maths behind both Upgrade and
// UpgradeQuote, so a preview can never disagree with what is actually charged.
func (s *Service) buildUpgradeQuote(
	ctx context.Context, memberID, newPlanID int64, effective time.Time,
) (*memberSnapshot, *planSnapshot, *UpgradeQuoteResponse, error) {

	m, err := s.repo.FindMember(ctx, memberID)
	if err != nil {
		return nil, nil, nil, fmt.Errorf("upgrade quote: find member: %w", err)
	}
	if m == nil {
		return nil, nil, nil, ErrMemberNotFound
	}
	if m.Status == StatusTerminated {
		return nil, nil, nil, ErrAlreadyTerminated
	}
	if m.isEffectivelyFrozen(today()) {
		return nil, nil, nil, ErrUpgradeWhileFrozen
	}
	if m.MembershipPlanID != nil && *m.MembershipPlanID == newPlanID {
		return nil, nil, nil, ErrSamePlan
	}

	newPlan, err := s.repo.FindPlan(ctx, newPlanID)
	if err != nil {
		return nil, nil, nil, fmt.Errorf("upgrade quote: find plan: %w", err)
	}
	if newPlan == nil {
		return nil, nil, nil, ErrPlanNotFound
	}
	if !newPlan.IsActive {
		return nil, nil, nil, ErrPlanInactive
	}

	// Old plan may be absent (member never had one) — its daily rate is then 0,
	// which correctly makes the whole remaining term chargeable at the new rate.
	var oldDaily int64
	var oldPlanName *string
	if m.MembershipPlanID != nil {
		if op, err := s.repo.FindPlan(ctx, *m.MembershipPlanID); err == nil && op != nil {
			oldDaily = op.dailyRatePaise()
			oldPlanName = &op.Name
		}
	}

	remaining := m.remainingDays(effective)
	newDaily := newPlan.dailyRatePaise()
	delta := (newDaily - oldDaily) * int64(remaining)

	q := &UpgradeQuoteResponse{
		MemberID:          m.ID,
		CurrentPlanID:     m.MembershipPlanID,
		CurrentPlanName:   oldPlanName,
		NewPlanID:         newPlan.ID,
		NewPlanName:       newPlan.Name,
		RemainingDays:     remaining,
		OldDailyRatePaise: oldDaily,
		NewDailyRatePaise: newDaily,
	}
	if delta >= 0 {
		q.AmountDueInPaise = delta
		q.AmountDueInRupees = paiseToRupees(delta)
	} else {
		// Downgrade: recorded as credit, not refunded. FR-01 §2.
		q.IsDowngrade = true
		q.AmountCreditInPaise = -delta
		q.AmountCreditInRupees = paiseToRupees(-delta)
	}
	return m, newPlan, q, nil
}

// ─── Transfer ─────────────────────────────────────────────────────────────────

// Transfer moves remaining validity from one member to another, terminating the
// source. Writes paired transfer_out / transfer_in events so a resold
// membership can always be traced.
func (s *Service) Transfer(ctx context.Context, fromMemberID int64, req TransferRequest) (*MemberLifecycleResponse, error) {
	tc := database.MustGetTenant(ctx)

	effective, err := validateTransfer(req)
	if err != nil {
		return nil, err
	}
	if fromMemberID == req.ToMemberID {
		return nil, ErrTransferToSelf
	}

	src, err := s.repo.FindMember(ctx, fromMemberID)
	if err != nil {
		return nil, fmt.Errorf("transfer: find source: %w", err)
	}
	if src == nil {
		return nil, ErrMemberNotFound
	}
	dst, err := s.repo.FindMember(ctx, req.ToMemberID)
	if err != nil {
		return nil, fmt.Errorf("transfer: find target: %w", err)
	}
	if dst == nil {
		return nil, ErrMemberNotFound
	}

	// ScopedDB already constrains both lookups to the caller's gym, so this can
	// only trip if the data itself is inconsistent — but a cross-gym transfer
	// would be severe enough to be worth an explicit guard.
	if src.GymID != dst.GymID {
		return nil, ErrCrossGymTransfer
	}
	if src.Status == StatusTerminated {
		return nil, ErrAlreadyTerminated
	}
	if src.remainingDays(effective) <= 0 {
		return nil, ErrNothingToTransfer
	}
	// Merging two live memberships is ambiguous — reject rather than guess.
	if dst.Status == StatusActive && dst.remainingDays(effective) > 0 {
		return nil, ErrTargetHasActive
	}

	outEv := &MembershipEvent{
		GymID:             tc.GymID(),
		MemberID:          src.ID,
		EventType:         EventTransferOut,
		EffectiveDate:     effective,
		OldPlanID:         src.MembershipPlanID,
		OldExpiryDate:     src.ExpiryDate,
		NewExpiryDate:     &effective,
		OldStatus:         ptr(src.Status),
		NewStatus:         ptr(StatusTerminated),
		FeeInPaise:        req.FeeInPaise,
		AmountDueInPaise:  req.FeeInPaise,
		RelatedMemberID:   &dst.ID,
		Reason:            optionalText(orDefault(req.Reason, "transferred")),
		Notes:             optionalText(req.Notes),
		PerformedByUserID: tc.UserID(),
	}

	inEv := &MembershipEvent{
		GymID:             tc.GymID(),
		MemberID:          dst.ID,
		EventType:         EventTransferIn,
		EffectiveDate:     effective,
		OldPlanID:         dst.MembershipPlanID,
		NewPlanID:         src.MembershipPlanID,
		OldExpiryDate:     dst.ExpiryDate,
		NewExpiryDate:     src.ExpiryDate,
		OldStatus:         ptr(dst.Status),
		NewStatus:         ptr(StatusActive),
		RelatedMemberID:   &src.ID,
		Reason:            optionalText(orDefault(req.Reason, "transferred")),
		Notes:             optionalText(req.Notes),
		PerformedByUserID: tc.UserID(),
	}

	srcMut := memberMutation{
		"status":             StatusTerminated,
		"expiry_date":        effective,
		"terminated_at":      effective,
		"termination_reason": orDefault(req.Reason, "transferred"),
	}
	dstMut := memberMutation{
		"status":             StatusActive,
		"membership_plan_id": src.MembershipPlanID,
		"start_date":         effective,
		"expiry_date":        src.ExpiryDate,
	}

	if err := s.repo.ApplyTransfer(ctx, outEv, inEv, src.ID, srcMut, dst.ID, dstMut); err != nil {
		return nil, fmt.Errorf("transfer: apply: %w", err)
	}
	return s.reload(ctx, dst.ID, inEv)
}

// ─── Terminate ────────────────────────────────────────────────────────────────

// Terminate ends a membership permanently. Terminal — see FR-01 §4.
func (s *Service) Terminate(ctx context.Context, memberID int64, req TerminateRequest) (*MemberLifecycleResponse, error) {
	tc := database.MustGetTenant(ctx)

	effective, err := validateTerminate(req)
	if err != nil {
		return nil, err
	}

	m, quote, err := s.buildTerminationQuote(ctx, memberID, effective, req.TerminationFeePaise)
	if err != nil {
		return nil, err
	}

	ev := &MembershipEvent{
		GymID:               tc.GymID(),
		MemberID:            m.ID,
		EventType:           EventTerminate,
		EffectiveDate:       effective,
		OldPlanID:           m.MembershipPlanID,
		OldExpiryDate:       m.ExpiryDate,
		NewExpiryDate:       &effective,
		OldStatus:           ptr(m.Status),
		NewStatus:           ptr(StatusTerminated),
		FeeInPaise:          req.TerminationFeePaise,
		AmountCreditInPaise: quote.NetRefundPaise,
		RelatedMemberID:     nil,
		Reason:              optionalText(req.Reason),
		Notes:               optionalText(req.Notes),
		PerformedByUserID:   tc.UserID(),
	}

	mut := memberMutation{
		"status":             StatusTerminated,
		"expiry_date":        effective,
		"terminated_at":      effective,
		"termination_reason": req.Reason,
		// A terminated membership is not frozen — clear any freeze window so the
		// member can't be picked up by thaw housekeeping later.
		"frozen_from":  nil,
		"frozen_until": nil,
	}

	if err := s.repo.ApplyEvent(ctx, ev, m.ID, mut); err != nil {
		return nil, fmt.Errorf("terminate: apply: %w", err)
	}
	return s.reload(ctx, m.ID, ev)
}

// TerminationQuote previews the refund without committing the termination.
func (s *Service) TerminationQuote(ctx context.Context, memberID int64, feePaise int64) (*TerminationQuoteResponse, error) {
	_, q, err := s.buildTerminationQuote(ctx, memberID, today(), feePaise)
	return q, err
}

func (s *Service) buildTerminationQuote(
	ctx context.Context, memberID int64, effective time.Time, feePaise int64,
) (*memberSnapshot, *TerminationQuoteResponse, error) {

	m, err := s.repo.FindMember(ctx, memberID)
	if err != nil {
		return nil, nil, fmt.Errorf("termination quote: find member: %w", err)
	}
	if m == nil {
		return nil, nil, ErrMemberNotFound
	}
	if m.Status == StatusTerminated {
		return nil, nil, ErrAlreadyTerminated
	}

	// A frozen member's refund is computed from their pre-freeze position:
	// unused frozen days are forfeit on termination. FR-01 §4.
	refundFrom := effective
	if m.isEffectivelyFrozen(today()) && m.FrozenFrom != nil {
		refundFrom = *m.FrozenFrom
	}

	var daily int64
	if m.MembershipPlanID != nil {
		if p, err := s.repo.FindPlan(ctx, *m.MembershipPlanID); err == nil && p != nil {
			daily = p.dailyRatePaise()
		}
	}

	remaining := m.remainingDays(refundFrom)
	gross := daily * int64(remaining)
	net := gross - feePaise
	if net < 0 {
		net = 0
	}

	return m, &TerminationQuoteResponse{
		MemberID:            m.ID,
		RemainingDays:       remaining,
		DailyRatePaise:      daily,
		GrossRefundPaise:    gross,
		TerminationFeePaise: feePaise,
		NetRefundPaise:      net,
		NetRefundInRupees:   paiseToRupees(net),
	}, nil
}

// ─── Timeline ─────────────────────────────────────────────────────────────────

// MemberTimeline returns a member's lifecycle history, newest first.
func (s *Service) MemberTimeline(ctx context.Context, memberID int64) ([]EventResponse, error) {
	m, err := s.repo.FindMember(ctx, memberID)
	if err != nil {
		return nil, fmt.Errorf("timeline: find member: %w", err)
	}
	if m == nil {
		return nil, ErrMemberNotFound
	}

	rows, err := s.repo.ListMemberEvents(ctx, memberID)
	if err != nil {
		return nil, fmt.Errorf("timeline: list events: %w", err)
	}

	out := make([]EventResponse, 0, len(rows))
	for _, row := range rows {
		out = append(out, toEventResponse(row))
	}
	return out, nil
}

// ThawExpired is housekeeping: clears freeze state for members whose window has
// passed. Correctness does not depend on it — see Repository.ThawExpiredFreezes.
func (s *Service) ThawExpired(ctx context.Context) (int64, error) {
	return s.repo.ThawExpiredFreezes(ctx)
}

// ─── Internals ────────────────────────────────────────────────────────────────

// assertFreezable enforces the status preconditions for freezing.
func (s *Service) assertFreezable(m memberSnapshot) error {
	switch {
	case m.Status == StatusTerminated:
		return ErrAlreadyTerminated
	case m.isEffectivelyFrozen(today()):
		return ErrAlreadyFrozen
	case m.Status == StatusExpired:
		return ErrCannotFreezeExpiry
	case m.ExpiryDate == nil || !m.ExpiryDate.After(today()):
		// Nothing left to preserve — freezing this would be a no-op that looks
		// like it did something.
		return ErrCannotFreezeExpiry
	}
	return nil
}

// currentFreezeAllowance returns the start of the member's current membership
// year and how many freeze days they have used within it.
//
// The allowance rolls on the join-date anniversary. When the stored year start
// is missing or stale, usage resets — a member who froze 90 days last year gets
// a fresh 90 this year.
func (s *Service) currentFreezeAllowance(m memberSnapshot) (yearStart time.Time, used int) {
	t := today()

	anniversary := time.Date(t.Year(), m.JoinDate.Month(), m.JoinDate.Day(), 0, 0, 0, 0, time.UTC)
	if anniversary.After(t) {
		anniversary = anniversary.AddDate(-1, 0, 0)
	}

	if m.FreezeYearStart == nil || m.FreezeYearStart.Before(anniversary) {
		return anniversary, 0 // rolled into a new membership year
	}
	return *m.FreezeYearStart, m.FreezeDaysUsedYTD
}

// reload re-reads the member after a mutation and packages it with the event
// that produced it, so the client gets resulting state and history in one call.
func (s *Service) reload(ctx context.Context, memberID int64, ev *MembershipEvent) (*MemberLifecycleResponse, error) {
	m, err := s.repo.FindMember(ctx, memberID)
	if err != nil {
		return nil, fmt.Errorf("reload member: %w", err)
	}
	if m == nil {
		return nil, ErrMemberNotFound
	}

	_, used := s.currentFreezeAllowance(*m)
	left := MaxFreezeDaysPerYear - used
	if left < 0 {
		left = 0
	}

	resp := &MemberLifecycleResponse{
		MemberID:          m.ID,
		MemberName:        m.fullName(),
		Status:            m.Status,
		MembershipPlanID:  m.MembershipPlanID,
		ExpiryDate:        m.ExpiryDate,
		FrozenFrom:        m.FrozenFrom,
		FrozenUntil:       m.FrozenUntil,
		FreezeDaysUsedYTD: used,
		FreezeDaysLeftYTD: left,
	}

	if m.MembershipPlanID != nil {
		if p, err := s.repo.FindPlan(ctx, *m.MembershipPlanID); err == nil && p != nil {
			resp.PlanName = &p.Name
		}
	}

	resp.Event = EventResponse{
		ID:                   ev.ID,
		MemberID:             ev.MemberID,
		MemberName:           m.fullName(),
		EventType:            ev.EventType,
		Label:                eventLabel(*ev, resp.PlanName),
		EffectiveDate:        ev.EffectiveDate,
		OldPlanID:            ev.OldPlanID,
		NewPlanID:            ev.NewPlanID,
		OldExpiryDate:        ev.OldExpiryDate,
		NewExpiryDate:        ev.NewExpiryDate,
		OldStatus:            ev.OldStatus,
		NewStatus:            ev.NewStatus,
		FreezeStart:          ev.FreezeStart,
		FreezeEnd:            ev.FreezeEnd,
		FreezeDays:           ev.FreezeDays,
		AmountDueInPaise:     ev.AmountDueInPaise,
		AmountDueInRupees:    paiseToRupees(ev.AmountDueInPaise),
		AmountCreditInPaise:  ev.AmountCreditInPaise,
		AmountCreditInRupees: paiseToRupees(ev.AmountCreditInPaise),
		FeeInPaise:           ev.FeeInPaise,
		RelatedMemberID:      ev.RelatedMemberID,
		Reason:               ev.Reason,
		Notes:                ev.Notes,
		PerformedByUserID:    ev.PerformedByUserID,
		CreatedAt:            ev.CreatedAt,
	}
	return resp, nil
}

func toEventResponse(row eventRow) EventResponse {
	return EventResponse{
		ID:                   row.ID,
		MemberID:             row.MemberID,
		MemberName:           row.MemberName,
		EventType:            row.EventType,
		Label:                eventLabel(row.MembershipEvent, row.NewPlanName),
		EffectiveDate:        row.EffectiveDate,
		OldPlanID:            row.OldPlanID,
		OldPlanName:          row.OldPlanName,
		NewPlanID:            row.NewPlanID,
		NewPlanName:          row.NewPlanName,
		OldExpiryDate:        row.OldExpiryDate,
		NewExpiryDate:        row.NewExpiryDate,
		OldStatus:            row.OldStatus,
		NewStatus:            row.NewStatus,
		FreezeStart:          row.FreezeStart,
		FreezeEnd:            row.FreezeEnd,
		FreezeDays:           row.FreezeDays,
		AmountDueInPaise:     row.AmountDueInPaise,
		AmountDueInRupees:    paiseToRupees(row.AmountDueInPaise),
		AmountCreditInPaise:  row.AmountCreditInPaise,
		AmountCreditInRupees: paiseToRupees(row.AmountCreditInPaise),
		FeeInPaise:           row.FeeInPaise,
		RelatedMemberID:      row.RelatedMemberID,
		RelatedMemberName:    row.RelatedMemberName,
		Reason:               row.Reason,
		Notes:                row.Notes,
		PerformedByUserID:    row.PerformedByUserID,
		PerformedByUserName:  row.PerformedByUserName,
		CreatedAt:            row.CreatedAt,
	}
}

// eventLabel builds the staff-readable phrase shown on a timeline. Generated
// server-side so every client renders identical wording.
func eventLabel(ev MembershipEvent, planName *string) string {
	switch ev.EventType {
	case EventFreeze:
		if ev.FreezeDays != nil {
			return fmt.Sprintf("Frozen for %d days", *ev.FreezeDays)
		}
		return "Frozen"
	case EventUnfreeze:
		if ev.FreezeDays != nil {
			return fmt.Sprintf("Unfrozen after %d days", *ev.FreezeDays)
		}
		return "Unfrozen"
	case EventUpgrade:
		if planName != nil {
			return "Moved to " + *planName
		}
		return "Plan changed"
	case EventTransferOut:
		return "Membership transferred out"
	case EventTransferIn:
		return "Membership received by transfer"
	case EventTerminate:
		return "Membership terminated"
	default:
		return string(ev.EventType)
	}
}

func optionalText(s string) *string {
	if s == "" {
		return nil
	}
	return &s
}

func orDefault(s, fallback string) string {
	if s == "" {
		return fallback
	}
	return s
}
