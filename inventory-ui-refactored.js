// ========================================
// 🎨 Toast POS Style - 库存管理界面重构代码
// ========================================
//
// 使用说明：
// 1. 这个文件包含重构后的表格部分代码
// 2. 替换 admin.html 中对应的表格代码（约 2888-3083 行）
// 3. 保持其他部分不变（KPI 卡片和搜索栏已经重构完成）
//
// ========================================

// 替换表格部分（从 <table className="table-modern"> 开始）

<table className="table-modern">
    <thead>
        <tr>
            <th>品項名稱</th>
            <th>現有庫存</th>
            <th>狀態</th>
            <th style={{ textAlign: 'right' }}>操作</th>
        </tr>
    </thead>
    <tbody>
        {inventoryItems
            .filter(item => {
                // 搜索过滤
                const matchSearch = item.name.toLowerCase().includes(searchQuery.toLowerCase());
                // 状态过滤
                const matchStatus = statusFilter === 'all' || item.stock_status === statusFilter;
                return matchSearch && matchStatus;
            })
            .map(item => (
                <React.Fragment key={item.id}>
                    <tr onClick={() => {
                        if (expandedRows.includes(item.id)) {
                            setExpandedRows(expandedRows.filter(id => id !== item.id));
                        } else {
                            setExpandedRows([...expandedRows, item.id]);
                        }
                    }}>
                        <td style={{ fontWeight: 'bold', color: '#111827' }}>
                            <span style={{ marginRight: '8px', color: '#6b7280' }}>
                                {expandedRows.includes(item.id) ? '▼' : '▶'}
                            </span>
                            {item.name}
                        </td>
                        <td>
                            <span style={{
                                fontSize: '20px',
                                fontWeight: 'bold',
                                color: item.stock_status === 'ok' ? '#10b981' :
                                       item.stock_status === 'low_stock' ? '#f59e0b' : '#ef4444'
                            }}>
                                {item.qty_on_hand}
                            </span>
                            <span style={{ marginLeft: '8px', fontSize: '14px', color: '#6b7280' }}>
                                {item.unit}
                            </span>
                        </td>
                        <td>
                            <span className={`status-badge ${item.stock_status === 'ok' ? 'ok' : item.stock_status === 'low_stock' ? 'low' : 'out'}`}>
                                {item.stock_status === 'ok' ? '✅ 正常' :
                                 item.stock_status === 'low_stock' ? '⚠️ 偏低' : '❌ 缺貨'}
                            </span>
                        </td>
                        <td>
                            <div className="action-buttons" style={{ justifyContent: 'flex-end' }}>
                                <button
                                    className="btn-action-primary"
                                    onClick={(e) => {
                                        e.stopPropagation();
                                        setSelectedItem(item);
                                        setReceiveForm({ qty: '', unit: item.unit || 'pcs', cost: item.current_cost?.toString() || '', supplier: '' });
                                        setShowReceiveModal(true);
                                    }}
                                >
                                    進貨
                                </button>
                                <div style={{ position: 'relative' }}>
                                    <button
                                        className="btn-more"
                                        onClick={(e) => {
                                            e.stopPropagation();
                                            setOpenMenuId(openMenuId === item.id ? null : item.id);
                                        }}
                                    >
                                        ⋯
                                    </button>
                                    {openMenuId === item.id && (
                                        <div className="dropdown-menu" onClick={(e) => e.stopPropagation()}>
                                            <button
                                                className="dropdown-item"
                                                onClick={() => {
                                                    setSelectedItem(item);
                                                    setCountForm({ actualQty: item.qty_on_hand?.toString() || '0', notes: '' });
                                                    setShowCountModal(true);
                                                    setOpenMenuId(null);
                                                }}
                                            >
                                                📝 盤點
                                            </button>
                                            <button
                                                className="dropdown-item"
                                                onClick={() => {
                                                    setSelectedItem(item);
                                                    setEditForm({
                                                        reorderPoint: item.reorder_point?.toString() || '100',
                                                        reorderQty: item.reorder_qty?.toString() || '200',
                                                        leadTimeDays: item.lead_time_days?.toString() || '3',
                                                        currentCost: item.current_cost?.toString() || '0.50',
                                                        unitsPerCase: item.units_per_case?.toString() || ''
                                                    });
                                                    setShowEditModal(true);
                                                    setOpenMenuId(null);
                                                }}
                                            >
                                                ✏️ 編輯
                                            </button>
                                            <button
                                                className="dropdown-item"
                                                onClick={async () => {
                                                    setSelectedItem(item);
                                                    setShowHistoryModal(true);
                                                    setOpenMenuId(null);
                                                    try {
                                                        const { data, error } = await window.supabaseClient
                                                            .from('inventory_transactions')
                                                            .select('*')
                                                            .eq('item_id', item.id)
                                                            .order('created_at', { ascending: false })
                                                            .limit(50);
                                                        if (!error) setTransactions(data || []);
                                                    } catch (e) { console.error(e); }
                                                }}
                                            >
                                                📊 歷史
                                            </button>
                                            <div className="dropdown-divider"></div>
                                            <button
                                                className="dropdown-item"
                                                onClick={() => {
                                                    openQuickAction(item, 'staff_meal');
                                                    setOpenMenuId(null);
                                                }}
                                            >
                                                🍴 員工餐
                                            </button>
                                            <button
                                                className="dropdown-item"
                                                onClick={() => {
                                                    openQuickAction(item, 'waste');
                                                    setOpenMenuId(null);
                                                }}
                                            >
                                                🗑️ 報廢
                                            </button>
                                            <button
                                                className="dropdown-item"
                                                onClick={() => {
                                                    openQuickAction(item, 'gift');
                                                    setOpenMenuId(null);
                                                }}
                                            >
                                                🎁 贈送
                                            </button>
                                        </div>
                                    )}
                                </div>
                            </div>
                        </td>
                    </tr>

                    {/* 展开详情 */}
                    {expandedRows.includes(item.id) && (
                        <tr>
                            <td colSpan="4" style={{ padding: 0, border: 'none' }}>
                                <div className="expanded-details">
                                    <div className="detail-grid">
                                        <div className="detail-item">
                                            <div className="detail-label">安全庫存</div>
                                            <div className="detail-value">{item.reorder_point} {item.unit}</div>
                                        </div>
                                        <div className="detail-item">
                                            <div className="detail-label">單位成本</div>
                                            <div className="detail-value">${parseFloat(item.current_cost || 0).toFixed(2)}</div>
                                        </div>
                                        <div className="detail-item">
                                            <div className="detail-label">庫存價值</div>
                                            <div className="detail-value" style={{ color: '#6B4423' }}>
                                                ${(parseFloat(item.current_cost || 0) * parseInt(item.qty_on_hand || 0)).toFixed(2)}
                                            </div>
                                        </div>
                                        <div className="detail-item">
                                            <div className="detail-label">周轉天數</div>
                                            <div className="detail-value">
                                                {item.days_of_cover !== null ? (
                                                    <span style={{
                                                        color: parseFloat(item.days_of_cover) < 3 ? '#ef4444' :
                                                               parseFloat(item.days_of_cover) < 7 ? '#f59e0b' : '#10b981'
                                                    }}>
                                                        {parseFloat(item.days_of_cover).toFixed(1)} 天
                                                    </span>
                                                ) : (
                                                    <span style={{ color: '#9ca3af' }}>N/A</span>
                                                )}
                                            </div>
                                        </div>
                                    </div>

                                    {/* 最近操作记录预留区 */}
                                    <div className="recent-transactions" style={{ display: 'none' }}>
                                        <div style={{ fontWeight: '600', fontSize: '13px', color: '#6b7280', marginBottom: '8px' }}>
                                            📝 最近操作記錄
                                        </div>
                                        {/* 可以在这里添加最近的交易记录 */}
                                    </div>
                                </div>
                            </td>
                        </tr>
                    )}
                </React.Fragment>
            ))}
    </tbody>
</table>

{inventoryItems
    .filter(item => {
        const matchSearch = item.name.toLowerCase().includes(searchQuery.toLowerCase());
        const matchStatus = statusFilter === 'all' || item.stock_status === statusFilter;
        return matchSearch && matchStatus;
    }).length === 0 && (
    <div style={{ textAlign: 'center', padding: '60px 20px', color: '#9ca3af', background: 'white', borderRadius: '8px', marginTop: '20px' }}>
        <div style={{ fontSize: '48px', marginBottom: '16px' }}>📭</div>
        <div style={{ fontSize: '16px', fontWeight: '600', marginBottom: '8px' }}>找不到符合條件的品項</div>
        <div style={{ fontSize: '14px' }}>請嘗試調整搜尋條件或篩選器</div>
    </div>
)}
