-- ==========================================
-- 库存管理系统 - 数据库 Schema
-- Lee's Taiwanese Comfort Food
-- ==========================================

-- ==========================================
-- 1. 库存物品主表 (inventory_items)
-- ==========================================
CREATE TABLE IF NOT EXISTS inventory_items (
    id BIGSERIAL PRIMARY KEY,
    name TEXT NOT NULL,                          -- 中文名称
    name_en TEXT,                                -- 英文名称
    unit TEXT NOT NULL DEFAULT 'unit',           -- 单位：份、kg、个、ml
    reorder_point INTEGER NOT NULL DEFAULT 50,   -- 补货点（触发预警）
    lead_time_days INTEGER NOT NULL DEFAULT 3,   -- 到货天数
    safety_buffer_days INTEGER DEFAULT 2,        -- 安全缓冲天数
    current_cost NUMERIC(10, 2),                 -- 当前成本/单位
    menu_item_id BIGINT,                         -- 关联菜单（可选）
    category TEXT,                               -- 分类：食材、包装、调料
    supplier TEXT,                               -- 默认供应商
    notes TEXT,                                  -- 备注
    is_active BOOLEAN DEFAULT true,              -- 是否启用
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    -- 外键约束
    CONSTRAINT fk_menu_item FOREIGN KEY (menu_item_id) 
        REFERENCES menu(id) ON DELETE SET NULL
);

-- 索引
CREATE INDEX IF NOT EXISTS idx_inventory_items_active ON inventory_items(is_active);
CREATE INDEX IF NOT EXISTS idx_inventory_items_category ON inventory_items(category);

-- ==========================================
-- 2. 批次表 (inventory_batches) - FIFO 核心
-- ==========================================
CREATE TABLE IF NOT EXISTS inventory_batches (
    id BIGSERIAL PRIMARY KEY,
    item_id BIGINT NOT NULL,                     -- 关联物品
    batch_number TEXT NOT NULL,                  -- 批次号
    qty_received INTEGER NOT NULL,               -- 入库数量
    qty_remaining INTEGER NOT NULL,              -- 剩余数量
    cost_per_unit NUMERIC(10, 2) NOT NULL,       -- 该批次成本
    received_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),  -- 入库时间（FIFO排序）
    expiry_date DATE,                            -- 过期日期（可选）
    supplier TEXT,                               -- 供应商
    po_number TEXT,                              -- 采购单号
    is_active BOOLEAN DEFAULT true,              -- 是否活跃（qty_remaining > 0）
    notes TEXT,                                  -- 备注
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    -- 外键约束
    CONSTRAINT fk_item FOREIGN KEY (item_id) 
        REFERENCES inventory_items(id) ON DELETE CASCADE,
    
    -- 检查约束
    CONSTRAINT check_qty_positive CHECK (qty_received > 0),
    CONSTRAINT check_remaining CHECK (qty_remaining >= 0 AND qty_remaining <= qty_received)
);

-- 索引（FIFO 查询优化）
CREATE INDEX IF NOT EXISTS idx_batches_item_fifo 
    ON inventory_batches(item_id, received_at) 
    WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_batches_active ON inventory_batches(is_active);

-- ==========================================
-- 3. 库存调整表 (inventory_adjustments)
-- ==========================================
CREATE TABLE IF NOT EXISTS inventory_adjustments (
    id BIGSERIAL PRIMARY KEY,
    item_id BIGINT NOT NULL,
    batch_id BIGINT,                             -- 关联批次（可选）
    adjustment_type TEXT NOT NULL,               -- 类型
    qty_change INTEGER NOT NULL,                 -- 数量变化（可正可负）
    cost_impact NUMERIC(10, 2),                  -- 成本影响
    reason TEXT,                                 -- 原因
    adjusted_by TEXT,                            -- 操作人员
    adjusted_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    notes TEXT,
    
    -- 外键约束
    CONSTRAINT fk_adjustment_item FOREIGN KEY (item_id) 
        REFERENCES inventory_items(id) ON DELETE CASCADE,
    CONSTRAINT fk_adjustment_batch FOREIGN KEY (batch_id) 
        REFERENCES inventory_batches(id) ON DELETE SET NULL,
    
    -- 检查约束
    CONSTRAINT check_adjustment_type CHECK (
        adjustment_type IN ('staff_meal', 'waste', 'damaged', 'gift', 'count_adjustment', 'return')
    )
);

-- 索引
CREATE INDEX IF NOT EXISTS idx_adjustments_item ON inventory_adjustments(item_id);
CREATE INDEX IF NOT EXISTS idx_adjustments_date ON inventory_adjustments(adjusted_at DESC);
CREATE INDEX IF NOT EXISTS idx_adjustments_type ON inventory_adjustments(adjustment_type);

