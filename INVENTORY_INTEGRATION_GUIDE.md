# 🚀 库存系统完整集成指南

## 📌 您提出的三大核心问题 ✅ 已解决

### ✅ 问题 1：Single Source of Truth
**解决方案**：RLS 策略锁定，禁止前端直接修改 `qty_remaining`

### ✅ 问题 2：唯一库存扣除逻辑
**解决方案**：
- `inventory_batches.qty_remaining` = 物理库存（Source of Truth）
- `inventory_transactions` = 完整审计追踪（Ledger）
- 只能通过 RPC 函数修改，保证一致性

### ✅ 问题 3：订单-库存自动集成
**解决方案**：创建 `consume_inventory_for_order()` 函数，订单完成时自动扣库存

---

## 🎯 完整实施流程

### 步骤 1️⃣：执行 RLS 策略（锁定直接修改）⏱️ 1 分钟

**打开 Supabase SQL Editor**，执行：

```bash
# 文件：inventory-rls-policies.sql
```

**执行后验证**：
- ✅ 前端无法直接 UPDATE `inventory_batches`
- ✅ 只能通过 RPC 函数修改库存

---

### 步骤 2️⃣：创建订单-库存集成函数 ⏱️ 2 分钟

**打开 Supabase SQL Editor**，执行：

```bash
# 文件：inventory-order-integration.sql
```

**这个文件创建**：
1. `menu_item_recipes` 表（菜品-原料映射）
2. `consume_inventory_for_order()` 函数

**执行后验证**：
- ✅ Supabase Dashboard → Table Editor → 看到 `menu_item_recipes` 表
- ✅ Supabase Dashboard → Database → Functions → 看到 `consume_inventory_for_order`

---

### 步骤 3️⃣：配置菜品-原料映射 ⏱️ 5-10 分钟

**重要**：您需要告诉系统「每个菜品需要哪些原料」

#### 示例配置

假设您的餐厅有以下菜品：

| 菜品 | 需要的原料 |
|------|-----------|
| 滷肉飯 | 米饭 x1, 滷肉 x1 |
| 牛肉麵 | 麵條 x1, 牛肉 x1 |
| 珍珠奶茶 | 茶葉 x0.05, 牛奶 x0.2, 珍珠 x0.1 |

**在 Supabase SQL Editor 执行**：

```sql
-- 1. 先确保 inventory_items 中有这些原料
-- 如果没有，先插入
INSERT INTO inventory_items (name, unit, reorder_point, lead_time_days, current_cost)
VALUES
    ('米饭', 'kg', 50, 3, 2.50),
    ('滷肉', 'kg', 30, 3, 8.00),
    ('麵條', 'kg', 40, 3, 3.50),
    ('牛肉', 'kg', 20, 3, 15.00),
    ('茶葉', 'kg', 10, 7, 12.00),
    ('牛奶', 'L', 20, 2, 3.00),
    ('珍珠', 'kg', 15, 3, 5.00)
ON CONFLICT (name) DO NOTHING;

-- 2. 配置菜品配方
INSERT INTO menu_item_recipes (menu_item_name, inventory_item_id, qty_needed)
SELECT '滷肉飯', id, 0.25 FROM inventory_items WHERE name = '米饭'
UNION ALL
SELECT '滷肉飯', id, 0.15 FROM inventory_items WHERE name = '滷肉'
UNION ALL
SELECT '牛肉麵', id, 0.20 FROM inventory_items WHERE name = '麵條'
UNION ALL
SELECT '牛肉麵', id, 0.18 FROM inventory_items WHERE name = '牛肉'
UNION ALL
SELECT '珍珠奶茶', id, 0.05 FROM inventory_items WHERE name = '茶葉'
UNION ALL
SELECT '珍珠奶茶', id, 0.20 FROM inventory_items WHERE name = '牛奶'
UNION ALL
SELECT '珍珠奶茶', id, 0.10 FROM inventory_items WHERE name = '珍珠';

-- 3. 验证配置
SELECT
    mir.menu_item_name AS 菜品,
    ii.name AS 原料,
    mir.qty_needed AS 每份需要数量,
    ii.unit AS 单位
FROM menu_item_recipes mir
JOIN inventory_items ii ON ii.id = mir.inventory_item_id
ORDER BY mir.menu_item_name, ii.name;
```

