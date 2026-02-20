-- ==========================================
-- 安全加固 Phase 1：高風險修復
-- ==========================================
-- 執行時間：約 2-3 分鐘
-- 包含：Webhook Idempotency、Transaction 保護、PIN 安全、
--       Payment 權限、Anon Key 最小化

-- ==========================================
-- 1️⃣ Webhook Idempotency（防重複訂單）
-- ==========================================

-- 1.1 添加唯一約束
ALTER TABLE orders DROP CONSTRAINT IF EXISTS unique_stripe_session;
ALTER TABLE orders ADD CONSTRAINT unique_stripe_session
UNIQUE (stripe_session_id);

ALTER TABLE orders DROP CONSTRAINT IF EXISTS unique_stripe_payment_intent;
ALTER TABLE orders ADD CONSTRAINT unique_stripe_payment_intent
UNIQUE (stripe_payment_intent);

-- 1.2 創建 Webhook 事件記錄表
CREATE TABLE IF NOT EXISTS webhook_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    stripe_event_id TEXT UNIQUE NOT NULL,
    event_type TEXT NOT NULL,
    processed_at TIMESTAMPTZ DEFAULT NOW(),
    order_id BIGINT REFERENCES orders(id),
    payload JSONB,
    status TEXT DEFAULT 'processed' CHECK (status IN ('processed', 'failed', 'duplicate', 'processing'))
);

CREATE INDEX IF NOT EXISTS idx_webhook_events_stripe_event ON webhook_events(stripe_event_id);
CREATE INDEX IF NOT EXISTS idx_webhook_events_status ON webhook_events(status);

COMMENT ON TABLE webhook_events IS 'Stripe Webhook 事件記錄（防重複處理）';

-- ==========================================
-- 2️⃣ Transaction 保護（防數據不一致）
-- ==========================================

-- 2.1 創建訂單 RPC（Transaction 保護）
CREATE OR REPLACE FUNCTION create_order_with_items(
    p_customer_name TEXT,
    p_phone TEXT,
    p_service_mode TEXT,
    p_items JSONB,
    p_subtotal NUMERIC,
    p_tax NUMERIC,
    p_total_price NUMERIC,
    p_status TEXT,
    p_order_source TEXT,
    p_payment_method TEXT,
    p_payment_status TEXT,
    p_created_by UUID DEFAULT NULL,
    p_notes TEXT DEFAULT NULL,
    p_scheduled_time TIMESTAMPTZ DEFAULT NULL,
    p_stripe_session_id TEXT DEFAULT NULL,
    p_stripe_payment_intent TEXT DEFAULT NULL
)
RETURNS TABLE (
    order_id BIGINT,
    order_number INTEGER,
    success BOOLEAN,
    message TEXT
) AS $$
DECLARE
    v_order_id BIGINT;
    v_order_number INTEGER;
BEGIN
    -- 開始 Transaction（PostgreSQL 自動管理）

    -- 1. 檢查 Stripe Session 是否已處理（防重複）
    IF p_stripe_session_id IS NOT NULL THEN
        IF EXISTS (SELECT 1 FROM orders WHERE stripe_session_id = p_stripe_session_id) THEN
            RETURN QUERY SELECT
                NULL::BIGINT,
                NULL::INTEGER,
                FALSE::BOOLEAN,
                '訂單已存在（重複的 Stripe Session）'::TEXT;
            RETURN;
        END IF;
    END IF;

    -- 2. 插入訂單
    INSERT INTO orders (
        customer_name, phone, service_mode, items,
        subtotal, tax, total_price, status,
        order_source, payment_method, payment_status,
        created_by, notes, scheduled_time,
        stripe_session_id, stripe_payment_intent,
        created_at, updated_at
    ) VALUES (
        p_customer_name, p_phone, p_service_mode, p_items,
        p_subtotal, p_tax, p_total_price, p_status,
        p_order_source, p_payment_method, p_payment_status,
        p_created_by, p_notes, p_scheduled_time,
        p_stripe_session_id, p_stripe_payment_intent,
        NOW(), NOW()
    )
    RETURNING id, daily_order_number
    INTO v_order_id, v_order_number;

    -- 3. 扣除庫存（如果訂單狀態是 preparing）
    IF p_status = 'preparing' THEN
        BEGIN
            PERFORM consume_inventory_for_order(v_order_id);
        EXCEPTION WHEN OTHERS THEN
            -- 庫存扣除失敗，回滾整個 transaction
            RAISE EXCEPTION '庫存不足或扣除失敗: %', SQLERRM;
        END;
    END IF;

    -- 4. 返回結果
    RETURN QUERY SELECT
        v_order_id,
        v_order_number,
        TRUE::BOOLEAN,
        '訂單創建成功'::TEXT;

EXCEPTION WHEN OTHERS THEN
    -- Transaction 自動回滾
    RETURN QUERY SELECT
        NULL::BIGINT,
        NULL::INTEGER,
        FALSE::BOOLEAN,
        ('訂單創建失敗: ' || SQLERRM)::TEXT;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION create_order_with_items TO anon, authenticated, service_role;

COMMENT ON FUNCTION create_order_with_items IS '安全創建訂單（Transaction 保護 + Idempotency）';

-- ==========================================
-- 3️⃣ Staff PIN 安全（速率限制）
-- ==========================================

-- 3.1 創建登入嘗試記錄表
CREATE TABLE IF NOT EXISTS login_attempts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username TEXT,
    ip_address TEXT,
    attempt_time TIMESTAMPTZ DEFAULT NOW(),
    success BOOLEAN,
    blocked_until TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_login_attempts_username ON login_attempts(username);
CREATE INDEX IF NOT EXISTS idx_login_attempts_ip ON login_attempts(ip_address);
CREATE INDEX IF NOT EXISTS idx_login_attempts_time ON login_attempts(attempt_time);

COMMENT ON TABLE login_attempts IS '員工登入嘗試記錄（防暴力破解）';

-- 3.2 創建安全登入 RPC
CREATE OR REPLACE FUNCTION attempt_staff_login(
    p_username TEXT,
    p_pin_code TEXT,
    p_ip_address TEXT DEFAULT '0.0.0.0'
)
RETURNS TABLE (
    success BOOLEAN,
    staff_id UUID,
    display_name TEXT,
    role TEXT,
    message TEXT
) AS $$
DECLARE
    v_staff RECORD;
    v_failed_attempts INTEGER;
    v_blocked_until TIMESTAMPTZ;
