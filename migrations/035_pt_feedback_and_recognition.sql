-- 035: PT feedback and private member recognition.
--
-- Two tables from what looked like four asks. member_feedback is one growing
-- log for both "what the member said" and "what the trainer observed" —
-- same shape either way, staff writes both (trainers have no login, see
-- FR-03 §0: users.role is only owner/staff), only author_role differs.
--
-- member_recognitions is a separate, rare, human-authored event: an
-- owner/staff pick, a written reason, optionally citing a signal that
-- informed the call. Deliberately not a score and not rankable — no points
-- column, no ordering field, one row per act of recognition. Nothing in this
-- schema computes or triggers a recognition; the signal columns are inert
-- citations, same anti-ranking spirit as staff work (FR-13 §1: "no
-- productivity score, no ranking").

BEGIN;

-- ─── member_feedback ────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS member_feedback (
    id                 BIGSERIAL    PRIMARY KEY,
    gym_id             BIGINT       NOT NULL REFERENCES gyms(id),
    member_id          BIGINT       NOT NULL REFERENCES members(id),

    -- Who the note is about is member_id, always. author_role says whose
    -- words these are: the member's own (staff transcribed what they said)
    -- or the trainer's observation (staff transcribed, or the trainer
    -- dictated to the desk). Both rows are staff-authored by
    -- created_by_user_id regardless of author_role.
    author_role        VARCHAR(20)  NOT NULL,

    -- Optional context, independent of each other. trainer_id is set
    -- whenever the note concerns PT, from either role — a member note can be
    -- "said the trainer helped a lot". pt_appointment_id ties a note to one
    -- specific session; pt_package_id ties it to the package/engagement
    -- without pinning to a single visit. A note can have neither (general
    -- feedback), either, or both.
    trainer_id         BIGINT       REFERENCES trainers(id),
    pt_package_id      BIGINT       REFERENCES pt_packages(id),
    pt_appointment_id  BIGINT       REFERENCES pt_appointments(id),

    note               TEXT         NOT NULL,

    created_by_user_id BIGINT       NOT NULL REFERENCES users(id),
    created_at         TIMESTAMPTZ  NOT NULL DEFAULT now(),

    CONSTRAINT chk_member_feedback_author_role
        CHECK (author_role IN ('member', 'trainer')),
    CONSTRAINT chk_member_feedback_note_not_blank
        CHECK (btrim(note) <> '')
);

-- Dominant reads: a member's feedback history, and a trainer's feedback given.
CREATE INDEX IF NOT EXISTS idx_member_feedback_member
    ON member_feedback (gym_id, member_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_member_feedback_trainer
    ON member_feedback (gym_id, trainer_id, created_at DESC)
    WHERE trainer_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_member_feedback_appointment
    ON member_feedback (pt_appointment_id)
    WHERE pt_appointment_id IS NOT NULL;

COMMENT ON TABLE member_feedback IS
    'Staff-transcribed feedback, from either the member or about the member '
    'via a trainer. author_role distinguishes whose words they are; both are '
    'written by staff since trainers have no login (FR-03).';

-- ─── member_recognitions ────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS member_recognitions (
    id                 BIGSERIAL    PRIMARY KEY,
    gym_id             BIGINT       NOT NULL REFERENCES gyms(id),
    member_id          BIGINT       NOT NULL REFERENCES members(id),

    reason             TEXT         NOT NULL,

    -- What the owner leaned on, if anything: 'rhythm' (member_rhythm_profiles)
    -- or 'feedback' (a member_feedback row). NULL means pure judgment call.
    -- Either way this is a citation the caller already fetched, never a
    -- value this table computes or looks up on its own.
    signal_type        VARCHAR(20),
    signal_id          BIGINT,

    created_by_user_id BIGINT       NOT NULL REFERENCES users(id),
    created_at         TIMESTAMPTZ  NOT NULL DEFAULT now(),

    CONSTRAINT chk_member_recognitions_reason_not_blank
        CHECK (btrim(reason) <> ''),
    CONSTRAINT chk_member_recognitions_signal_type
        CHECK (signal_type IS NULL OR signal_type IN ('rhythm', 'feedback')),
    CONSTRAINT chk_member_recognitions_signal_pair
        CHECK ((signal_type IS NULL) = (signal_id IS NULL))
);

CREATE INDEX IF NOT EXISTS idx_member_recognitions_member
    ON member_recognitions (gym_id, member_id, created_at DESC);

COMMENT ON TABLE member_recognitions IS
    'Private, owner-curated member recognition. No score, no rank, no '
    'automatic trigger — always a human pick with a written reason, in the '
    'same spirit as the no-ranking rule in FR-13 §1.';

COMMIT;
