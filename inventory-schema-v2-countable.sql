-- ==========================================
-- 库存系统 V2：可数库存（包材/成品为主）
-- ==========================================
-- 作者建议：先做包材/成品，比做食材准 100 倍！

-- ==========================================
-- 1. 升级 inventory_items 表（增加实战字段）
-- ==========================================

-- 添加新字段
ALTER TABLE inventory_items
ADD COLUMN IF NOT EXISTS item_type TEXT DEFAULT 'PACKAGING',
ADD COLUMN IF NOT EXISTS is_countable BOOLEAN DEFAULT true,
ADD COLUMN IF NOT EXISTS base_unit TEXT DEFAULT 'pcs',
ADD COLUMN IF NOT EXISTS units_per_case INTEGER,
ADD COLUMN IF NOT EXISTS reorder_qty INTEGER DEFAULT 100,
ADD COLUMN IF NOT EXISTS menu_item_id BIGINT REFERENCES menu(id);

-- 添加注释
COMMENT ON COLUMN inventory_items.item_type IS
'库存品项类型：PACKAGING（包材）, BEVERAGE_PACKAGED（瓶装饮料）, PREPACKAGED_FOOD（预包装食品）, EGGS_PACK（蛋类）, SUPPLY（耗材）';

COMMENT ON COLUMN inventory_items.base_unit IS
'主单位：pcs（个）, box（盒）, bag（包）, bottle（瓶）, can（罐）, roll（卷）, pack（组）';

COMMENT ON COLUMN inventory_items.units_per_case IS
'每箱/盒/包包含的基础单位数量。例：1 box = 50 pcs';

COMMENT ON COLUMN inventory_items.reorder_qty IS
'建议补货数量（以 base_unit 为单位）';

COMMENT ON COLUMN inventory_items.menu_item_id IS
'如果该库存品项直接对应某个菜单项（如瓶装水），关联 menu.id';

-- ==========================================
-- 2. 创建菜单-包材映射表（核心！）
-- ==========================================
CREATE TABLE IF NOT EXISTS menu_packaging_map (
    id BIGSERIAL PRIMARY KEY,
    menu_item_name TEXT NOT NULL,
    inventory_item_id BIGINT NOT NULL REFERENCES inventory_items(id) ON DELETE CASCADE,
    qty_per_sale INTEGER NOT NULL DEFAULT 1,
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    -- 确保同一菜品+同一包材只有一条记录
    UNIQUE(menu_item_name, inventory_item_id)
);

-- 索引优化
CREATE INDEX IF NOT EXISTS idx_menu_packaging_map_menu_name
ON menu_packaging_map(menu_item_name);

CREATE INDEX IF NOT EXISTS idx_menu_packaging_map_inventory_item
ON menu_packaging_map(inventory_item_id);

-- 注释
COMMENT ON TABLE menu_packaging_map IS
'菜单-包材映射表：记录每个菜品需要消耗哪些包材（盒子、袋子、吸管等）';

COMMENT ON COLUMN menu_packaging_map.qty_per_sale IS
'每卖 1 份该菜品，需要消耗的包材数量（通常是 1）';

-- RLS 策略
ALTER TABLE menu_packaging_map ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow read menu_packaging_map" ON menu_packaging_map;
CREATE POLICY "Allow read menu_packaging_map"
ON menu_packaging_map FOR SELECT USING (true);

DROP POLICY IF EXISTS "Allow authenticated modify menu_packaging_map" ON menu_packaging_map;
CREATE POLICY "Allow authenticated modify menu_packaging_map"
ON menu_packaging_map FOR ALL TO authenticated
USING (true) WITH CHECK (true);

-- ==========================================
-- 3. 更新 inventory_overview VIEW（增加预警逻辑）
-- ==========================================
DROP VIEW IF EXISTS inventory_overview;

