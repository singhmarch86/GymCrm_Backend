package importer

import (
	"encoding/csv"
	"fmt"
	"strconv"
	"strings"
	"time"
)

// CSV parsing and field coercion. See docs/FR-05-data-import.md §2.
//
// Everything here is deliberately forgiving about *shape* (header spelling,
// column order, extra columns) and deliberately strict about *meaning* (an
// ambiguous date is an error, not a guess). A gym's spreadsheet will never
// match our field names; a wrongly-guessed expiry date is a real problem for a
// real member.

// normaliseHeader lowercases and strips spaces, underscores and hyphens so
// "First Name", "first_name" and "FIRSTNAME" all collapse to "firstname".
func normaliseHeader(s string) string {
	s = strings.ToLower(strings.TrimSpace(s))
	s = strings.ReplaceAll(s, " ", "")
	s = strings.ReplaceAll(s, "_", "")
	s = strings.ReplaceAll(s, "-", "")
	return s
}

// fieldAliases maps a canonical field name to every header spelling seen in
// practice. Unlisted columns are ignored rather than rejected — a real export
// carries plenty of columns we don't care about (FR-05 §2.1).
var fieldAliases = map[string][]string{
	"first_name":    {"firstname", "first", "fname", "givenname", "name"},
	"last_name":     {"lastname", "last", "surname", "lname", "familyname"},
	"phone":         {"phone", "mobile", "contact", "phonenumber", "mobileno", "contactnumber", "mobilenumber"},
	"email":         {"email", "emailaddress", "mail"},
	"gender":        {"gender", "sex"},
	"date_of_birth": {"dateofbirth", "dob", "birthdate", "birthday"},
	"address":       {"address", "addressline", "residence"},
	"plan":          {"plan", "planname", "membership", "membershipplan", "package"},
	"start_date":    {"startdate", "joindate", "joiningdate", "joined", "membershipstart"},
	"expiry_date":   {"expirydate", "enddate", "validtill", "validupto", "expires", "expiry", "membershipend"},
	"status":        {"status", "memberstatus"},
	"notes":         {"notes", "note", "remarks", "comment", "comments"},

	// Plans
	"price":         {"price", "amount", "fee", "cost", "planprice"},
	"duration_days": {"durationdays", "duration", "days", "validitydays", "period"},
	"description":   {"description", "desc", "details"},

	// Payments
	"amount":       {"amount", "paid", "amountpaid", "payment", "price", "fee"},
	"payment_date": {"paymentdate", "date", "paidon", "paiddate", "transactiondate"},
	"payment_mode": {"paymentmode", "mode", "method", "paymentmethod", "paymenttype"},
	"reference":    {"reference", "referencenumber", "refno", "transactionid", "txnid", "receiptno"},
}

// buildHeaderMap resolves the file's header row to canonical field names.
// Returns field -> column index. First match wins, so a file with both "name"
// and "first name" prefers the more specific one by alias ordering.
func buildHeaderMap(header []string) map[string]int {
	seen := make(map[string]int, len(header))
	for i, h := range header {
		seen[normaliseHeader(h)] = i
	}

	out := make(map[string]int)
	for field, aliases := range fieldAliases {
		for _, alias := range aliases {
			if idx, ok := seen[alias]; ok {
				if _, already := out[field]; !already {
					out[field] = idx
				}
				break
			}
		}
	}
	return out
}

// parseCSV reads the whole file into a header map plus rows. Ragged rows are
// tolerated (FieldsPerRecord = -1): a trailing comma or a short last line is a
// spreadsheet artefact, not a reason to reject someone's data.
func parseCSV(content string) (map[string]int, [][]string, error) {
	// Excel writes a UTF-8 BOM; left in place it becomes part of the first
	// header name and that column stops being recognised.
	content = strings.TrimPrefix(content, "\uFEFF")

	r := csv.NewReader(strings.NewReader(content))
	r.Comma = detectDelimiter(content)
	r.FieldsPerRecord = -1
	r.TrimLeadingSpace = true
	r.LazyQuotes = true

	records, err := r.ReadAll()
	if err != nil {
		return nil, nil, fmt.Errorf("could not read the file as CSV: %w", err)
	}
	if len(records) == 0 {
		return nil, nil, fmt.Errorf("the file is empty")
	}

	headerMap := buildHeaderMap(records[0])
	if len(headerMap) == 0 {
		return nil, nil, fmt.Errorf("no recognisable columns found in the header row")
	}
	return headerMap, records[1:], nil
}

// detectDelimiter picks the separator from the header line.
//
// Staff very often paste straight out of Excel rather than exporting a file,
// and that clipboard content is TAB-separated. Assuming commas would turn the
// whole paste into one unrecognisable column, so the delimiter is inferred
// from whichever candidate appears most in the first line.
func detectDelimiter(content string) rune {
	header := content
	if i := strings.IndexAny(header, "\r\n"); i > 0 {
		header = header[:i]
	}

	best, bestCount := ',', strings.Count(header, ",")
	for _, c := range []struct {
		r rune
		s string
	}{{'\t', "\t"}, {';', ";"}, {'|', "|"}} {
		if n := strings.Count(header, c.s); n > bestCount {
			best, bestCount = c.r, n
		}
	}
	return best
}