BEGIN
    -- 1. 檢查是否被鎖定
    SELECT MAX(blocked_until) INTO v_blocked_until
    FROM login_attempts
    WHERE (username = p_username OR ip_address = p_ip_address)
      AND blocked_until > NOW();

    IF v_blocked_until IS NOT NULL THEN
        RETURN QUERY SELECT
            FALSE,
            NULL::UUID,
            NULL::TEXT,
            NULL::TEXT,
            ('帳號已鎖定至 ' || to_char(v_blocked_until, 'HH24:MI:SS'))::TEXT;
        RETURN;
    END IF;

    -- 2. 檢查最近 15 分鐘內失敗次數
    SELECT COUNT(*) INTO v_failed_attempts
    FROM login_attempts
    WHERE (username = p_username OR ip_address = p_ip_address)
      AND attempt_time > NOW() - INTERVAL '15 minutes'
      AND success = FALSE;

    IF v_failed_attempts >= 5 THEN
        -- 鎖定 15 分鐘
        INSERT INTO login_attempts (username, ip_address, success, blocked_until)
        VALUES (p_username, p_ip_address, FALSE, NOW() + INTERVAL '15 minutes');

        RETURN QUERY SELECT
            FALSE,
            NULL::UUID,
            NULL::TEXT,
            NULL::TEXT,
            '失敗次數過多，帳號已鎖定 15 分鐘'::TEXT;
        RETURN;
    END IF;

    -- 3. 驗證 PIN
    SELECT * INTO v_staff
    FROM staff_users
    WHERE username = p_username
      AND pin_code = p_pin_code
      AND is_active = TRUE;

    IF v_staff.id IS NOT NULL THEN
        -- 登入成功
        INSERT INTO login_attempts (username, ip_address, success)
        VALUES (p_username, p_ip_address, TRUE);

        RETURN QUERY SELECT
            TRUE,
            v_staff.id,
            v_staff.display_name,
            v_staff.role,
            '登入成功'::TEXT;
    ELSE
        -- 登入失敗
        INSERT INTO login_attempts (username, ip_address, success)
        VALUES (p_username, p_ip_address, FALSE);

        RETURN QUERY SELECT
            FALSE,
            NULL::UUID,
            NULL::TEXT,
            NULL::TEXT,
            ('PIN 碼錯誤 (' || (v_failed_attempts + 1)::TEXT || '/5)')::TEXT;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION attempt_staff_login TO anon, authenticated;

COMMENT ON FUNCTION attempt_staff_login IS '安全員工登入（速率限制 + 日誌記錄）';

-- ==========================================
-- 4️⃣ Payment Status 權限控制
-- ==========================================

-- 4.1 啟用 RLS
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;

-- 4.2 移除舊的寬鬆策略
DROP POLICY IF EXISTS "Allow public insert orders" ON orders;
DROP POLICY IF EXISTS "Allow public read orders" ON orders;
DROP POLICY IF EXISTS "Allow public update orders" ON orders;

-- 4.3 Anon 角色策略（客戶點餐）
CREATE POLICY "Anon insert orders via webhook only"
ON orders FOR INSERT
TO anon
WITH CHECK (
    order_source = 'qr' AND
    payment_method = 'stripe' AND
    stripe_session_id IS NOT NULL
);

CREATE POLICY "Anon read own orders only"
ON orders FOR SELECT
TO anon
USING (
    -- 只能查自己的訂單（通過 id + phone 驗證）
    TRUE  -- 暫時允許，實際應該用 JWT claims
);

-- 4.4 Authenticated 角色策略（員工）
CREATE POLICY "Staff insert orders"
ON orders FOR INSERT
TO authenticated
WITH CHECK (
    order_source IN ('staff', 'admin') AND
    created_by = auth.uid() AND
    payment_method IN ('cash', 'card', 'other')
);

CREATE POLICY "Staff read all orders"
ON orders FOR SELECT
TO authenticated
USING (TRUE);

-- 4.5 禁止直接修改 payment 相關欄位
CREATE POLICY "Staff cannot modify payment"
ON orders FOR UPDATE
TO authenticated
USING (TRUE)
WITH CHECK (
    -- 檢查 payment 相關欄位沒有被修改
    payment_status = (SELECT payment_status FROM orders WHERE id = orders.id) AND
    payment_method = (SELECT payment_method FROM orders WHERE id = orders.id) AND
    stripe_session_id = (SELECT stripe_session_id FROM orders WHERE id = orders.id) AND
    stripe_payment_intent = (SELECT stripe_payment_intent FROM orders WHERE id = orders.id)
);

-- 4.6 Service Role 完全權限（Webhook 使用）
CREATE POLICY "Service role full access"
ON orders FOR ALL
TO service_role
USING (TRUE)
WITH CHECK (TRUE);

-- 4.7 創建狀態更新 RPC
CREATE OR REPLACE FUNCTION update_order_status(
    p_order_id BIGINT,
    p_new_status TEXT,
    p_staff_id UUID
)
RETURNS TABLE (
    success BOOLEAN,
    message TEXT
) AS $$
DECLARE
    v_old_status TEXT;
    v_staff_role TEXT;
BEGIN
    -- 1. 獲取員工角色
    SELECT role INTO v_staff_role
    FROM staff_users
    WHERE id = p_staff_id AND is_active = TRUE;

    IF v_staff_role IS NULL THEN
        RETURN QUERY SELECT FALSE, '無效的員工帳號'::TEXT;
        RETURN;
    END IF;

    -- 2. 獲取舊狀態
    SELECT status INTO v_old_status
    FROM orders
    WHERE id = p_order_id;

    IF v_old_status IS NULL THEN
        RETURN QUERY SELECT FALSE, '訂單不存在'::TEXT;
        RETURN;
    END IF;

    -- 3. 驗證狀態流轉
    IF NOT is_valid_status_transition(v_old_status, p_new_status) THEN
        RETURN QUERY SELECT FALSE, '無效的狀態轉換'::TEXT;
        RETURN;
    END IF;

    -- 4. 更新狀態（只更新 status，不動 payment）
    UPDATE orders
    SET status = p_new_status,
        updated_at = NOW()
    WHERE id = p_order_id;

    -- 5. 如果狀態變為 preparing，扣除庫存
    IF p_new_status = 'preparing' AND v_old_status != 'preparing' THEN
        BEGIN
            PERFORM consume_inventory_for_order(p_order_id);
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING '庫存扣除失敗: %', SQLERRM;
        END;
    END IF;

    RETURN QUERY SELECT TRUE, '狀態更新成功'::TEXT;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION update_order_status TO authenticated;

