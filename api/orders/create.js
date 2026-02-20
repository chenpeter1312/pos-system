/**
 * API: 客人下單（安全版本）
 *
 * POST /api/orders/create
 *
 * 安全特性：
 * - 使用 Service Role Key（不暴露給前端）
 * - 呼叫 create_public_order RPC（有 Rate Limiting）
 * - 價格由後端驗證
 * - IP 追蹤防止濫用
 */

import { createClient } from '@supabase/supabase-js';

// 建立 Supabase 客戶端（使用 Service Role Key）
const supabase = createClient(
    process.env.SUPABASE_URL,
    process.env.SUPABASE_SERVICE_ROLE_KEY
);

export default async function handler(req, res) {
    // 只允許 POST
    if (req.method !== 'POST') {
        return res.status(405).json({
            success: false,
            error: 'Method not allowed'
        });
    }

    try {
        const { items, orderType, paymentMethod } = req.body;

        // 驗證必要參數
        if (!items || !Array.isArray(items) || items.length === 0) {
            return res.status(400).json({
                success: false,
                error: '訂單項目不能為空'
            });
        }

        if (!orderType || !['dine_in', 'takeout'].includes(orderType)) {
            return res.status(400).json({
                success: false,
                error: '訂單類型錯誤'
            });
        }

        if (!paymentMethod || !['cash', 'card', 'stripe', 'other'].includes(paymentMethod)) {
            return res.status(400).json({
                success: false,
                error: '付款方式錯誤'
            });
        }

        // 取得客戶端 IP（用於 Rate Limiting）
        const clientIP = req.headers['x-forwarded-for'] ||
                         req.headers['x-real-ip'] ||
                         req.socket.remoteAddress ||
                         'unknown';

        // 呼叫安全的 RPC 函數（已有 Rate Limiting + 價格驗證）
        const { data, error } = await supabase.rpc('create_public_order', {
            p_items: items,
            p_order_type: orderType,
            p_payment_method: paymentMethod,
            p_ip_address: clientIP,
            p_device_info: req.headers['user-agent'] || 'unknown'
        });

        if (error) {
            console.error('❌ RPC 錯誤:', error);
            return res.status(500).json({
                success: false,
                error: '訂單建立失敗',
                details: error.message
            });
        }

        // RPC 返回的是陣列，取第一筆
        const result = data[0];

        if (!result.success) {
            return res.status(400).json({
                success: false,
                error: result.message
            });
        }

        // 成功！
        return res.status(200).json({
            success: true,
            message: result.message,
            order: {
                orderId: result.order_id,
                subtotal: parseFloat(result.calculated_subtotal),
                tax: parseFloat(result.calculated_tax),
                total: parseFloat(result.calculated_total)
            }
        });

    } catch (error) {
        console.error('❌ API 錯誤:', error);
        return res.status(500).json({
            success: false,
            error: '伺服器錯誤',
            details: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
}