CREATE VIEW inventory_overview AS
SELECT
    ii.id,
    ii.name,
    ii.item_type,
    ii.is_countable,
    ii.base_unit AS unit,
    ii.units_per_case,
    ii.reorder_point,
    ii.reorder_qty,
    ii.lead_time_days,
    ii.safety_buffer_days,
    ii.current_cost,
    ii.menu_item_id,

    -- 现有库存（base_unit）
    COALESCE(SUM(ib.qty_remaining), 0) AS qty_on_hand,

    -- 库存状态
    CASE
        WHEN COALESCE(SUM(ib.qty_remaining), 0) = 0 THEN 'out_of_stock'
        WHEN COALESCE(SUM(ib.qty_remaining), 0) <= ii.reorder_point THEN 'low_stock'
        ELSE 'ok'
    END AS stock_status,

    -- 建议补货数量（当低于 reorder_point 时显示）
    CASE
        WHEN COALESCE(SUM(ib.qty_remaining), 0) <= ii.reorder_point
        THEN ii.reorder_qty
        ELSE 0
    END AS suggested_reorder_qty,

    -- 库存价值
    COALESCE(SUM(ib.qty_remaining), 0) * ii.current_cost AS inventory_value,

    -- 周转天数（过去7天平均消耗）
    calculate_days_of_cover(ii.id) AS days_of_cover,

    -- 预计到货日期（如果现在补货）
    CURRENT_DATE + INTERVAL '1 day' * (ii.lead_time_days + COALESCE(ii.safety_buffer_days, 0)) AS estimated_delivery_date,

    ii.created_at,
    ii.updated_at
FROM inventory_items ii
LEFT JOIN inventory_batches ib ON ib.item_id = ii.id AND ib.is_active = true
WHERE ii.is_countable = true  -- 只显示可数库存
GROUP BY ii.id;

COMMENT ON VIEW inventory_overview IS
'库存总览视图（仅可数库存）：包含库存状态、补货建议、周转天数等';

-- ==========================================
-- 4. 升级订单扣库存函数（改为扣包材）
-- ==========================================
CREATE OR REPLACE FUNCTION consume_inventory_for_order(
    p_order_id BIGINT
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
    v_order RECORD;
    v_item JSONB;
    v_packaging RECORD;
    v_deductions JSONB := '[]'::JSONB;
    v_result JSONB;
    v_item_name TEXT;
    v_item_qty INTEGER;
    v_total_packaging_qty INTEGER;
BEGIN
    -- 1. 读取订单
    SELECT * INTO v_order FROM orders WHERE id = p_order_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', false,
            'message', '订单不存在：' || p_order_id
        );
    END IF;

    RAISE NOTICE '开始扣库存：订单 #%', p_order_id;

    -- 2. 遍历订单中的每个商品
    FOR v_item IN SELECT * FROM jsonb_array_elements(v_order.items)
    LOOP
        v_item_name := v_item->>'name';
        v_item_qty := (v_item->>'quantity')::INTEGER;

        RAISE NOTICE '处理菜品：% x %', v_item_name, v_item_qty;

        -- 3. 查找该菜品需要的包材
        FOR v_packaging IN
            SELECT
                mpm.inventory_item_id,
                mpm.qty_per_sale,
                ii.name AS packaging_name,
                ii.base_unit
            FROM menu_packaging_map mpm
            JOIN inventory_items ii ON ii.id = mpm.inventory_item_id
            WHERE mpm.menu_item_name = v_item_name
        LOOP
            -- 计算需要扣除的包材数量
            v_total_packaging_qty := v_packaging.qty_per_sale * v_item_qty;

            RAISE NOTICE '  - 需要包材：% x % = %',
                v_packaging.packaging_name,
                v_packaging.qty_per_sale,
                v_total_packaging_qty;

            -- 4. FIFO 扣除库存
            BEGIN
                v_result := deduct_inventory_fifo(
                    v_packaging.inventory_item_id,
                    v_total_packaging_qty,
                    'order',
                    p_order_id
                );

                IF NOT (v_result->>'success')::BOOLEAN THEN
                    -- 库存不足
                    RETURN jsonb_build_object(
                        'success', false,
                        'message', '包材库存不足：' || v_packaging.packaging_name,
                        'inventory_item_id', v_packaging.inventory_item_id,
                        'required_qty', v_total_packaging_qty
                    );
                END IF;

                -- 累加扣除记录
                v_deductions := v_deductions || jsonb_build_object(
                    'menu_item', v_item_name,
                    'packaging', v_packaging.packaging_name,
                    'qty_deducted', v_total_packaging_qty,
                    'unit', v_packaging.base_unit
                );

            EXCEPTION WHEN OTHERS THEN
                RETURN jsonb_build_object(
                    'success', false,
                    'message', SQLERRM,
                    'packaging', v_packaging.packaging_name
                );
            END;
        END LOOP;

    END LOOP;

    -- 5. 所有包材扣除成功
    RAISE NOTICE '✅ 订单 #% 库存扣除完成', p_order_id;

    RETURN jsonb_build_object(
        'success', true,
        'order_id', p_order_id,
        'deductions', v_deductions,
        'message', '包材库存扣除成功'
    );

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', false,
        'message', '扣库存失败：' || SQLERRM
    );