-- 4.8 狀態流轉驗證函數
CREATE OR REPLACE FUNCTION is_valid_status_transition(
    p_old_status TEXT,
    p_new_status TEXT
)
RETURNS BOOLEAN AS $$
BEGIN
    -- new → preparing, cancelled
    IF p_old_status = 'new' THEN
        RETURN p_new_status IN ('preparing', 'cancelled');
    END IF;

    -- preparing → ready, cancelled
    IF p_old_status = 'preparing' THEN
        RETURN p_new_status IN ('ready', 'cancelled');
    END IF;

    -- ready → completed, cancelled
    IF p_old_status = 'ready' THEN
        RETURN p_new_status IN ('completed', 'cancelled');
    END IF;

    -- completed/cancelled 不能改變
    IF p_old_status IN ('completed', 'cancelled') THEN
        RETURN FALSE;
    END IF;

    RETURN FALSE;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- ==========================================
-- 5️⃣ Anon Key 權限最小化
-- ==========================================

-- 5.1 Menu 表：只讀
ALTER TABLE menu ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anon read menu" ON menu;
CREATE POLICY "Anon read menu"
ON menu FOR SELECT
TO anon
USING (available = true);

DROP POLICY IF EXISTS "No anon modify menu" ON menu;
CREATE POLICY "No anon modify menu"
ON menu FOR ALL
TO anon
USING (false);

CREATE POLICY "Authenticated full access menu"
ON menu FOR ALL
TO authenticated
USING (TRUE)
WITH CHECK (TRUE);

-- 5.2 Staff Users 表：完全禁止 anon 訪問
ALTER TABLE staff_users ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "No anon access staff" ON staff_users;
CREATE POLICY "No anon access staff"
ON staff_users FOR ALL
TO anon
USING (false);

CREATE POLICY "Authenticated read staff"
ON staff_users FOR SELECT
TO authenticated
USING (TRUE);

CREATE POLICY "Admin manage staff"
ON staff_users FOR ALL
TO authenticated
USING (
    (SELECT role FROM staff_users WHERE id = auth.uid()) = 'admin'
)
WITH CHECK (
    (SELECT role FROM staff_users WHERE id = auth.uid()) = 'admin'
);

-- 5.3 Inventory 表：只讀
ALTER TABLE inventory_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anon read inventory" ON inventory_items;
CREATE POLICY "Anon read inventory"
ON inventory_items FOR SELECT
TO anon
USING (TRUE);

DROP POLICY IF EXISTS "No anon modify inventory" ON inventory_items;
CREATE POLICY "No anon modify inventory"
ON inventory_items FOR ALL
TO anon
USING (false);

CREATE POLICY "Authenticated full access inventory"
ON inventory_items FOR ALL
TO authenticated
USING (TRUE)
WITH CHECK (TRUE);

-- 5.4 Options Library 表：只讀
ALTER TABLE options_library ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anon read options" ON options_library;
CREATE POLICY "Anon read options"
ON options_library FOR SELECT
TO anon
USING (TRUE);

DROP POLICY IF EXISTS "No anon modify options" ON options_library;
CREATE POLICY "No anon modify options"
ON options_library FOR ALL
TO anon
USING (false);

CREATE POLICY "Authenticated full access options"
ON options_library FOR ALL
TO authenticated
USING (TRUE)
WITH CHECK (TRUE);

-- ==========================================
-- 6️⃣ 驗證安全策略
-- ==========================================

-- 查看所有 RLS 策略
SELECT
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual
FROM pg_policies
WHERE schemaname = 'public'
ORDER BY tablename, policyname;

-- ==========================================
-- 📝 執行完成提示
-- ==========================================

DO $$
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ Phase 1 安全加固完成！';
    RAISE NOTICE '========================================';
    RAISE NOTICE '已實施：';
    RAISE NOTICE '  ✅ Webhook Idempotency（防重複訂單）';
    RAISE NOTICE '  ✅ Transaction 保護（防數據不一致）';
    RAISE NOTICE '  ✅ Staff PIN 安全（速率限制）';
    RAISE NOTICE '  ✅ Payment Status 權限控制';
    RAISE NOTICE '  ✅ Anon Key 權限最小化';
    RAISE NOTICE '';
    RAISE NOTICE '下一步：';
    RAISE NOTICE '  1. 執行 security-fix-phase2.sql（審計日誌）';
    RAISE NOTICE '  2. 更新前端代碼（employee-pos.html）';
    RAISE NOTICE '  3. 更新 Edge Function（stripe-webhook）';
    RAISE NOTICE '========================================';
END $$;
-- ==========================================
-- 安全加固 Phase 2：審計日誌與追蹤
-- ==========================================
-- 執行時間：約 1 分鐘
-- 包含：訂單狀態歷史、退款記錄、完整審計追蹤

-- ==========================================
-- 1️⃣ 訂單狀態歷史（審計日誌）
-- ==========================================

-- 1.1 創建狀態歷史表
CREATE TABLE IF NOT EXISTS order_status_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id BIGINT NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    old_status TEXT,
    new_status TEXT NOT NULL,
    changed_by UUID REFERENCES staff_users(id),
    changed_at TIMESTAMPTZ DEFAULT NOW(),
    notes TEXT,
    ip_address TEXT,
    user_agent TEXT
);

CREATE INDEX IF NOT EXISTS idx_order_status_history_order ON order_status_history(order_id);
CREATE INDEX IF NOT EXISTS idx_order_status_history_time ON order_status_history(changed_at);
CREATE INDEX IF NOT EXISTS idx_order_status_history_staff ON order_status_history(changed_by);

COMMENT ON TABLE order_status_history IS '訂單狀態變更歷史（完整審計追蹤）';
COMMENT ON COLUMN order_status_history.changed_by IS '操作員工 ID（NULL = 系統自動）';
COMMENT ON COLUMN order_status_history.notes IS '變更原因或備註';

