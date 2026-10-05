package queues

import "errors"

// Invoicing from expected payments (FR-19 §6).
//
// Only *raised* dues can be invoiced. An expiring membership is a plan price
// nobody has agreed to pay, and an invoice is not a guess — it is a numbered
// document that enters the gym's tax records as a supply that happened. Issue
// one for a renewal the member never accepted and the gym has told its
// accountant about revenue it invented, and told the member they owe money
// they never agreed to.
//
// The API cannot express the mistake: expiring rows carry no payment ID, so
// there is nothing to pass. The route for an expiring membership is to record
// that the member agreed — POST /api/v1/payments/due, which raises a real due
// — and invoice that. One extra step, and it is the step where the agreement
// actually happens.
//
// Everything created here is a DRAFT. Issuing assigns a permanent number from
// the financial-year sequence and makes the document immutable, which is a
// decision a person makes about one invoice, not a side effect of a batch.

var (
	ErrNoPayments  = errors.New("queues: no dues selected")
	ErrTooManyDues = errors.New("queues: too many dues in one batch")
)

// MaxInvoiceBatch caps one request.
//
// Not a performance limit — a correctness one. Every invoice in a batch is a
// document somebody is answerable for, and a run that creates three hundred of
// them in one click is one misclick away from a mess that has to be cancelled
// one at a time.
const MaxInvoiceBatch = 50

// InvoiceDuesRequest asks for draft invoices covering the given raised dues.
type InvoiceDuesRequest struct {
	PaymentIDs []int64 `json:"payment_ids"`

	// Optional note copied onto every invoice created by this batch.
	Notes string `json:"notes"`
}

// InvoicedMember is one draft invoice that now exists.
type InvoicedMember struct {
	InvoiceID int64  `json:"invoice_id"`
	MemberID  int64  `json:"member_id"`
	Member    string `json:"member"`

	// The dues folded into this invoice. One invoice per member per batch:
	// three unpaid dues for the same person is one conversation and one
	// document, not three.
	PaymentIDs []int64 `json:"payment_ids"`

	TotalInPaise int64 `json:"total_in_paise"`
}

// SkippedDue explains one due that was asked for and not invoiced.
//
// Reported per row rather than failing the batch. A single already-invoiced
// due should not cost the other forty-nine, and silently dropping it would
// leave the caller believing it was done.
type SkippedDue struct {
	PaymentID int64  `json:"payment_id"`
	Reason    string `json:"reason"`
}

// Skip reasons.
const (
	SkipAlreadyInvoiced = "already on an invoice"
	SkipNotOutstanding  = "settled or written off"
	SkipNotFound        = "no such due at this gym"
)

// InvoiceDuesResult is what the batch did.
type InvoiceDuesResult struct {
	Created []InvoicedMember `json:"created"`
	Skipped []SkippedDue     `json:"skipped"`

	InvoiceCount int   `json:"invoice_count"`
	TotalInPaise int64 `json:"total_in_paise"`
}
