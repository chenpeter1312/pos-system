-- 1. 刪除舊函數
DROP FUNCTION IF EXISTS decrement_inventory(UUID, DECIMAL);
DROP FUNCTION IF EXISTS decrement_inventory_for_order(UUID);

-- 2. 建立新的安全庫存扣除函數
CREATE OR REPLACE FUNCTION decrement_inventory(
    item_id UUID,
    quantity DECIMAL
) RETURNS TABLE (
    success BOOLEAN,
    message TEXT,
    new_quantity DECIMAL
) AS $$
DECLARE
    v_current_qty DECIMAL;
    v_new_qty DECIMAL;
BEGIN
    SELECT inventory_items.quantity INTO v_current_qty
    FROM inventory_items WHERE id = item_id FOR UPDATE;

    IF NOT FOUND THEN
        RETURN QUERY SELECT FALSE, '❌ 庫存項目不存在', NULL::DECIMAL;
        RETURN;
    END IF;

    IF v_current_qty < quantity THEN
        RETURN QUERY SELECT FALSE, '⚠️ 庫存不足（當前：' || v_current_qty || '，需要：' || quantity || '）', v_current_qty;
        RETURN;
    END IF;

    v_new_qty := v_current_qty - quantity;
    UPDATE inventory_items SET quantity = v_new_qty, updated_at = NOW() WHERE id = item_id;

    RETURN QUERY SELECT TRUE, '✅ 庫存已扣除', v_new_qty;
END;
$$ LANGUAGE plpgsql;

-- 3. 建立批次庫存扣除
CREATE OR REPLACE FUNCTION decrement_inventory_for_order(
    p_order_id UUID
) RETURNS TABLE (
    success BOOLEAN,
    message TEXT,
    items_processed INT
) AS $$
DECLARE
    v_order_item RECORD;
    v_packaging RECORD;
    v_deduct_qty DECIMAL;
    v_result RECORD;
    v_items_count INT := 0;
BEGIN
    FOR v_order_item IN SELECT * FROM order_items WHERE order_id = p_order_id
    LOOP
        FOR v_packaging IN SELECT * FROM menu_packaging_map WHERE menu_item_name = v_order_item.item_name
        LOOP
            v_deduct_qty := v_packaging.qty_per_sale * v_order_item.quantity;
            SELECT * INTO v_result FROM decrement_inventory(v_packaging.inventory_item_id, v_deduct_qty);
            IF NOT v_result.success THEN
                RAISE WARNING '庫存扣除失敗：%', v_result.message;
            ELSE
                v_items_count := v_items_count + 1;
            END IF;
        END LOOP;
    END LOOP;

    RETURN QUERY SELECT TRUE, '✅ 已處理 ' || v_items_count || ' 個庫存項目', v_items_count;
END;
$$ LANGUAGE plpgsql;

-- 4. 授權
GRANT EXECUTE ON FUNCTION decrement_inventory TO authenticated, anon;
GRANT EXECUTE ON FUNCTION decrement_inventory_for_order TO authenticated, anon;