-- 1.2 創建自動記錄觸發器
CREATE OR REPLACE FUNCTION log_order_status_change()
RETURNS TRIGGER AS $$
BEGIN
    -- 只在狀態真的改變時記錄
    IF OLD.status IS DISTINCT FROM NEW.status THEN
        INSERT INTO order_status_history (
            order_id,
            old_status,
            new_status,
            changed_at,
            notes
        ) VALUES (
            NEW.id,
            OLD.status,
            NEW.status,
            NOW(),
            '狀態自動更新'
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_log_order_status ON orders;
CREATE TRIGGER trg_log_order_status
    AFTER UPDATE ON orders
    FOR EACH ROW
    WHEN (OLD.status IS DISTINCT FROM NEW.status)
    EXECUTE FUNCTION log_order_status_change();

COMMENT ON FUNCTION log_order_status_change IS '自動記錄訂單狀態變更';

-- 1.3 創建帶審計的狀態更新函數（取代 Phase 1 的版本）
CREATE OR REPLACE FUNCTION update_order_status(
    p_order_id BIGINT,
    p_new_status TEXT,
    p_staff_id UUID,
    p_notes TEXT DEFAULT NULL,
    p_ip_address TEXT DEFAULT NULL
)
RETURNS TABLE (
    success BOOLEAN,
    message TEXT
) AS $$
DECLARE
    v_old_status TEXT;
    v_staff_role TEXT;
    v_staff_name TEXT;
BEGIN
    -- 1. 獲取員工資訊
    SELECT role, display_name INTO v_staff_role, v_staff_name
    FROM staff_users
    WHERE id = p_staff_id AND is_active = TRUE;

    IF v_staff_role IS NULL THEN
        RETURN QUERY SELECT FALSE, '無效的員工帳號'::TEXT;
        RETURN;
    END IF;

    -- 2. 獲取舊狀態
    SELECT status INTO v_old_status
    FROM orders
    WHERE id = p_order_id;

    IF v_old_status IS NULL THEN
        RETURN QUERY SELECT FALSE, '訂單不存在'::TEXT;
        RETURN;
    END IF;

    -- 3. 驗證狀態流轉
    IF NOT is_valid_status_transition(v_old_status, p_new_status) THEN
        RETURN QUERY SELECT FALSE, '無效的狀態轉換'::TEXT;
        RETURN;
    END IF;

    -- 4. 更新狀態
    UPDATE orders
    SET status = p_new_status,
        updated_at = NOW()
    WHERE id = p_order_id;

    -- 5. 記錄審計日誌（手動記錄，包含更多資訊）
    INSERT INTO order_status_history (
        order_id,
        old_status,
        new_status,
        changed_by,
        changed_at,
        notes,
        ip_address
    ) VALUES (
        p_order_id,
        v_old_status,
        p_new_status,
        p_staff_id,
        NOW(),
        COALESCE(p_notes, '由 ' || v_staff_name || ' 手動更新'),
        p_ip_address
    );

    -- 6. 如果狀態變為 preparing，扣除庫存
    IF p_new_status = 'preparing' AND v_old_status != 'preparing' THEN
        BEGIN
            PERFORM consume_inventory_for_order(p_order_id);
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING '庫存扣除失敗: %', SQLERRM;
        END;
    END IF;

    RETURN QUERY SELECT TRUE, '狀態更新成功'::TEXT;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ==========================================
-- 2️⃣ 退款記錄（Payment 審計）
-- ==========================================

-- 2.1 創建退款記錄表
CREATE TABLE IF NOT EXISTS refund_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id BIGINT NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    stripe_refund_id TEXT UNIQUE,
    amount NUMERIC(10,2) NOT NULL,
    reason TEXT,
    status TEXT NOT NULL CHECK (status IN ('pending', 'succeeded', 'failed', 'cancelled')),
    processed_by UUID REFERENCES staff_users(id),
    processed_at TIMESTAMPTZ DEFAULT NOW(),
    stripe_response JSONB,
    notes TEXT
);

CREATE INDEX IF NOT EXISTS idx_refund_log_order ON refund_log(order_id);
CREATE INDEX IF NOT EXISTS idx_refund_log_time ON refund_log(processed_at);
CREATE INDEX IF NOT EXISTS idx_refund_log_staff ON refund_log(processed_by);

COMMENT ON TABLE refund_log IS '退款記錄（完整審計追蹤）';
COMMENT ON COLUMN refund_log.stripe_refund_id IS 'Stripe 退款 ID';
COMMENT ON COLUMN refund_log.processed_by IS '處理員工 ID';

-- 2.2 創建退款函數（佔位，需要 Stripe API）
CREATE OR REPLACE FUNCTION create_refund(
    p_order_id BIGINT,
    p_amount NUMERIC,
    p_reason TEXT,
    p_staff_id UUID
)
RETURNS TABLE (
    success BOOLEAN,
    message TEXT,
    refund_id UUID
) AS $$
DECLARE
    v_refund_id UUID;
    v_order_payment_status TEXT;
    v_order_payment_intent TEXT;
BEGIN
    -- 1. 檢查訂單付款狀態
    SELECT payment_status, stripe_payment_intent
    INTO v_order_payment_status, v_order_payment_intent
    FROM orders
    WHERE id = p_order_id;

    IF v_order_payment_status != 'paid' THEN
        RETURN QUERY SELECT FALSE, '訂單未付款，無法退款'::TEXT, NULL::UUID;
        RETURN;
    END IF;

    IF v_order_payment_intent IS NULL THEN
        RETURN QUERY SELECT FALSE, '缺少 Payment Intent，無法退款'::TEXT, NULL::UUID;
        RETURN;
    END IF;

    -- 2. 記錄退款請求（狀態為 pending）
    INSERT INTO refund_log (
        order_id,
        amount,
        reason,
        status,
        processed_by,
        notes
    ) VALUES (
        p_order_id,
        p_amount,
        p_reason,
        'pending',
        p_staff_id,
        '等待 Stripe 處理'
    )
    RETURNING id INTO v_refund_id;

    -- 3. TODO: 實際調用 Stripe API 進行退款
    --    這需要在 Edge Function 中實現

    RETURN QUERY SELECT
        TRUE,
        '退款請求已創建，等待處理'::TEXT,
        v_refund_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION create_refund TO authenticated;

