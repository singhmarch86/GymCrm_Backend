package invoicing

import "errors"

// Not-found errors → 404.
var (
	ErrInvoiceNotFound  = errors.New("invoice not found")
	ErrItemNotFound     = errors.New("invoice line not found")
	ErrDiscountNotFound = errors.New("discount not found")
	ErrMemberNotFound   = errors.New("member not found")
)

// State-conflict errors → 409. These are the guards that actually block an
// action, as opposed to input validation.
var (
	// The core immutability rule — FR-04 §2.1.
	ErrInvoiceNotDraft   = errors.New("only a draft invoice can be changed; issued invoices are immutable")
	ErrInvoiceNotIssued  = errors.New("only an issued invoice can be cancelled")
	ErrInvoiceCancelled  = errors.New("this invoice is cancelled")
	ErrInvoiceHasNoItems = errors.New("cannot issue an invoice with no line items")
	ErrDiscountInactive  = errors.New("this discount is not active")
	ErrDiscountExpired   = errors.New("this discount is outside its valid dates")
	ErrDiscountExhausted = errors.New("this discount has reached its maximum number of uses")
	ErrDiscountCodeTaken = errors.New("a discount with this code already exists")
)

// Validation errors → 422.
var (
	ErrDescriptionRequired = errors.New("description is required")
	ErrQuantityInvalid     = errors.New("quantity must be greater than 0")
	ErrUnitPriceNegative   = errors.New("unit price cannot be negative")
	ErrDiscountNegative    = errors.New("discount cannot be negative")
	ErrCancelReasonMissing = errors.New("a reason is required to cancel an invoice")
	ErrDiscountCodeMissing = errors.New("discount code is required")
	ErrDiscountNameMissing = errors.New("discount name is required")
	ErrDiscountValueRange  = errors.New("discount value is out of range")
)
