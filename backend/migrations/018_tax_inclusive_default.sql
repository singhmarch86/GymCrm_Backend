-- 018_tax_inclusive_default.sql
--
-- Switch the default pricing basis to tax-INCLUSIVE. See FR-04 §5.3.
--
-- Why: Indian gyms quote all-in ("₹12,000 a year") and collect exactly that.
-- Under exclusive pricing an invoice for a ₹12,000 plan totals ₹14,160, the
-- member pays the advertised ₹12,000, and the invoice reads "part paid" with
-- ₹2,160 outstanding forever — manufacturing phantom receivables across the
-- whole member base. Inclusive keeps invoice totals matching the payments
-- already recorded.
--
-- Gyms selling B2B (corporate memberships where the buyer claims input credit)
-- can still switch back per-gym; this only changes the default.

ALTER TABLE gym_billing_settings ALTER COLUMN prices_include_tax SET DEFAULT true;

-- Existing gyms that never configured this were sitting on the old default
-- rather than making a considered choice, so move them to the new one.
-- Deliberately does NOT touch invoices: issued documents snapshot their own
-- basis and must never be rewritten.
UPDATE gym_billing_settings SET prices_include_tax = true, updated_at = now()
WHERE prices_include_tax = false;
