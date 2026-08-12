package queues

import (
	"errors"
	"log"
	"net/http"

	"gymcrm/internal/shared/response"
)

// InvoiceDues godoc
// @Summary      Create draft invoices for raised dues
// @Description  One draft invoice per member, covering the dues given. Only dues already raised can be invoiced — an expiring membership is a plan price nobody has agreed to pay, so it carries no payment ID and cannot be passed here. To invoice a renewal, record the agreement first with POST /api/v1/payments/due. Nothing is issued: every invoice comes back as a draft.
// @Tags         queues
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        body  body      InvoiceDuesRequest  true  "Dues to invoice"
// @Success      200   {object}  InvoiceDuesResult
// @Router       /api/v1/queues/expected/invoice [post]
func (h *Handler) InvoiceDues(w http.ResponseWriter, r *http.Request) {
	var req InvoiceDuesRequest
	if !decode(w, r, &req) {
		return
	}

	result, err := h.svc.InvoiceDues(r.Context(), req)
	if err != nil {
		switch {
		case errors.Is(err, ErrNoPayments):
			response.BadRequest(w,
				"pick at least one raised due. Memberships that are only "+
					"expiring cannot be invoiced — record that the member "+
					"agreed and raise the due first")
		case errors.Is(err, ErrTooManyDues):
			response.BadRequest(w,
				"that is more than 50 dues in one go. Every invoice is a "+
					"document somebody answers for; do it in smaller batches")
		default:
			log.Printf("queues: invoice dues: %v", err)
			response.InternalServerError(w)
		}
		return
	}
	response.OK(w, result)
}
