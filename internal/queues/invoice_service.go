package queues

import (
	"context"
	"fmt"

	"gymcrm/internal/invoicing"
)

// InvoiceDues creates one draft invoice per member covering their selected
// raised dues.
//
// Draft, never issued. Issuing burns a number from the financial-year sequence
// and freezes the document; that belongs to a person looking at one invoice,
// not to a batch that just touched fifty.
func (s *Service) InvoiceDues(
	ctx context.Context, req InvoiceDuesRequest,
) (*InvoiceDuesResult, error) {
	ids := dedupe(req.PaymentIDs)
	if len(ids) == 0 {
		return nil, ErrNoPayments
	}
	if len(ids) > MaxInvoiceBatch {
		return nil, ErrTooManyDues
	}
	if s.invoicing == nil {
		return nil, fmt.Errorf("queues: invoicing service not wired")
	}

	dues, err := s.repo.InvoiceableDues(ctx, ids)
	if err != nil {
		return nil, fmt.Errorf("invoice dues: load: %w", err)
	}

	out := &InvoiceDuesResult{
		Created: []InvoicedMember{},
		Skipped: []SkippedDue{},
	}

	// Explain every id that will not be invoiced, before creating anything.
	usable := make(map[int64]bool, len(dues))
	for _, d := range dues {
		usable[d.PaymentID] = true
	}
	if len(usable) != len(ids) {
		states, err := s.repo.DueStates(ctx, ids)
		if err != nil {
			return nil, fmt.Errorf("invoice dues: states: %w", err)
		}
		for _, id := range ids {
			if usable[id] {
				continue
			}
			out.Skipped = append(out.Skipped, SkippedDue{
				PaymentID: id,
				Reason:    skipReason(states[id]),
			})
		}
	}
	if len(dues) == 0 {
		return out, nil
	}

	// One invoice per member. Three unpaid dues for the same person is one
	// conversation and one document.
	for _, group := range groupByMember(dues) {
		items := make([]invoicing.AddItemRequest, 0, len(group.dues))
		for _, d := range group.dues {
			items = append(items, invoicing.AddItemRequest{
				Description:      dueDescription(d),
				ItemType:         itemTypeFor(d),
				ReferenceID:      d.PlanID,
				Quantity:         1,
				UnitPriceInPaise: d.AmountInPaise,
			})
		}

		inv, err := s.invoicing.CreateInvoice(ctx, invoicing.CreateInvoiceRequest{
			MemberID: group.memberID,
			// The invoice inherits the earliest due date it covers. Inventing
			// "today + 7" would move a deadline the member was already given.
			DueDate: earliestDue(group.dues),
			Notes:   req.Notes,
			Items:   items,
		})
		if err != nil {
			return nil, fmt.Errorf("invoice dues: member %d: %w",
				group.memberID, err)
		}

		paymentIDs := make([]int64, 0, len(group.dues))
		for _, d := range group.dues {
			paymentIDs = append(paymentIDs, d.PaymentID)
		}

		linked, err := s.repo.LinkDuesToInvoice(ctx, inv.ID, paymentIDs)
		if err != nil {
			return nil, fmt.Errorf("invoice dues: link %d: %w", inv.ID, err)
		}
		// Somebody else invoiced one of these between the read and the write.
		// Said out loud rather than swallowed: the invoice exists and is a
		// draft, so a human can delete it, and a silent duplicate would be
		// found much later by whoever reconciles the month.
		if linked != int64(len(paymentIDs)) {
			out.Skipped = append(out.Skipped, SkippedDue{
				PaymentID: paymentIDs[0],
				Reason: fmt.Sprintf(
					"invoice %d covers %d of %d dues — another user invoiced "+
						"the rest first; check it before issuing",
					inv.ID, linked, len(paymentIDs)),
			})
		}

		out.Created = append(out.Created, InvoicedMember{
			InvoiceID:    inv.ID,
			MemberID:     group.memberID,
			Member:       group.member,
			PaymentIDs:   paymentIDs,
			TotalInPaise: inv.TotalInPaise,
		})
		out.TotalInPaise += inv.TotalInPaise
	}

	out.InvoiceCount = len(out.Created)
	return out, nil
}

type memberGroup struct {
	memberID int64
	member   string
	dues     []invoiceableDue
}

// groupByMember keeps the repository's ordering, which is already by member
// then by date, so the caller gets a stable result rather than map order.
func groupByMember(dues []invoiceableDue) []memberGroup {
	var out []memberGroup
	index := make(map[int64]int, len(dues))

	for _, d := range dues {
		at, ok := index[d.MemberID]
		if !ok {
			index[d.MemberID] = len(out)
			out = append(out, memberGroup{
				memberID: d.MemberID,
				member:   d.Member,
				dues:     []invoiceableDue{d},
			})
			continue
		}
		out[at].dues = append(out[at].dues, d)
	}
	return out
}

// dueDescription writes the line a member will read on the document.
//
// The due's own note wins when there is one: somebody typed "PT package
// balance" for a reason, and replacing it with "Membership due" on the
// document they receive would lose the only explanation the row ever had.
func dueDescription(d invoiceableDue) string {
	if d.Notes != nil && *d.Notes != "" {
		return truncate(*d.Notes, 300)
	}
	if d.PlanName != nil && *d.PlanName != "" {
		return *d.PlanName
	}
	if d.DueDate != nil {
		return "Amount due " + d.DueDate.Format("2 Jan 2006")
	}
	return "Outstanding due"
}

func itemTypeFor(d invoiceableDue) string {
	if d.PlanID != nil {
		return "plan"
	}
	return "custom"
}

func earliestDue(dues []invoiceableDue) string {
	var earliest string
	for _, d := range dues {
		if d.DueDate == nil {
			continue
		}
		s := d.DueDate.Format("2006-01-02")
		if earliest == "" || s < earliest {
			earliest = s
		}
	}
	return earliest
}

func skipReason(st dueState) string {
	switch {
	case st.PaymentID == 0:
		return SkipNotFound
	case st.InvoiceID != nil:
		return SkipAlreadyInvoiced
	case st.Status != "pending" && st.Status != "overdue":
		return SkipNotOutstanding
	}
	return SkipNotFound
}

func dedupe(ids []int64) []int64 {
	seen := make(map[int64]bool, len(ids))
	out := make([]int64, 0, len(ids))
	for _, id := range ids {
		if id <= 0 || seen[id] {
			continue
		}
		seen[id] = true
		out = append(out, id)
	}
	return out
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n]
}
