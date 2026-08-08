package branches

import (
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"

	"gymcrm/internal/shared/response"
)

type Handler struct {
	svc *Service
}

func NewHandler(svc *Service) *Handler { return &Handler{svc: svc} }

func (h *Handler) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("GET /api/v1/branches", h.MyBranches)
	mux.HandleFunc("POST /api/v1/branches", h.CreateBranch)
	mux.HandleFunc("POST /api/v1/branches/switch", h.Switch)
	mux.HandleFunc("POST /api/v1/branches/access", h.GrantAccess)
	mux.HandleFunc("DELETE /api/v1/branches/{gym_id}/access/{user_id}", h.RevokeAccess)
	mux.HandleFunc("GET /api/v1/org/summary", h.ChainSummary)
	mux.HandleFunc("PUT /api/v1/branches/{gym_id}/targets", h.SetTargets)
	mux.HandleFunc("POST /api/v1/branches/transfer-member", h.TransferMember)
	mux.HandleFunc("POST /api/v1/branches/transfer-staff", h.TransferStaff)
	mux.HandleFunc("POST /api/v1/branches/transfer-trainer", h.TransferTrainer)
	mux.HandleFunc("GET /api/v1/org/report", h.PeriodReport)
}

// PeriodReport godoc
// @Summary      Branch league table for a period
// @Description  Per-branch revenue (membership and retail), new members, target attainment, ranked. Owners only.
// @Tags         branches
// @Produce      json
// @Security     BearerAuth
// @Param        from  query     string  false  "YYYY-MM-DD, defaults to start of this month"
// @Param        to    query     string  false  "YYYY-MM-DD, defaults to today"
// @Success      200   {array}   BranchPeriodReport
// @Failure      403   {object}  response.Envelope  "Owners only"
// @Router       /api/v1/org/report [get]
func (h *Handler) PeriodReport(w http.ResponseWriter, r *http.Request) {
	now := time.Now()
	from := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, time.UTC)
	to := time.Date(now.Year(), now.Month(), now.Day(), 23, 59, 59, 0, time.UTC)

	if raw := strings.TrimSpace(r.URL.Query().Get("from")); raw != "" {
		t, err := time.Parse("2006-01-02", raw)
		if err != nil {
			response.BadRequest(w, "from must be YYYY-MM-DD")
			return
		}
		from = t
	}
	if raw := strings.TrimSpace(r.URL.Query().Get("to")); raw != "" {
		t, err := time.Parse("2006-01-02", raw)
		if err != nil {
			response.BadRequest(w, "to must be YYYY-MM-DD")
			return
		}
		to = time.Date(t.Year(), t.Month(), t.Day(), 23, 59, 59, 0, time.UTC)
	}

	res, err := h.svc.PeriodReport(r.Context(), from, to)
	if err != nil {
		writeErr(w, err, "period report")
		return
	}
	response.OK(w, res)
}

type transferStaffRequest struct {
	UserID  int64  `json:"user_id"`
	ToGymID int64  `json:"to_gym_id"`
	Role    string `json:"role"` // role at the destination branch
}

type transferTrainerRequest struct {
	TrainerID int64 `json:"trainer_id"`
	ToGymID   int64 `json:"to_gym_id"`
}

// TransferStaff godoc
// @Summary      Move a staff member to another branch
// @Description  Changes their home branch and grants access there. Their old branch access is kept.
// @Tags         branches
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        body  body      transferStaffRequest  true  "Transfer"
// @Success      200   {object}  response.Envelope
// @Failure      403   {object}  response.Envelope
// @Router       /api/v1/branches/transfer-staff [post]
func (h *Handler) TransferStaff(w http.ResponseWriter, r *http.Request) {
	var req transferStaffRequest
	if !decode(w, r, &req) {
		return
	}
	if req.UserID <= 0 || req.ToGymID <= 0 {
		response.BadRequest(w, "user_id and to_gym_id are required")
		return
	}
	if err := h.svc.TransferStaff(r.Context(), req.UserID, req.ToGymID, req.Role); err != nil {
		writeErr(w, err, "transfer staff")
		return
	}
	response.OK(w, map[string]string{"status": "transferred"})
}

