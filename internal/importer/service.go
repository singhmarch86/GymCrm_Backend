package importer

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	"gymcrm/internal/database"
)

// Service implements the two-phase import. See docs/FR-05-data-import.md.
//
// Phase one (Validate) parses and judges every row and writes ONLY to the
// staging tables. Phase two (Commit) writes the real records. Nothing in
// between is implicit — a batch sits in `validated` until a human says go.
type Service struct {
	repo *Repository
}

func NewService(repo *Repository) *Service { return &Service{repo: repo} }

var (
	ErrBatchNotFound     = errors.New("import not found")
	ErrBatchNotValidated = errors.New("this import has already been committed or discarded")
	ErrUnknownEntity     = errors.New("entity must be one of: members, plans, payments")
	ErrEmptyFile         = errors.New("the file has no data rows")
)

// Validate parses the upload, judges each row, and stores the result for
// preview. It writes nothing to members, plans or payments — FR-05 §5.1.
func (s *Service) Validate(ctx context.Context, entityType, filename, content string) (*BatchResponse, error) {
	switch entityType {
	case EntityMembers, EntityPlans, EntityPayments:
	default:
		return nil, ErrUnknownEntity
	}

	headerMap, records, err := parseCSV(content)
	if err != nil {
		return nil, err
	}
	if len(records) == 0 {
		return nil, ErrEmptyFile
	}

	tc := database.MustGetTenant(ctx)
	batch := &ImportBatch{
		GymID:           tc.GymID(),
		EntityType:      entityType,
		Filename:        optional(filename),
		RawContent:      &content,
		Status:          BatchValidated,
		DuplicatePolicy: PolicySkip,
		CreatedByUserID: tc.UserID(),
	}
	if err := s.repo.CreateBatch(ctx, batch); err != nil {
		return nil, fmt.Errorf("validate: create batch: %w", err)
	}

	// Duplicates within the file itself matter as much as duplicates against
	// the database — a spreadsheet with the same phone twice would otherwise
	// create two members.
	seenInFile := map[string]int{}

	rows := make([]ImportRow, 0, len(records))
	var valid, invalid, dupes int

	for i, rec := range records {
		lineNo := i + 2 // +1 for zero-index, +1 for the header row
		if isBlankRow(rec) {
			continue
		}

		raw, _ := json.Marshal(rawMap(headerMap, rec))
		row := ImportRow{
			GymID: tc.GymID(), BatchID: batch.ID, LineNumber: lineNo,
			RawData: string(raw), Status: RowValid,
		}

		parsed, status, errMsg := s.judgeRow(ctx, entityType, rec, headerMap, seenInFile, lineNo)
		row.Status = status
		if errMsg != "" {
			msg := errMsg
			row.ErrorMessage = &msg
		}
		if parsed != nil {
			if b, err := json.Marshal(parsed); err == nil {
				p := string(b)
				row.ParsedData = &p
			}
		}

		switch status {
		case RowValid:
			valid++
		case RowDuplicate:
			dupes++
		default:
			invalid++
		}
		rows = append(rows, row)
	}

	if err := s.repo.CreateRows(ctx, rows); err != nil {
		return nil, fmt.Errorf("validate: store rows: %w", err)
	}

	counts := map[string]any{
		"total_rows": len(rows), "valid_rows": valid,
		"invalid_rows": invalid, "duplicate_rows": dupes,
	}
	if err := s.repo.UpdateBatch(ctx, batch.ID, counts); err != nil {
		return nil, fmt.Errorf("validate: update counts: %w", err)
	}
	return s.GetBatch(ctx, batch.ID)
}

