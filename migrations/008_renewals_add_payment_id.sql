-- Migration 008: link renewals to the payment that funded them
--
-- Adds a nullable renewals.payment_id FK pointing at payments.id.
-- This is the ONLY change made to the renewals table or its surrounding
-- module in Sprint 4. The Go code in internal/renewals/{model,repository,
-- service,handler}.go is intentionally left untouched — per Sprint 4
-- instructions, that module's architecture is not to be rewritten.
--
-- Practical effect of leaving the Go code alone: this column exists in the
-- database and is correctly populated by internal/payments/repository.go's
-- CollectPayment transaction, but it will NOT appear in any response from
-- the existing renewals API (GET /api/v1/renewals, GET /api/v1/renewals/{id},
-- etc.) until someone adds PaymentID to renewals.Renewal and renewals.dto.go's
-- RenewalResponse in a future, deliberate change to that module. Until then,
-- the only way to see which payment funded a renewal is via the payments
-- side: GET /api/v1/payments/{id} or GET /api/v1/members/{id}/payments,
-- which already carry the renewal's effects (new expiry date) without
-- needing renewals.payment_id at all.
--
-- Nullable because:
--   - Historical renewals created before this migration have no payment row
--   - Future renewal paths that don't originate from Collect Payment
--     (if any are ever added) aren't required to create a payment

ALTER TABLE renewals
    ADD COLUMN payment_id BIGINT REFERENCES payments(id);

CREATE INDEX idx_renewals_payment
    ON renewals (payment_id)
    WHERE payment_id IS NOT NULL;
