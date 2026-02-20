-- ==========================================
-- 🔒 安全的客人下單 RPC（不信任前端價格）
-- ==========================================

-- 1. 建立 Rate Limiting 表（追蹤 IP 請求次數）
CREATE TABLE IF NOT EXISTS public_order_rate_limit (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    ip_address TEXT NOT NULL,
    request_count INT DEFAULT 1,
    window_start TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_rate_limit_ip_time 
ON public_order_rate_limit(ip_address, window_start);

-- 2. 安全的客人下單 RPC
CREATE OR REPLACE FUNCTION create_public_order(
    p_items JSONB,              -- [{"item_id": "uuid", "quantity": 2}, ...]
    p_order_type TEXT,          -- 'dine_in' or 'takeout'
    p_payment_method TEXT,      -- 'cash', 'card', 'other'
    p_ip_address TEXT DEFAULT NULL,
    p_device_info TEXT DEFAULT NULL
) RETURNS TABLE (
    success BOOLEAN,
    message TEXT,
    order_id UUID,
    calculated_subtotal DECIMAL,
    calculated_tax DECIMAL,
    calculated_total DECIMAL
) AS $$
DECLARE
    v_order_id UUID;
    v_subtotal DECIMAL := 0;
    v_tax DECIMAL;
    v_total DECIMAL;
    v_item JSONB;
    v_menu_item RECORD;
    v_quantity INT;
    v_rate_count INT;
BEGIN
    -- ==========================================
    -- 1. Rate Limiting（每 IP 每分鐘最多 10 筆訂單）
    -- ==========================================
    IF p_ip_address IS NOT NULL THEN
        -- 清理超過 1 分鐘的舊記錄
        DELETE FROM public_order_rate_limit
        WHERE ip_address = p_ip_address
          AND window_start < NOW() - INTERVAL '1 minute';

        -- 檢查當前 IP 的請求次數
        SELECT COUNT(*) INTO v_rate_count
        FROM public_order_rate_limit
        WHERE ip_address = p_ip_address
          AND window_start > NOW() - INTERVAL '1 minute';

        IF v_rate_count >= 10 THEN
            RETURN QUERY SELECT
                FALSE,
                '⚠️ 下單次數過多，請稍後再試（每分鐘限制 10 筆）',
                NULL::UUID,
                NULL::DECIMAL,
                NULL::DECIMAL,
                NULL::DECIMAL;
            RETURN;
        END IF;

        -- 記錄此次請求
        INSERT INTO public_order_rate_limit (ip_address, request_count)
        VALUES (p_ip_address, 1);
    END IF;

    -- ==========================================
    -- 2. 驗證訂單項目（只信任 item_id + quantity）
    -- ==========================================
    IF jsonb_array_length(p_items) = 0 THEN
        RETURN QUERY SELECT
            FALSE,
            '❌ 訂單不能為空',
            NULL::UUID,
            NULL::DECIMAL,
            NULL::DECIMAL,
            NULL::DECIMAL;
        RETURN;
    END IF;

    -- 檢查數量是否合理（防止惡意大量下單）
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_quantity := (v_item->>'quantity')::INT;
        
        IF v_quantity < 1 OR v_quantity > 99 THEN
            RETURN QUERY SELECT
                FALSE,
                '❌ 商品數量不合理（1-99）',
                NULL::UUID,
                NULL::DECIMAL,
                NULL::DECIMAL,
                NULL::DECIMAL;
            RETURN;
        END IF;
    END LOOP;

    -- ==========================================
    -- 3. 重新計算價格（不信任前端）
    -- ==========================================
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        -- 從資料庫查詢真實價格
        SELECT * INTO v_menu_item
        FROM menu_items
        WHERE id = (v_item->>'item_id')::UUID
          AND available = TRUE;

        IF NOT FOUND THEN
            RETURN QUERY SELECT
                FALSE,
                '❌ 商品不存在或已下架：' || (v_item->>'item_id'),
                NULL::UUID,
                NULL::DECIMAL,
                NULL::DECIMAL,
                NULL::DECIMAL;
            RETURN;
        END IF;

        -- 累加小計（使用資料庫價格，不是前端傳來的）
        v_quantity := (v_item->>'quantity')::INT;
        v_subtotal := v_subtotal + (v_menu_item.price * v_quantity);
    END LOOP;

    -- 計算稅金（8.25%）
    v_tax := v_subtotal * 0.0825;
    v_total := v_subtotal + v_tax;

    -- ==========================================
    -- 4. 建立訂單（原子性操作）
    -- ==========================================
    BEGIN
        -- 插入訂單主表
        INSERT INTO orders (
            order_type,
            payment_method,
            subtotal,
            tax,
            total_price,
            status,
            created_at
        ) VALUES (
            p_order_type,
            p_payment_method,
            v_subtotal,
            v_tax,
            v_total,
            'pending',
            NOW()
        ) RETURNING id INTO v_order_id;

        -- 插入訂單項目（批次）
        FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
        LOOP
            SELECT * INTO v_menu_item
            FROM menu_items
            WHERE id = (v_item->>'item_id')::UUID;

            v_quantity := (v_item->>'quantity')::INT;

            INSERT INTO order_items (
                order_id,
                item_id,
                item_name,
                quantity,
                price,
                subtotal
            ) VALUES (
                v_order_id,
                v_menu_item.id,
                v_menu_item.name,
                v_quantity,
                v_menu_item.price,
                v_menu_item.price * v_quantity
            );
        END LOOP;

        -- 扣除庫存（如果有配置）
        PERFORM decrement_inventory_for_order(v_order_id);

        -- 成功
        RETURN QUERY SELECT
            TRUE,
            '✅ 訂單建立成功',
            v_order_id,
            v_subtotal,
            v_tax,
            v_total;

    EXCEPTION WHEN OTHERS THEN
        -- 發生錯誤時回滾
        RETURN QUERY SELECT
            FALSE,
            '❌ 訂單建立失敗：' || SQLERRM,
            NULL::UUID,
            NULL::DECIMAL,
            NULL::DECIMAL,
            NULL::DECIMAL;
    END;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. 授權給匿名用戶（但已經有 Rate Limiting 保護）
GRANT EXECUTE ON FUNCTION create_public_order TO anon, authenticated;

COMMENT ON FUNCTION create_public_order IS 
'安全的客人下單 RPC：
1. Rate Limiting（每 IP 每分鐘 10 筆）
2. 重新計算價格（不信任前端）
3. 驗證數量合理性（1-99）
4. 原子性操作
5. 自動扣庫存';
