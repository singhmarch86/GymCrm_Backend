package leads

import (
	"encoding/json"
	"net/http"

	"gymcrm/internal/shared/response"
)

// ListActivities godoc
// @Summary      Get a lead's activity timeline
// @Tags         leads
// @Produce      json
// @Security     BearerAuth
// @Param        id   path      int  true  "Lead ID"
// @Success      200  {object}  ActivityListResponse
// @Router       /api/v1/leads/{id}/activities [get]
func (h *Handler) ListActivities(w http.ResponseWriter, r *http.Request) {
	id, err := pathID(r, "id")
	if err != nil {
		response.BadRequest(w, "invalid lead id")
		return
	}
	items, err := h.svc.ListActivities(r.Context(), id)
	if err != nil {
		h.handleError(w, err)
		return
	}
	response.OK(w, ActivityListResponse{Activities: items})
}

// AddActivity godoc
// @Summary      Log a call, note, follow-up or trial on a lead
// @Tags         leads
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        id    path      int                 true  "Lead ID"
// @Param        body  body      AddActivityRequest  true  "Activity"
// @Success      201   {object}  LeadActivity
// @Router       /api/v1/leads/{id}/activities [post]
func (h *Handler) AddActivity(w http.ResponseWriter, r *http.Request) {
	id, err := pathID(r, "id")
	if err != nil {
		response.BadRequest(w, "invalid lead id")
		return
	}
	var req AddActivityRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.BadRequest(w, "invalid request body")
		return
	}
	activity, err := h.svc.AddActivity(r.Context(), id, req)
	if err != nil {
		h.handleError(w, err)
		return
	}
	response.Created(w, activity)
}

// Assignees godoc
// @Summary      List gym staff who can be assigned leads
// @Tags         leads
// @Produce      json
// @Security     BearerAuth
// @Success      200  {object}  AssigneeListResponse
// @Router       /api/v1/leads/assignees [get]
func (h *Handler) Assignees(w http.ResponseWriter, r *http.Request) {
	items, err := h.svc.ListAssignees(r.Context())
	if err != nil {
		h.handleError(w, err)
		return
	}
	response.OK(w, AssigneeListResponse{Assignees: items})
}

// Assign godoc
// @Summary      Assign a lead to a staff member (or clear the assignment)
// @Tags         leads
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        id    path      int            true  "Lead ID"
// @Param        body  body      AssignRequest  true  "Assignee"
// @Success      200   {object}  LeadResponse
// @Router       /api/v1/leads/{id}/assign [patch]
func (h *Handler) Assign(w http.ResponseWriter, r *http.Request) {
	id, err := pathID(r, "id")
	if err != nil {
		response.BadRequest(w, "invalid lead id")
		return
	}
	var req AssignRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.BadRequest(w, "invalid request body")
		return
	}
	result, err := h.svc.AssignLead(r.Context(), id, req.AssignedUserID)
	if err != nil {
		h.handleError(w, err)
		return
	}
	response.OK(w, result)
}

// FollowUps godoc
// @Summary      Daily follow-up queue (overdue / today / upcoming / trials)
// @Tags         leads
// @Produce      json
// @Security     BearerAuth
// @Success      200  {object}  FollowUpResponse
// @Router       /api/v1/leads/followups [get]
func (h *Handler) FollowUps(w http.ResponseWriter, r *http.Request) {
	result, err := h.svc.GetFollowUps(r.Context())
	if err != nil {
		h.handleError(w, err)
		return
	}
	response.OK(w, result)
}

// Analytics godoc
// @Summary      Pipeline analytics — funnel, source performance, lost reasons
// @Tags         leads
// @Produce      json
// @Security     BearerAuth
// @Success      200  {object}  AnalyticsResponse
// @Router       /api/v1/leads/analytics [get]
func (h *Handler) Analytics(w http.ResponseWriter, r *http.Request) {
	result, err := h.svc.GetAnalytics(r.Context())
	if err != nil {
		h.handleError(w, err)
		return
	}
	response.OK(w, result)
}
