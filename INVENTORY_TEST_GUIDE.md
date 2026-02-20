# 📋 库存管理系统 - 测试执行指南

## 🎯 测试目标

验证以下核心功能：
- ✅ FIFO (先进先出) 逻辑
- ✅ 快捷操作（员工餐/报废/赠送）
- ✅ 盘点调整
- ✅ 库存预警
- ✅ 成本追踪
- ✅ 数据一致性

---

## 📝 执行步骤

### 第一步：执行 Schema 创建

1. **打开 Supabase Dashboard**
   - 访问：https://supabase.com/dashboard
   - 选择你的项目

2. **打开 SQL Editor**
   - 左侧菜单 → SQL Editor
   - 点击 "+ New query"

3. **复制并执行 `inventory-schema.sql`**
   - 复制整个文件内容
   - 粘贴到 SQL Editor
   - 点击 "Run" 按钮
   - ✅ 看到 "库存管理系统 Schema 创建成功！"

4. **验证表创建**
   - 左侧菜单 → Table Editor
   - 应该看到新增的表：
     - ✅ `inventory_items`
     - ✅ `inventory_batches`
     - ✅ `inventory_adjustments`
     - ✅ `inventory_transactions`
     - ✅ `menu_item_costs`

---

### 第二步：执行核心函数

1. **新建 SQL Query**
   - SQL Editor → "+ New query"

2. **复制并执行 `inventory-functions.sql`**
   - 复制整个文件内容
   - 粘贴到 SQL Editor
   - 点击 "Run"
   - ✅ 看到 "库存管理核心函数创建成功！"

3. **验证函数创建**
   - 在 SQL Editor 中执行：
   ```sql
   SELECT routine_name 
   FROM information_schema.routines 
   WHERE routine_schema = 'public' 
   AND routine_name LIKE '%inventory%';
   ```
   - 应该看到 5 个函数：
     - ✅ `deduct_inventory_fifo`
     - ✅ `quick_adjustment`
     - ✅ `receive_inventory`
     - ✅ `inventory_count_adjustment`
     - ✅ `calculate_days_of_cover`

---

### 第三步：执行测试套件

1. **新建 SQL Query**
   - SQL Editor → "+ New query"

2. **复制并执行 `inventory-test.sql`**
   - 复制整个文件内容
   - 粘贴到 SQL Editor
   - 点击 "Run"
   - **耐心等待** - 测试会逐步执行，可能需要 5-10 秒

3. **查看测试结果**
   - 向下滚动 Results 窗口
   - 查看每个测试步骤的输出

---

## ✅ 预期测试结果

### 测试 1：创建测试数据
```
✅ 创建了 4 个库存物品
```

### 测试 2：入库功能
```json
{
  "success": true,
  "batch_id": 1,
  "batch_number": "BATCH-20260201-001",
  "qty_received": 100
}
```

### 测试 3：FIFO 扣除（关键测试！）

**批次状态应该显示：**
| 批次号 | 入库数量 | 剩余数量 | 是否活跃 |
|--------|---------|---------|---------|
| BATCH-20260201-001 | 100 | 40 | true |
| BATCH-20260210-002 | 50 | 30 | true |

**解读：**
- 扣除了 60 个
- **先从批次1扣除** 60 个 → 批次1剩余 40
- 批次2没动 → 批次2剩余 50
- **✅ FIFO 逻辑正确！**

### 测试 4：快捷操作
```
物品          | 类型       | 数量变化 | 成本影响
章鱼烧原料    | waste      | -3       | $15.00
章鱼烧原料    | gift       | -2       | $10.00
鸡排原料      | staff_meal | -5       | $37.50
```

### 测试 5：盘点调整
```json
{
  "success": true,
  "system_qty": 85,
  "actual_qty": 80,
  "delta": -5,
  "adjusted": true
}
```

### 测试 6：库存总览
```
物品名称      | 当前库存 | 活跃批次 | 库存价值 | 库存状态
章鱼烧原料    | 80       | 2        | $428.00  | ok
鸡排原料      | 75       | 1        | $562.50  | ok
```

### 测试 7：周转天数
```
物品          | 当前库存 | 可用天数 | 预警状态
鸡排原料      | 75       | 999.0    | ✅ 库存充足
章鱼烧原料    | 80       | 999.0    | ✅ 库存充足
```
*(999 表示"无限天"，因为还没有销售记录)*

### 测试 8：库存不足保护
```
✅ 测试通过：正确抛出异常 - 库存不足！需要 999 但只有 80
```

### 测试 9：数据一致性
```
✅ 通过：所有批次数据一致
✅ 通过：所有批次状态正确
✅ 入库交易：3 条
✅ 出库交易：5 条
```

### 测试 10：测试报告
```
指标          | 数值
总物品数      | 4
总批次数      | 3
活跃批次数    | 3
交易记录数    | 8
调整记录数    | 4
库存总价值    | $990.50
```

---

## 🔍 关键验证点

### ✅ FIFO 逻辑验证

**执行此查询手动验证：**
```sql
SELECT 
    batch_number,
    qty_received,
    qty_remaining,
    received_at,
    is_active
FROM inventory_batches
WHERE item_id = (SELECT id FROM inventory_items WHERE name = '章鱼烧原料')
ORDER BY received_at;
```

**预期结果：**
- 早期批次先被扣除
- 晚期批次后扣除
- qty_remaining = 0 时，is_active = false

---

### ✅ 成本追踪验证

**执行此查询验证加权平均成本：**
```sql
SELECT 
    name,
    current_cost as "当前成本",
    (
        SELECT 
            SUM(qty_remaining * cost_per_unit) / SUM(qty_remaining)
        FROM inventory_batches 
        WHERE item_id = i.id AND is_active = true
    ) as "计算的加权成本"
FROM inventory_items i
WHERE name = '章鱼烧原料';
```

**预期：两个值应该相等**

---

### ✅ 交易记录完整性

**执行此查询验证所有交易：**
```sql
SELECT 
    i.name,
    t.transaction_type,
    t.qty,
    t.cost_per_unit,
    t.reference_type,
    t.created_at
FROM inventory_transactions t
JOIN inventory_items i ON t.item_id = i.id
ORDER BY t.created_at;
```

**验证：**
- 每次扣除都有对应交易记录
- 成本正确记录
- 关联类型正确

---

## 🐛 常见问题排查

### 问题 1：函数未找到

**错误信息：**
```
function deduct_inventory_fifo does not exist
```

**解决：**
- 确认已执行 `inventory-functions.sql`
- 重新执行函数创建脚本

---

### 问题 2：外键约束错误

**错误信息：**
```
violates foreign key constraint "fk_menu_item"
```

**解决：**
- 确认 `menu` 表已存在
- 或者修改 Schema，移除 `menu_item_id` 的外键约束

---

### 问题 3：权限错误

**错误信息：**
```
permission denied for table inventory_items
```

**解决：**
- 确认 RLS 策略已创建
- 或临时禁用 RLS：
  ```sql
  ALTER TABLE inventory_items DISABLE ROW LEVEL SECURITY;
  ```

---

## 🎉 测试通过后

如果所有测试都通过，说明：

✅ **数据库层完全正常！**
- FIFO 逻辑正确
- 快捷操作工作正常
- 盘点功能准确
- 成本追踪精确
- 数据一致性保证

**下一步：**
- 开始构建 UI 界面
- 或者先做最小可用版本（MVP）

---

## 📞 需要帮助？

如果测试失败或有疑问：
1. 截图错误信息
2. 复制完整的错误日志
3. 告诉 Claude 具体是哪个测试步骤失败

祝测试顺利！🚀
