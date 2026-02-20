-- ==========================================
-- 库存管理系统 - 完整测试套件
-- ==========================================

-- ==========================================
-- 测试准备：清理旧数据（可选）
-- ==========================================
-- 如果需要重新测试，取消下面的注释
/*
TRUNCATE TABLE inventory_transactions CASCADE;
TRUNCATE TABLE inventory_adjustments CASCADE;
TRUNCATE TABLE inventory_batches CASCADE;
TRUNCATE TABLE inventory_items CASCADE;
TRUNCATE TABLE menu_item_costs CASCADE;
*/

-- ==========================================
-- 第一步：创建测试数据
-- ==========================================
SELECT '📦 第一步：创建测试库存物品...' as step;

-- 插入测试物品
INSERT INTO inventory_items (name, name_en, unit, reorder_point, lead_time_days, safety_buffer_days, current_cost, category) VALUES
    ('章鱼烧原料', 'Takoyaki Ingredients', 'batch', 10, 3, 2, 5.50, '食材'),
    ('鸡排原料', 'Chicken Steak Ingredients', 'kg', 20, 2, 1, 8.00, '食材'),
    ('外带纸盒', 'Takeout Box', 'unit', 50, 5, 2, 0.30, '包装'),
    ('酱油', 'Soy Sauce', 'bottle', 10, 7, 3, 3.50, '调料')
ON CONFLICT DO NOTHING;

SELECT '✅ 创建了 ' || COUNT(*) || ' 个库存物品' as result 
FROM inventory_items WHERE name IN ('章鱼烧原料', '鸡排原料', '外带纸盒', '酱油');

-- ==========================================
-- 第二步：测试入库功能
-- ==========================================
SELECT '📥 第二步：测试入库功能（receive_inventory）...' as step;

-- 入库批次1：章鱼烧（旧批次）
SELECT receive_inventory(
    (SELECT id FROM inventory_items WHERE name = '章鱼烧原料'),
    100,  -- 数量
    5.00, -- 成本
    'Supply Co.',
    'BATCH-20260201-001',
    '2026-03-01'::DATE
) as batch_1_result;

-- 稍微延迟，确保时间戳不同
SELECT pg_sleep(0.1);

-- 入库批次2：章鱼烧（新批次，成本上涨）
SELECT receive_inventory(
    (SELECT id FROM inventory_items WHERE name = '章鱼烧原料'),
    50,   -- 数量
    5.80, -- 成本上涨
    'Supply Co.',
    'BATCH-20260210-002',
    '2026-03-10'::DATE
) as batch_2_result;

-- 入库批次3：鸡排
SELECT receive_inventory(
    (SELECT id FROM inventory_items WHERE name = '鸡排原料'),
    80,
    7.50,
    'Meat Supplier',
    'BATCH-CHICKEN-001'
) as batch_3_result;

-- 验证入库结果
SELECT '✅ 入库结果验证：' as status;
SELECT 
    i.name,
    COUNT(b.id) as "批次数",
    SUM(b.qty_remaining) as "总库存",
    ROUND(AVG(b.cost_per_unit), 2) as "平均成本"
FROM inventory_items i
LEFT JOIN inventory_batches b ON i.id = b.item_id
WHERE i.name IN ('章鱼烧原料', '鸡排原料')
GROUP BY i.name;

-- ==========================================
-- 第三步：测试 FIFO 扣除逻辑
-- ==========================================
SELECT '🔄 第三步：测试 FIFO 扣除（deduct_inventory_fifo）...' as step;

-- 扣除 60 个章鱼烧原料
-- 预期：先从批次1扣除（最早的），如果不够再从批次2扣除
SELECT deduct_inventory_fifo(
    (SELECT id FROM inventory_items WHERE name = '章鱼烧原料'),
    60,
    'test_order',
    999
) as fifo_deduction_result;

