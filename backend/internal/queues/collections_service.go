package queues

import (
	"context"
	"errors"
	"strings"
	"time"

	"gymcrm/internal/database"
)

var (
	ErrNotOutstanding = errors.New("queues: payment is not outstanding")
	ErrReasonRequired = errors.New("queues: a write-off needs a reason")
	ErrOwnerOnly      = errors.New("queues: only an owner may write off a due")
	ErrPastPromise    = errors.New("queues: a promised date cannot be in the past")
	ErrNotFound       = errors.New("queues: payment not found")
	ErrBadMode        = errors.New("queues: unknown payment mode")
	ErrBadAmount      = errors.New("queues: amount must be more than zero")
	ErrMemberNotFound = errors.New("queues: member not found")
)

// Collections builds the queue (FR-19 §3).
//
// Visibility is deliberately not narrowed by user. Unlike staff work, this is
// not a record of who did what — it is a worklist, and a receptionist working
// the desk needs the whole list to be useful (FR-19 §7.3). Nothing here is
// attributed to a staff member in a way that could be totalled.
// The window filters by DUE DATE, and is off by default.
//
// That default is deliberate. Filtering a worklist by date is not the same as
// filtering a report: the oldest debt is the worst debt, and a month filter
// silently drops it. Live, a filter to August would show 15 dues worth
// Rs 58,500 and hide 27 older ones worth Rs 1,45,000. So the queue opens on
// everything, and whenever a window is set the screen is told what it hides.
func (s *Service) Collections(
	ctx context.Context, from, to string,
) (*CollectionQueue, error) {
	rows, err := s.repo.Collections(ctx, from, to)
	if err != nil {
		return nil, err
	}

	unchased := CollectionGroup{
		Key:      GroupUnchased,
		Label:    "Nobody has chased these",
		Note:     "Overdue, and no contact has been recorded. These are the dues that go quiet — the money nobody has mentioned to anybody.",
		Severity: "urgent",
		Items:    []CollectionItem{},
	}
	chased := CollectionGroup{
		Key:      GroupChased,
		Label:    "Chased, still unpaid",
		Note:     "Somebody made contact and the money has not arrived. Worth a different approach rather than the same call again.",
		Severity: "warn",
		Items:    []CollectionItem{},
	}
	promised := CollectionGroup{
		Key:      GroupPromised,
		Label:    "Promised to pay",
		Note:     "The member agreed a date. Soonest first — chasing before the date they gave is how a gym loses goodwill it did not need to.",
		Severity: "normal",
		Items:    []CollectionItem{},
	}
	upcoming := CollectionGroup{
		Key:      GroupUpcoming,
		Label:    "Due later",
		Note:     "Not yet due. Here so the desk can see what is coming, not so anybody chases it early.",
		Severity: "normal",
		Items:    []CollectionItem{},
	}

	today := time.Now().In(IST)
	todayOnly := time.Date(today.Year(), today.Month(), today.Day(), 0, 0, 0, 0, IST)

	members := map[int64]bool{}

	queue := &CollectionQueue{From: from, To: to}

	if from != "" && to != "" {
		n, amount, err := s.repo.OutsideWindow(ctx, from, to)
		if err != nil {
			return nil, err
		}
		queue.OutsideCount = n
		queue.OutsideInPaise = amount
	}

	for _, r := range rows {
		item := CollectionItem{
			PaymentID:          r.PaymentID,
			MemberID:           r.MemberID,
			Member:             r.Member,
			Phone:              r.Phone,
			AmountInPaise:      r.AmountInPaise,
			DueDate:            r.DueDate,
			MemberTotalInPaise: r.MemberTotalInPaise,
			MemberInactive:     r.MemberInactive,
			LastContactAt:      r.LastContactAt,
			LastContactBy:      r.LastContactBy,
			LastContactNote:    r.LastContactNote,
			LastReached:        r.LastReached,
		}

		if r.DueDate != nil {
			d := time.Date(r.DueDate.Year(), r.DueDate.Month(), r.DueDate.Day(),
				0, 0, 0, 0, IST)
			days := int(todayOnly.Sub(d).Hours() / 24)
			item.DaysOverdue = &days
		}

		members[r.MemberID] = true
		queue.TotalCount++
		queue.TotalInPaise += r.AmountInPaise

		// A promise is only live while it is the newest thing on the due and
		// has not passed. Once the date goes by without payment the promise
		// was not kept, and the due drops back to "chased, still unpaid" —
		// leaving it under Promised would quietly hide a broken commitment.
		if r.LastActivityType != nil && *r.LastActivityType == ActivityPromise &&
			r.PromisedOn != nil {
			p := time.Date(r.PromisedOn.Year(), r.PromisedOn.Month(),
				r.PromisedOn.Day(), 0, 0, 0, 0, IST)
			if !p.Before(todayOnly) {
				item.PromisedOn = r.PromisedOn
				promised.Items = append(promised.Items, item)
				promised.TotalInPaise += r.AmountInPaise
				continue
			}
		}

		// Not yet due. Checked before the chase groups: chasing something that
		// is not due is not diligence, and calling it unchased would be wrong.
		if item.DaysOverdue != nil && *item.DaysOverdue < 0 {
			upcoming.Items = append(upcoming.Items, item)
			upcoming.TotalInPaise += r.AmountInPaise
			continue
		}

		if r.LastContactAt == nil {
			unchased.Items = append(unchased.Items, item)
			unchased.TotalInPaise += r.AmountInPaise
			queue.UnchasedCount++
			continue
		}

		chased.Items = append(chased.Items, item)
		chased.TotalInPaise += r.AmountInPaise
	}

	queue.MembersInvolved = len(members)
	queue.Groups = []CollectionGroup{unchased, chased, promised, upcoming}
	return queue, nil
}

