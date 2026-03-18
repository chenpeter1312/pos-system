/**
 * API: 客人下單（現金/現場付款）
 *
 * POST /api/orders/create-cash
 *
 * 不連接 Stripe，訂單直接建立為待付款狀態，客人到櫃檯付款。
 */

import { createClient } from '@supabase/supabase-js';

const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY
);

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Credentials', 'true');
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'POST') {
    return res.status(405).json({ success: false, error: 'Method not allowed' });
  }

  try {
    const { clientOrderId, customerName, phone, email, orderType = 'dine_in', items } = req.body;

    if (!customerName) {
      return res.status(400).json({ success: false, error: '請填寫客人姓名' });
    }
    if (!items || !Array.isArray(items) || items.length === 0) {
      return res.status(400).json({ success: false, error: '訂單項目不能為空' });
    }

    const clientIP = req.headers['x-forwarded-for']?.split(',')[0]?.trim()
      || req.headers['x-real-ip']
      || 'unknown';

    const orderId = clientOrderId || crypto.randomUUID();

    // 使用與 Stripe 流程相同的 RPC 建立訂單（含客人資訊與伺服器端價格計算）
    const { data, error } = await supabase.rpc('create_pending_stripe_order', {
      p_client_order_id: orderId,
      p_customer_name: customerName,
      p_phone: phone || null,
      p_email: email || null,
      p_order_type: orderType,
      p_items: items,
      p_ip_address: clientIP
    });

    if (error) {
      console.error('❌ RPC error:', error);
      return res.status(500).json({ success: false, error: '訂單建立失敗', details: error.message });
    }

    if (!data || data.length === 0) {
      return res.status(500).json({ success: false, error: '訂單建立失敗（無資料回傳）' });
    }

    const resultOrderId = data[0].order_id;

    // 更新為現金付款、狀態改為 new（廚房可見）
    await supabase
      .from('orders')
      .update({ payment_method: 'cash', payment_status: 'pending', status: 'new' })
      .eq('id', resultOrderId);

    console.log(`✅ Cash order created: #${resultOrderId} for ${customerName}`);

    return res.status(200).json({
      success: true,
      orderId: resultOrderId,
      message: '訂單已送出，請到櫃檯付款'
    });

  } catch (err) {
    console.error('❌ API error:', err);
    return res.status(500).json({ success: false, error: '伺服器錯誤', details: err.message });
  }
}
