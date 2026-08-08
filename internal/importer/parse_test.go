package importer

import "testing"

func TestParseDate_DayFirst(t *testing.T) {
	// The whole point: 03/04/2026 is 3 April, not 4 March. Getting this wrong
	// silently moves a member's expiry by a month (FR-05 §2.2).
	d, err := parseDate("03/04/2026")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if d.Day() != 3 || d.Month() != 4 || d.Year() != 2026 {
		t.Errorf("03/04/2026 parsed as %s, want 3 April 2026", d.Format("2 Jan 2006"))
	}

	for _, s := range []string{"2026-04-03", "03-04-2026", "03.04.2026", "2026/04/03"} {
		got, err := parseDate(s)
		if err != nil {
			t.Errorf("%q: unexpected error %v", s, err)
			continue
		}
		if got.Day() != 3 || got.Month() != 4 {
			t.Errorf("%q parsed as %s, want 3 April", s, got.Format("2 Jan 2006"))
		}
	}
}

func TestParseDate_EmptyAndInvalid(t *testing.T) {
	d, err := parseDate("")
	if err != nil || d != nil {
		t.Errorf("empty date should be (nil, nil), got (%v, %v)", d, err)
	}
	if _, err := parseDate("not a date"); err == nil {
		t.Error("garbage date should fail rather than default to something")
	}
}

func TestParseDate_StripsTimeComponent(t *testing.T) {
	d, err := parseDate("2026-04-03 14:30:00")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if d.Day() != 3 || d.Hour() != 0 {
		t.Errorf("got %s, want midnight on 3 April", d)
	}
}

func TestParseRupeesToPaise(t *testing.T) {
	tests := []struct {
		in   string
		want int64
	}{
		{"1200", 120000},
		{"1,200", 120000},
		{"₹1,200.00", 120000},
		{"Rs. 1500", 150000},
		{"1200.50", 120050},
		{"0", 0},
		{"", 0},
	}
	for _, tc := range tests {
		got, err := parseRupeesToPaise(tc.in)
		if err != nil {
			t.Errorf("%q: unexpected error %v", tc.in, err)
			continue
		}
		if got != tc.want {
			t.Errorf("%q = %d paise, want %d", tc.in, got, tc.want)
		}
	}

	for _, bad := range []string{"abc", "-500"} {
		if _, err := parseRupeesToPaise(bad); err == nil {
			t.Errorf("%q should fail", bad)
		}
	}
}

func TestNormalisePhone(t *testing.T) {
	// All of these are the same person in different exports.
	for _, s := range []string{"9876543210", "+91 9876543210", "919876543210", "09876543210", "98765-43210"} {
		if got := normalisePhone(s); got != "9876543210" {
			t.Errorf("normalisePhone(%q) = %q, want 9876543210", s, got)
		}
	}
}

func TestBuildHeaderMap_Aliases(t *testing.T) {
	header := []string{"First Name", "SURNAME", "Mobile No", "Valid Till", "Junk Column"}
	h := buildHeaderMap(header)

	checks := map[string]int{
		"first_name":  0,
		"last_name":   1,
		"phone":       2,
		"expiry_date": 3,
	}
	for field, wantIdx := range checks {
		if got, ok := h[field]; !ok || got != wantIdx {
			t.Errorf("field %s mapped to %d (present=%v), want %d", field, got, ok, wantIdx)
		}
	}
	// Unknown columns are ignored, not fatal.
	if len(h) != len(checks) {
		t.Errorf("expected exactly %d mapped fields, got %d: %v", len(checks), len(h), h)
	}
}

func TestParseCSV_BOMAndRaggedRows(t *testing.T) {
	content := "\uFEFFfirst_name,last_name,phone\nAjinkya,Rahane,9876543210\nShort,Row\n"
	h, rows, err := parseCSV(content)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if _, ok := h["first_name"]; !ok {
		t.Error("BOM prevented the first header from being recognised")
	}
	if len(rows) != 2 {
		t.Errorf("got %d rows, want 2", len(rows))
	}
	// A short row must not panic — the missing column reads as empty.
	if got := cell(rows[1], h, "phone"); got != "" {
		t.Errorf("missing cell = %q, want empty", got)
	}
}

func TestParseMemberRow(t *testing.T) {
	h := buildHeaderMap([]string{"first_name", "last_name", "phone", "expiry_date", "status"})

	m, err := parseMemberRow([]string{"Ajinkya", "Rahane", "+91 9876543210", "31/03/2027", "active"}, h)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if m.Phone != "9876543210" {
		t.Errorf("phone = %q, want normalised 9876543210", m.Phone)
	}
	if m.ExpiryDate == nil || m.ExpiryDate.Month() != 3 {
		t.Errorf("expiry not parsed day-first: %v", m.ExpiryDate)
	}

	// Missing phone is fatal — a member without a contact number is not usable.
	if _, err := parseMemberRow([]string{"Ajinkya", "Rahane", "", "", ""}, h); err == nil {
		t.Error("missing phone should fail the row")
	}

	// Status defaults rather than failing.
	m2, err := parseMemberRow([]string{"A", "B", "9876543211", "", ""}, h)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if m2.Status != "active" {
		t.Errorf("status = %q, want default active", m2.Status)
	}
}

func TestParseMemberRow_SingleNameColumn(t *testing.T) {
	// A file with one "Name" column must still work.
	h := buildHeaderMap([]string{"Name", "Phone"})
	m, err := parseMemberRow([]string{"Ajinkya Rahane", "9876543210"}, h)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if m.FirstName != "Ajinkya" || m.LastName != "Rahane" {
		t.Errorf("split name = %q / %q, want Ajinkya / Rahane", m.FirstName, m.LastName)
	}
}

func TestParseMemberRow_ExpiryBeforeStart(t *testing.T) {
	h := buildHeaderMap([]string{"first_name", "phone", "start_date", "expiry_date"})
	_, err := parseMemberRow([]string{"A", "9876543210", "01/04/2026", "01/01/2026"}, h)
	if err == nil {
		t.Error("an expiry before the start date should be rejected")
	}
}

func TestParsePaymentRow_ModeAliases(t *testing.T) {
	h := buildHeaderMap([]string{"phone", "amount", "payment_mode"})
	for raw, want := range map[string]string{
		"UPI": "upi", "GPay": "upi", "Cash": "cash",
		"NEFT": "bank_transfer", "Credit Card": "credit_card",
		"something odd": "cash", // unknown modes record as cash rather than failing
	} {
		p, err := parsePaymentRow([]string{"9876543210", "1500", raw}, h)
		if err != nil {
			t.Errorf("%q: unexpected error %v", raw, err)
			continue
		}
		if p.PaymentMode != want {
			t.Errorf("mode %q = %q, want %q", raw, p.PaymentMode, want)
		}
	}

	// Zero amount is meaningless for a payment.
	if _, err := parsePaymentRow([]string{"9876543210", "0", "cash"}, h); err == nil {
		t.Error("a zero payment should be rejected")
	}
}
