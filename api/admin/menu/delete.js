/**
 * API: Admin 刪除菜單項目
 * DELETE /api/admin/menu/delete
 */

import { createClient } from '@supabase/supabase-js';

const supabase = createClient(
    process.env.SUPABASE_URL,
    process.env.SUPABASE_SERVICE_ROLE_KEY
);

export default async function handler(req, res) {
    if (req.method !== 'DELETE') {
        return res.status(405).json({ success: false, error: 'Method not allowed' });
    }

    try {
        const sessionToken = req.headers['authorization']?.replace('Bearer ', '');
        if (!sessionToken) {
            return res.status(401).json({ success: false, error: '❌ 未提供認證 Token' });
        }

        const { itemId } = req.query;

        if (!itemId) {
            return res.status(400).json({ success: false, error: '❌ 商品 ID 為必填' });
        }

        const { data, error } = await supabase.rpc('admin_delete_menu_item', {
            p_session_token: sessionToken,
            p_item_id: itemId
        });

        if (error) {
            return res.status(500).json({ success: false, error: '刪除失敗', details: error.message });
        }

        const result = data[0];
        if (!result.success) {
            return res.status(403).json({ success: false, error: result.message });
        }

        return res.status(200).json({ success: true, message: result.message });

    } catch (error) {
        console.error('❌ API 錯誤:', error);
        return res.status(500).json({ success: false, error: '伺服器錯誤' });
    }
}
