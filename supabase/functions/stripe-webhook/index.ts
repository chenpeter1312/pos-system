// Supabase Edge Function: Stripe Webhook Handler
// 用途：接收 Stripe 付款成功事件，創建訂單到 Supabase

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0'
import Stripe from 'https://esm.sh/stripe@14.10.0?target=deno'

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') || '', {
  apiVersion: '2023-10-16',
  httpClient: Stripe.createFetchHttpClient(),
})

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

serve(async (req) => {
  const signature = req.headers.get('stripe-signature')

  if (!signature) {
    return new Response('No signature', { status: 400 })
  }

  try {
    const body = await req.text()
    const webhookSecret = Deno.env.get('STRIPE_WEBHOOK_SECRET')!

    // 驗證 Stripe 簽名
    const event = stripe.webhooks.constructEvent(body, signature, webhookSecret)

    console.log('✅ Webhook verified:', event.type, 'Event ID:', event.id)

    // 初始化 Supabase 客戶端（提前初始化，用於 idempotency 檢查）
    const supabase = createClient(supabaseUrl, supabaseServiceKey)

    // ==================== Idempotency 檢查（防重複訂單）====================
    // 1. 檢查事件是否已處理
    const { data: existingEvent, error: checkError } = await supabase
      .from('webhook_events')
      .select('*')
      .eq('stripe_event_id', event.id)
      .single()

    if (existingEvent) {
      console.log('⚠️ Event already processed:', event.id, 'Order ID:', existingEvent.order_id)
      return new Response(
        JSON.stringify({
          received: true,
          message: 'Event already processed',
          order_id: existingEvent.order_id
        }),
        {
          status: 200,
          headers: { 'Content-Type': 'application/json' },
        }
      )
    }

    // 2. 記錄事件（先佔位，防止並發處理）
    const { error: logError } = await supabase
      .from('webhook_events')
      .insert([{
        stripe_event_id: event.id,
        event_type: event.type,
        status: 'processing'
      }])

    if (logError) {
      // 如果是 unique constraint 錯誤，說明另一個請求正在處理
      if (logError.code === '23505') { // PostgreSQL unique violation
        console.log('⚠️ Event being processed concurrently:', event.id)
        return new Response(
          JSON.stringify({ received: true, message: 'Event being processed' }),
          {
            status: 200,
            headers: { 'Content-Type': 'application/json' },
          }
        )
      }
      // 其他錯誤
      console.error('❌ Failed to log event:', logError)
      throw logError
    }

    console.log('✅ Event logged, proceeding to create order')

    // ==================== 處理付款成功事件 ====================
    if (event.type === 'checkout.session.completed') {
      const session = event.data.object as Stripe.Checkout.Session

      // 從 metadata 取得訂單資料
      const orderData = JSON.parse(session.metadata?.orderData || '{}')

      if (!orderData || !orderData.items) {
        console.error('❌ Invalid order data in metadata')

        // 更新事件狀態為失敗
        await supabase
          .from('webhook_events')
          .update({ status: 'failed' })
          .eq('stripe_event_id', event.id)

        return new Response(JSON.stringify({ error: 'Invalid order data' }), {
          status: 400,
          headers: { 'Content-Type': 'application/json' },
        })
      }

      // 計算金額
      const subtotal = parseFloat(orderData.subtotal || '0')
      const tax = parseFloat(orderData.tax || '0')
      const tip = parseFloat(orderData.tip || '0')
      const total = subtotal + tax + tip

      // 準備商品列表
      const itemsForRPC = orderData.items.map((item: any) => ({
        item_id: item.menuItemId || null,
        name: item.name,
        quantity: item.quantity,
        price: item.price,
        options: item.selectedOptions || [],
        is_custom: false
      }))

      try {
        // 安全：使用 RPC 創建訂單（有 transaction 保護）
        const { data: result, error: rpcError } = await supabase.rpc(
          'create_order_with_items',
          {
            p_customer_name: orderData.customerName || 'Guest',
            p_phone: orderData.phone || '',
            p_email: orderData.email || '',
            p_order_type: orderData.orderType || orderData.service_mode || 'dine-in',
            p_scheduled_time: orderData.scheduledTime || null,
            p_items: itemsForRPC,
            p_subtotal: subtotal,
            p_tax: tax,
            p_tip: tip,
            p_total: total,
            p_order_source: 'qr',
            p_payment_method: 'stripe',
            p_payment_status: 'paid',
            p_stripe_session_id: session.id,
            p_stripe_payment_intent: session.payment_intent as string || '',
            p_status: 'preparing', // QR 訂單直接進入製作
            p_notes: orderData.notes || 'Online order via Stripe'
          }
        )

        if (rpcError || !result || !result[0].success) {
          console.error('❌ RPC error:', rpcError || result[0].message)

          // 更新事件狀態為失敗
          await supabase
            .from('webhook_events')
            .update({ status: 'failed' })
            .eq('stripe_event_id', event.id)

          throw new Error(result[0].message || rpcError.message)
        }

        const orderId = result[0].order_id
        console.log('✅ Order created via RPC:', orderId)

        // 更新事件狀態為成功
        await supabase
          .from('webhook_events')
          .update({
            status: 'processed',
            order_id: orderId
          })
          .eq('stripe_event_id', event.id)

        return new Response(
          JSON.stringify({
            success: true,
            orderId: orderId,
            message: 'Order created successfully'
          }),
          {
            status: 200,
            headers: { 'Content-Type': 'application/json' },
          }
        )
      } catch (err) {
        console.error('❌ Order creation failed:', err)

        // 確保事件標記為失敗
        await supabase
          .from('webhook_events')
          .update({ status: 'failed' })
          .eq('stripe_event_id', event.id)

        throw err
      }
    }

    // 處理付款失敗事件
    if (event.type === 'checkout.session.expired') {
      const session = event.data.object as Stripe.Checkout.Session
      console.log('⚠️ Session expired:', session.id)
      // 可以記錄到資料庫或發送通知
    }

    // 其他事件直接返回成功
    return new Response(JSON.stringify({ received: true }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    })

  } catch (err) {
    console.error('❌ Webhook error:', err)
    return new Response(
      JSON.stringify({ error: err.message }),
      {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      }
    )
  }
})