-- 验证 FIFO 结果
SELECT '✅ FIFO 扣除后的批次状态：' as status;
SELECT 
    batch_number as "批次号",
    qty_received as "入库数量",
    qty_remaining as "剩余数量",
    cost_per_unit as "单位成本",
    is_active as "是否活跃",
    TO_CHAR(received_at, 'YYYY-MM-DD HH24:MI:SS') as "入库时间"
FROM inventory_batches
WHERE item_id = (SELECT id FROM inventory_items WHERE name = '章鱼烧原料')
ORDER BY received_at;

-- 验证交易记录
SELECT '✅ 交易记录验证：' as status;
SELECT 
    transaction_type as "类型",
    qty as "数量",
    cost_per_unit as "单位成本",
    reference_type as "关联类型",
    TO_CHAR(created_at, 'YYYY-MM-DD HH24:MI:SS') as "时间"
FROM inventory_transactions
WHERE item_id = (SELECT id FROM inventory_items WHERE name = '章鱼烧原料')
ORDER BY created_at;

-- ==========================================
-- 第四步：测试快捷操作（员工餐/报废/赠送）
-- ==========================================
SELECT '🍴 第四步：测试快捷操作（quick_adjustment）...' as step;

-- 员工餐：消耗 5 个鸡排
SELECT quick_adjustment(
    (SELECT id FROM inventory_items WHERE name = '鸡排原料'),
    'staff_meal',
    5,
    '员工午餐',
    'admin'
) as staff_meal_result;

-- 报废：损坏 3 个章鱼烧原料
SELECT quick_adjustment(
    (SELECT id FROM inventory_items WHERE name = '章鱼烧原料'),
    'waste',
    3,
    '过期损坏',
    'admin'
) as waste_result;

-- 赠送：送出 2 个章鱼烧原料
SELECT quick_adjustment(
    (SELECT id FROM inventory_items WHERE name = '章鱼烧原料'),
    'gift',
    2,
    '客户赠品',
    'admin'
) as gift_result;

-- 验证调整记录
SELECT '✅ 调整记录验证：' as status;
SELECT 
    i.name as "物品",
    a.adjustment_type as "类型",
    a.qty_change as "数量变化",
    a.cost_impact as "成本影响",
    a.reason as "原因",
    TO_CHAR(a.adjusted_at, 'YYYY-MM-DD HH24:MI:SS') as "时间"
FROM inventory_adjustments a
JOIN inventory_items i ON a.item_id = i.id
ORDER BY a.adjusted_at;

-- ==========================================
-- 第五步：测试盘点调整
-- ==========================================
SELECT '📊 第五步：测试盘点调整（inventory_count_adjustment）...' as step;

-- 获取当前系统库存
SELECT '当前系统库存：' as status;
SELECT 
    name as "物品",
    (SELECT SUM(qty_remaining) FROM inventory_batches WHERE item_id = i.id) as "系统数量"
FROM inventory_items i
WHERE name = '章鱼烧原料';

-- 盘点：实际库存比系统少了 5 个（盘亏）
SELECT inventory_count_adjustment(
    (SELECT id FROM inventory_items WHERE name = '章鱼烧原料'),
    80,  -- 实际数量
    'admin',
    '月度盘点'
) as count_adjustment_result;

-- 验证盘点结果
SELECT '✅ 盘点后库存：' as status;
SELECT 
    name as "物品",
    (SELECT SUM(qty_remaining) FROM inventory_batches WHERE item_id = i.id) as "盘点后数量"
FROM inventory_items i
WHERE name = '章鱼烧原料';

-- ==========================================
-- 第六步：测试库存视图
-- ==========================================
SELECT '📈 第六步：测试库存总览视图（inventory_overview）...' as step;

SELECT 
    name as "物品名称",
    unit as "单位",
    on_hand as "当前库存",
    reorder_point as "补货点",
    active_batches as "活跃批次",
    ROUND(total_value, 2) as "库存价值",
    ROUND(weighted_avg_cost, 2) as "加权成本",
    stock_status as "库存状态"
FROM inventory_overview
ORDER BY name;