// judgeRow parses one row and decides its fate. Returns the parsed payload
// (for preview and later commit), the row status, and a human-readable reason
// when it fails.
func (s *Service) judgeRow(
	ctx context.Context, entityType string, rec []string, h map[string]int,
	seenInFile map[string]int, lineNo int,
) (any, string, string) {
	switch entityType {
	case EntityMembers:
		m, err := parseMemberRow(rec, h)
		if err != nil {
			return nil, RowInvalid, err.Error()
		}
		if prev, ok := seenInFile[m.Phone]; ok {
			return m, RowDuplicate, fmt.Sprintf("same phone number as line %d in this file", prev)
		}
		seenInFile[m.Phone] = lineNo

		// A named plan that doesn't exist is a warning, not a failure: the
		// member is still worth importing (FR-05 §6.2).
		if m.PlanName != "" {
			if id, err := s.repo.existingPlanIDByName(ctx, m.PlanName); err == nil && id > 0 {
				m.PlanID = &id
			} else {
				m.PlanWarning = fmt.Sprintf("plan %q not found — member will be imported without a plan", m.PlanName)
			}
		}

		if id, err := s.repo.existingMemberIDByPhone(ctx, m.Phone); err == nil && id > 0 {
			return m, RowDuplicate, "a member with this phone number already exists"
		}
		return m, RowValid, ""

	case EntityPlans:
		p, err := parsePlanRow(rec, h)
		if err != nil {
			return nil, RowInvalid, err.Error()
		}
		key := "plan:" + strings.ToLower(p.Name)
		if prev, ok := seenInFile[key]; ok {
			return p, RowDuplicate, fmt.Sprintf("same plan name as line %d in this file", prev)
		}
		seenInFile[key] = lineNo

		if id, err := s.repo.existingPlanIDByName(ctx, p.Name); err == nil && id > 0 {
			return p, RowDuplicate, "a plan with this name already exists"
		}
		return p, RowValid, ""

	case EntityPayments:
		p, err := parsePaymentRow(rec, h)
		if err != nil {
			return nil, RowInvalid, err.Error()
		}
		// Money with no owner cannot be imported.
		id, err := s.repo.existingMemberIDByPhone(ctx, p.Phone)
		if err != nil || id == 0 {
			return p, RowInvalid, fmt.Sprintf("no member found with phone %s — import that member first", p.Phone)
		}
		p.MemberID = id
		return p, RowValid, ""
	}
	return nil, RowInvalid, "unsupported entity"
}

// Commit writes the real records. Each row commits independently so a single
// failure cannot roll back the rest of the file (FR-05 §5.2).
func (s *Service) Commit(ctx context.Context, batchID int64, policy string) (*BatchResponse, error) {
	batch, err := s.repo.FindBatch(ctx, batchID)
	if err != nil {
		return nil, fmt.Errorf("commit: %w", err)
	}
	if batch == nil {
		return nil, ErrBatchNotFound
	}
	if batch.Status != BatchValidated {
		return nil, ErrBatchNotValidated
	}
	if policy != PolicySkip && policy != PolicyUpdate {
		policy = PolicySkip
	}

	// Only rows that passed, plus duplicates when the policy says to update
	// them, are eligible.
	statuses := []string{RowValid}
	if policy == PolicyUpdate {
		statuses = append(statuses, RowDuplicate)
	}

	var imported, skipped, updated int

	for _, status := range statuses {
		rows, err := s.repo.ListRows(ctx, batchID, status, 0)
		if err != nil {
			return nil, fmt.Errorf("commit: read rows: %w", err)
		}
		for i := range rows {
			row := rows[i]
			if row.ParsedData == nil {
				continue
			}
			outcome, id, err := s.commitRow(ctx, batch.EntityType, row, policy)
			if err != nil {
				// The row failed at write time; record why and carry on.
				msg := err.Error()
				_ = s.repo.UpdateRow(ctx, row.ID, map[string]any{
					"status": RowInvalid, "error_message": msg,
				})
				continue
			}
			fields := map[string]any{"status": outcome}
			if id > 0 {
				fields["created_id"] = id
			}
			_ = s.repo.UpdateRow(ctx, row.ID, fields)

			switch outcome {
			case RowImported:
				imported++
			case RowUpdated:
				updated++
			case RowSkipped:
				skipped++
			}
		}
	}

	// Duplicates left untouched under the skip policy still count as skipped.
	if policy == PolicySkip {
		skipped += batch.DuplicateRows
	}

	now := time.Now()
	if err := s.repo.UpdateBatch(ctx, batchID, map[string]any{
		"status": BatchCommitted, "duplicate_policy": policy,
		"imported_rows": imported, "updated_rows": updated, "skipped_rows": skipped,
		"committed_at": now,
	}); err != nil {
		return nil, fmt.Errorf("commit: update batch: %w", err)
	}
	return s.GetBatch(ctx, batchID)
}

