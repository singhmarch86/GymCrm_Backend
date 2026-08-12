package queues

import (
	"testing"
	"time"

	"gymcrm/internal/staffwork"
)

func ymd(s string) time.Time {
	d, err := time.ParseInLocation("2006-01-02", s, staffwork.IST)
	if err != nil {
		panic(err)
	}
	return d
}

func rangeOf(from, to string) staffwork.Range {
	return staffwork.Range{From: ymd(from), To: ymd(to)}
}

// The point of filling: a day with nothing due must still be a column. Without
// this, a chart draws straight over a quiet week and the shape lies about
// exactly the thing it exists to show.
func TestFillBucketsInsertsQuietDays(t *testing.T) {
	got := fillBuckets(
		rangeOf("2026-08-01", "2026-08-05"),
		[]ExpectedBucket{
			{Key: "2026-08-01", RaisedInPaise: 500000, RaisedCount: 2},
			{Key: "2026-08-04", ExpiringInPaise: 300000, ExpiringCount: 1},
		},
		false,
	)

	if len(got) != 5 {
		t.Fatalf("want 5 daily buckets, got %d", len(got))
	}
	if got[0].RaisedInPaise != 500000 {
		t.Errorf("day 1 lost its raised total: %+v", got[0])
	}
	for _, i := range []int{1, 2, 4} {
		if got[i].RaisedInPaise != 0 || got[i].ExpiringInPaise != 0 {
			t.Errorf("bucket %d should be an explicit zero, got %+v", i, got[i])
		}
		if got[i].Key == "" || got[i].Label == "" {
			t.Errorf("bucket %d must still be labelled: %+v", i, got[i])
		}
	}
	if got[3].ExpiringCount != 1 {
		t.Errorf("day 4 lost its expiring count: %+v", got[3])
	}
}

// A single day is one bucket, not zero — the inclusive-range rule the staff
// work range already follows.
func TestFillBucketsSingleDay(t *testing.T) {
	got := fillBuckets(rangeOf("2026-08-12", "2026-08-12"), nil, false)
	if len(got) != 1 {
		t.Fatalf("want 1 bucket for a single day, got %d", len(got))
	}
	if got[0].Key != "2026-08-12" {
		t.Errorf("wrong key: %q", got[0].Key)
	}
}

// Monthly bucketing starts at the first of the month the range starts in, so a
// range beginning mid-month still produces a column for that whole month
// rather than an orphan keyed to the 12th.
func TestFillBucketsByMonthSnapsToMonthStart(t *testing.T) {
	got := fillBuckets(
		rangeOf("2026-08-12", "2026-10-31"),
		[]ExpectedBucket{{Key: "2026-09-01", ExpiringInPaise: 100, ExpiringCount: 1}},
		true,
	)

	want := []string{"2026-08-01", "2026-09-01", "2026-10-01"}
	if len(got) != len(want) {
		t.Fatalf("want %d monthly buckets, got %d: %+v", len(want), len(got), got)
	}
	for i, key := range want {
		if got[i].Key != key {
			t.Errorf("bucket %d: want key %q, got %q", i, key, got[i].Key)
		}
	}
	if got[1].ExpiringCount != 1 {
		t.Errorf("September lost its data: %+v", got[1])
	}
	if got[0].Label != "Aug 2026" {
		t.Errorf("monthly label should name the month, got %q", got[0].Label)
	}
}

// The switch between day and month columns is a readability threshold, not a
// data one. Pinned so a change to it is a deliberate edit rather than a
// side effect.
func TestBucketThreshold(t *testing.T) {
	if BucketByMonth != 31 {
		t.Fatalf("BucketByMonth changed to %d; update the UI copy that says "+
			"'day by day' before loosening this", BucketByMonth)
	}
	if got := rangeOf("2026-08-01", "2026-08-31").Days(); got != 31 {
		t.Fatalf("a full August should be 31 days, got %d", got)
	}
}