-- ==========================================
-- 第七步：测试周转天数计算
-- ==========================================
SELECT '⏱️ 第七步：测试周转天数（calculate_days_of_cover）...' as step;

SELECT 
    i.name as "物品",
    (SELECT SUM(qty_remaining) FROM inventory_batches WHERE item_id = i.id) as "当前库存",
    ROUND(calculate_days_of_cover(i.id), 1) as "可用天数",
    i.lead_time_days + i.safety_buffer_days as "安全库存天数",
    CASE 
        WHEN calculate_days_of_cover(i.id) <= i.lead_time_days + i.safety_buffer_days 
        THEN '⚠️ 需要补货'
        ELSE '✅ 库存充足'
    END as "预警状态"
FROM inventory_items i
WHERE i.name IN ('章鱼烧原料', '鸡排原料')
ORDER BY calculate_days_of_cover(i.id);

-- ==========================================
-- 第八步：测试库存不足异常
-- ==========================================
SELECT '❌ 第八步：测试库存不足保护...' as step;

-- 尝试扣除超过库存的数量（应该失败）
DO $$
BEGIN
    PERFORM deduct_inventory_fifo(
        (SELECT id FROM inventory_items WHERE name = '章鱼烧原料'),
        999,  -- 超过库存
        'test',
        NULL
    );
    RAISE NOTICE '❌ 测试失败：应该抛出库存不足异常！';
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE '✅ 测试通过：正确抛出异常 - %', SQLERRM;
END $$;

-- ==========================================
-- 第九步：综合数据一致性检查
-- ==========================================
SELECT '🔍 第九步：数据一致性检查...' as step;

-- 检查批次数量一致性
SELECT '批次数量一致性：' as check_name;
SELECT 
    CASE 
        WHEN COUNT(*) = 0 THEN '✅ 通过：所有批次数据一致'
        ELSE '❌ 失败：发现 ' || COUNT(*) || ' 个批次数据不一致'
    END as result
FROM inventory_batches
WHERE qty_remaining > qty_received OR qty_remaining < 0;

-- 检查 is_active 状态一致性
SELECT 'is_active 状态一致性：' as check_name;
SELECT 
    CASE 
        WHEN COUNT(*) = 0 THEN '✅ 通过：所有批次状态正确'
        ELSE '❌ 失败：发现 ' || COUNT(*) || ' 个批次状态错误'
    END as result
FROM inventory_batches
WHERE (qty_remaining = 0 AND is_active = true) 
   OR (qty_remaining > 0 AND is_active = false);

-- 检查交易记录完整性
SELECT '交易记录完整性：' as check_name;
SELECT 
    '✅ 入库交易：' || COUNT(*) || ' 条' as result
FROM inventory_transactions
WHERE transaction_type = 'in'
UNION ALL
SELECT 
    '✅ 出库交易：' || COUNT(*) || ' 条' as result
FROM inventory_transactions
WHERE transaction_type = 'out';

-- ==========================================
-- 第十步：生成测试报告
-- ==========================================
SELECT '📋 测试报告总结' as "======================";

SELECT 
    '总物品数' as "指标",
    COUNT(*)::TEXT as "数值"
FROM inventory_items
UNION ALL
SELECT 
    '总批次数',
    COUNT(*)::TEXT
FROM inventory_batches
UNION ALL
SELECT 
    '活跃批次数',
    COUNT(*)::TEXT
FROM inventory_batches WHERE is_active = true
UNION ALL
SELECT 
    '交易记录数',
    COUNT(*)::TEXT
FROM inventory_transactions
UNION ALL
SELECT 
    '调整记录数',
    COUNT(*)::TEXT
FROM inventory_adjustments
UNION ALL
SELECT 
    '库存总价值',
    '$' || ROUND(SUM(total_value), 2)::TEXT
FROM inventory_overview;

-- ==========================================
-- 完成！
-- ==========================================
SELECT '🎉 所有测试完成！' as status;
SELECT '请检查上面的测试结果，确认所有功能正常工作。' as next_step;