-- ==========================================
-- 4. 库存交易记录表 (inventory_transactions)
-- ==========================================
CREATE TABLE IF NOT EXISTS inventory_transactions (
    id BIGSERIAL PRIMARY KEY,
    item_id BIGINT NOT NULL,
    batch_id BIGINT,                             -- 关联批次
    transaction_type TEXT NOT NULL,              -- in/out
    qty INTEGER NOT NULL,                        -- 数量
    cost_per_unit NUMERIC(10, 2),                -- 单位成本
    reference_type TEXT,                         -- order/adjustment/receive
    reference_id BIGINT,                         -- 关联ID
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    -- 外键约束
    CONSTRAINT fk_transaction_item FOREIGN KEY (item_id) 
        REFERENCES inventory_items(id) ON DELETE CASCADE,
    CONSTRAINT fk_transaction_batch FOREIGN KEY (batch_id) 
        REFERENCES inventory_batches(id) ON DELETE SET NULL,
    
    -- 检查约束
    CONSTRAINT check_transaction_type CHECK (transaction_type IN ('in', 'out')),
    CONSTRAINT check_qty_positive_tx CHECK (qty > 0)
);

-- 索引
CREATE INDEX IF NOT EXISTS idx_transactions_item ON inventory_transactions(item_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_transactions_batch ON inventory_transactions(batch_id);
CREATE INDEX IF NOT EXISTS idx_transactions_reference ON inventory_transactions(reference_type, reference_id);

-- ==========================================
-- 5. 菜单成本历史表 (menu_item_costs)
-- ==========================================
CREATE TABLE IF NOT EXISTS menu_item_costs (
    id BIGSERIAL PRIMARY KEY,
    menu_item_id BIGINT NOT NULL,
    cost_per_unit NUMERIC(10, 2) NOT NULL,       -- 计算出的成本
    ingredient_costs JSONB,                      -- 详细成本明细
    calculated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    -- 外键约束
    CONSTRAINT fk_cost_menu_item FOREIGN KEY (menu_item_id) 
        REFERENCES menu(id) ON DELETE CASCADE
);

-- 索引
CREATE INDEX IF NOT EXISTS idx_menu_costs_item ON menu_item_costs(menu_item_id, calculated_at DESC);

-- ==========================================
-- 6. 自动更新 updated_at 触发器
-- ==========================================
CREATE TRIGGER update_inventory_items_updated_at
    BEFORE UPDATE ON inventory_items
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ==========================================
-- 7. 启用 RLS (Row Level Security)
-- ==========================================
ALTER TABLE inventory_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory_batches ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory_adjustments ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE menu_item_costs ENABLE ROW LEVEL SECURITY;

-- 策略：公开可读，认证可写
CREATE POLICY "Anyone can view inventory items" 
    ON inventory_items FOR SELECT USING (true);
CREATE POLICY "Authenticated can modify inventory items" 
    ON inventory_items FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE POLICY "Anyone can view batches" 
    ON inventory_batches FOR SELECT USING (true);
CREATE POLICY "Authenticated can modify batches" 
    ON inventory_batches FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE POLICY "Anyone can view adjustments" 
    ON inventory_adjustments FOR SELECT USING (true);
CREATE POLICY "Authenticated can modify adjustments" 
    ON inventory_adjustments FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE POLICY "Anyone can view transactions" 
    ON inventory_transactions FOR SELECT USING (true);
CREATE POLICY "Authenticated can modify transactions" 
    ON inventory_transactions FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE POLICY "Anyone can view menu costs" 
    ON menu_item_costs FOR SELECT USING (true);
CREATE POLICY "Authenticated can modify menu costs" 
    ON menu_item_costs FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- ==========================================
-- 8. 创建视图：实时库存总览
-- ==========================================
CREATE OR REPLACE VIEW inventory_overview AS
SELECT 
    i.id,
    i.name,
    i.name_en,
    i.unit,
    i.current_cost,
    i.reorder_point,
    i.lead_time_days,
    i.safety_buffer_days,
    
    -- 当前库存（所有活跃批次剩余数量总和）
    COALESCE(SUM(b.qty_remaining), 0) AS on_hand,
    
    -- 批次数量
    COUNT(DISTINCT CASE WHEN b.is_active THEN b.id END) AS active_batches,
    
    -- 总成本价值
    COALESCE(SUM(b.qty_remaining * b.cost_per_unit), 0) AS total_value,
    
    -- 加权平均成本
    CASE 
        WHEN SUM(b.qty_remaining) > 0 
        THEN SUM(b.qty_remaining * b.cost_per_unit) / SUM(b.qty_remaining)
        ELSE i.current_cost
    END AS weighted_avg_cost,
    
    -- 最早批次日期
    MIN(CASE WHEN b.is_active THEN b.received_at END) AS oldest_batch_date,
    
    -- 预警状态
    CASE 
        WHEN COALESCE(SUM(b.qty_remaining), 0) <= i.reorder_point 
        THEN 'low_stock'
        WHEN COALESCE(SUM(b.qty_remaining), 0) = 0 
        THEN 'out_of_stock'
        ELSE 'ok'
    END AS stock_status
    
FROM inventory_items i
LEFT JOIN inventory_batches b ON i.id = b.item_id AND b.is_active = true
WHERE i.is_active = true
GROUP BY i.id, i.name, i.name_en, i.unit, i.current_cost, 
         i.reorder_point, i.lead_time_days, i.safety_buffer_days;

-- ==========================================
-- 完成！
-- ==========================================
SELECT '✅ 库存管理系统 Schema 创建成功！' as status;