// TransferTrainer godoc
// @Summary      Move a trainer to another branch
// @Description  PT packages already sold stay with the branch that sold them.
// @Tags         branches
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        body  body      transferTrainerRequest  true  "Transfer"
// @Success      200   {object}  response.Envelope
// @Failure      403   {object}  response.Envelope
// @Router       /api/v1/branches/transfer-trainer [post]
func (h *Handler) TransferTrainer(w http.ResponseWriter, r *http.Request) {
	var req transferTrainerRequest
	if !decode(w, r, &req) {
		return
	}
	if req.TrainerID <= 0 || req.ToGymID <= 0 {
		response.BadRequest(w, "trainer_id and to_gym_id are required")
		return
	}
	if err := h.svc.TransferTrainer(r.Context(), req.TrainerID, req.ToGymID); err != nil {
		writeErr(w, err, "transfer trainer")
		return
	}
	response.OK(w, map[string]string{"status": "transferred"})
}

type targetsRequest struct {
	MonthlyRevenueTargetInPaise int64 `json:"monthly_revenue_target_in_paise"`
	MonthlyMemberTarget         int   `json:"monthly_member_target"`
}

type transferMemberRequest struct {
	MemberID int64  `json:"member_id"`
	ToGymID  int64  `json:"to_gym_id"`
	Reason   string `json:"reason"`
}

// SetTargets godoc
// @Summary      Set a branch's monthly targets
// @Tags         branches
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        gym_id  path      int             true  "Branch"
// @Param        body    body      targetsRequest  true  "Targets"
// @Success      200     {object}  response.Envelope
// @Failure      403     {object}  response.Envelope  "Owners only, and only for branches you hold"
// @Router       /api/v1/branches/{gym_id}/targets [put]
func (h *Handler) SetTargets(w http.ResponseWriter, r *http.Request) {
	gymID, err := strconv.ParseInt(r.PathValue("gym_id"), 10, 64)
	if err != nil || gymID <= 0 {
		response.BadRequest(w, "invalid gym_id")
		return
	}
	var req targetsRequest
	if !decode(w, r, &req) {
		return
	}
	if err := h.svc.SetTargets(r.Context(), gymID, req.MonthlyRevenueTargetInPaise, req.MonthlyMemberTarget); err != nil {
		writeErr(w, err, "set targets")
		return
	}
	response.OK(w, map[string]string{"status": "saved"})
}

// TransferMember godoc
// @Summary      Move a member to another branch
// @Description  The member moves; their payments and invoices stay with the branch that issued them.
// @Tags         branches
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        body  body      transferMemberRequest  true  "Transfer"
// @Success      200   {object}  response.Envelope
// @Failure      403   {object}  response.Envelope  "No access to the destination branch"
// @Router       /api/v1/branches/transfer-member [post]
func (h *Handler) TransferMember(w http.ResponseWriter, r *http.Request) {
	var req transferMemberRequest
	if !decode(w, r, &req) {
		return
	}
	if req.MemberID <= 0 || req.ToGymID <= 0 {
		response.BadRequest(w, "member_id and to_gym_id are required")
		return
	}
	if err := h.svc.TransferMember(r.Context(), req.MemberID, req.ToGymID, req.Reason); err != nil {
		writeErr(w, err, "transfer member")
		return
	}
	response.OK(w, map[string]string{"status": "transferred"})
}

type createBranchRequest struct {
	Name       string `json:"name"`        // required — the gym's full name
	BranchName string `json:"branch_name"` // optional short label for the switcher
	City       string `json:"city"`
	State      string `json:"state"`
	Phone      string `json:"phone"`
}

type switchRequest struct {
	GymID int64 `json:"gym_id"` // required
}

type grantRequest struct {
	UserID int64  `json:"user_id"`
	GymID  int64  `json:"gym_id"`
	Role   string `json:"role"` // owner | manager | staff
}

// MyBranches godoc
// @Summary      Branches this user can work in
// @Tags         branches
// @Produce      json
// @Security     BearerAuth
// @Success      200  {array}  Branch
// @Router       /api/v1/branches [get]
func (h *Handler) MyBranches(w http.ResponseWriter, r *http.Request) {
	res, err := h.svc.MyBranches(r.Context())
	if err != nil {
		writeErr(w, err, "my branches")
		return
	}
	response.OK(w, res)
}

// Switch godoc
// @Summary      Switch to another branch
// @Description  Issues a new token scoped to that branch. Rejected unless the user holds a grant for it.
// @Tags         branches
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        body  body      switchRequest  true  "Target branch"
// @Success      200   {object}  SwitchResult
// @Failure      403   {object}  response.Envelope  "No access to that branch"
// @Router       /api/v1/branches/switch [post]
func (h *Handler) Switch(w http.ResponseWriter, r *http.Request) {
	var req switchRequest
	if !decode(w, r, &req) {
		return
	}
	if req.GymID <= 0 {
		response.BadRequest(w, "gym_id is required")
		return
	}
	res, err := h.svc.Switch(r.Context(), req.GymID)
	if err != nil {
		writeErr(w, err, "switch branch")
		return
	}
	response.OK(w, res)
}