**重要说明**：
- `qty_needed` 单位必须与 `inventory_items.unit` 一致
- 例如：1份滷肉飯需要 0.25 kg 米饭

---

### 步骤 4️⃣：修改前端订单完成逻辑 ⏱️ 3 分钟

**目标**：当订单状态变为 `completed` 时，自动扣库存

#### 找到订单更新函数

在 `admin.html` 中找到 `handleUpdateOrder` 或订单状态更新的地方。

**当前代码可能是**：
```javascript
const handleUpdateOrder = async (orderId, updatedOrder) => {
    // 更新订单状态
    await updateOrderInSupabase(orderId, updatedOrder);

    // ...
};
```

**修改为**：
```javascript
const handleUpdateOrder = async (orderId, updatedOrder) => {
    // 1. 更新订单状态
    await updateOrderInSupabase(orderId, updatedOrder);

    // 2. 如果订单状态变为 completed，扣库存
    if (updatedOrder.status === 'completed') {
        try {
            const { data, error } = await window.supabaseClient
                .rpc('consume_inventory_for_order', {
                    p_order_id: orderId
                });

            if (error) {
                console.error('❌ 扣库存失败:', error);
                alert('⚠️ 订单已完成，但库存扣除失败：' + error.message);
                return;
            }

            if (!data.success) {
                console.error('❌ 库存不足:', data);
                alert('⚠️ ' + data.message);
                // 可选：回滚订单状态
                // updatedOrder.status = 'accepted';
                // await updateOrderInSupabase(orderId, updatedOrder);
                return;
            }

            console.log('✅ 库存扣除成功:', data);
        } catch (err) {
            console.error('❌ 扣库存异常:', err);
            alert('扣库存失败，请检查配方配置');
        }
    }

    // 3. 更新本地状态
    setOrders(orders.map(o => o.id === orderId ? updatedOrder : o));
};
```

---

### 步骤 5️⃣：测试完整流程 ⏱️ 5 分钟

#### 测试清单

1. **下单测试**
   - [ ] 前台下单：滷肉飯 x2
   - [ ] 订单创建成功，状态 = `pending`

2. **接受订单**
   - [ ] 后台订单管理 → 接受订单
   - [ ] 状态变为 `accepted`
   - [ ] **此时库存不扣除**（正确！）

3. **完成订单（关键步骤）**
   - [ ] 后台订单管理 → 完成订单
   - [ ] 状态变为 `completed`
   - [ ] **自动扣除库存**
   - [ ] 打开浏览器控制台，看到：`✅ 库存扣除成功`

4. **验证库存变化**
   - [ ] 前往 **库存管理** 页面
   - [ ] 查看「米饭」和「滷肉」的现有库存
   - [ ] 应该分别减少：
     - 米饭：-0.5 kg（0.25 x 2）
     - 滷肉：-0.3 kg（0.15 x 2）

5. **验证 transactions 记录**
   - [ ] Supabase Dashboard → Table Editor → `inventory_transactions`
   - [ ] 最新记录的 `reference_type` = `order`
   - [ ] `reference_id` = 刚才的订单 ID
   - [ ] `transaction_type` = `out`

---

## 🎯 完整数据流

