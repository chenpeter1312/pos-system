-- ==========================================
-- 菜单-包装配置管理
-- ==========================================

-- ==========================================
-- 1️⃣ 查看当前配置
-- ==========================================

-- 查看所有菜品的包装配置
SELECT
    mpm.menu_item_name AS 菜品名稱,
    ii.name AS 包材名稱,
    mpm.qty_per_sale AS 每單用量,
    mpm.notes AS 備註,
    ii.base_unit AS 單位,
    ii.qty_on_hand AS 當前庫存
FROM menu_packaging_map mpm
JOIN inventory_items ii ON ii.id = mpm.inventory_item_id
LEFT JOIN inventory_overview io ON io.item_id = ii.id
ORDER BY mpm.menu_item_name, ii.name;

-- 统计各菜品的包材种类
SELECT
    menu_item_name AS 菜品,
    COUNT(*) AS 包材種類數,
    STRING_AGG(ii.name || ' x' || qty_per_sale, ', ') AS 包材清單
FROM menu_packaging_map mpm
JOIN inventory_items ii ON ii.id = mpm.inventory_item_id
GROUP BY menu_item_name
ORDER BY menu_item_name;

-- ==========================================
-- 2️⃣ 修改配置示例
-- ==========================================

-- 示例 A：修改某个菜品的包材用量
-- 例如：「滷肉飯」需要 2 個紙盒（因為飯量大）
UPDATE menu_packaging_map
SET qty_per_sale = 2
WHERE menu_item_name = '滷肉飯'
  AND inventory_item_id = (SELECT id FROM inventory_items WHERE name = '外帶紙盒');

-- 示例 B：某些菜品不需要餐具（例如飲料）
-- 刪除「台灣啤酒」的餐具配置
DELETE FROM menu_packaging_map
WHERE menu_item_name = '台灣啤酒'
  AND inventory_item_id = (SELECT id FROM inventory_items WHERE name = '一次性餐具組');

-- 示例 C：為特定菜品添加額外包材
-- 例如：「湯類」需要額外的湯杯
INSERT INTO menu_packaging_map (menu_item_name, inventory_item_id, qty_per_sale, notes)
SELECT
    '酸辣湯',
    id,
    1,
    '湯杯'
FROM inventory_items
WHERE name = '外帶湯杯'
ON CONFLICT (menu_item_name, inventory_item_id) DO UPDATE
SET qty_per_sale = EXCLUDED.qty_per_sale;

-- 示例 D：批量修改所有飲料類不需要紙盒（只需要紙袋）
DELETE FROM menu_packaging_map
WHERE menu_item_name IN ('台灣啤酒', '可樂', '雪碧', '珍珠奶茶')
  AND inventory_item_id = (SELECT id FROM inventory_items WHERE name = '外帶紙盒');

-- ==========================================
-- 3️⃣ 常見配置模板
-- ==========================================

-- 模板 1：便當類（需要：紙盒 + 紙袋 + 餐具）
-- 已由 inventory-basic-setup.sql 自動配置

-- 模板 2：飲料類（只需要：紙袋）
-- 刪除飲料的紙盒和餐具配置
DO $$
DECLARE
    drink_names TEXT[] := ARRAY['台灣啤酒', '可樂', '雪碧', '珍珠奶茶'];
    drink_name TEXT;
BEGIN
    FOREACH drink_name IN ARRAY drink_names LOOP
        -- 刪除紙盒
        DELETE FROM menu_packaging_map
        WHERE menu_item_name = drink_name
          AND inventory_item_id = (SELECT id FROM inventory_items WHERE name = '外帶紙盒');

        -- 刪除餐具
        DELETE FROM menu_packaging_map
        WHERE menu_item_name = drink_name
          AND inventory_item_id = (SELECT id FROM inventory_items WHERE name = '一次性餐具組');
    END LOOP;
END $$;

-- 模板 3：湯類（需要：湯杯 + 紙袋）
-- 首先確保有湯杯品項
INSERT INTO inventory_items (
    name, item_type, is_countable, base_unit, units_per_case,
    reorder_point, reorder_qty, lead_time_days, safety_buffer_days, current_cost
) VALUES (
    '外帶湯杯', 'PACKAGING', true, 'pcs', 100, 150, 300, 3, 2, 0.40
)
ON CONFLICT (name) DO NOTHING;

-- 為湯類菜品配置湯杯
INSERT INTO menu_packaging_map (menu_item_name, inventory_item_id, qty_per_sale, notes)
SELECT
    '酸辣湯',
    ii.id,
    1,
    '湯杯'
FROM inventory_items ii
WHERE ii.name = '外帶湯杯'
ON CONFLICT (menu_item_name, inventory_item_id) DO NOTHING;

-- ==========================================
-- 4️⃣ 重置某個菜品的配置
-- ==========================================

-- 例如：重置「滷肉飯」為標準配置（1紙盒+1紙袋+1餐具）
-- 先刪除舊配置
DELETE FROM menu_packaging_map WHERE menu_item_name = '滷肉飯';

-- 重新添加標準配置
INSERT INTO menu_packaging_map (menu_item_name, inventory_item_id, qty_per_sale, notes)
SELECT
    '滷肉飯',
    ii.id,
    1,
    CASE ii.name
        WHEN '外帶紙盒' THEN '便當盒'
        WHEN '外帶紙袋' THEN '提袋'
        WHEN '一次性餐具組' THEN '餐具'
    END
FROM inventory_items ii
WHERE ii.name IN ('外帶紙盒', '外帶紙袋', '一次性餐具組');

-- ==========================================
-- 5️⃣ 驗證配置變更
-- ==========================================

-- 查看修改後的配置
SELECT
    '✅ 配置驗證' AS 類別,
    mpm.menu_item_name AS 菜品,
    STRING_AGG(ii.name || ' x' || mpm.qty_per_sale, ', ' ORDER BY ii.name) AS 包材配置
FROM menu_packaging_map mpm
JOIN inventory_items ii ON ii.id = mpm.inventory_item_id
GROUP BY mpm.menu_item_name
ORDER BY mpm.menu_item_name;

-- ==========================================
-- 📝 使用說明
-- ==========================================

-- 1. 在 Supabase Dashboard → SQL Editor 執行查詢
-- 2. 先執行「1️⃣ 查看當前配置」了解現狀
-- 3. 根據需求修改「2️⃣ 修改配置示例」中的 SQL
-- 4. 執行修改後，用「5️⃣ 驗證配置變更」檢查結果

-- ⚠️ 注意事項：
-- - menu_item_name 必須與 menu 表中的 name 完全一致
-- - 修改後會立即生效，下一筆訂單就會使用新配置
-- - 建議先在測試環境驗證，再應用到生產環境
