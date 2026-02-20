# 🎯 可数库存系统实施指南（V2 - 实战版）

## 💡 核心理念

> **"从包材开始，比做食材准 100 倍！"**

### 为什么先做包材？

| 类型 | 准确度 | 实施难度 | 价值 |
|------|--------|---------|------|
| **包材**（盒子、袋子、吸管） | ✅ 99% | ⭐ 简单 | 🔥 高（不缺包材才能营业） |
| 饮料罐装 | ✅ 99% | ⭐ 简单 | 🔥 高 |
| 食材（克数、配方） | ⚠️ 60% | ⭐⭐⭐ 复杂 | 📊 中（参考用） |

**结论**：包材消耗 = 1:1 精准，而且是餐厅生存必需品！

---

## 🚀 完整实施流程（15 分钟）

### 步骤 1️⃣：执行升级 SQL（3 分钟）

**在 Supabase SQL Editor 执行**：

```bash
文件：inventory-schema-v2-countable.sql
```

这会：
- ✅ 升级 `inventory_items` 表（增加 item_type, base_unit, units_per_case 等）
- ✅ 创建 `menu_packaging_map` 表（菜品-包材映射）
- ✅ 更新 `consume_inventory_for_order()` 函数（改为扣包材）
- ✅ 创建 `receive_inventory_with_conversion()` 函数（支持单位换算）

---

### 步骤 2️⃣：插入示例数据（2 分钟）⏸️ 可选

**如果您想测试系统，执行**：

```bash
文件：inventory-sample-data-countable.sql
```

这会插入：
- 📦 8 种包材（纸盒、纸袋、杯子、吸管等）
- 🥤 3 种瓶装饮料
- 🍟 2 种预包装食品
- 🥚 1 种蛋类
- 🧼 2 种清潔耗材
- 📋 示例菜单-包材映射（滷肉飯、牛肉麵、珍珠奶茶）

---

### 步骤 3️⃣：配置您的实际数据（10 分钟）

#### A. 添加您的包材品项

```sql
INSERT INTO inventory_items (
    name,                 -- 品项名称
    item_type,            -- PACKAGING / BEVERAGE_PACKAGED / PREPACKAGED_FOOD / EGGS_PACK / SUPPLY
    is_countable,         -- true
    base_unit,            -- pcs / box / bag / bottle / can / roll / pack
    units_per_case,       -- 每箱/盒/包包含的数量（可选）
    reorder_point,        -- 低于此数量时预警
    reorder_qty,          -- 建议补货数量
    lead_time_days,       -- 供应商到货天数
    safety_buffer_days,   -- 安全缓冲天数（Texas 天气延误）
    current_cost          -- 单位成本
) VALUES
    ('外帶紙盒', 'PACKAGING', true, 'pcs', 50, 100, 200, 3, 2, 0.50),
    ('塑膠杯 - 大', 'PACKAGING', true, 'pcs', 50, 80, 200, 5, 2, 0.40);
    -- ... 继续添加您的品项
```

**关键字段说明**：

| 字段 | 说明 | 示例 |
|------|------|------|
| `base_unit` | 主单位（只选一个） | `pcs`（个）、`can`（罐）、`bottle`（瓶） |
| `units_per_case` | 每箱/盒包含的基础单位数 | 50（1 box = 50 pcs） |
| `reorder_point` | 低于此数量触发预警 | 100（低于 100 个时提醒补货） |
| `reorder_qty` | 建议补货数量 | 200（建议一次补 200 个） |

---

#### B. 配置菜单-包材映射

**重要**：告诉系统「每卖 1 份菜品，需要消耗哪些包材」

