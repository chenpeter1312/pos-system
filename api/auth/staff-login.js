/**
 * API: 員工登入
 *
 * POST /api/auth/staff-login
 *
 * 安全特性：
 * - PIN 碼驗證
 * - Rate Limiting（5 次失敗鎖定 15 分鐘）
 * - Session Token 管理
 * - IP 追蹤
 */

import { createClient } from '@supabase/supabase-js';

const supabase = createClient(
    process.env.SUPABASE_URL,
    process.env.SUPABASE_SERVICE_ROLE_KEY
);

export default async function handler(req, res) {
    if (req.method !== 'POST') {
        return res.status(405).json({
            success: false,
            error: 'Method not allowed'
        });
    }

    try {
        const { pinCode } = req.body;

        // 驗證 PIN 碼格式
        if (!pinCode || !/^\d{4,6}$/.test(pinCode)) {
            return res.status(400).json({
                success: false,
                error: 'PIN 碼格式錯誤（4-6 位數字）'
            });
        }

        // 取得客戶端 IP
        const clientIP = req.headers['x-forwarded-for'] ||
                         req.headers['x-real-ip'] ||
                         req.socket.remoteAddress ||
                         'unknown';

        // 呼叫登入 RPC（已有 Rate Limiting 保護）
        const { data, error } = await supabase.rpc('attempt_staff_login', {
            p_username: pinCode,  // 相容舊版參數
            p_pin_code: pinCode,
            p_ip_address: clientIP,
            p_device_info: req.headers['user-agent'] || 'unknown'
        });

        if (error) {
            console.error('❌ RPC 錯誤:', error);
            return res.status(500).json({
                success: false,
                error: '登入失敗',
                details: error.message
            });
        }

        const result = data[0];

        if (!result.success) {
            return res.status(401).json({
                success: false,
                error: result.message
            });
        }

        // 登入成功！
        return res.status(200).json({
            success: true,
            message: result.message,
            session: {
                sessionToken: result.session_token,
                staffId: result.staff_id,
                staffName: result.staff_name,
                role: result.staff_role,
                expiresAt: result.expires_at
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
