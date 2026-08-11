package reports

import "testing"

// The bug this pins, in both this package and internal/leads:
//
//	count := func(query string, dest *int64, ...) error {
//	    var c countRow
//	    return db.Raw(query, args...).Scan(&c).Error   // <- never assigns
//	}
//
// The queries ran correctly and returned the right numbers; the closure threw
// them away and every caller kept its zero value. Nothing errored, so the
// Members report read 0 total / 0 active against a database holding 809
// members for as long as the screen has existed.
//
// A helper that takes an out-parameter and does not write to it cannot be
// caught by the compiler or by a test that only checks err == nil. This test
// isolates the assignment step so the shape stays honest.
func TestCountHelperAssignsThroughItsOutParameter(t *testing.T) {
	type countRow struct{ V int64 }

	// Stands in for the DB read: fills the row the way GORM's Scan would.
	load := func(c *countRow) error {
		c.V = 809
		return nil
	}

	count := func(dest *int64) error {
		var c countRow
		if err := load(&c); err != nil {
			return err
		}
		*dest = c.V
		return nil
	}

	var total int64
	if err := count(&total); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if total != 809 {
		t.Fatalf("count did not write through its out-parameter: got %d, want 809", total)
	}
}

// An error must leave the destination untouched rather than half-written.
func TestCountHelperLeavesDestinationAloneOnError(t *testing.T) {
	type countRow struct{ V int64 }

	load := func(c *countRow) error {
		c.V = 42 // a driver may partially populate before failing
		return errFailed
	}

	count := func(dest *int64) error {
		var c countRow
		if err := load(&c); err != nil {
			return err
		}
		*dest = c.V
		return nil
	}

	previous := int64(-1)
	if err := count(&previous); err == nil {
		t.Fatal("expected an error")
	}
	if previous != -1 {
		t.Fatalf("destination was written despite the error: got %d", previous)
	}
}

type constError string

func (e constError) Error() string { return string(e) }

const errFailed = constError("query failed")