```sql
-- 示例：滷肉飯需要 1 个盒子 + 1 个袋子 + 1 套餐具
INSERT INTO menu_packaging_map (menu_item_name, inventory_item_id, qty_per_sale, notes)
SELECT '滷肉飯', id, 1, '便當盒' FROM inventory_items WHERE name = '外帶紙盒'
UNION ALL
SELECT '滷肉飯', id, 1, '提袋' FROM inventory_items WHERE name = '外帶紙袋'
UNION ALL
SELECT '滷肉飯', id, 1, '餐具' FROM inventory_items WHERE name = '一次性餐具組';

-- 示例：珍珠奶茶需要 1 个杯子 + 1 个封膜 + 1 根吸管
INSERT INTO menu_packaging_map (menu_item_name, inventory_item_id, qty_per_sale, notes)
SELECT '珍珠奶茶', id, 1, '飲料杯' FROM inventory_items WHERE name = '塑膠杯 - 大'
UNION ALL
SELECT '珍珠奶茶', id, 1, '封口' FROM inventory_items WHERE name = '封膜'
UNION ALL
SELECT '珍珠奶茶', id, 1, '吸管' FROM inventory_items WHERE name = '吸管';
```

**验证配置**：

```sql
SELECT
    mpm.menu_item_name AS 菜品,
    ii.name AS 包材,
    mpm.qty_per_sale AS 每份消耗,
    ii.base_unit AS 单位
FROM menu_packaging_map mpm
JOIN inventory_items ii ON ii.id = mpm.inventory_item_id
ORDER BY mpm.menu_item_name;
```

---

#### C. 初始化库存批次

**手动添加初始库存**：

```sql
-- 示例：外帶紙盒，进货 300 个
INSERT INTO inventory_batches (item_id, batch_number, qty_received, qty_remaining, cost_per_unit, is_active)
SELECT
    id,
    'INIT-20260217',  -- 批次号
    300,              -- 入库数量
    300,              -- 剩余数量
    0.50,             -- 单位成本
    true              -- 活跃批次
FROM inventory_items
WHERE name = '外帶紙盒';
```

**或使用进货函数**（支持单位换算）：

```sql
-- 进货 6 box 纸盒（每 box = 50 pcs）
SELECT receive_inventory_with_conversion(
    (SELECT id FROM inventory_items WHERE name = '外帶紙盒'),  -- 品项 ID
    6,                -- 数量
    'box',            -- 单位（会自动转换为 pcs）
    0.50,             -- 单位成本
    'ABC 供应商',      -- 供应商
    NULL,             -- 批次号（自动生成）
    NULL              -- 过期日期
);

-- 系统会自动计算：6 box x 50 pcs/box = 300 pcs 入库
```

---

## 🔄 订单完成自动扣库存

### 前端集成（admin.html）

找到订单状态更新的地方，添加库存扣除逻辑：

```javascript
const handleCompleteOrder = async (orderId, updatedOrder) => {
    // 1. 更新订单状态为 completed
    await updateOrderInSupabase(orderId, { ...updatedOrder, status: 'completed' });

    // 2. 自动扣除包材库存
    try {
        const { data, error } = await window.supabaseClient
            .rpc('consume_inventory_for_order', {
                p_order_id: orderId
            });

        if (error || !data.success) {
            console.error('❌ 库存扣除失败:', error || data);
            alert('⚠️ 订单已完成，但包材库存扣除失败：' + (data?.message || error.message));
            // 可选：回滚订单状态
            return;
        }

        console.log('✅ 包材库存扣除成功:', data);
        alert('✅ 订单完成，包材已自动扣除！');

    } catch (err) {
        console.error('❌ 扣库存异常:', err);
        alert('扣库存失败，请检查包材配置');
    }

    // 3. 刷新订单列表
    loadOrders();
};
```

---

## 📊 后台操作（3 个核心功能）

### 1️⃣ 进货（支持单位换算）

