-- ==========================================
-- 基础包材配置（修复版）
-- ==========================================

-- ==========================================
-- 1. 先确保 inventory_items.name 有唯一约束
-- ==========================================
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'inventory_items_name_key'
    ) THEN
        ALTER TABLE inventory_items ADD CONSTRAINT inventory_items_name_key UNIQUE (name);
    END IF;
END $$;

-- ==========================================
-- 2. 插入 3 个核心包材品项
-- ==========================================
INSERT INTO inventory_items (
    name, item_type, is_countable, base_unit, units_per_case,
    reorder_point, reorder_qty, lead_time_days, safety_buffer_days, current_cost
) VALUES
    ('外帶紙盒', 'PACKAGING', true, 'pcs', 50, 100, 200, 3, 2, 0.50),
    ('外帶紙袋', 'PACKAGING', true, 'pcs', 100, 150, 300, 3, 2, 0.30),
    ('一次性餐具組', 'PACKAGING', true, 'pack', 50, 100, 200, 3, 2, 0.25)
ON CONFLICT (name) DO UPDATE SET
    item_type = EXCLUDED.item_type,
    base_unit = EXCLUDED.base_unit,
    units_per_case = EXCLUDED.units_per_case,
    reorder_point = EXCLUDED.reorder_point,
    reorder_qty = EXCLUDED.reorder_qty,
    current_cost = EXCLUDED.current_cost;

-- ==========================================
-- 3. 为每个包材添加初始库存（各 400 个）
-- ==========================================

-- 先删除可能存在的初始化批次（避免重复）
DELETE FROM inventory_batches
WHERE batch_number LIKE 'INIT-%'
  AND item_id IN (
      SELECT id FROM inventory_items
      WHERE name IN ('外帶紙盒', '外帶紙袋', '一次性餐具組')
  );

-- 插入新的初始批次
INSERT INTO inventory_batches (item_id, batch_number, qty_received, qty_remaining, cost_per_unit, supplier, is_active)
SELECT
    id,
    'INIT-' || TO_CHAR(NOW(), 'YYYYMMDD'),
    400,
    400,
    current_cost,
    'Initial Setup',
    true
FROM inventory_items
WHERE name IN ('外帶紙盒', '外帶紙袋', '一次性餐具組');

-- 写入 transactions 记录
INSERT INTO inventory_transactions (item_id, batch_id, transaction_type, qty, cost_per_unit, reference_type)
SELECT
    ib.item_id,
    ib.id,
    'in',
    ib.qty_received,
    ib.cost_per_unit,
    'initial_setup'
FROM inventory_batches ib
JOIN inventory_items ii ON ii.id = ib.item_id
WHERE ii.name IN ('外帶紙盒', '外帶紙袋', '一次性餐具組')
  AND ib.batch_number LIKE 'INIT-%';

-- ==========================================
-- 4. 自动为所有菜单项配置默认包材映射
-- ==========================================
INSERT INTO menu_packaging_map (menu_item_name, inventory_item_id, qty_per_sale, notes)
SELECT
    m.name AS menu_item_name,
    ii.id AS inventory_item_id,
    1 AS qty_per_sale,
    CASE ii.name
        WHEN '外帶紙盒' THEN '便當盒'
        WHEN '外帶紙袋' THEN '提袋'
        WHEN '一次性餐具組' THEN '餐具'
    END AS notes
FROM menu m
CROSS JOIN inventory_items ii
WHERE ii.name IN ('外帶紙盒', '外帶紙袋', '一次性餐具組')
  AND m.is_available = true
ON CONFLICT (menu_item_name, inventory_item_id) DO NOTHING;

-- ==========================================
-- 5. 查看配置结果
-- ==========================================

-- 包材库存
SELECT
    '📦 包材庫存' AS 类别,
    ii.name AS 包材名稱,
    ii.base_unit AS 單位,
    COALESCE(SUM(ib.qty_remaining), 0) AS 現有庫存,
    ii.reorder_point AS 補貨點,
    ii.reorder_qty AS 建議補貨量
FROM inventory_items ii
LEFT JOIN inventory_batches ib ON ib.item_id = ii.id AND ib.is_active = true
WHERE ii.name IN ('外帶紙盒', '外帶紙袋', '一次性餐具組')
GROUP BY ii.id, ii.name, ii.base_unit, ii.reorder_point, ii.reorder_qty
ORDER BY ii.name;

-- 菜单映射统计
SELECT
    '📋 菜單映射' AS 类别,
    mpm.menu_item_name AS 菜品,
    COUNT(*) AS 包材數量,
    STRING_AGG(ii.name || ' x' || mpm.qty_per_sale, ', ') AS 包材清單
FROM menu_packaging_map mpm
JOIN inventory_items ii ON ii.id = mpm.inventory_item_id
GROUP BY mpm.menu_item_name
ORDER BY mpm.menu_item_name
LIMIT 10;  -- 只显示前 10 个菜品

-- 库存总览
SELECT
    '📊 庫存總覽' AS 类别,
    name AS 品項,
    qty_on_hand AS 現有庫存,
    unit AS 單位,
    stock_status AS 狀態,
    CASE
        WHEN stock_status = 'ok' THEN '✅ 充足'
        WHEN stock_status = 'low_stock' THEN '⚠️ 偏低'
        WHEN stock_status = 'out_of_stock' THEN '❌ 缺貨'
    END AS 狀態說明
FROM inventory_overview
ORDER BY name;

-- 最终统计
SELECT
    '✅ 基础包材配置完成！' AS status,
    (SELECT COUNT(*) FROM inventory_items WHERE name IN ('外帶紙盒', '外帶紙袋', '一次性餐具組')) AS 包材品項數,
    (SELECT COUNT(DISTINCT menu_item_name) FROM menu_packaging_map) AS 已配置菜品數,
    (SELECT COUNT(*) FROM menu_packaging_map) AS 總映射數,
    (SELECT SUM(qty_on_hand) FROM inventory_overview) AS 總庫存數量;
