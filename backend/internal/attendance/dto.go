package attendance

import "time"

// ─── Request DTOs ─────────────────────────────────────────────────────────────

// CheckInRequest is the payload for POST /api/v1/attendance/checkin.
// gym_id comes from JWT. checked_in_at is set by the server.
// @Description Check in a member. Server sets the timestamp.
type CheckInRequest struct {
	MemberID int64 `json:"member_id"` // required
}

// ─── Response DTOs ────────────────────────────────────────────────────────────

// AttendanceResponse is the full attendance record.
// member_name included for Flutter display — avoids extra lookup.
// @Description Single attendance record.
type AttendanceResponse struct {
	ID            int64     `json:"id"`
	GymID         int64     `json:"gym_id"`
	MemberID      int64     `json:"member_id"`
	MemberName    string    `json:"member_name"`
	CheckedInAt   time.Time `json:"checked_in_at"`
	CheckedInDate time.Time `json:"checked_in_date"`
	CreatedAt     time.Time `json:"created_at"`
}

// AttendanceListResponse wraps a slice of attendance records.
// @Description Paginated attendance list.
type AttendanceListResponse struct {
	Attendance []AttendanceResponse `json:"attendance"`
}

// AttendanceWithContext carries the record plus resolved member name from JOIN.
type AttendanceWithContext struct {
	Attendance
	MemberFirstName string
	MemberLastName  string
}

func (a *AttendanceWithContext) ToResponse() AttendanceResponse {
	return AttendanceResponse{
		ID:            a.ID,
		GymID:         a.GymID,
		MemberID:      a.MemberID,
		MemberName:    a.MemberFirstName + " " + a.MemberLastName,
		CheckedInAt:   a.CheckedInAt,
		CheckedInDate: a.CheckedInDate,
		CreatedAt:     a.CreatedAt,
	}
}

func ToResponseList(items []AttendanceWithContext) []AttendanceResponse {
	out := make([]AttendanceResponse, 0, len(items))
	for i := range items {
		out = append(out, items[i].ToResponse())
	}
	return out
}
