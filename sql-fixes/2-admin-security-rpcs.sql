-- ==========================================
-- 🔒 POS 系統安全修復包（完整版）
-- ==========================================
-- 修復內容：
-- 1. Session Token 安全升級
-- 2. Admin 權限驗證 RPC
-- 3. Admin 操作 RPC（菜單、庫存、訂單）
-- ==========================================

-- ==========================================
-- PART 1: 升級 Session Token 安全性
-- ==========================================

ALTER TABLE staff_sessions 
ADD COLUMN IF NOT EXISTS revoked_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS last_seen_at TIMESTAMPTZ DEFAULT NOW(),
ADD COLUMN IF NOT EXISTS device_id TEXT;

CREATE INDEX IF NOT EXISTS idx_sessions_token_active 
ON staff_sessions(session_token) 
WHERE revoked_at IS NULL AND expires_at > NOW();

CREATE INDEX IF NOT EXISTS idx_sessions_staff_active
ON staff_sessions(staff_id)
WHERE revoked_at IS NULL;

-- ==========================================
-- PART 2: Admin 權限驗證函數
-- ==========================================

CREATE OR REPLACE FUNCTION verify_admin_session(p_session_token TEXT)
RETURNS TABLE (
    is_valid BOOLEAN,
    staff_id UUID,
    staff_role TEXT
) AS $$
DECLARE
    v_session RECORD;
    v_staff RECORD;
BEGIN
    SELECT * INTO v_session
    FROM staff_sessions
    WHERE session_token = p_session_token
      AND expires_at > NOW()
      AND revoked_at IS NULL;

    IF NOT FOUND THEN
        RETURN QUERY SELECT FALSE, NULL::UUID, NULL::TEXT;
        RETURN;
    END IF;

    SELECT * INTO v_staff
    FROM staff_users
    WHERE id = v_session.staff_id
      AND is_active = TRUE
      AND role = 'admin';

    IF NOT FOUND THEN
        RETURN QUERY SELECT FALSE, NULL::UUID, NULL::TEXT;
        RETURN;
    END IF;

    RETURN QUERY SELECT TRUE, v_staff.id, v_staff.role;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ==========================================
-- PART 3: Admin 新增菜單項目
-- ==========================================

CREATE OR REPLACE FUNCTION admin_create_menu_item(
    p_session_token TEXT,
    p_name TEXT,
    p_description TEXT,
    p_price DECIMAL,
    p_category TEXT,
    p_emoji TEXT DEFAULT '🍽️',
    p_available BOOLEAN DEFAULT TRUE
) RETURNS TABLE (
    success BOOLEAN,
    message TEXT,
    item_id UUID
) AS $$
DECLARE
    v_admin RECORD;
    v_new_item_id UUID;
BEGIN
    SELECT * INTO v_admin FROM verify_admin_session(p_session_token);
    
    IF NOT v_admin.is_valid THEN
        RETURN QUERY SELECT FALSE, '❌ 權限不足：需要管理員權限', NULL::UUID;
        RETURN;
    END IF;

    IF p_name IS NULL OR trim(p_name) = '' THEN
        RETURN QUERY SELECT FALSE, '❌ 商品名稱不能為空', NULL::UUID;
        RETURN;
    END IF;

    IF p_price < 0 THEN
        RETURN QUERY SELECT FALSE, '❌ 價格不能為負數', NULL::UUID;
        RETURN;
    END IF;

    INSERT INTO menu_items (name, description, price, category, emoji, available, created_at, updated_at)
    VALUES (trim(p_name), p_description, p_price, p_category, p_emoji, p_available, NOW(), NOW())
    RETURNING id INTO v_new_item_id;

    RETURN QUERY SELECT TRUE, '✅ 菜單項目已新增', v_new_item_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ==========================================
-- PART 4: Admin 更新菜單項目
-- ==========================================

CREATE OR REPLACE FUNCTION admin_update_menu_item(
    p_session_token TEXT,
    p_item_id UUID,
    p_name TEXT DEFAULT NULL,
    p_description TEXT DEFAULT NULL,
    p_price DECIMAL DEFAULT NULL,
    p_category TEXT DEFAULT NULL,
    p_emoji TEXT DEFAULT NULL,
    p_available BOOLEAN DEFAULT NULL
) RETURNS TABLE (
    success BOOLEAN,
    message TEXT
) AS $$
DECLARE
    v_admin RECORD;
