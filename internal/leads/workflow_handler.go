package leads

import (
	"encoding/json"
	"net/http"
	"strings"

	"gymcrm/internal/shared/response"
)

// SetNextStepRequest is the payload for PATCH /api/v1/leads/{id}/next-step.
//
// Both fields empty clears the step. Both set records it. One without the
// other is rejected — see ErrNextStepDueRequired.
type SetNextStepRequest struct {
	Step string `json:"step"`
	Due  string `json:"due"` // YYYY-MM-DD
}

// Workflow godoc
// @Summary      The lead workflow queue — unattended first, then overdue
// @Description  Every open lead grouped by what needs doing. Groups are always
// @Description  returned, including empty ones.
// @Tags         leads
// @Produce      json
// @Security     BearerAuth
// @Param        assigned_to  query  string  false  "user id, 'unassigned', or omit for everyone"
// @Success      200  {object}  WorkflowResponse
// @Router       /api/v1/leads/workflow [get]
func (h *Handler) Workflow(w http.ResponseWriter, r *http.Request) {
	assignedTo := strings.TrimSpace(r.URL.Query().Get("assigned_to"))

	result, err := h.svc.GetWorkflow(r.Context(), assignedTo)
	if err != nil {
		h.handleError(w, err)
		return
	}
	response.OK(w, result)
}

// SetNextStep godoc
// @Summary      Record what happens next for a lead
// @Description  Send both step and due to set one, or neither to clear it.
// @Tags         leads
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        id    path  int                 true  "Lead ID"
// @Param        body  body  SetNextStepRequest  true  "Next step"
// @Success      200   {object}  LeadResponse
// @Router       /api/v1/leads/{id}/next-step [patch]
func (h *Handler) SetNextStep(w http.ResponseWriter, r *http.Request) {
	id, err := pathID(r, "id")
	if err != nil {
		response.BadRequest(w, "invalid lead id")
		return
	}

	var req SetNextStepRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.BadRequest(w, "invalid request body")
		return
	}

	result, err := h.svc.SetNextStep(
		r.Context(), id,
		strings.TrimSpace(req.Step),
		strings.TrimSpace(req.Due),
	)
	if err != nil {
		h.handleError(w, err)
		return
	}
	response.OK(w, result)
}

// NextStepOptions godoc
// @Summary      The next steps a client may set, with labels
// @Description  Served rather than hard-coded in each client so the vocabulary
// @Description  has one source. The pilot gym is expected to revise it.
// @Tags         leads
// @Produce      json
// @Security     BearerAuth
// @Success      200  {object}  map[string]interface{}
// @Router       /api/v1/leads/next-steps [get]
func (h *Handler) NextStepOptions(w http.ResponseWriter, r *http.Request) {
	type option struct {
		Step  string `json:"step"`
		Label string `json:"label"`
	}
	out := make([]option, 0, len(AllNextSteps))
	for _, s := range AllNextSteps {
		out = append(out, option{Step: string(s), Label: s.Label()})
	}
	response.OK(w, map[string]interface{}{"next_steps": out})
}
