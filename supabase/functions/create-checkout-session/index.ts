// Supabase Edge Function: Create Stripe Checkout Session
// 用途：為客戶創建 Stripe 付款 Session

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import Stripe from 'https://esm.sh/stripe@14.10.0?target=deno'

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') || '', {
  apiVersion: '2023-10-16',
  httpClient: Stripe.createFetchHttpClient(),
})

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  if (req.method !== 'POST') {
    return new Response('Method not allowed', {
      status: 405,
      headers: corsHeaders
    })
  }

  try {
    const { orderData } = await req.json()

    if (!orderData || !orderData.items || orderData.items.length === 0) {
      throw new Error('Invalid order data')
    }

    // 計算金額
    const subtotal = parseFloat(orderData.subtotal || '0')
    const tax = parseFloat(orderData.tax || '0')
    const tip = parseFloat(orderData.tip || '0')

    // 創建 line items
    const lineItems = []

    // 添加每個菜品
    for (const item of orderData.items) {
      lineItems.push({
        price_data: {
          currency: 'usd',
          product_data: {
            name: item.name,
            description: item.selectedOptions ?
              `加料: ${item.selectedOptions.map(o => o.optionName).join(', ')}` :
              undefined,
          },
          unit_amount: Math.round(item.price * 100), // 轉為美分
        },
        quantity: item.quantity,
      })
    }

    // 添加稅金
    if (tax > 0) {
      lineItems.push({
        price_data: {
          currency: 'usd',
          product_data: {
            name: 'Tax (8.25%)',
          },
          unit_amount: Math.round(tax * 100),
        },
        quantity: 1,
      })
    }

    // 添加小費
    if (tip > 0) {
      lineItems.push({
        price_data: {
          currency: 'usd',
          product_data: {
            name: 'Tip',
          },
          unit_amount: Math.round(tip * 100),
        },
        quantity: 1,
      })
    }

    // 獲取網站 URL
    const origin = req.headers.get('origin') || 'http://localhost:8000'

    // 創建 Stripe Checkout Session
    const session = await stripe.checkout.sessions.create({
      payment_method_types: ['card'],
      line_items: lineItems,
      mode: 'payment',
      success_url: `${origin}/order-success.html?session_id={CHECKOUT_SESSION_ID}`,
      cancel_url: `${origin}/`,
      customer_email: orderData.phone ? undefined : undefined, // 可選：添加客戶 email
      metadata: {
        // 將訂單資料存入 metadata，webhook 時會用到
        orderData: JSON.stringify(orderData),
      },
      // 自動稅金（如果不用 line item 方式）
      // automatic_tax: { enabled: false },
    })

    console.log('✅ Checkout session created:', session.id)

    return new Response(
      JSON.stringify({
        sessionId: session.id,
        url: session.url
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    )

  } catch (err) {
    console.error('❌ Error creating checkout session:', err)
    return new Response(
      JSON.stringify({ error: err.message }),
      {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    )
  }
})