BEGIN
    SELECT * INTO v_admin FROM verify_admin_session(p_session_token);
    
    IF NOT v_admin.is_valid THEN
        RETURN QUERY SELECT FALSE, '❌ 權限不足：需要管理員權限';
        RETURN;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM menu_items WHERE id = p_item_id) THEN
        RETURN QUERY SELECT FALSE, '❌ 商品不存在';
        RETURN;
    END IF;

    UPDATE menu_items
    SET
        name = COALESCE(p_name, name),
        description = COALESCE(p_description, description),
        price = COALESCE(p_price, price),
        category = COALESCE(p_category, category),
        emoji = COALESCE(p_emoji, emoji),
        available = COALESCE(p_available, available),
        updated_at = NOW()
    WHERE id = p_item_id;

    RETURN QUERY SELECT TRUE, '✅ 菜單項目已更新';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ==========================================
-- PART 5: Admin 刪除菜單項目（軟刪除）
-- ==========================================

CREATE OR REPLACE FUNCTION admin_delete_menu_item(
    p_session_token TEXT,
    p_item_id UUID
) RETURNS TABLE (
    success BOOLEAN,
    message TEXT
) AS $$
DECLARE
    v_admin RECORD;
BEGIN
    SELECT * INTO v_admin FROM verify_admin_session(p_session_token);
    
    IF NOT v_admin.is_valid THEN
        RETURN QUERY SELECT FALSE, '❌ 權限不足：需要管理員權限';
        RETURN;
    END IF;

    UPDATE menu_items SET available = FALSE, updated_at = NOW() WHERE id = p_item_id;

    IF NOT FOUND THEN
        RETURN QUERY SELECT FALSE, '❌ 商品不存在';
        RETURN;
    END IF;

    RETURN QUERY SELECT TRUE, '✅ 菜單項目已刪除';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ==========================================
-- PART 6: Admin 更新庫存
-- ==========================================

CREATE OR REPLACE FUNCTION admin_update_inventory(
    p_session_token TEXT,
    p_item_id UUID,
    p_quantity DECIMAL,
    p_reason TEXT DEFAULT NULL
) RETURNS TABLE (
    success BOOLEAN,
    message TEXT,
    new_quantity DECIMAL
) AS $$
DECLARE
    v_admin RECORD;
BEGIN
    SELECT * INTO v_admin FROM verify_admin_session(p_session_token);
    
    IF NOT v_admin.is_valid THEN
        RETURN QUERY SELECT FALSE, '❌ 權限不足：需要管理員權限', NULL::DECIMAL;
        RETURN;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM inventory_items WHERE id = p_item_id) THEN
        RETURN QUERY SELECT FALSE, '❌ 庫存項目不存在', NULL::DECIMAL;
        RETURN;
    END IF;

    UPDATE inventory_items SET quantity = p_quantity, updated_at = NOW() WHERE id = p_item_id;

    RETURN QUERY SELECT TRUE, '✅ 庫存已更新', p_quantity;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ==========================================
-- PART 7: Admin 查看所有訂單
-- ==========================================

CREATE OR REPLACE FUNCTION admin_get_all_orders(
    p_session_token TEXT,
    p_start_date TIMESTAMPTZ DEFAULT NULL,
    p_end_date TIMESTAMPTZ DEFAULT NULL,
    p_limit INT DEFAULT 100
) RETURNS TABLE (
    order_id UUID,
    order_type TEXT,
    payment_method TEXT,
    total_price DECIMAL,
    status TEXT,
    created_at TIMESTAMPTZ,
    staff_name TEXT,
    items_json JSONB
) AS $$
DECLARE
    v_admin RECORD;
BEGIN
    SELECT * INTO v_admin FROM verify_admin_session(p_session_token);
    
    IF NOT v_admin.is_valid THEN
        RAISE EXCEPTION '❌ 權限不足：需要管理員權限';
    END IF;

    RETURN QUERY
    SELECT
        o.id, o.order_type, o.payment_method, o.total_price, o.status, o.created_at,
        s.display_name AS staff_name,
        (SELECT jsonb_agg(jsonb_build_object('name', oi.item_name, 'quantity', oi.quantity, 'price', oi.price, 'subtotal', oi.subtotal))
         FROM order_items oi WHERE oi.order_id = o.id) AS items_json
    FROM orders o
    LEFT JOIN staff_users s ON o.staff_id = s.id
    WHERE (p_start_date IS NULL OR o.created_at >= p_start_date)
      AND (p_end_date IS NULL OR o.created_at <= p_end_date)
    ORDER BY o.created_at DESC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ==========================================
-- PART 8: 授權
-- ==========================================

GRANT EXECUTE ON FUNCTION verify_admin_session TO authenticated;
GRANT EXECUTE ON FUNCTION admin_create_menu_item TO authenticated;
GRANT EXECUTE ON FUNCTION admin_update_menu_item TO authenticated;
GRANT EXECUTE ON FUNCTION admin_delete_menu_item TO authenticated;
GRANT EXECUTE ON FUNCTION admin_update_inventory TO authenticated;
GRANT EXECUTE ON FUNCTION admin_get_all_orders TO authenticated;

-- ==========================================
-- ✅ 安全修復完成！
-- ==========================================