// cell safely reads a column that may not exist in this file or this row.
func cell(row []string, headerMap map[string]int, field string) string {
	idx, ok := headerMap[field]
	if !ok || idx >= len(row) {
		return ""
	}
	return strings.TrimSpace(row[idx])
}

// ─── Dates ────────────────────────────────────────────────────────────────────

// parseDate accepts the formats Indian gym exports actually contain, all
// day-first. US-style MM/DD/YYYY is deliberately NOT accepted: 03/04/2026 is
// indistinguishable from day-first, and guessing wrong moves a member's expiry
// by months (FR-05 §2.2).
func parseDate(s string) (*time.Time, error) {
	s = strings.TrimSpace(s)
	if s == "" {
		return nil, nil
	}
	// Some exports carry a time component; keep only the date part.
	if i := strings.IndexAny(s, " T"); i > 0 {
		s = s[:i]
	}

	formats := []string{
		"2006-01-02", // ISO
		"02/01/2006", // day-first slashes
		"02-01-2006", // day-first dashes
		"02.01.2006",
		"2006/01/02",
	}
	for _, f := range formats {
		if t, err := time.Parse(f, s); err == nil {
			d := time.Date(t.Year(), t.Month(), t.Day(), 0, 0, 0, 0, time.UTC)
			return &d, nil
		}
	}
	// Two-digit years appear in older exports; treat 00-99 as 2000-2099 rather
	// than silently failing an otherwise good row.
	for _, f := range []string{"02/01/06", "02-01-06"} {
		if t, err := time.Parse(f, s); err == nil {
			d := time.Date(t.Year(), t.Month(), t.Day(), 0, 0, 0, 0, time.UTC)
			return &d, nil
		}
	}
	return nil, fmt.Errorf("date %q is not a format we recognise (use DD/MM/YYYY or YYYY-MM-DD)", s)
}

// ─── Money ────────────────────────────────────────────────────────────────────

// parseRupeesToPaise accepts "1200", "1,200", "₹1,200.00", "Rs. 1200.50" and
// returns paise. Float is used only transiently for the decimal part and
// immediately rounded — no amount is ever stored as float.
func parseRupeesToPaise(s string) (int64, error) {
	s = strings.TrimSpace(s)
	if s == "" {
		return 0, nil
	}
	cleaned := strings.Map(func(r rune) rune {
		if (r >= '0' && r <= '9') || r == '.' || r == '-' {
			return r
		}
		return -1 // drops ₹, Rs, commas, spaces
	}, s)

	if strings.Contains(cleaned, "-") {
		return 0, fmt.Errorf("amount %q cannot be negative", s)
	}

	// "Rs. 1500" cleans to ".1500", and parsing that as a decimal yields 15
	// paise instead of ₹1,500 — a 10,000× error that would look plausible in a
	// spreadsheet. Any dot not sitting between digits is punctuation from a
	// currency prefix, not a decimal point.
	cleaned = strings.TrimLeft(cleaned, ".")

	if cleaned == "" {
		return 0, fmt.Errorf("amount %q is not a number", s)
	}
	if strings.Count(cleaned, ".") > 1 {
		return 0, fmt.Errorf("amount %q is not a number", s)
	}

	v, err := strconv.ParseFloat(cleaned, 64)
	if err != nil {
		return 0, fmt.Errorf("amount %q is not a number", s)
	}
	return int64(v*100 + 0.5), nil
}

func parseInt(s string) (int, error) {
	s = strings.TrimSpace(s)
	if s == "" {
		return 0, nil
	}
	cleaned := strings.Map(func(r rune) rune {
		if r >= '0' && r <= '9' {
			return r
		}
		return -1
	}, s)
	if cleaned == "" {
		return 0, fmt.Errorf("%q is not a whole number", s)
	}
	return strconv.Atoi(cleaned)
}

// ─── Phone ────────────────────────────────────────────────────────────────────

// normalisePhone strips formatting and the +91 / 0 prefixes that Indian
// exports mix freely, so duplicate detection compares like with like.
func normalisePhone(s string) string {
	digits := strings.Map(func(r rune) rune {
		if r >= '0' && r <= '9' {
			return r
		}
		return -1
	}, s)

	switch {
	case len(digits) == 12 && strings.HasPrefix(digits, "91"):
		return digits[2:]
	case len(digits) == 11 && strings.HasPrefix(digits, "0"):
		return digits[1:]
	default:
		return digits
	}
}

// splitName handles files with a single "name" column by splitting on the
// first space — "Ajinkya Rahane" → ("Ajinkya", "Rahane"). A single-word name
// keeps an empty surname rather than duplicating the first name.
func splitName(full string) (first, last string) {
	full = strings.TrimSpace(full)
	if full == "" {
		return "", ""
	}
	parts := strings.SplitN(full, " ", 2)
	if len(parts) == 1 {
		return parts[0], ""
	}
	return strings.TrimSpace(parts[0]), strings.TrimSpace(parts[1])
}