```
用户下单
   ↓
orders 表插入记录
status = 'pending'
   ↓
后台接受订单
status = 'accepted'
（库存不扣除）
   ↓
后台完成订单
status = 'completed'
   ↓
⚡️ 触发：handleUpdateOrder()
   ↓
调用 RPC: consume_inventory_for_order(order_id)
   ↓
函数逻辑：
  1. 读取 orders.items
  2. 查询 menu_item_recipes（配方）
  3. 计算需要的原料数量
  4. 调用 deduct_inventory_fifo()（FIFO 扣库存）
  5. 写入 inventory_transactions
  6. 更新 inventory_batches.qty_remaining
   ↓
返回结果：
{ success: true, deductions: [...] }
   ↓
前端显示：✅ 订单完成，库存已扣除
```

---

## 🔒 数据保护机制

### RLS 策略强制执行

| 表 | SELECT | INSERT | UPDATE | DELETE |
|----|--------|--------|--------|--------|
| `inventory_batches` | ✅ All | ❌ | ❌ | ❌ |
| `inventory_transactions` | ✅ All | ❌ | ❌ | ❌ |
| `inventory_adjustments` | ✅ All | ❌ | ❌ | ❌ |
| `menu_item_recipes` | ✅ All | ✅ Authenticated | ✅ Authenticated | ✅ Authenticated |

**说明**：
- ✅ All = 所有人可以读取
- ❌ = 禁止直接操作
- ✅ Authenticated = 认证用户可操作（用于配置配方）

---

## 🚨 常见问题

### Q1：库存扣除失败，怎么办？

**可能原因**：
1. 配方未配置（`menu_item_recipes` 表为空）
2. 库存不足
3. 菜品名称不匹配

**解决方案**：
```sql
-- 检查配方
SELECT * FROM menu_item_recipes WHERE menu_item_name = '滷肉飯';

-- 检查库存
SELECT * FROM inventory_overview;
```

---

### Q2：如何查看库存扣除历史？

```sql
SELECT
    t.created_at AS 时间,
    o.id AS 订单ID,
    o.customer_name AS 客户,
    ii.name AS 原料,
    t.qty AS 扣除数量,
    t.cost_per_unit AS 单位成本
FROM inventory_transactions t
JOIN inventory_items ii ON ii.id = t.item_id
LEFT JOIN orders o ON o.id = t.reference_id
WHERE t.reference_type = 'order'
ORDER BY t.created_at DESC
LIMIT 20;
```

---

### Q3：如何添加新菜品配方？

```sql
-- 假设要添加「三杯雞」
INSERT INTO menu_item_recipes (menu_item_name, inventory_item_id, qty_needed)
SELECT '三杯雞', id, 0.20 FROM inventory_items WHERE name = '雞肉'
UNION ALL
SELECT '三杯雞', id, 0.30 FROM inventory_items WHERE name = '米饭';
```

---

## ✅ 实施检查清单

在 Supabase Dashboard 验证：

- [ ] **Database → Functions**：看到 `consume_inventory_for_order`
- [ ] **Table Editor → menu_item_recipes**：有配方数据
- [ ] **Table Editor → inventory_batches**：有库存批次
- [ ] **Database → Policies**：RLS 策略已启用

在前端测试：

- [ ] 下单 → 接受 → 完成 → 库存自动扣除
- [ ] 控制台无错误
- [ ] 库存管理页面显示最新数量

---

## 🎉 完成后的系统架构

```
┌─────────────────────────────────────────────────────────┐
│                    订单系统                              │
│  orders (status: pending → accepted → completed)        │
└────────────────────┬────────────────────────────────────┘
                     │
                     │ completed 时触发
                     ↓
┌─────────────────────────────────────────────────────────┐
│            consume_inventory_for_order()                │
│  (订单 ID → 查配方 → FIFO 扣库存 → 写 transaction)        │
└────────────────────┬────────────────────────────────────┘
                     │
       ┌─────────────┼─────────────┐
       ↓             ↓             ↓
 inventory_batches  inventory_  menu_item_
 (qty_remaining)    transactions  recipes
```

**这就是完整的、符合 Single Source of Truth 的库存管理系统！** 🚀

---

需要帮助实施哪一步？告诉我！
