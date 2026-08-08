package importer

import "time"

// ImportBatch is one uploaded file and everything that happened to it.
// See docs/FR-05-data-import.md.
//
// The batch survives commit as an audit record: what was imported, when, by
// whom, from which file, and with which duplicate policy.
type ImportBatch struct {
	ID         int64  `gorm:"primaryKey;autoIncrement" json:"id"`
	GymID      int64  `gorm:"not null"                json:"gym_id"`
	EntityType string `gorm:"type:varchar(20);not null" json:"entity_type"`
	Filename   *string `gorm:"type:varchar(255)"      json:"filename,omitempty"`
	// Retained so a disputed import can be checked against what was actually
	// uploaded (FR-05 §5.3). Not returned in list responses.
	RawContent      *string `gorm:"type:text" json:"-"`
	Status          string  `gorm:"type:varchar(20);not null;default:'validated'" json:"status"`
	DuplicatePolicy string  `gorm:"type:varchar(10);not null;default:'skip'"      json:"duplicate_policy"`

	TotalRows     int `gorm:"not null;default:0" json:"total_rows"`
	ValidRows     int `gorm:"not null;default:0" json:"valid_rows"`
	InvalidRows   int `gorm:"not null;default:0" json:"invalid_rows"`
	DuplicateRows int `gorm:"not null;default:0" json:"duplicate_rows"`
	ImportedRows  int `gorm:"not null;default:0" json:"imported_rows"`
	SkippedRows   int `gorm:"not null;default:0" json:"skipped_rows"`
	UpdatedRows   int `gorm:"not null;default:0" json:"updated_rows"`

	CreatedByUserID int64      `gorm:"not null" json:"created_by_user_id"`
	CommittedAt     *time.Time `json:"committed_at,omitempty"`
	CreatedAt       time.Time  `gorm:"autoCreateTime" json:"created_at"`
	UpdatedAt       time.Time  `gorm:"autoUpdateTime" json:"updated_at"`
}

func (ImportBatch) TableName() string { return "import_batches" }

// Batch statuses.
const (
	BatchValidated = "validated"
	BatchCommitted = "committed"
	BatchDiscarded = "discarded"
)

// Entity types importable in v1 (FR-05 §2).
const (
	EntityMembers  = "members"
	EntityPlans    = "plans"
	EntityPayments = "payments"
)

// Duplicate policies (FR-05 §4).
const (
	PolicySkip   = "skip"
	PolicyUpdate = "update"
)

// ImportRow is one line of the uploaded file, parsed and judged.
type ImportRow struct {
	ID         int64 `gorm:"primaryKey;autoIncrement" json:"id"`
	GymID      int64 `gorm:"not null"                json:"gym_id"`
	BatchID    int64 `gorm:"not null"                json:"batch_id"`
	LineNumber int   `gorm:"not null"                json:"line_number"`

	// Held as JSON text rather than a typed JSON column: this package only ever
	// writes and echoes these blobs, never queries inside them, so a dedicated
	// JSON datatype dependency would buy nothing.
	RawData    string  `gorm:"type:jsonb;not null" json:"-"`
	ParsedData *string `gorm:"type:jsonb"          json:"-"`

	Status       string  `gorm:"type:varchar(20);not null;default:'valid'" json:"status"`
	ErrorMessage *string `gorm:"type:text" json:"error_message,omitempty"`
	CreatedID    *int64  `json:"created_id,omitempty"`

	CreatedAt time.Time `gorm:"autoCreateTime" json:"created_at"`
}

func (ImportRow) TableName() string { return "import_rows" }

// Row outcomes (FR-05 §3). valid/invalid/duplicate are set at validation;
// imported/skipped/updated are set at commit.
const (
	RowValid     = "valid"
	RowInvalid   = "invalid"
	RowDuplicate = "duplicate"
	RowImported  = "imported"
	RowSkipped   = "skipped"
	RowUpdated   = "updated"
)
