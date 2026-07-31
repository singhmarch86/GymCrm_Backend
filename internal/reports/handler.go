package reports

import (
	"log"
	"net/http"

	"gymcrm/internal/shared/response"
)

type Handler struct {
	svc *Service
}

func NewHandler(svc *Service) *Handler {
	return &Handler{svc: svc}
}

func (h *Handler) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("GET /api/v1/reports/revenue",  h.Revenue)
	mux.HandleFunc("GET /api/v1/reports/members",  h.Members)
	mux.HandleFunc("GET /api/v1/reports/payments", h.Payments)
	mux.HandleFunc("GET /api/v1/reports/renewals", h.Renewals)
	mux.HandleFunc("GET /api/v1/reports/plans",    h.Plans)
}

// Revenue godoc
// @Summary      Revenue analytics
// @Tags         reports
// @Produce      json
// @Security     BearerAuth
// @Success      200  {object}  RevenueReport
// @Router       /api/v1/reports/revenue [get]
func (h *Handler) Revenue(w http.ResponseWriter, r *http.Request) {
	data, err := h.svc.GetRevenueReport(r.Context())
	if err != nil {
		log.Printf("ERROR reports/revenue: %v", err)
		response.InternalServerError(w)
		return
	}
	response.OK(w, data)
}

// Members godoc
// @Summary      Member analytics
// @Tags         reports
// @Produce      json
// @Security     BearerAuth
// @Success      200  {object}  MemberReport
// @Router       /api/v1/reports/members [get]
func (h *Handler) Members(w http.ResponseWriter, r *http.Request) {
	data, err := h.svc.GetMemberReport(r.Context())
	if err != nil {
		log.Printf("ERROR reports/members: %v", err)
		response.InternalServerError(w)
		return
	}
	response.OK(w, data)
}

// Payments godoc
// @Summary      Payment analytics
// @Tags         reports
// @Produce      json
// @Security     BearerAuth
// @Success      200  {object}  PaymentReport
// @Router       /api/v1/reports/payments [get]
func (h *Handler) Payments(w http.ResponseWriter, r *http.Request) {
	data, err := h.svc.GetPaymentReport(r.Context())
	if err != nil {
		log.Printf("ERROR reports/payments: %v", err)
		response.InternalServerError(w)
		return
	}
	response.OK(w, data)
}

// Renewals godoc
// @Summary      Renewal analytics
// @Tags         reports
// @Produce      json
// @Security     BearerAuth
// @Success      200  {object}  RenewalReport
// @Router       /api/v1/reports/renewals [get]
func (h *Handler) Renewals(w http.ResponseWriter, r *http.Request) {
	data, err := h.svc.GetRenewalReport(r.Context())
	if err != nil {
		log.Printf("ERROR reports/renewals: %v", err)
		response.InternalServerError(w)
		return
	}
	response.OK(w, data)
}

// Plans godoc
// @Summary      Plan analytics
// @Tags         reports
// @Produce      json
// @Security     BearerAuth
// @Success      200  {object}  PlanReport
// @Router       /api/v1/reports/plans [get]
func (h *Handler) Plans(w http.ResponseWriter, r *http.Request) {
	data, err := h.svc.GetPlanReport(r.Context())
	if err != nil {
		log.Printf("ERROR reports/plans: %v", err)
		response.InternalServerError(w)
		return
	}
	response.OK(w, data)
}