END;
$$;

-- ==========================================
-- 5. 进货函数：支持单位换算
-- ==========================================
CREATE OR REPLACE FUNCTION receive_inventory_with_conversion(
    p_item_id BIGINT,
    p_qty INTEGER,
    p_unit TEXT,  -- 'pcs' 或 'box' 或 'bag' 等
    p_cost_per_unit NUMERIC(10, 2),
    p_supplier TEXT DEFAULT NULL,
    p_batch_number TEXT DEFAULT NULL,
    p_expiry_date DATE DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
    v_item RECORD;
    v_base_qty INTEGER;
    v_batch_id BIGINT;
    v_generated_batch_number TEXT;
BEGIN
    -- 获取品项信息
    SELECT * INTO v_item FROM inventory_items WHERE id = p_item_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'message', '品项不存在');
    END IF;

    -- 单位换算
    IF p_unit = v_item.base_unit THEN
        -- 单位一致，直接使用
        v_base_qty := p_qty;
    ELSIF v_item.units_per_case IS NOT NULL AND p_unit IN ('box', 'bag', 'pack', 'case') THEN
        -- 换算：箱/盒/包 → 基础单位
        v_base_qty := p_qty * v_item.units_per_case;
        RAISE NOTICE '单位换算：% % x % = % %',
            p_qty, p_unit, v_item.units_per_case, v_base_qty, v_item.base_unit;
    ELSE
        -- 无法换算，报错
        RETURN jsonb_build_object(
            'success', false,
            'message', FORMAT('无法换算单位：% → %', p_unit, v_item.base_unit)
        );
    END IF;

    -- 生成批次号
    IF p_batch_number IS NULL THEN
        v_generated_batch_number := 'BATCH-' ||
            TO_CHAR(NOW(), 'YYYYMMDD') || '-' ||
            LPAD(nextval('inventory_batches_id_seq')::TEXT, 6, '0');
    ELSE
        v_generated_batch_number := p_batch_number;
    END IF;

    -- 创建批次
    INSERT INTO inventory_batches (
        item_id, batch_number, qty_received, qty_remaining,
        cost_per_unit, supplier, expiry_date, is_active
    ) VALUES (
        p_item_id, v_generated_batch_number, v_base_qty, v_base_qty,
        p_cost_per_unit, p_supplier, p_expiry_date, true
    ) RETURNING id INTO v_batch_id;

    -- 记录交易
    INSERT INTO inventory_transactions (
        item_id, batch_id, transaction_type, qty,
        cost_per_unit, reference_type
    ) VALUES (
        p_item_id, v_batch_id, 'in', v_base_qty,
        p_cost_per_unit, 'receive'
    );

    -- 更新加权平均成本
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
        'qty_received', v_base_qty,
        'unit', v_item.base_unit,
        'message', FORMAT('成功入库：% % %', v_base_qty, v_item.base_unit, v_item.name)
    );
END;
$$;

-- ==========================================
-- 完成！
-- ==========================================
SELECT '✅ 可数库存系统（V2）创建成功！' as status;