// RecordContact logs an attempt to collect.
//
// Records the attempt whether or not the member was reached. A call that rang
// out is work done and moves the due out of "nobody has chased these", which
// is honest — somebody did try. Conflating it with actual contact would be the
// dishonest part, which is why `reached` is a separate field.
func (s *Service) RecordContact(
	ctx context.Context, paymentID int64, channel string, reached bool, note string,
) error {
	ok, err := s.repo.PaymentBelongsToGym(ctx, paymentID)
	if err != nil {
		return err
	}
	if !ok {
		return ErrNotFound
	}

	a := &PaymentActivity{
		PaymentID: paymentID,
		Type:      ActivityContact,
		Channel:   &channel,
		Reached:   &reached,
	}
	if n := strings.TrimSpace(note); n != "" {
		a.Note = &n
	}
	return s.repo.AddActivity(ctx, a)
}

// RecordPromise stores a date the member agreed to pay by.
func (s *Service) RecordPromise(
	ctx context.Context, paymentID int64, on time.Time, note string,
) error {
	ok, err := s.repo.PaymentBelongsToGym(ctx, paymentID)
	if err != nil {
		return err
	}
	if !ok {
		return ErrNotFound
	}

	// A promise in the past is either a typo or a promise already broken.
	// Neither should be recordable as a live commitment.
	today := time.Now().In(IST)
	todayOnly := time.Date(today.Year(), today.Month(), today.Day(), 0, 0, 0, 0, IST)
	p := time.Date(on.Year(), on.Month(), on.Day(), 0, 0, 0, 0, IST)
	if p.Before(todayOnly) {
		return ErrPastPromise
	}

	a := &PaymentActivity{
		PaymentID:  paymentID,
		Type:       ActivityPromise,
		PromisedOn: &p,
	}
	if n := strings.TrimSpace(note); n != "" {
		a.Note = &n
	}
	return s.repo.AddActivity(ctx, a)
}

// ValidPaymentModes mirrors the database constraint. Duplicated deliberately:
// a bad mode should come back as a readable message, not a constraint
// violation the caller cannot act on.
var ValidPaymentModes = map[string]bool{
	"cash": true, "upi": true, "credit_card": true,
	"debit_card": true, "bank_transfer": true,
}

// Settle takes the money for a due that already exists.
//
// Any signed-in staff member may collect — that is the desk's job. Only
// write-off is restricted.
func (s *Service) Settle(
	ctx context.Context, paymentID int64, mode, reference string,
) error {
	if !ValidPaymentModes[mode] {
		return ErrBadMode
	}

	ok, err := s.repo.PaymentBelongsToGym(ctx, paymentID)
	if err != nil {
		return err
	}
	if !ok {
		return ErrNotFound
	}

	return s.repo.Settle(ctx, paymentID, mode, strings.TrimSpace(reference))
}

// WriteOff gives up on a due.
//
// Owner only, and a reason is required. This is the one irreversible action in
// the queue — the money stops being receivable — and an unexplained write-off
// is indistinguishable from money going missing.
func (s *Service) WriteOff(ctx context.Context, paymentID int64, reason string) error {
	tc := database.MustGetTenant(ctx)
	if !tc.IsOwner() {
		return ErrOwnerOnly
	}

	r := strings.TrimSpace(reason)
	if r == "" {
		return ErrReasonRequired
	}

	ok, err := s.repo.PaymentBelongsToGym(ctx, paymentID)
	if err != nil {
		return err
	}
	if !ok {
		return ErrNotFound
	}

	return s.repo.WriteOff(ctx, paymentID, r)
}

// RaiseDue records that a member owes money.
//
// The gap this fills: CollectPayment only ever writes a paid row, so before
// this there was no way to enter "they owe us" at all. The collections queue
// could only show dues some other process happened to create — and a gym that
// cannot raise a due cannot chase it.
//
// A due date is required, not defaulted to today. Every group in the queue is
// computed from it, and a due with no date sorts last and reads as a data
// problem — inventing one to avoid asking would bury that.
func (s *Service) RaiseDue(
	ctx context.Context, memberID int64, planID *int64,
	amountInPaise int64, due time.Time, notes string,
) (int64, error) {
	if amountInPaise <= 0 {
		return 0, ErrBadAmount
	}

	ok, err := s.repo.MemberBelongsToGym(ctx, memberID)
	if err != nil {
		return 0, err
	}
	if !ok {
		return 0, ErrMemberNotFound
	}

	// Backdating is allowed on purpose. The common case for raising a due by
	// hand is catching up on something that was already owed last month, and
	// refusing it would push the desk to enter a date they do not mean.
	return s.repo.RaiseDue(ctx, memberID, planID, amountInPaise, due,
		strings.TrimSpace(notes))
}