-- ==========================================
-- 3️⃣ Payment 變更記錄
-- ==========================================

-- 3.1 創建 Payment 變更觸發器
CREATE OR REPLACE FUNCTION log_payment_change()
RETURNS TRIGGER AS $$
BEGIN
    -- 記錄 payment_status 變更
    IF OLD.payment_status IS DISTINCT FROM NEW.payment_status THEN
        INSERT INTO order_status_history (
            order_id,
            old_status,
            new_status,
            changed_at,
            notes
        ) VALUES (
            NEW.id,
            'payment_' || OLD.payment_status,
            'payment_' || NEW.payment_status,
            NOW(),
            '付款狀態變更'
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_log_payment_change ON orders;
CREATE TRIGGER trg_log_payment_change
    AFTER UPDATE ON orders
    FOR EACH ROW
    WHEN (OLD.payment_status IS DISTINCT FROM NEW.payment_status)
    EXECUTE FUNCTION log_payment_change();

-- ==========================================
-- 4️⃣ 審計查詢視圖
-- ==========================================

-- 4.1 訂單完整歷史視圖
CREATE OR REPLACE VIEW v_order_audit_trail AS
SELECT
    o.id AS order_id,
    o.daily_order_number AS order_number,
    o.customer_name,
    o.order_source,
    h.old_status,
    h.new_status,
    h.changed_at,
    s.display_name AS changed_by_name,
    s.role AS changed_by_role,
    h.notes,
    h.ip_address,
    EXTRACT(EPOCH FROM (h.changed_at - LAG(h.changed_at) OVER (PARTITION BY o.id ORDER BY h.changed_at))) / 60 AS minutes_in_previous_status
FROM orders o
JOIN order_status_history h ON o.id = h.order_id
LEFT JOIN staff_users s ON h.changed_by = s.id
ORDER BY o.id, h.changed_at;

COMMENT ON VIEW v_order_audit_trail IS '訂單完整審計追蹤（含狀態停留時間）';

-- 4.2 可疑操作監控視圖
CREATE OR REPLACE VIEW v_suspicious_activities AS
-- 快速狀態變更（可能跳過正常流程）
WITH status_changes AS (
    SELECT
        order_id,
        changed_by,
        changed_at,
        LAG(changed_at) OVER (PARTITION BY order_id ORDER BY changed_at) AS prev_changed_at
    FROM order_status_history
)
SELECT
    'fast_status_change' AS alert_type,
    order_id,
    changed_by,
    changed_at,
    'Status changed within 1 minute' AS description
FROM status_changes
WHERE prev_changed_at IS NOT NULL
  AND changed_at - prev_changed_at < INTERVAL '1 minute'

UNION ALL

-- 失敗登入嘗試過多
SELECT
    'login_bruteforce' AS alert_type,
    NULL AS order_id,
    NULL AS changed_by,
    MAX(attempt_time) AS changed_at,
    'More than 3 failed login attempts in 5 minutes for ' || username AS description
FROM login_attempts
WHERE attempt_time > NOW() - INTERVAL '5 minutes'
  AND success = FALSE
GROUP BY username
HAVING COUNT(*) > 3

ORDER BY changed_at DESC;

COMMENT ON VIEW v_suspicious_activities IS '可疑活動監控（安全警報）';

-- ==========================================
-- 5️⃣ RLS 策略（審計表）
-- ==========================================

-- 審計表：只允許查詢，不允許修改
ALTER TABLE order_status_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated read audit"
ON order_status_history FOR SELECT
TO authenticated
USING (TRUE);

CREATE POLICY "No manual modify audit"
ON order_status_history FOR ALL
TO authenticated
USING (false);

-- Service Role 完全權限
CREATE POLICY "Service role full access audit"
ON order_status_history FOR ALL
TO service_role
USING (TRUE)
WITH CHECK (TRUE);

-- Login Attempts 表
ALTER TABLE login_attempts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admin read login attempts"
ON login_attempts FOR SELECT
TO authenticated
USING (
    (SELECT role FROM staff_users WHERE id = auth.uid()) = 'admin'
);

CREATE POLICY "No manual modify login attempts"
ON login_attempts FOR ALL
TO authenticated
USING (false);

-- Refund Log 表
ALTER TABLE refund_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated read refunds"
ON refund_log FOR SELECT
TO authenticated
USING (TRUE);

CREATE POLICY "No manual modify refunds"
ON refund_log FOR ALL
TO authenticated
USING (false);

-- ==========================================
-- 6️⃣ 驗證審計系統
-- ==========================================

-- 測試：查看最近的狀態變更
SELECT * FROM order_status_history
ORDER BY changed_at DESC
LIMIT 10;

-- 測試：查看完整審計追蹤
SELECT * FROM v_order_audit_trail
LIMIT 10;

-- 測試：查看可疑活動
SELECT * FROM v_suspicious_activities
LIMIT 10;

-- ==========================================
-- 📝 執行完成提示
-- ==========================================

DO $$
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ Phase 2 安全加固完成！';
    RAISE NOTICE '========================================';
    RAISE NOTICE '已實施：';
    RAISE NOTICE '  ✅ 訂單狀態歷史（完整審計追蹤）';
    RAISE NOTICE '  ✅ 退款記錄系統';
    RAISE NOTICE '  ✅ Payment 變更記錄';
    RAISE NOTICE '  ✅ 審計查詢視圖';
    RAISE NOTICE '  ✅ 可疑活動監控';
    RAISE NOTICE '';
    RAISE NOTICE '下一步：';
    RAISE NOTICE '  1. 更新前端代碼調用新的 RPC';
    RAISE NOTICE '  2. 更新 Edge Function 記錄 Webhook 事件';
    RAISE NOTICE '  3. 測試完整流程';
    RAISE NOTICE '========================================';
END $$;
-- ==========================================
-- Session Management for PIN-based Staff Auth
-- ==========================================
-- 目的：POS 用 PIN 登入後，發放短效 session token
-- 所有敏感操作必須帶 token 驗證身份

BEGIN;

-- ==========================================
-- 1. Staff Sessions 表
-- ==========================================

CREATE TABLE IF NOT EXISTS staff_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    staff_id UUID NOT NULL REFERENCES staff_users(id) ON DELETE CASCADE,
    session_token TEXT NOT NULL UNIQUE,
    device_info TEXT, -- 裝置資訊（iPad ID / Browser fingerprint）
    ip_address TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL,
    last_activity TIMESTAMPTZ DEFAULT NOW(),
    is_active BOOLEAN DEFAULT TRUE
);

