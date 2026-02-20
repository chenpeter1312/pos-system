-- ==========================================
-- 創建庫存扣除 RPC 函數
-- ==========================================
-- 說明：員工 POS 系統使用此函數來自動扣除庫存

-- 創建庫存扣除函數
CREATE OR REPLACE FUNCTION decrement_inventory(
    item_id UUID,
    quantity NUMERIC
)
RETURNS VOID AS $$
BEGIN
    -- 更新庫存數量
    UPDATE inventory_items
    SET
        qty_on_hand = qty_on_hand - quantity,
        updated_at = NOW()
    WHERE id = item_id;

    -- 記錄庫存交易（如果有 inventory_transactions 表）
    INSERT INTO inventory_transactions (
        item_id,
        transaction_type,
        quantity,
        notes,
        created_at
    )
    VALUES (
        item_id,
        'deduction',
        -quantity,
        '員工 POS 自動扣除',
        NOW()
    )
    ON CONFLICT DO NOTHING;

END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION decrement_inventory IS '扣除庫存數量（用於員工POS訂單）';

-- ==========================================
-- 測試函數
-- ==========================================

-- 查看某個庫存項目的當前數量
-- SELECT id, name, qty_on_hand FROM inventory_items WHERE name = '外帶紙盒';

-- 測試扣除（將 UUID 替換為實際的 item_id）
-- SELECT decrement_inventory('你的-item-id-這裡', 5);

-- 再次查看數量確認
-- SELECT id, name, qty_on_hand FROM inventory_items WHERE name = '外帶紙盒';
