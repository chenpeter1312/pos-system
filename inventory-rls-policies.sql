-- ==========================================
-- 库存管理 RLS 策略：强制 Single Source of Truth
-- ==========================================

-- ==========================================
-- 1. 锁定 inventory_batches - 禁止直接修改 qty_remaining
-- ==========================================

-- 删除现有的宽松策略
DROP POLICY IF EXISTS "Allow authenticated users all access" ON inventory_batches;
DROP POLICY IF EXISTS "Allow public read access" ON inventory_batches;

-- 只允许读取
CREATE POLICY "Allow read inventory_batches"
ON inventory_batches
FOR SELECT
USING (true);

-- 禁止 UPDATE/DELETE（只能通过 RPC 函数修改）
CREATE POLICY "Deny direct updates to inventory_batches"
ON inventory_batches
FOR UPDATE
USING (false);

CREATE POLICY "Deny direct deletes from inventory_batches"
ON inventory_batches
FOR DELETE
USING (false);

-- 只允许通过 receive_inventory() 函数插入（由函数执行，不是用户）
-- 用户不能直接 INSERT
CREATE POLICY "Deny direct inserts to inventory_batches"
ON inventory_batches
FOR INSERT
WITH CHECK (false);

-- ==========================================
-- 2. 锁定 inventory_transactions - 只读（只能通过函数写入）
-- ==========================================

DROP POLICY IF EXISTS "Allow authenticated users all access" ON inventory_transactions;
DROP POLICY IF EXISTS "Allow public read access" ON inventory_transactions;

-- 只允许读取
CREATE POLICY "Allow read inventory_transactions"
ON inventory_transactions
FOR SELECT
USING (true);

-- 禁止任何直接写入
CREATE POLICY "Deny direct modifications to inventory_transactions"
ON inventory_transactions
FOR ALL
USING (false)
WITH CHECK (false);

-- ==========================================
-- 3. 锁定 inventory_adjustments - 只读
-- ==========================================

DROP POLICY IF EXISTS "Allow authenticated users all access" ON inventory_adjustments;
DROP POLICY IF EXISTS "Allow public read access" ON inventory_adjustments;

CREATE POLICY "Allow read inventory_adjustments"
ON inventory_adjustments
FOR SELECT
USING (true);

CREATE POLICY "Deny direct modifications to inventory_adjustments"
ON inventory_adjustments
FOR ALL
USING (false)
WITH CHECK (false);

-- ==========================================
-- 4. inventory_items 可以更新基础信息，但 current_cost 由函数计算
-- ==========================================

DROP POLICY IF EXISTS "Allow authenticated users all access" ON inventory_items;
DROP POLICY IF EXISTS "Allow public read access" ON inventory_items;

-- 允许读取
CREATE POLICY "Allow read inventory_items"
ON inventory_items
FOR SELECT
USING (true);

-- 允许认证用户更新基础信息（但不建议直接改 current_cost）
CREATE POLICY "Allow authenticated users update inventory_items"
ON inventory_items
FOR UPDATE
TO authenticated
USING (true)
WITH CHECK (true);

-- 允许认证用户插入新品项
CREATE POLICY "Allow authenticated users insert inventory_items"
ON inventory_items
FOR INSERT
TO authenticated
WITH CHECK (true);

-- ==========================================
-- 重要说明
-- ==========================================
--
-- 数据修改只能通过以下 RPC 函数：
-- 1. receive_inventory() - 入库
-- 2. deduct_inventory_fifo() - 出库（FIFO）
-- 3. quick_adjustment() - 快速调整（员工餐/报废/赠送）
-- 4. inventory_count_adjustment() - 盘点调整
-- 5. consume_inventory_for_order() - 订单扣库存（新增）
--
-- 这确保：Single Source of Truth
-- ==========================================

SELECT '🔒 RLS 策略已更新：强制通过函数修改库存！' as status;