```javascript
// 前端调用
const handleReceiveInventory = async () => {
    const { data, error } = await supabaseClient
        .rpc('receive_inventory_with_conversion', {
            p_item_id: selectedItem.id,
            p_qty: parseInt(qty),
            p_unit: selectedUnit,  // 'pcs' 或 'box' 或 'bag'
            p_cost_per_unit: parseFloat(cost),
            p_supplier: supplier,
            p_batch_number: batchNumber || null,
            p_expiry_date: expiryDate || null
        });

    if (data.success) {
        alert(`✅ ${data.message}`);
    }
};
```

---

### 2️⃣ 快速调整（员工餐/报废/赠送）

**前端已实现**（在库存管理页面）：

- 🍴 员工餐
- 🗑️ 报废
- 🎁 赠送

调用现有的 `quick_adjustment()` 函数。

---

### 3️⃣ 盘点调整

```javascript
const handleInventoryCount = async () => {
    const { data, error } = await supabaseClient
        .rpc('inventory_count_adjustment', {
            p_item_id: selectedItem.id,
            p_actual_qty: parseInt(actualQty),
            p_adjusted_by: currentUser.email,
            p_notes: notes
        });

    if (data.success) {
        alert(`✅ 盘点完成！差异：${data.delta}`);
    }
};
```

---

## 📈 低库存预警（自动）

### 查看预警品项

```sql
SELECT
    name AS 品項,
    qty_on_hand AS 現有庫存,
    reorder_point AS 補貨點,
    suggested_reorder_qty AS 建議補貨量,
    unit AS 單位,
    estimated_delivery_date AS 預計到貨日期
FROM inventory_overview
WHERE stock_status IN ('low_stock', 'out_of_stock')
ORDER BY
    CASE stock_status
        WHEN 'out_of_stock' THEN 1
        ELSE 2
    END,
    qty_on_hand ASC;
```

---

## ✅ 测试清单

### 完整流程测试

1. **查看库存**
   - [ ] 打开后台 → 库存管理
   - [ ] 看到所有包材品项和现有库存

2. **下单测试**
   - [ ] 前台下单：滷肉飯 x2
   - [ ] 后台接受订单（status = accepted）
   - [ ] **此时库存不扣除**

3. **完成订单（关键）**
   - [ ] 后台完成订单（status = completed）
   - [ ] **自动扣除包材**：
     - 外帶紙盒 -2
     - 外帶紙袋 -2
     - 餐具組 -2
   - [ ] 控制台显示：`✅ 包材库存扣除成功`

4. **验证库存变化**
   - [ ] 库存管理页面，看到数量减少
   - [ ] Supabase → inventory_transactions → 看到 `reference_type = 'order'` 的记录

5. **低库存预警**
   - [ ] 当库存低于 reorder_point 时
   - [ ] 库存管理页面显示橙色/红色预警
   - [ ] 显示建议补货数量

---

## 🎯 系统优势

| 优势 | 说明 |
|------|------|
| **精准** | 1 份餐点 = 1 个盒子，不会算错 |
| **实用** | 不缺包材才能营业，优先级最高 |
| **简单** | 不需要配方、不需要克数 |
| **自动** | 订单完成自动扣库存 |
| **预警** | 低于补货点自动提醒 |
| **单位换算** | 进货用箱/盒，库存用个，自动转换 |
| **审计追踪** | 每次变动都有完整记录 |

---

## 🚀 下一步扩展

完成包材系统后，可以逐步添加：

1. **瓶装饮料**（已支持） - 扣除逻辑同包材
2. **预包装食品**（已支持） - 冷冻薯条、章鱼烧等
3. **成本分析** - 统计每月包材成本
4. **供应商管理** - 记录供应商信息和采购历史
5. **食材管理**（可选） - 如果需要更精细管理

---

## 📞 需要帮助？

- 查看 [INVENTORY_ARCHITECTURE.md](INVENTORY_ARCHITECTURE.md) - 系统架构说明
- 查看示例数据：`inventory-sample-data-countable.sql`
- 执行 SQL 查询查看配置状态

---

**准备好了吗？让我们开始实施！** 🎉