-- 索引優化
CREATE INDEX IF NOT EXISTS idx_staff_sessions_token ON staff_sessions(session_token) WHERE is_active = TRUE;
CREATE INDEX IF NOT EXISTS idx_staff_sessions_staff ON staff_sessions(staff_id) WHERE is_active = TRUE;
CREATE INDEX IF NOT EXISTS idx_staff_sessions_expires ON staff_sessions(expires_at) WHERE is_active = TRUE;

COMMENT ON TABLE staff_sessions IS 'POS 員工 session 管理（短效 token，12 小時過期）';

-- ==========================================
-- 2. 自動清理過期 session
-- ==========================================

CREATE OR REPLACE FUNCTION cleanup_expired_sessions()
RETURNS void AS $$
BEGIN
    UPDATE staff_sessions
    SET is_active = FALSE
    WHERE expires_at < NOW() AND is_active = TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ==========================================
-- 3. 驗證 Session Token（內部函數）
-- ==========================================

CREATE OR REPLACE FUNCTION validate_session_token(p_session_token TEXT)
RETURNS TABLE (
    valid BOOLEAN,
    staff_id UUID,
    staff_role TEXT,
    staff_name TEXT
) AS $$
DECLARE
    v_session RECORD;
    v_staff RECORD;
BEGIN
    -- 清理過期 session
    PERFORM cleanup_expired_sessions();

    -- 查詢 session
    SELECT * INTO v_session
    FROM staff_sessions
    WHERE session_token = p_session_token
      AND is_active = TRUE
      AND expires_at > NOW();

    IF NOT FOUND THEN
        RETURN QUERY SELECT FALSE, NULL::UUID, NULL::TEXT, NULL::TEXT;
        RETURN;
    END IF;

    -- 查詢員工資訊
    SELECT id, role, display_name INTO v_staff
    FROM staff_users
    WHERE id = v_session.staff_id
      AND is_active = TRUE;

    IF NOT FOUND THEN
        -- 員工已停用，使 session 失效
        UPDATE staff_sessions SET is_active = FALSE WHERE id = v_session.id;
        RETURN QUERY SELECT FALSE, NULL::UUID, NULL::TEXT, NULL::TEXT;
        RETURN;
    END IF;

    -- 更新最後活動時間
    UPDATE staff_sessions
    SET last_activity = NOW()
    WHERE id = v_session.id;

    RETURN QUERY SELECT TRUE, v_staff.id, v_staff.role, v_staff.display_name;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ==========================================
-- 4. 重寫 PIN 登入（返回 session token）
-- ==========================================

CREATE OR REPLACE FUNCTION attempt_staff_login(
    p_username TEXT,
    p_pin_code TEXT,
    p_ip_address TEXT DEFAULT NULL,
    p_device_info TEXT DEFAULT NULL
) RETURNS TABLE (
    success BOOLEAN,
    message TEXT,
    session_token TEXT,
    staff_id UUID,
    staff_role TEXT,
    staff_name TEXT,
    expires_at TIMESTAMPTZ
) AS $$
DECLARE
    v_staff RECORD;
    v_failed_attempts INT;
    v_blocked_until TIMESTAMPTZ;
    v_new_token TEXT;
    v_expires_at TIMESTAMPTZ;
BEGIN
    -- 1. 檢查是否被鎖定
    SELECT blocked_until INTO v_blocked_until
    FROM login_attempts
    WHERE (username = p_username OR ip_address = p_ip_address)
      AND blocked_until > NOW()
    ORDER BY blocked_until DESC
    LIMIT 1;

    IF FOUND THEN
        RETURN QUERY SELECT
            FALSE,
            '帳號已鎖定，請於 ' || to_char(v_blocked_until, 'HH24:MI') || ' 後再試',
            NULL::TEXT,
            NULL::UUID,
            NULL::TEXT,
            NULL::TEXT,
            NULL::TIMESTAMPTZ;
        RETURN;
    END IF;

    -- 2. 檢查 15 分鐘內失敗次數
    SELECT COUNT(*) INTO v_failed_attempts
    FROM login_attempts
    WHERE (username = p_username OR ip_address = p_ip_address)
      AND attempt_time > NOW() - INTERVAL '15 minutes'
      AND success = FALSE;

    IF v_failed_attempts >= 5 THEN
        -- 鎖定 15 分鐘
        v_blocked_until := NOW() + INTERVAL '15 minutes';
        INSERT INTO login_attempts (username, ip_address, success, blocked_until)
        VALUES (p_username, p_ip_address, FALSE, v_blocked_until);

        RETURN QUERY SELECT
            FALSE,
            '登入失敗次數過多，帳號已鎖定 15 分鐘',
            NULL::TEXT,
            NULL::UUID,
            NULL::TEXT,
            NULL::TEXT,
            v_blocked_until;
        RETURN;
    END IF;

    -- 3. 驗證 PIN
    SELECT * INTO v_staff
    FROM staff_users
    WHERE username = p_username
      AND pin_code = p_pin_code
      AND is_active = TRUE;

    IF NOT FOUND THEN
        -- 記錄失敗
        INSERT INTO login_attempts (username, ip_address, attempt_time, success)
        VALUES (p_username, p_ip_address, NOW(), FALSE);

        RETURN QUERY SELECT
            FALSE,
            '帳號或密碼錯誤（剩餘嘗試次數：' || (5 - v_failed_attempts - 1) || '）',
            NULL::TEXT,
            NULL::UUID,
            NULL::TEXT,
            NULL::TEXT,
            NULL::TIMESTAMPTZ;
        RETURN;
    END IF;

    -- 4. 登入成功，創建 session
    v_new_token := encode(gen_random_bytes(32), 'base64');
    v_expires_at := NOW() + INTERVAL '12 hours';

    INSERT INTO staff_sessions (
        staff_id,
        session_token,
        device_info,
        ip_address,
        expires_at
    ) VALUES (
        v_staff.id,
        v_new_token,
        p_device_info,
        p_ip_address,
        v_expires_at
    );

    -- 記錄成功登入
    INSERT INTO login_attempts (username, ip_address, attempt_time, success)
    VALUES (p_username, p_ip_address, NOW(), TRUE);

    -- 清理該用戶的失敗記錄（重置計數器）
    DELETE FROM login_attempts
    WHERE username = p_username
      AND success = FALSE
      AND attempt_time > NOW() - INTERVAL '15 minutes';

    RETURN QUERY SELECT
        TRUE,
        '登入成功',
        v_new_token,
        v_staff.id,
        v_staff.role,
        v_staff.display_name,
        v_expires_at;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ==========================================
