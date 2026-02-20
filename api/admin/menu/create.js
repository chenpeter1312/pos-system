/**
 * API: Admin 新增菜單項目
 *
 * POST /api/admin/menu/create
 *
 * 安全特性：
 * - 需要 Admin Session Token
 * - 呼叫 admin_create_menu_item RPC（有權限驗證）
 */

import { createClient } from '@supabase/supabase-js';

const supabase = createClient(
    process.env.SUPABASE_URL,
    process.env.SUPABASE_SERVICE_ROLE_KEY
);

export default async function handler(req, res) {
    if (req.method !== 'POST') {
        return res.status(405).json({ success: false, error: 'Method not allowed' });
    }

    try {
        // 從 Header 取得 Session Token
        const sessionToken = req.headers['authorization']?.replace('Bearer ', '');

        if (!sessionToken) {
            return res.status(401).json({
                success: false,
                error: '❌ 未提供認證 Token'
            });
        }

        const { name, description, price, category, emoji, available } = req.body;

        // 驗證必要參數
        if (!name || price === undefined) {
            return res.status(400).json({
                success: false,
                error: '❌ 商品名稱和價格為必填'
            });
        }

        // 呼叫 Admin RPC（會驗證 token 和 admin 權限）
        const { data, error } = await supabase.rpc('admin_create_menu_item', {
            p_session_token: sessionToken,
            p_name: name,
            p_description: description || '',
            p_price: parseFloat(price),
            p_category: category || '主食',
            p_emoji: emoji || '🍽️',
            p_available: available !== undefined ? available : true
        });

        if (error) {
            console.error('❌ RPC 錯誤:', error);
            return res.status(500).json({
                success: false,
                error: '新增失敗',
                details: error.message
            });
        }

        const result = data[0];

        if (!result.success) {
            return res.status(403).json({
                success: false,
                error: result.message
            });
        }

        return res.status(200).json({
            success: true,
            message: result.message,
            itemId: result.item_id
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
