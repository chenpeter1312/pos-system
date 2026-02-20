-- ==========================================
-- 订单-库存集成：自动扣库存函数
-- ==========================================

-- ==========================================
-- 创建菜单-库存映射表（Menu Recipe）
-- ==========================================
CREATE TABLE IF NOT EXISTS menu_item_recipes (
    id BIGSERIAL PRIMARY KEY,
    menu_item_name TEXT NOT NULL,  -- 菜单品项名称（例如："滷肉飯"）
    inventory_item_id BIGINT NOT NULL REFERENCES inventory_items(id),
    qty_needed NUMERIC(10, 3) NOT NULL,  -- 每份需要的数量（可以是小数）
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 索引优化
CREATE INDEX IF NOT EXISTS idx_menu_item_recipes_menu_name
ON menu_item_recipes(menu_item_name);

-- RLS 策略
ALTER TABLE menu_item_recipes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow read menu_item_recipes" ON menu_item_recipes;
CREATE POLICY "Allow read menu_item_recipes"
ON menu_item_recipes
FOR SELECT
USING (true);

DROP POLICY IF EXISTS "Allow authenticated users modify menu_item_recipes" ON menu_item_recipes;
CREATE POLICY "Allow authenticated users modify menu_item_recipes"
ON menu_item_recipes
FOR ALL
TO authenticated
USING (true)
WITH CHECK (true);

-- ==========================================
-- 函数：订单完成时扣库存
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
    v_recipe RECORD;
    v_total_cost NUMERIC(10, 2) := 0;
    v_deductions JSONB := '[]'::JSONB;
    v_result JSONB;
    v_item_name TEXT;
    v_item_qty INTEGER;
    v_inventory_qty NUMERIC(10, 3);
BEGIN
    -- 1. 读取订单
    SELECT * INTO v_order
    FROM orders
    WHERE id = p_order_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', false,
            'message', '订单不存在：' || p_order_id
        );
    END IF;

    -- 2. 遍历订单中的每个商品
    FOR v_item IN SELECT * FROM jsonb_array_elements(v_order.items)
    LOOP
        v_item_name := v_item->>'name';
        v_item_qty := (v_item->>'quantity')::INTEGER;

        RAISE NOTICE '处理菜品：% x %', v_item_name, v_item_qty;

        -- 3. 查找该菜品的原料配方
        FOR v_recipe IN
            SELECT
                mir.inventory_item_id,
                mir.qty_needed,
                ii.name AS inventory_name
            FROM menu_item_recipes mir
            JOIN inventory_items ii ON ii.id = mir.inventory_item_id
            WHERE mir.menu_item_name = v_item_name
        LOOP
            -- 计算需要扣除的库存数量
            v_inventory_qty := v_recipe.qty_needed * v_item_qty;

            RAISE NOTICE '  - 需要原料：% x %.3f = %.3f',
                v_recipe.inventory_name,
                v_recipe.qty_needed,
                v_inventory_qty;

            -- 4. FIFO 扣除库存
            BEGIN
                v_result := deduct_inventory_fifo(
                    v_recipe.inventory_item_id,
                    CEIL(v_inventory_qty)::INTEGER,  -- 向上取整
                    'order',
                    p_order_id
                );

                IF NOT (v_result->>'success')::BOOLEAN THEN
                    -- 库存不足
                    RETURN jsonb_build_object(
                        'success', false,
                        'message', '库存不足：' || v_recipe.inventory_name,
                        'inventory_item_id', v_recipe.inventory_item_id,
                        'required_qty', v_inventory_qty
                    );
                END IF;

                -- 累加扣除记录
                v_deductions := v_deductions || jsonb_build_object(
                    'menu_item', v_item_name,
                    'inventory_item', v_recipe.inventory_name,
                    'qty_deducted', v_inventory_qty,
                    'fifo_result', v_result
                );

            EXCEPTION WHEN OTHERS THEN
                -- 捕获库存不足异常
                RETURN jsonb_build_object(
                    'success', false,
                    'message', SQLERRM,
                    'inventory_item', v_recipe.inventory_name
                );
            END;
        END LOOP;

    END LOOP;

    -- 5. 所有库存扣除成功
    RETURN jsonb_build_object(
        'success', true,
        'order_id', p_order_id,
        'deductions', v_deductions,
        'message', '库存扣除成功'
    );

EXCEPTION WHEN OTHERS THEN
    -- 捕获其他异常
    RETURN jsonb_build_object(
        'success', false,
        'message', '扣库存失败：' || SQLERRM
    );
END;
$$;

-- ==========================================
-- 插入测试配方数据（示例）
-- ==========================================
-- 假设您有以下菜品和原料：
-- 菜品：滷肉飯 → 需要：米饭 x1, 滷肉 x1
-- 菜品：牛肉麵 → 需要：麵條 x1, 牛肉 x1

-- 示例（需要根据实际情况调整）：
-- INSERT INTO menu_item_recipes (menu_item_name, inventory_item_id, qty_needed)
-- SELECT '滷肉飯', id, 1.0 FROM inventory_items WHERE name = '米饭'
-- UNION ALL
-- SELECT '滷肉飯', id, 1.0 FROM inventory_items WHERE name = '滷肉';

-- ==========================================
-- 完成！
-- ==========================================
SELECT '✅ 订单-库存集成函数创建成功！' as status;
