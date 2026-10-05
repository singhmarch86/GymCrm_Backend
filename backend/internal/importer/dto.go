package importer

import (
	"encoding/json"
	"time"
)

// ValidateRequest uploads a file for checking. Content is sent as text rather
// than multipart: a CSV is text, and this keeps the client simple.
// @Description Upload a CSV for validation. Nothing is written until you commit.
type ValidateRequest struct {
	EntityType string `json:"entity_type"` // required: members | plans | payments
	Filename   string `json:"filename"`    // optional, for the audit record
	Content    string `json:"content"`     // required: raw CSV text
}

// CommitRequest turns a validated batch into real records.
// @Description Commit a validated import.
type CommitRequest struct {
	DuplicatePolicy string `json:"duplicate_policy"` // skip (default) | update
}

// RowResponse is one line of the file as judged.
// @Description One row of an import, with its outcome.
type RowResponse struct {
	LineNumber   int               `json:"line_number"`
	Status       string            `json:"status"`
	ErrorMessage *string           `json:"error_message,omitempty"`
	Data         map[string]string `json:"data"`
	CreatedID    *int64            `json:"created_id,omitempty"`
}

// BatchResponse is the preview: counts plus the rows themselves.
// @Description An import batch with its rows.
type BatchResponse struct {
	ID              int64      `json:"id"`
	EntityType      string     `json:"entity_type"`
	Filename        *string    `json:"filename,omitempty"`
	Status          string     `json:"status"`
	DuplicatePolicy string     `json:"duplicate_policy"`
	TotalRows       int        `json:"total_rows"`
	ValidRows       int        `json:"valid_rows"`
	InvalidRows     int        `json:"invalid_rows"`
	DuplicateRows   int        `json:"duplicate_rows"`
	ImportedRows    int        `json:"imported_rows"`
	SkippedRows     int        `json:"skipped_rows"`
	UpdatedRows     int        `json:"updated_rows"`
	CommittedAt     *time.Time `json:"committed_at,omitempty"`
	CreatedAt       time.Time  `json:"created_at"`

	Rows []RowResponse `json:"rows"`
}

// BatchSummaryResponse is the history-list shape.
// @Description An import as it appears in the history list.
type BatchSummaryResponse struct {
	ID            int64      `json:"id"`
	EntityType    string     `json:"entity_type"`
	Filename      *string    `json:"filename,omitempty"`
	Status        string     `json:"status"`
	TotalRows     int        `json:"total_rows"`
	ValidRows     int        `json:"valid_rows"`
	InvalidRows   int        `json:"invalid_rows"`
	DuplicateRows int        `json:"duplicate_rows"`
	ImportedRows  int        `json:"imported_rows"`
	UpdatedRows   int        `json:"updated_rows"`
	SkippedRows   int        `json:"skipped_rows"`
	CommittedAt   *time.Time `json:"committed_at,omitempty"`
	CreatedAt     time.Time  `json:"created_at"`
}

func toBatchResponse(b ImportBatch, rows []ImportRow) BatchResponse {
	out := make([]RowResponse, 0, len(rows))
	for _, r := range rows {
		var data map[string]string
		_ = json.Unmarshal([]byte(r.RawData), &data)
		out = append(out, RowResponse{
			LineNumber: r.LineNumber, Status: r.Status,
			ErrorMessage: r.ErrorMessage, Data: data, CreatedID: r.CreatedID,
		})
	}
	return BatchResponse{
		ID: b.ID, EntityType: b.EntityType, Filename: b.Filename,
		Status: b.Status, DuplicatePolicy: b.DuplicatePolicy,
		TotalRows: b.TotalRows, ValidRows: b.ValidRows, InvalidRows: b.InvalidRows,
		DuplicateRows: b.DuplicateRows, ImportedRows: b.ImportedRows,
		SkippedRows: b.SkippedRows, UpdatedRows: b.UpdatedRows,
		CommittedAt: b.CommittedAt, CreatedAt: b.CreatedAt,
		Rows: out,
	}
}

func toSummary(b ImportBatch) BatchSummaryResponse {
	return BatchSummaryResponse{
		ID: b.ID, EntityType: b.EntityType, Filename: b.Filename, Status: b.Status,
		TotalRows: b.TotalRows, ValidRows: b.ValidRows, InvalidRows: b.InvalidRows,
		DuplicateRows: b.DuplicateRows, ImportedRows: b.ImportedRows,
		UpdatedRows: b.UpdatedRows, SkippedRows: b.SkippedRows,
		CommittedAt: b.CommittedAt, CreatedAt: b.CreatedAt,
	}
}

// TemplateFor returns a starter CSV so a gym knows exactly what we expect.
// Headers use our canonical names, but the importer accepts many aliases —
// see FR-05 §2.1.
func TemplateFor(entityType string) string {
	switch entityType {
	case EntityPlans:
		return "name,price,duration_days,description\n" +
			"Monthly,1500,30,Standard monthly membership\n" +
			"Annual,13000,365,Best value\n"
	case EntityPayments:
		return "phone,amount,payment_date,payment_mode,reference\n" +
			"9876543210,1500,05/04/2026,upi,TXN123456\n"
	default:
		return "first_name,last_name,phone,email,gender,date_of_birth,plan,start_date,expiry_date,status\n" +
			"Ajinkya,Rahane,9876543210,a.rahane@example.com,male,15/06/1990,Annual,01/04/2026,31/03/2027,active\n"
	}
}
