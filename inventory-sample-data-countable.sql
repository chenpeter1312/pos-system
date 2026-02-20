-- ==========================================
-- 可数库存系统：示例数据（餐厅实战）
-- ==========================================

-- ==========================================
-- 1. 插入包材/成品库存品项
-- ==========================================

-- A. 包材/餐具（PACKAGING）
INSERT INTO inventory_items (
    name, item_type, is_countable, base_unit, units_per_case,
    reorder_point, reorder_qty, lead_time_days, safety_buffer_days, current_cost
) VALUES
    ('外帶紙盒', 'PACKAGING', true, 'pcs', 50, 100, 200, 3, 2, 0.50),
    ('外帶紙袋', 'PACKAGING', true, 'pcs', 100, 150, 300, 3, 2, 0.30),
    ('塑膠杯 - 大', 'PACKAGING', true, 'pcs', 50, 80, 200, 5, 2, 0.40),
    ('塑膠杯 - 中', 'PACKAGING', true, 'pcs', 50, 80, 200, 5, 2, 0.35),
    ('封膜', 'PACKAGING', true, 'roll', NULL, 5, 20, 7, 2, 8.00),
    ('吸管', 'PACKAGING', true, 'pcs', 100, 200, 500, 3, 1, 0.02),
    ('一次性餐具組', 'PACKAGING', true, 'pack', 50, 100, 200, 3, 2, 0.25),
    ('餐巾紙', 'PACKAGING', true, 'pack', 20, 30, 100, 3, 1, 1.50)
ON CONFLICT (name) DO UPDATE SET
    item_type = EXCLUDED.item_type,
    base_unit = EXCLUDED.base_unit,
    units_per_case = EXCLUDED.units_per_case,
    reorder_point = EXCLUDED.reorder_point,
    reorder_qty = EXCLUDED.reorder_qty;

-- B. 瓶裝飲料（BEVERAGE_PACKAGED）
INSERT INTO inventory_items (
    name, item_type, is_countable, base_unit, units_per_case,
    reorder_point, reorder_qty, lead_time_days, current_cost
) VALUES
    ('可口可樂 330ml', 'BEVERAGE_PACKAGED', true, 'can', 24, 48, 96, 2, 0.80),
    ('雪碧 330ml', 'BEVERAGE_PACKAGED', true, 'can', 24, 48, 96, 2, 0.80),
    ('瓶裝水 500ml', 'BEVERAGE_PACKAGED', true, 'bottle', 24, 48, 96, 2, 0.50)
ON CONFLICT (name) DO UPDATE SET
    item_type = EXCLUDED.item_type,
    base_unit = EXCLUDED.base_unit,
    units_per_case = EXCLUDED.units_per_case;

-- C. 冷凍成品/預包裝（PREPACKAGED_FOOD）
INSERT INTO inventory_items (
    name, item_type, is_countable, base_unit, units_per_case,
    reorder_point, reorder_qty, lead_time_days, current_cost
) VALUES
    ('冷凍薯條 1kg', 'PREPACKAGED_FOOD', true, 'bag', 10, 20, 50, 5, 3.50),
    ('章魚燒冷凍包', 'PREPACKAGED_FOOD', true, 'pack', 20, 30, 80, 5, 4.20)
ON CONFLICT (name) DO UPDATE SET
    item_type = EXCLUDED.item_type;

-- D. 蛋類（EGGS_PACK）
INSERT INTO inventory_items (
    name, item_type, is_countable, base_unit, units_per_case,
    reorder_point, reorder_qty, lead_time_days, current_cost
) VALUES
    ('雞蛋', 'EGGS_PACK', true, 'pcs', 12, 60, 120, 2, 0.25)
ON CONFLICT (name) DO UPDATE SET
    item_type = EXCLUDED.item_type,
    units_per_case = EXCLUDED.units_per_case;

-- E. 清潔/耗材（SUPPLY）
INSERT INTO inventory_items (
    name, item_type, is_countable, base_unit, units_per_case,
    reorder_point, reorder_qty, lead_time_days, current_cost
) VALUES
    ('一次性手套 - 盒', 'SUPPLY', true, 'box', NULL, 5, 20, 7, 5.00),
    ('廚房清潔劑', 'SUPPLY', true, 'bottle', 6, 3, 12, 7, 3.50)
ON CONFLICT (name) DO UPDATE SET
    item_type = EXCLUDED.item_type;

-- ==========================================
-- 2. 插入测试批次（模拟已有库存）
-- ==========================================