func (s *Service) commitRow(ctx context.Context, entityType string, row ImportRow, policy string) (string, int64, error) {
	switch entityType {
	case EntityMembers:
		var m memberRow
		if err := json.Unmarshal([]byte(*row.ParsedData), &m); err != nil {
			return "", 0, err
		}
		if row.Status == RowDuplicate {
			if policy != PolicyUpdate {
				return RowSkipped, 0, nil
			}
			existingID, err := s.repo.existingMemberIDByPhone(ctx, m.Phone)
			if err != nil || existingID == 0 {
				return "", 0, fmt.Errorf("the existing member could not be found to update")
			}
			// Only overwrite status/expiry when the file actually carried them.
			hasStatus, hasExpiry := rowHadColumn(row.RawData, "status"), rowHadColumn(row.RawData, "expiry_date")
			if err := s.repo.updateMember(ctx, existingID, &m, hasStatus, hasExpiry); err != nil {
				return "", 0, err
			}
			return RowUpdated, existingID, nil
		}
		id, err := s.repo.insertMember(ctx, &m)
		if err != nil {
			return "", 0, err
		}
		return RowImported, id, nil

	case EntityPlans:
		var p planRow
		if err := json.Unmarshal([]byte(*row.ParsedData), &p); err != nil {
			return "", 0, err
		}
		if row.Status == RowDuplicate {
			return RowSkipped, 0, nil // plans are never overwritten by an import
		}
		id, err := s.repo.insertPlan(ctx, &p)
		if err != nil {
			return "", 0, err
		}
		return RowImported, id, nil

	case EntityPayments:
		var p paymentRow
		if err := json.Unmarshal([]byte(*row.ParsedData), &p); err != nil {
			return "", 0, err
		}
		id, err := s.repo.insertPayment(ctx, &p)
		if err != nil {
			return "", 0, err
		}
		return RowImported, id, nil
	}
	return "", 0, fmt.Errorf("unsupported entity")
}

// Discard throws a batch away before it is committed. Nothing was written to
// the real tables, so there is nothing to undo.
func (s *Service) Discard(ctx context.Context, batchID int64) error {
	batch, err := s.repo.FindBatch(ctx, batchID)
	if err != nil {
		return fmt.Errorf("discard: %w", err)
	}
	if batch == nil {
		return ErrBatchNotFound
	}
	if batch.Status != BatchValidated {
		return ErrBatchNotValidated
	}
	return s.repo.UpdateBatch(ctx, batchID, map[string]any{"status": BatchDiscarded})
}

func (s *Service) GetBatch(ctx context.Context, id int64) (*BatchResponse, error) {
	batch, err := s.repo.FindBatch(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("get batch: %w", err)
	}
	if batch == nil {
		return nil, ErrBatchNotFound
	}
	// Preview shows problems first: valid rows need no explanation, broken ones
	// do. Capped so a 5,000-row disaster doesn't produce a 5,000-item response.
	problems, err := s.repo.ListRows(ctx, id, "", 0)
	if err != nil {
		return nil, fmt.Errorf("get batch: rows: %w", err)
	}
	resp := toBatchResponse(*batch, problems)
	return &resp, nil
}

func (s *Service) ListBatches(ctx context.Context) ([]BatchSummaryResponse, error) {
	batches, err := s.repo.ListBatches(ctx)
	if err != nil {
		return nil, fmt.Errorf("list batches: %w", err)
	}
	out := make([]BatchSummaryResponse, 0, len(batches))
	for _, b := range batches {
		out = append(out, toSummary(b))
	}
	return out, nil
}

// ─── helpers ──────────────────────────────────────────────────────────────────

func isBlankRow(rec []string) bool {
	for _, c := range rec {
		if strings.TrimSpace(c) != "" {
			return false
		}
	}
	return true
}

// rawMap keeps only the columns we recognised, so the stored raw payload is
// the data we actually acted on.
func rawMap(h map[string]int, rec []string) map[string]string {
	out := make(map[string]string, len(h))
	for field, idx := range h {
		if idx < len(rec) {
			out[field] = strings.TrimSpace(rec[idx])
		}
	}
	return out
}

// rowHadColumn reports whether the source row actually carried a value for a
// field — the difference between "set it to empty" and "didn't mention it".
func rowHadColumn(raw string, field string) bool {
	var m map[string]string
	if err := json.Unmarshal([]byte(raw), &m); err != nil {
		return false
	}
	v, ok := m[field]
	return ok && strings.TrimSpace(v) != ""
}
