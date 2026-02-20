-- ==========================================
-- 库存管理核心业务逻辑函数
-- ==========================================

-- ==========================================
-- 函数 1：FIFO 库存扣除
-- ==========================================
CREATE OR REPLACE FUNCTION deduct_inventory_fifo(
    p_item_id BIGINT,
    p_qty INTEGER,
    p_reference_type TEXT DEFAULT 'order',
    p_reference_id BIGINT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
    v_remaining_qty INTEGER := p_qty;
    v_batch RECORD;
    v_deducted_qty INTEGER;
    v_total_deducted INTEGER := 0;
    v_transactions JSONB := '[]'::JSONB;
BEGIN
    -- 检查总库存是否足够
    IF (SELECT COALESCE(SUM(qty_remaining), 0) 
        FROM inventory_batches 
        WHERE item_id = p_item_id AND is_active = true) < p_qty THEN
        RAISE EXCEPTION '库存不足！需要 % 但只有 %', 
            p_qty, 
            (SELECT COALESCE(SUM(qty_remaining), 0) 
             FROM inventory_batches 
             WHERE item_id = p_item_id AND is_active = true);
    END IF;

    -- FIFO 逻辑：按入库时间从早到晚扣除
    FOR v_batch IN 
        SELECT id, qty_remaining, cost_per_unit, received_at
        FROM inventory_batches
        WHERE item_id = p_item_id 
          AND is_active = true
          AND qty_remaining > 0
        ORDER BY received_at ASC  -- FIFO: 先进先出
    LOOP
        -- 计算本批次可扣除数量
        v_deducted_qty := LEAST(v_remaining_qty, v_batch.qty_remaining);
        
        -- 更新批次剩余数量
        UPDATE inventory_batches
        SET qty_remaining = qty_remaining - v_deducted_qty,
            is_active = CASE 
                WHEN qty_remaining - v_deducted_qty = 0 THEN false 
                ELSE true 
            END
        WHERE id = v_batch.id;
        
        -- 记录交易
        INSERT INTO inventory_transactions (
            item_id, batch_id, transaction_type, qty, 
            cost_per_unit, reference_type, reference_id
        ) VALUES (
            p_item_id, v_batch.id, 'out', v_deducted_qty,
            v_batch.cost_per_unit, p_reference_type, p_reference_id
        );
        
        -- 累加交易记录
        v_transactions := v_transactions || jsonb_build_object(
            'batch_id', v_batch.id,
            'qty', v_deducted_qty,
            'cost_per_unit', v_batch.cost_per_unit,
            'received_at', v_batch.received_at
        );
        
        v_total_deducted := v_total_deducted + v_deducted_qty;
        v_remaining_qty := v_remaining_qty - v_deducted_qty;
        
        -- 如果已全部扣除，退出循环
        EXIT WHEN v_remaining_qty = 0;
    END LOOP;
    
    RETURN jsonb_build_object(
        'success', true,
        'total_deducted', v_total_deducted,
        'transactions', v_transactions
    );
END;
$$;

-- ==========================================
-- 函数 2：快速调整（员工餐/报废/赠送）
-- ==========================================
CREATE OR REPLACE FUNCTION quick_adjustment(
    p_item_id BIGINT,
    p_adjustment_type TEXT,
    p_qty INTEGER,
    p_reason TEXT DEFAULT NULL,
    p_adjusted_by TEXT DEFAULT 'admin'
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
    v_result JSONB;
    v_cost_impact NUMERIC(10, 2);
BEGIN
    -- 使用 FIFO 扣除库存
    v_result := deduct_inventory_fifo(p_item_id, p_qty, 'adjustment', NULL);
    
    -- 计算成本影响
    SELECT SUM((tx->>'qty')::INTEGER * (tx->>'cost_per_unit')::NUMERIC)
    INTO v_cost_impact
    FROM jsonb_array_elements(v_result->'transactions') AS tx;
    
    -- 记录调整
    INSERT INTO inventory_adjustments (
        item_id, adjustment_type, qty_change, 
        cost_impact, reason, adjusted_by
    ) VALUES (
        p_item_id, p_adjustment_type, -p_qty,
        v_cost_impact, p_reason, p_adjusted_by
    );
    
    RETURN jsonb_build_object(
        'success', true,
        'adjustment_type', p_adjustment_type,
        'qty_deducted', p_qty,
        'cost_impact', v_cost_impact
    );
END;
$$;

-- ==========================================
-- 函数 3：入库（接收新批次）
-- ==========================================
CREATE OR REPLACE FUNCTION receive_inventory(
    p_item_id BIGINT,
    p_qty INTEGER,
    p_cost_per_unit NUMERIC(10, 2),
    p_supplier TEXT DEFAULT NULL,
    p_batch_number TEXT DEFAULT NULL,
    p_expiry_date DATE DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
    v_batch_id BIGINT;
    v_generated_batch_number TEXT;
BEGIN
    -- 生成批次号（如果未提供）
    IF p_batch_number IS NULL THEN
        v_generated_batch_number := 'BATCH-' || 
            TO_CHAR(NOW(), 'YYYYMMDD') || '-' || 
            LPAD(nextval('inventory_batches_id_seq')::TEXT, 6, '0');
    ELSE
        v_generated_batch_number := p_batch_number;
    END IF;
    
    -- 创建新批次
    INSERT INTO inventory_batches (
        item_id, batch_number, qty_received, qty_remaining,
        cost_per_unit, supplier, expiry_date, is_active
    ) VALUES (
        p_item_id, v_generated_batch_number, p_qty, p_qty,
        p_cost_per_unit, p_supplier, p_expiry_date, true
    ) RETURNING id INTO v_batch_id;
    
    -- 记录入库交易
    INSERT INTO inventory_transactions (
        item_id, batch_id, transaction_type, qty,
        cost_per_unit, reference_type
    ) VALUES (
        p_item_id, v_batch_id, 'in', p_qty,
        p_cost_per_unit, 'receive'
    );
    
    -- 更新物品当前成本（加权平均）
    UPDATE inventory_items
    SET current_cost = (
        SELECT 
            CASE 
                WHEN SUM(qty_remaining) > 0 
                THEN SUM(qty_remaining * cost_per_unit) / SUM(qty_remaining)
                ELSE current_cost
            END
        FROM inventory_batches
        WHERE item_id = p_item_id AND is_active = true
    )
    WHERE id = p_item_id;
    
    RETURN jsonb_build_object(
        'success', true,
        'batch_id', v_batch_id,
        'batch_number', v_generated_batch_number,
        'qty_received', p_qty
    );
END;
$$;

-- ==========================================
-- 函数 4：盘点调整
-- ==========================================
CREATE OR REPLACE FUNCTION inventory_count_adjustment(
    p_item_id BIGINT,
    p_actual_qty INTEGER,
    p_adjusted_by TEXT DEFAULT 'admin',
    p_notes TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
    v_system_qty INTEGER;
    v_delta INTEGER;
    v_oldest_batch RECORD;
BEGIN
    -- 计算系统库存
    SELECT COALESCE(SUM(qty_remaining), 0)
    INTO v_system_qty
    FROM inventory_batches
    WHERE item_id = p_item_id AND is_active = true;
    
    -- 计算差异
    v_delta := p_actual_qty - v_system_qty;
    
    -- 如果有差异，进行调整
    IF v_delta != 0 THEN
        IF v_delta > 0 THEN
            -- 盘盈：增加到最早的活跃批次，如果没有则创建新批次
            SELECT id INTO v_oldest_batch
            FROM inventory_batches
            WHERE item_id = p_item_id AND is_active = true
            ORDER BY received_at ASC
            LIMIT 1;
            
            IF v_oldest_batch IS NULL THEN
                -- 没有活跃批次，创建新批次
                PERFORM receive_inventory(
                    p_item_id, 
                    v_delta, 
                    (SELECT current_cost FROM inventory_items WHERE id = p_item_id),
                    'Count Adjustment',
                    'ADJ-' || TO_CHAR(NOW(), 'YYYYMMDD-HH24MISS')
                );
            ELSE
                -- 增加到最早批次
                UPDATE inventory_batches
                SET qty_remaining = qty_remaining + v_delta,
                    qty_received = qty_received + v_delta
                WHERE id = v_oldest_batch.id;
            END IF;
        ELSE
            -- 盘亏：使用 FIFO 扣除
            PERFORM deduct_inventory_fifo(
                p_item_id, 
                ABS(v_delta), 
                'count_adjustment'
            );
        END IF;
        
        -- 记录调整
        INSERT INTO inventory_adjustments (
            item_id, adjustment_type, qty_change,
            reason, adjusted_by, notes
        ) VALUES (
            p_item_id, 'count_adjustment', v_delta,
            FORMAT('盘点调整：系统 %s，实际 %s，差异 %s', v_system_qty, p_actual_qty, v_delta),
            p_adjusted_by, p_notes
        );
    END IF;
    
    RETURN jsonb_build_object(
        'success', true,
        'system_qty', v_system_qty,
        'actual_qty', p_actual_qty,
        'delta', v_delta,
        'adjusted', v_delta != 0
    );
END;
$$;

-- ==========================================
-- 函数 5：计算库存周转天数
-- ==========================================
CREATE OR REPLACE FUNCTION calculate_days_of_cover(p_item_id BIGINT)
RETURNS NUMERIC
LANGUAGE plpgsql
AS $$
DECLARE
    v_on_hand INTEGER;
    v_daily_usage NUMERIC;
BEGIN
    -- 当前库存
    SELECT COALESCE(SUM(qty_remaining), 0)
    INTO v_on_hand
    FROM inventory_batches
    WHERE item_id = p_item_id AND is_active = true;
    
    -- 过去7天日均销量
    SELECT COALESCE(AVG(daily_qty), 0)
    INTO v_daily_usage
    FROM (
        SELECT DATE(created_at) AS date, SUM(qty) AS daily_qty
        FROM inventory_transactions
        WHERE item_id = p_item_id 
          AND transaction_type = 'out'
          AND created_at >= NOW() - INTERVAL '7 days'
        GROUP BY DATE(created_at)
    ) AS daily_sales;
    
    -- 避免除以0
    IF v_daily_usage = 0 THEN
        RETURN 999;  -- 返回一个大数表示"无限天"
    END IF;
    
    RETURN v_on_hand / v_daily_usage;
END;
$$;

-- ==========================================
-- 完成！
-- ==========================================
SELECT '✅ 库存管理核心函数创建成功！' as status;
