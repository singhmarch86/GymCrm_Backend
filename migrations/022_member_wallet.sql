-- 022_member_wallet.sql
--
-- Member wallet: stored credit against a member's account.
-- See docs/FR-08-member-wallet.md.
--
-- The balance is NEVER a directly-editable number. It is the running result of
-- an insert-only ledger, exactly like stock_movements (FR-07 §1) and
-- membership_events (FR-01): "why is my balance ₹300?" must always have an
-- answer, and a balance someone can simply type over cannot be reconciled.

CREATE TABLE IF NOT EXISTS wallet_transactions (
    id                 bigserial PRIMARY KEY,
    gym_id             bigint      NOT NULL,
    member_id          bigint      NOT NULL,

    -- Signed paise: positive adds credit, negative spends it. Storing the sign
    -- rather than inferring it from the type keeps the arithmetic honest.
    amount_in_paise    bigint      NOT NULL,
    balance_after      bigint      NOT NULL,
    transaction_type   varchar(20) NOT NULL,  -- topup|spend|refund|adjustment|expiry

    reason             text,
    -- What the credit was spent on, when it came from elsewhere in the system.
    sale_id            bigint,
    invoice_id         bigint,
    payment_id         bigint,

    created_by_user_id bigint      NOT NULL,
    created_at         timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT chk_wallet_type
        CHECK (transaction_type IN ('topup', 'spend', 'refund', 'adjustment', 'expiry')),
    CONSTRAINT chk_wallet_amount_nonzero CHECK (amount_in_paise <> 0)
);

CREATE INDEX IF NOT EXISTS idx_wallet_member ON wallet_transactions (member_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_wallet_gym ON wallet_transactions (gym_id, created_at DESC);

-- Cached running balance so the counter doesn't sum the whole ledger on every
-- lookup. Written only inside the same locked transaction that appends a
-- ledger row, so it can never drift from the rows behind it.
ALTER TABLE members ADD COLUMN IF NOT EXISTS wallet_balance_in_paise bigint NOT NULL DEFAULT 0;