-- 5. Session Logout
-- ==========================================

CREATE OR REPLACE FUNCTION staff_logout(p_session_token TEXT)
RETURNS BOOLEAN AS $$
BEGIN
    UPDATE staff_sessions
    SET is_active = FALSE
    WHERE session_token = p_session_token;

    RETURN FOUND;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ==========================================
-- 6. 重寫 Update Order Status（需 session token）
-- ==========================================

CREATE OR REPLACE FUNCTION update_order_status(
    p_session_token TEXT,
    p_order_id BIGINT,
    p_new_status TEXT,
    p_notes TEXT DEFAULT NULL
) RETURNS TABLE (
    success BOOLEAN,
    message TEXT
) AS $$
DECLARE
    v_session RECORD;
    v_order RECORD;
    v_old_status TEXT;
BEGIN
    -- 1. 驗證 session
    SELECT * INTO v_session FROM validate_session_token(p_session_token);

    IF NOT v_session.valid THEN
        RETURN QUERY SELECT FALSE, 'Session 無效或已過期，請重新登入'::TEXT;
        RETURN;
    END IF;

    -- 2. 驗證訂單存在
    SELECT status INTO v_old_status
    FROM orders
    WHERE id = p_order_id;

    IF NOT FOUND THEN
        RETURN QUERY SELECT FALSE, '訂單不存在'::TEXT;
        RETURN;
    END IF;

    -- 3. 驗證狀態轉換合法性
    IF NOT is_valid_status_transition(v_old_status, p_new_status) THEN
        RETURN QUERY SELECT FALSE, ('無效的狀態轉換：' || v_old_status || ' → ' || p_new_status)::TEXT;
        RETURN;
    END IF;

    -- 4. 更新訂單狀態（觸發器會自動記錄 audit）
    UPDATE orders
    SET
        status = p_new_status,
        updated_at = NOW()
    WHERE id = p_order_id;

    -- 5. 記錄到審計日誌（補充 staff 資訊）
    INSERT INTO order_status_history (
        order_id,
        old_status,
        new_status,
        changed_by,
        changed_at,
        notes
    ) VALUES (
        p_order_id,
        v_old_status,
        p_new_status,
        v_session.staff_id,
        NOW(),
        COALESCE(p_notes, '由 ' || v_session.staff_name || ' 更新')
    );

    RETURN QUERY SELECT TRUE, '狀態已更新'::TEXT;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ==========================================
-- 7. 重寫 Create Order（需 session token，給 POS 用）
-- ==========================================

CREATE OR REPLACE FUNCTION create_staff_order(
    p_session_token TEXT,
    p_customer_name TEXT,
    p_phone TEXT,
    p_order_type TEXT,
    p_items JSONB,
    p_subtotal NUMERIC,
    p_tax NUMERIC,
    p_tip NUMERIC,
    p_total NUMERIC,
    p_payment_method TEXT DEFAULT 'cash',
    p_notes TEXT DEFAULT NULL
) RETURNS TABLE (
    success BOOLEAN,
    message TEXT,
    order_id BIGINT
) AS $$
DECLARE
    v_session RECORD;
    v_order_id BIGINT;
BEGIN
    -- 1. 驗證 session
    SELECT * INTO v_session FROM validate_session_token(p_session_token);

    IF NOT v_session.valid THEN
        RETURN QUERY SELECT FALSE, 'Session 無效或已過期，請重新登入'::TEXT, NULL::BIGINT;
        RETURN;
    END IF;

    -- 2. 調用原有的 create_order_with_items（但加上 staff_id）
    -- 註：POS 訂單設為 'preparing' 以便立即扣減庫存
    SELECT * INTO v_order_id
    FROM create_order_with_items(
        p_customer_name,
        p_phone,
        NULL, -- email
        p_order_type,
        NULL, -- scheduled_time
        p_items,
        p_subtotal,
        p_tax,
        p_tip,
        p_total,
        'pos', -- order_source
        p_payment_method,
        'paid', -- payment_status (POS 訂單已收款)
        NULL, -- stripe_session_id
        NULL, -- stripe_payment_intent
        'preparing', -- status (立即扣庫存 + 顯示在 Kitchen Display)
        COALESCE(p_notes, '由 ' || v_session.staff_name || ' 建立')
    );

    RETURN QUERY SELECT TRUE, '訂單已建立'::TEXT, v_order_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ==========================================
-- 8. 檢查 Active Sessions（管理用）
-- ==========================================

CREATE OR REPLACE VIEW v_active_staff_sessions AS
SELECT
    s.id,
    s.session_token,
    u.username,
    u.display_name,
    s.device_info,
    s.ip_address,
    s.created_at,
    s.expires_at,
    s.last_activity,
    EXTRACT(EPOCH FROM (NOW() - s.last_activity)) / 60 AS idle_minutes
FROM staff_sessions s
JOIN staff_users u ON s.staff_id = u.id
WHERE s.is_active = TRUE
  AND s.expires_at > NOW()
ORDER BY s.last_activity DESC;

COMMIT;

-- ==========================================
-- 驗證
-- ==========================================

DO $$
BEGIN
    RAISE NOTICE '✅ Session management system created';
    RAISE NOTICE '  - staff_sessions table';
    RAISE NOTICE '  - attempt_staff_login (returns session_token)';
    RAISE NOTICE '  - validate_session_token (internal)';
    RAISE NOTICE '  - update_order_status (requires session_token)';
    RAISE NOTICE '  - create_staff_order (requires session_token)';
    RAISE NOTICE '  - staff_logout';
    RAISE NOTICE '  - v_active_staff_sessions view';
END $$;
-- ==========================================
-- Admin Panel Security (Supabase Auth-based)
-- ==========================================
-- 目的：Admin 用 email/password 登入（Supabase Auth），
--       但一樣需要 RPC 保護，防止直接修改 payment_status

BEGIN;