// CreateBranch godoc
// @Summary      Add a branch to your organization
// @Tags         branches
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        body  body      createBranchRequest  true  "Branch"
// @Success      201   {object}  Branch
// @Failure      403   {object}  response.Envelope  "Owners only"
// @Router       /api/v1/branches [post]
func (h *Handler) CreateBranch(w http.ResponseWriter, r *http.Request) {
	var req createBranchRequest
	if !decode(w, r, &req) {
		return
	}
	res, err := h.svc.CreateBranch(r.Context(), req.Name, req.BranchName, req.City, req.State, req.Phone)
	if err != nil {
		writeErr(w, err, "create branch")
		return
	}
	response.Created(w, res)
}

// GrantAccess godoc
// @Summary      Give a colleague access to a branch
// @Tags         branches
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        body  body      grantRequest  true  "Grant"
// @Success      200   {object}  response.Envelope
// @Failure      403   {object}  response.Envelope
// @Router       /api/v1/branches/access [post]
func (h *Handler) GrantAccess(w http.ResponseWriter, r *http.Request) {
	var req grantRequest
	if !decode(w, r, &req) {
		return
	}
	if req.UserID <= 0 || req.GymID <= 0 {
		response.BadRequest(w, "user_id and gym_id are required")
		return
	}
	if err := h.svc.GrantAccess(r.Context(), req.UserID, req.GymID, req.Role); err != nil {
		writeErr(w, err, "grant access")
		return
	}
	response.OK(w, map[string]string{"status": "granted"})
}

// RevokeAccess godoc
// @Summary      Remove a colleague's access to a branch
// @Tags         branches
// @Produce      json
// @Security     BearerAuth
// @Param        gym_id   path  int  true  "Branch"
// @Param        user_id  path  int  true  "User"
// @Success      200  {object}  response.Envelope
// @Router       /api/v1/branches/{gym_id}/access/{user_id} [delete]
func (h *Handler) RevokeAccess(w http.ResponseWriter, r *http.Request) {
	gymID, err1 := strconv.ParseInt(r.PathValue("gym_id"), 10, 64)
	userID, err2 := strconv.ParseInt(r.PathValue("user_id"), 10, 64)
	if err1 != nil || err2 != nil || gymID <= 0 || userID <= 0 {
		response.BadRequest(w, "invalid gym_id or user_id")
		return
	}
	if err := h.svc.RevokeAccess(r.Context(), userID, gymID); err != nil {
		writeErr(w, err, "revoke access")
		return
	}
	response.OK(w, map[string]string{"status": "revoked"})
}

// ChainSummary godoc
// @Summary      Consolidated figures across your branches
// @Description  Read-only, and only for branches where you are an owner.
// @Tags         branches
// @Produce      json
// @Security     BearerAuth
// @Success      200  {array}   BranchSummary
// @Failure      403  {object}  response.Envelope  "Owners only"
// @Router       /api/v1/org/summary [get]
func (h *Handler) ChainSummary(w http.ResponseWriter, r *http.Request) {
	res, err := h.svc.ChainSummary(r.Context())
	if err != nil {
		writeErr(w, err, "chain summary")
		return
	}
	response.OK(w, res)
}

// ─── helpers ──────────────────────────────────────────────────────────────────

func decode(w http.ResponseWriter, r *http.Request, dst any) bool {
	if r.Body == nil || r.ContentLength == 0 {
		return true
	}
	if err := json.NewDecoder(r.Body).Decode(dst); err != nil {
		response.BadRequest(w, "invalid request body")
		return false
	}
	return true
}

func writeErr(w http.ResponseWriter, err error, op string) {
	switch {
	case errors.Is(err, ErrBranchNotFound):
		response.NotFound(w, err.Error())

	// Access failures are 403, not 404: the caller is authenticated, they just
	// may not go there.
	case errors.Is(err, ErrNoAccess),
		errors.Is(err, ErrNotOwner),
		errors.Is(err, ErrDifferentOrg),
		errors.Is(err, ErrUserDifferentOrg):
		response.Forbidden(w, err.Error())

	case errors.Is(err, ErrMemberNotInBranch),
		errors.Is(err, ErrUserNotFound),
		errors.Is(err, ErrTrainerNotInBranch):
		response.NotFound(w, err.Error())

	case errors.Is(err, ErrNameRequired),
		errors.Is(err, ErrCannotRevokeSelf),
		errors.Is(err, ErrSameBranch):
		response.UnprocessableEntity(w, err.Error())

	default:
		log.Printf("branches %s: %v", op, err)
		response.InternalServerError(w)
	}
}
