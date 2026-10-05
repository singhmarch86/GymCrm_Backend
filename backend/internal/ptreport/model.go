package ptreport

import "time"

// PT reports — the member side and the trainer side, independently.
//
// Read-only compositions over pt (packages/appointments), ptfeedback and
// rhythm. Deliberately its own module rather than folded into any of those:
// each of the pieces it reads owns a different concept (a sale, a note, an
// attendance signal), and a report that joins them should not force any one
// of those modules to know about the others.

// MemberReport is one member's PT picture: what they've bought, what's left,
// what's been said about them, and how their attendance looks.
type MemberReport struct {
	MemberID int64            `json:"member_id"`
	Packages []PackageSummary `json:"packages"`
	Feedback []FeedbackRow    `json:"feedback"`
	Rhythm   *RhythmSummary   `json:"rhythm,omitempty"`
}

type PackageSummary struct {
	ID                int64      `json:"id"`
	TrainerID         int64      `json:"trainer_id"`
	TrainerName       string     `json:"trainer_name"`
	PackageName       string     `json:"package_name"`
	TotalSessions     int        `json:"total_sessions"`
	SessionsUsed      int        `json:"sessions_used"`
	SessionsRemaining int        `json:"sessions_remaining"`
	Status            string     `json:"status"`
	ExpiryDate        *time.Time `json:"expiry_date,omitempty"`
}

type FeedbackRow struct {
	ID         int64     `json:"id"`
	AuthorRole string    `json:"author_role"`
	Note       string    `json:"note"`
	CreatedAt  time.Time `json:"created_at"`
}

// RhythmSummary is the attendance-consistency signal, unmodified from
// member_rhythm_profiles — this report cites it, never recomputes it.
type RhythmSummary struct {
	RecentConsistency float64 `json:"recent_consistency"`
	RecentRate        float64 `json:"recent_rate"`
	IsBroken          bool    `json:"is_broken"`
}

// TrainerReport is one trainer's PT picture: sessions delivered, feedback
// given, who they currently work with, and what they were last paid.
type TrainerReport struct {
	TrainerID          int64         `json:"trainer_id"`
	SessionsCompleted  int           `json:"sessions_completed"`
	Feedback           []FeedbackRow `json:"feedback"`
	AssignedMembers    []MemberRef   `json:"assigned_members"`
	LastPayoutInPaise  *int64        `json:"last_payout_in_paise,omitempty"`
	LastPayoutPeriodTo *time.Time    `json:"last_payout_period_to,omitempty"`
}

// MemberRef is enough to label a row. Ordered by name, never by a
// performance figure — same anti-ranking rule as staff work (FR-13 §1).
type MemberRef struct {
	ID   int64  `json:"id"`
	Name string `json:"name"`
}