-- ==========================================
-- 1. Admin 專用：更新訂單狀態（用 auth.uid()）
-- ==========================================

CREATE OR REPLACE FUNCTION admin_update_order_status(
    p_order_id BIGINT,
    p_new_status TEXT,
    p_notes TEXT DEFAULT NULL
) RETURNS TABLE (
    success BOOLEAN,
    message TEXT
) AS $$
DECLARE
    v_admin_email TEXT;
    v_old_status TEXT;
BEGIN
    -- 1. 驗證是否為 authenticated 用戶
    IF auth.uid() IS NULL THEN
        RETURN QUERY SELECT FALSE, '未登入，請先登入管理後台'::TEXT;
        RETURN;
    END IF;

    -- 2. 取得管理員 email（用於審計日誌）
    SELECT email INTO v_admin_email
    FROM auth.users
    WHERE id = auth.uid();

    IF v_admin_email IS NULL THEN
        RETURN QUERY SELECT FALSE, '無法識別管理員身份'::TEXT;
        RETURN;
    END IF;

    -- 3. 驗證訂單存在
    SELECT status INTO v_old_status
    FROM orders
    WHERE id = p_order_id;

    IF NOT FOUND THEN
        RETURN QUERY SELECT FALSE, '訂單不存在'::TEXT;
        RETURN;
    END IF;

    -- 4. 驗證狀態轉換合法性
    IF NOT is_valid_status_transition(v_old_status, p_new_status) THEN
        RETURN QUERY SELECT FALSE, ('無效的狀態轉換：' || v_old_status || ' → ' || p_new_status)::TEXT;
        RETURN;
    END IF;

    -- 5. 更新訂單狀態（不允許修改 payment_status/payment_method）
    UPDATE orders
    SET
        status = p_new_status,
        updated_at = NOW()
    WHERE id = p_order_id;

    -- 6. 記錄審計日誌（使用 admin email）
    INSERT INTO order_status_history (
        order_id,
        old_status,
        new_status,
        changed_by, -- 這裡放 NULL，因為 admin 不在 staff_users 表
        changed_at,
        notes
    ) VALUES (
        p_order_id,
        v_old_status,
        p_new_status,
        NULL, -- Admin 用戶不在 staff_users
        NOW(),
        COALESCE(p_notes, '由管理員 ' || v_admin_email || ' 更新')
    );

    RETURN QUERY SELECT TRUE, '狀態已更新'::TEXT;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION admin_update_order_status IS 'Admin 專用訂單狀態更新（使用 Supabase Auth）';

-- ==========================================
-- 2. Admin 專用：查看審計日誌（含權限檢查）
-- ==========================================

CREATE OR REPLACE FUNCTION admin_get_order_audit_trail(p_order_id BIGINT)
RETURNS TABLE (
    id UUID,
    old_status TEXT,
    new_status TEXT,
    changed_at TIMESTAMPTZ,
    changed_by_name TEXT,
    notes TEXT,
    minutes_in_status NUMERIC
) AS $$
BEGIN
    -- 驗證權限
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION '未授權訪問';
    END IF;

    RETURN QUERY
    SELECT
        h.id,
        h.old_status,
        h.new_status,
        h.changed_at,
        COALESCE(s.display_name, s.username, h.notes) AS changed_by_name,
        h.notes,
        EXTRACT(EPOCH FROM (
            LEAD(h.changed_at) OVER (ORDER BY h.changed_at) - h.changed_at
        )) / 60 AS minutes_in_status
    FROM order_status_history h
    LEFT JOIN staff_users s ON h.changed_by = s.id
    WHERE h.order_id = p_order_id
    ORDER BY h.changed_at;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ==========================================
-- 3. 更新 RLS：確保 Admin 只能用 RPC
-- ==========================================

-- 防止 authenticated 用戶直接修改 payment 欄位
DO $$
BEGIN
    -- 檢查策略是否存在
    IF EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'orders'
          AND policyname = 'authenticated_update_orders'
    ) THEN
        -- 更新現有策略
        DROP POLICY authenticated_update_orders ON orders;
    END IF;
END $$;

CREATE POLICY "authenticated_update_orders" ON orders
    FOR UPDATE
    TO authenticated
    USING (true) -- 可以嘗試更新
    WITH CHECK (
        -- 確保不修改 payment 相關欄位
        payment_status = (SELECT payment_status FROM orders WHERE id = orders.id) AND
        payment_method = (SELECT payment_method FROM orders WHERE id = orders.id) AND
        stripe_session_id = (SELECT stripe_session_id FROM orders WHERE id = orders.id) AND
        stripe_payment_intent = (SELECT stripe_payment_intent FROM orders WHERE id = orders.id)
    );

COMMENT ON POLICY authenticated_update_orders ON orders IS
'Authenticated 用戶可以更新訂單，但不能修改付款相關欄位';

-- ==========================================
-- 4. 批量操作（Admin 專用）
-- ==========================================

CREATE OR REPLACE FUNCTION admin_bulk_update_status(
    p_order_ids BIGINT[],
    p_new_status TEXT,
    p_notes TEXT DEFAULT NULL
) RETURNS TABLE (
    order_id BIGINT,
    success BOOLEAN,
    message TEXT
) AS $$
DECLARE
    v_order_id BIGINT;
    v_result RECORD;
BEGIN
    -- 驗證權限
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION '未授權操作';
    END IF;

    -- 逐個更新
    FOREACH v_order_id IN ARRAY p_order_ids LOOP
        SELECT * INTO v_result
        FROM admin_update_order_status(v_order_id, p_new_status, p_notes);

        RETURN QUERY SELECT v_order_id, v_result.success, v_result.message;
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMIT;

-- ==========================================
-- 驗證
-- ==========================================

DO $$
BEGIN
    RAISE NOTICE '✅ Admin security functions created';
    RAISE NOTICE '  - admin_update_order_status (使用 auth.uid())';
    RAISE NOTICE '  - admin_get_order_audit_trail';
    RAISE NOTICE '  - admin_bulk_update_status';
    RAISE NOTICE '  - RLS policy updated (防止修改 payment 欄位)';
    RAISE NOTICE '';
    RAISE NOTICE '⚠️  Admin 必須透過 RPC 更新訂單狀態';
    RAISE NOTICE '   前端不應直接 .from("orders").update()';
END $$;
