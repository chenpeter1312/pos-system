-- ==========================================
-- 添加 Stripe 相關字段到 orders 表
-- ==========================================

-- 添加 Stripe Session ID（用於追蹤付款）
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'orders' AND column_name = 'stripe_session_id'
    ) THEN
        ALTER TABLE orders ADD COLUMN stripe_session_id TEXT;
        COMMENT ON COLUMN orders.stripe_session_id IS 'Stripe Checkout Session ID';
        CREATE INDEX IF NOT EXISTS idx_orders_stripe_session ON orders(stripe_session_id);
    END IF;
END $$;

-- 添加 Stripe Payment Intent ID
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'orders' AND column_name = 'stripe_payment_intent'
    ) THEN
        ALTER TABLE orders ADD COLUMN stripe_payment_intent TEXT;
        COMMENT ON COLUMN orders.stripe_payment_intent IS 'Stripe Payment Intent ID';
    END IF;
END $$;

-- 驗證
SELECT
    column_name,
    data_type,
    is_nullable
FROM information_schema.columns
WHERE table_name = 'orders'
AND column_name IN ('stripe_session_id', 'stripe_payment_intent');
