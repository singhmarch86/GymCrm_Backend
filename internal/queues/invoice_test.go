package queues

import (
	"testing"
	"time"
)

func due(id, member int64, name string, notes *string) invoiceableDue {
	return invoiceableDue{
		PaymentID: id, MemberID: member, Member: name, Notes: notes,
		AmountInPaise: 100000,
	}
}

// One invoice per member, not one per due. Three unpaid dues for the same
// person is one conversation and one document.
func TestGroupByMemberFoldsDues(t *testing.T) {
	got := groupByMember([]invoiceableDue{
		due(1, 10, "Asha", nil),
		due(2, 10, "Asha", nil),
		due(3, 20, "Bala", nil),
	})

	if len(got) != 2 {
		t.Fatalf("want 2 member groups, got %d", len(got))
	}
	if len(got[0].dues) != 2 || got[0].memberID != 10 {
		t.Errorf("Asha's two dues should be one group: %+v", got[0])
	}
	if len(got[1].dues) != 1 || got[1].memberID != 20 {
		t.Errorf("Bala should be his own group: %+v", got[1])
	}
}

// Repository order is member-then-date; the grouping must not reshuffle it
// into map order, or the same request returns a different-looking result each
// time it runs.
func TestGroupByMemberKeepsOrder(t *testing.T) {
	got := groupByMember([]invoiceableDue{
		due(1, 30, "Chandra", nil),
		due(2, 10, "Asha", nil),
		due(3, 30, "Chandra", nil),
	})

	if got[0].memberID != 30 || got[1].memberID != 10 {
		t.Fatalf("order not preserved: %d then %d",
			got[0].memberID, got[1].memberID)
	}
}

// The note somebody typed wins. Replacing "PT package balance" with a generic
// line on the document the member receives loses the only explanation the row
// ever had.
func TestDueDescriptionPrefersTheNote(t *testing.T) {
	note := "PT package balance"
	plan := "Gold Annual"
	d := due(1, 10, "Asha", &note)
	d.PlanName = &plan

	if got := dueDescription(d); got != note {
		t.Errorf("want the note %q, got %q", note, got)
	}
}

func TestDueDescriptionFallsBackToPlanThenDate(t *testing.T) {
	plan := "Gold Annual"
	d := due(1, 10, "Asha", nil)
	d.PlanName = &plan
	if got := dueDescription(d); got != plan {
		t.Errorf("want plan name, got %q", got)
	}

	when := time.Date(2026, 8, 3, 0, 0, 0, 0, time.UTC)
	bare := due(2, 10, "Asha", nil)
	bare.DueDate = &when
	if got := dueDescription(bare); got != "Amount due 3 Aug 2026" {
		t.Errorf("want a dated line, got %q", got)
	}

	if got := dueDescription(due(3, 10, "Asha", nil)); got != "Outstanding due" {
		t.Errorf("want the last-resort line, got %q", got)
	}
}

// The invoice inherits the earliest date it covers rather than inventing one.
// Making up "today + 7" would move a deadline the member was already given.
func TestEarliestDue(t *testing.T) {
	mk := func(y int, m time.Month, d int) *time.Time {
		t := time.Date(y, m, d, 0, 0, 0, 0, time.UTC)
		return &t
	}
	a := due(1, 10, "Asha", nil)
	a.DueDate = mk(2026, 9, 1)
	b := due(2, 10, "Asha", nil)
	b.DueDate = mk(2026, 7, 15)
	c := due(3, 10, "Asha", nil) // no date at all

	if got := earliestDue([]invoiceableDue{a, b, c}); got != "2026-07-15" {
		t.Errorf("want the earliest date, got %q", got)
	}
	if got := earliestDue([]invoiceableDue{c}); got != "" {
		t.Errorf("no dates means no due date, got %q", got)
	}
}

// Every skipped due must say which of the several possible reasons applied —
// "nothing happened" with no explanation is the failure mode this exists to
// prevent.
func TestSkipReason(t *testing.T) {
	inv := int64(7)
	cases := []struct {
		name  string
		state dueState
		want  string
	}{
		{"unknown id", dueState{}, SkipNotFound},
		{"already invoiced",
			dueState{PaymentID: 1, Status: "pending", InvoiceID: &inv},
			SkipAlreadyInvoiced},
		{"settled",
			dueState{PaymentID: 1, Status: "paid"}, SkipNotOutstanding},
		{"written off",
			dueState{PaymentID: 1, Status: "written_off"}, SkipNotOutstanding},
	}
	for _, c := range cases {
		if got := skipReason(c.state); got != c.want {
			t.Errorf("%s: want %q, got %q", c.name, c.want, got)
		}
	}
}

// A double-submitted list must not produce two invoices for one due.
func TestDedupeDropsRepeatsAndJunk(t *testing.T) {
	got := dedupe([]int64{5, 5, 0, -1, 7, 5})
	if len(got) != 2 || got[0] != 5 || got[1] != 7 {
		t.Fatalf("want [5 7], got %v", got)
	}
}

// The batch cap is a correctness limit, not a performance one. Pinned so
// raising it is a deliberate argument rather than a quiet edit.
func TestBatchCap(t *testing.T) {
	if MaxInvoiceBatch != 50 {
		t.Fatalf("MaxInvoiceBatch changed to %d; the handler's error message "+
			"names 50 and would start lying", MaxInvoiceBatch)
	}
}
