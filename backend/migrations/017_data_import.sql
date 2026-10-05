-- 017_data_import.sql
--
-- Staging tables for CSV import. See docs/FR-05-data-import.md.
--
-- These tables exist so that validating a file NEVER touches real data
-- (FR-05 §5.1): parsed rows live here until someone explicitly commits them.
-- Additive only — nothing existing is altered.

CREATE TABLE IF NOT EXISTS import_batches (
    id                 bigserial PRIMARY KEY,
    gym_id             bigint       NOT NULL,
    entity_type        varchar(20)  NOT NULL,           -- members | plans | payments
    filename           varchar(255),
    -- The uploaded content is retained so a disputed import can be re-examined
    -- against what was actually submitted (FR-05 §5.3).
    raw_content        text,
    status             varchar(20)  NOT NULL DEFAULT 'validated', -- validated | committed | discarded
    duplicate_policy   varchar(10)  NOT NULL DEFAULT 'skip',      -- skip | update

    total_rows         integer      NOT NULL DEFAULT 0,
    valid_rows         integer      NOT NULL DEFAULT 0,
    invalid_rows       integer      NOT NULL DEFAULT 0,
    duplicate_rows     integer      NOT NULL DEFAULT 0,
    imported_rows      integer      NOT NULL DEFAULT 0,
    skipped_rows       integer      NOT NULL DEFAULT 0,
    updated_rows       integer      NOT NULL DEFAULT 0,

    created_by_user_id bigint       NOT NULL,
    committed_at       timestamptz,
    created_at         timestamptz  NOT NULL DEFAULT now(),
    updated_at         timestamptz  NOT NULL DEFAULT now(),

    CONSTRAINT chk_import_entity CHECK (entity_type IN ('members', 'plans', 'payments')),
    CONSTRAINT chk_import_status CHECK (status IN ('validated', 'committed', 'discarded')),
    CONSTRAINT chk_import_policy CHECK (duplicate_policy IN ('skip', 'update')),
    CONSTRAINT chk_import_counts_nonneg CHECK (
        total_rows >= 0 AND valid_rows >= 0 AND invalid_rows >= 0
        AND duplicate_rows >= 0 AND imported_rows >= 0
        AND skipped_rows >= 0 AND updated_rows >= 0
    )
);

CREATE INDEX IF NOT EXISTS idx_import_batches_gym ON import_batches (gym_id, created_at DESC);

CREATE TABLE IF NOT EXISTS import_rows (
    id              bigserial PRIMARY KEY,
    gym_id          bigint      NOT NULL,
    batch_id        bigint      NOT NULL REFERENCES import_batches(id) ON DELETE CASCADE,

    -- The line number in the user's own file, so an error message can point at
    -- something they can actually find and fix.
    line_number     integer     NOT NULL,
    raw_data        jsonb       NOT NULL,
    -- Parsed/normalised values, kept separate from raw so the preview can show
    -- exactly what would be written.
    parsed_data     jsonb,

    status          varchar(20) NOT NULL DEFAULT 'valid', -- valid|invalid|duplicate|imported|skipped|updated
    error_message   text,
    -- Set on commit for rows that produced a record.
    created_id      bigint,

    created_at      timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT chk_import_row_status CHECK (
        status IN ('valid', 'invalid', 'duplicate', 'imported', 'skipped', 'updated')
    ),
    CONSTRAINT chk_import_row_line CHECK (line_number > 0),
    -- An invalid row must say why. "Import failed" with no reason is useless.
    CONSTRAINT chk_import_row_reason CHECK (status <> 'invalid' OR error_message IS NOT NULL)
);

CREATE INDEX IF NOT EXISTS idx_import_rows_batch ON import_rows (batch_id, line_number);
CREATE INDEX IF NOT EXISTS idx_import_rows_status ON import_rows (batch_id, status);