-- 为每个品项创建一个初始批次
INSERT INTO inventory_batches (item_id, batch_number, qty_received, qty_remaining, cost_per_unit, is_active)
SELECT
    id,
    'INITIAL-' || TO_CHAR(NOW(), 'YYYYMMDD'),
    reorder_qty * 2,  -- 初始库存是补货量的 2 倍
    reorder_qty * 2,
    current_cost,
    true
FROM inventory_items
WHERE is_countable = true
ON CONFLICT DO NOTHING;

-- ==========================================
-- 3. 配置菜单-包材映射（核心！）
-- ==========================================

-- 假设您的菜单有这些项目（需要根据实际菜单调整）
-- 这里用常见的台湾小吃举例

-- 滷肉飯 → 需要：外帶紙盒 x1, 外帶紙袋 x1, 餐具組 x1
INSERT INTO menu_packaging_map (menu_item_name, inventory_item_id, qty_per_sale, notes)
SELECT '滷肉飯', id, 1, '便當盒' FROM inventory_items WHERE name = '外帶紙盒'
UNION ALL
SELECT '滷肉飯', id, 1, '提袋' FROM inventory_items WHERE name = '外帶紙袋'
UNION ALL
SELECT '滷肉飯', id, 1, '餐具' FROM inventory_items WHERE name = '一次性餐具組'
ON CONFLICT DO NOTHING;

-- 牛肉麵 → 需要：外帶紙盒 x1, 外帶紙袋 x1, 餐具組 x1
INSERT INTO menu_packaging_map (menu_item_name, inventory_item_id, qty_per_sale, notes)
SELECT '牛肉麵', id, 1, '便當盒' FROM inventory_items WHERE name = '外帶紙盒'
UNION ALL
SELECT '牛肉麵', id, 1, '提袋' FROM inventory_items WHERE name = '外帶紙袋'
UNION ALL
SELECT '牛肉麵', id, 1, '餐具' FROM inventory_items WHERE name = '一次性餐具組'
ON CONFLICT DO NOTHING;

-- 珍珠奶茶 → 需要：塑膠杯-大 x1, 封膜 x1, 吸管 x1, 外帶紙袋 x1
INSERT INTO menu_packaging_map (menu_item_name, inventory_item_id, qty_per_sale, notes)
SELECT '珍珠奶茶', id, 1, '飲料杯' FROM inventory_items WHERE name = '塑膠杯 - 大'
UNION ALL
SELECT '珍珠奶茶', id, 1, '封口' FROM inventory_items WHERE name = '封膜'
UNION ALL
SELECT '珍珠奶茶', id, 1, '吸管' FROM inventory_items WHERE name = '吸管'
UNION ALL
SELECT '珍珠奶茶', id, 1, '提袋' FROM inventory_items WHERE name = '外帶紙袋'
ON CONFLICT DO NOTHING;

-- 可樂 → 如果是瓶裝，直接扣可樂庫存
INSERT INTO menu_packaging_map (menu_item_name, inventory_item_id, qty_per_sale, notes)
SELECT '可口可樂', id, 1, '罐裝飲料' FROM inventory_items WHERE name = '可口可樂 330ml'
ON CONFLICT DO NOTHING;

-- ==========================================
-- 4. 查看配置结果
-- ==========================================

-- 查看所有包材品项
SELECT
    item_type AS 分類,
    name AS 品項名稱,
    base_unit AS 單位,
    units_per_case AS 每箱數量,
    reorder_point AS 補貨點,
    reorder_qty AS 建議補貨量,
    current_cost AS 單位成本
FROM inventory_items
WHERE is_countable = true
ORDER BY item_type, name;

-- 查看菜单-包材映射
SELECT
    mpm.menu_item_name AS 菜品,
    ii.name AS 需要的包材,
    mpm.qty_per_sale AS 每份消耗數量,
    ii.base_unit AS 單位,
    mpm.notes AS 備註
FROM menu_packaging_map mpm
JOIN inventory_items ii ON ii.id = mpm.inventory_item_id
ORDER BY mpm.menu_item_name, ii.name;

-- 查看库存总览
SELECT
    name AS 品項,
    qty_on_hand AS 現有庫存,
    unit AS 單位,
    stock_status AS 狀態,
    CASE
        WHEN stock_status = 'low_stock' THEN suggested_reorder_qty
        ELSE 0
    END AS 建議補貨
FROM inventory_overview
ORDER BY
    CASE stock_status
        WHEN 'out_of_stock' THEN 1
        WHEN 'low_stock' THEN 2
        ELSE 3
    END,
    name;

-- ==========================================
-- 完成！
-- ==========================================
SELECT '✅ 示例数据插入成功！可以开始测试了！' as status;
