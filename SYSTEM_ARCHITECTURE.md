# 🏗️ Lee's POS 系統架構說明

## 📊 系統概覽

```
┌─────────────────────────────────────────────────────────────────────┐
│                          Vercel 靜態託管                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐              │
│  │              │  │              │  │              │              │
│  │  員工點餐     │  │  客人點餐     │  │  後台管理     │              │
│  │ employee-pos │  │    pos.html  │  │  admin.html  │              │
│  │    .html     │  │              │  │              │              │
│  │              │  │              │  │              │              │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘              │
│         │                 │                 │                      │
└─────────┼─────────────────┼─────────────────┼──────────────────────┘
          │                 │                 │
          │      ┌──────────▼─────────────────▼──────────┐
          │      │                                        │
          └──────►    Supabase（核心資料庫 + API）        │
                 │                                        │
                 │  ┌──────────────────────────────────┐ │
                 │  │     PostgreSQL Database          │ │
                 │  │  ┌────────────────────────────┐  │ │
                 │  │  │ • menu_items (菜單)         │  │ │
                 │  │  │ • orders (訂單)             │  │ │
                 │  │  │ • order_items (訂單項目)    │  │ │
                 │  │  │ • staff_users (員工)        │  │ │
                 │  │  │ • staff_sessions (登入)     │  │ │
                 │  │  │ • login_attempts (安全)     │  │ │
                 │  │  │ • inventory_items (庫存)    │  │ │
                 │  │  └────────────────────────────┘  │ │
                 │  └──────────────────────────────────┘ │
                 │                                        │
                 │  ┌──────────────────────────────────┐ │
                 │  │     RPC Functions (安全層)        │ │
                 │  │  • attempt_staff_login()         │ │
                 │  │  • create_order_with_items()     │ │
                 │  │  • decrement_inventory()         │ │
                 │  └──────────────────────────────────┘ │
                 │                                        │
                 │  ┌──────────────────────────────────┐ │
                 │  │     Row Level Security (RLS)      │ │
                 │  │  • 防止未授權存取                  │ │
                 │  │  • 基於 session token 驗證        │ │
                 │  └──────────────────────────────────┘ │
                 └────────────────────────────────────────┘
```

---

## 🎯 三大系統詳細說明

### 1️⃣ 員工點餐系統 (employee-pos.html)

**功能：**
- ✅ PIN 碼登入（4位數密碼）
- ✅ 瀏覽菜單並加入購物車
- ✅ 選擇內用/外帶
- ✅ 支援現金、刷卡、其他付款方式
- ✅ 查看今日訂單

**與 Supabase 的連接：**
```javascript
// 1. 登入驗證（使用 RPC）
supabase.rpc('attempt_staff_login', {
    p_pin_code: '1111',
    p_ip_address: 'device_ip',
    p_device_info: 'browser_info'
})
// 返回：session_token（12小時有效）

// 2. 讀取菜單
supabase.from('menu_items').select('*')

// 3. 建立訂單（使用 RPC，自動扣庫存）
supabase.rpc('create_order_with_items', {
    p_session_token: token,
    p_order_type: 'dine_in',
    p_payment_method: 'cash',
    p_items: [...],
    p_subtotal: 100,
    p_tax: 8.25,
    p_total_price: 108.25
})
```

**安全機制：**
- 🔐 登入失敗 5 次鎖定 15 分鐘
- 🔐 Session token 驗證（不直接存取資料庫）
- 🔐 所有操作記錄在 login_attempts 表

---

### 2️⃣ 客人點餐系統 (pos.html)

**功能：**
- ✅ 無需登入（公開訪問）
- ✅ 瀏覽菜單並加入購物車
- ✅ 選擇內用/外帶
- ✅ 支援現金、刷卡、其他付款方式

**與 Supabase 的連接：**
```javascript
// 1. 讀取菜單（公開存取）
supabase.from('menu_items').select('*')

// 2. 建立訂單（使用匿名權限）
supabase.from('orders').insert({...})
supabase.from('order_items').insert([...])
```

**差異：**
- ❌ 不需要員工登入
- ❌ 不記錄操作員資訊
- ✅ 使用 Supabase anon key（公開 API）

---

### 3️⃣ 後台管理系統 (admin.html)

**功能：**
- ✅ 查看所有訂單
- ✅ 管理菜單（新增、編輯、刪除）
- ✅ 管理庫存
- ✅ 查看營收報表
- ✅ 管理員工帳號

**與 Supabase 的連接：**
```javascript
// 1. 讀取所有訂單（需要 admin 權限）
supabase.from('orders')
    .select('*, order_items(*)')
    .order('created_at', { ascending: false })

// 2. 管理菜單
supabase.from('menu_items').insert({...})
supabase.from('menu_items').update({...}).eq('id', id)
supabase.from('menu_items').delete().eq('id', id)

// 3. 管理庫存
supabase.from('inventory_items').select('*')
supabase.from('inventory_items').update({ quantity })

// 4. 營收報表
supabase.from('orders')
    .select('total_price, created_at')
    .gte('created_at', startDate)
```

**安全考量：**
- ⚠️ 目前使用 anon key（需要加強權限控制）
- 🔒 建議：應該要有管理員登入系統
- 🔒 建議：使用 RLS 限制只有管理員能修改菜單

---

## 🔄 資料流向圖

### 訂單建立流程

```
┌──────────────┐
│ 使用者選擇商品 │
└───────┬──────┘
        │
        ▼
┌──────────────┐
│ 加入購物車     │  (前端狀態管理)
└───────┬──────┘
        │
        ▼
┌──────────────┐
│ 點擊付款按鈕   │
└───────┬──────┘
        │
        ▼
┌────────────────────────────────────┐
│ 呼叫 RPC: create_order_with_items   │
└───────┬────────────────────────────┘
        │
        ▼
┌────────────────────────────────────┐
│         Supabase RPC 函數           │
│  1. 驗證 session token (員工)       │
│  2. INSERT INTO orders              │
│  3. INSERT INTO order_items (批次)  │
│  4. 扣除庫存 (decrement_inventory)  │
│  5. 返回 order_id                   │
└───────┬────────────────────────────┘
        │
        ▼
┌────────────────────────────────────┐
│  前端顯示成功訊息（Toast）           │
│  "訂單 #12345 已完成"               │
└────────────────────────────────────┘
```

---

## 💳 未來整合 Stripe 支付方案

### 🎯 目標
讓客人點餐系統支援線上信用卡付款（Stripe）

### 📐 架構設計

```
┌─────────────────────────────────────────────────────────────────┐
│                     客人點餐系統 (pos.html)                       │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  1. 客人選擇商品 → 加入購物車                               │  │
│  │  2. 點擊「💳 信用卡付款」按鈕                               │  │
│  └──────────────────┬───────────────────────────────────────┘  │
└────────────────────┼──────────────────────────────────────────┘
                     │
                     ▼
        ┌────────────────────────────┐
        │   Stripe Checkout Session  │
        │  (在 Stripe 網站完成付款)   │
        └────────────┬───────────────┘
                     │
                     │ [付款成功]
                     ▼
        ┌────────────────────────────┐
        │   Stripe Webhook 回調       │
        │  POST /api/stripe/webhook   │
        └────────────┬───────────────┘
                     │
                     ▼
        ┌────────────────────────────────────┐
        │    Vercel Serverless Function      │
        │  (接收 Stripe webhook 通知)         │
        │  1. 驗證 Stripe 簽名                │
        │  2. 呼叫 Supabase RPC               │
        │  3. 建立訂單 + 扣庫存               │
        └────────────┬───────────────────────┘
                     │
                     ▼
        ┌────────────────────────────────────┐
        │       Supabase Database            │
        │  INSERT INTO orders                │
        │  payment_method = 'stripe'         │
        │  stripe_payment_id = 'pi_xxxxx'    │
        └────────────────────────────────────┘
```

### 🛠️ 實作步驟

#### Step 1: 在 Supabase 新增 Stripe 相關欄位

```sql
-- 擴充 orders 表
ALTER TABLE orders ADD COLUMN stripe_payment_intent_id TEXT;
ALTER TABLE orders ADD COLUMN stripe_checkout_session_id TEXT;
ALTER TABLE orders ADD COLUMN payment_status TEXT DEFAULT 'pending';
-- payment_status: pending, completed, failed, refunded

CREATE INDEX idx_orders_stripe_payment_intent
ON orders(stripe_payment_intent_id);
```

#### Step 2: 建立 Vercel Serverless API

在專案新增 `api/stripe/webhook.js`：

```javascript
// /api/stripe/webhook.js
import Stripe from 'stripe';
import { createClient } from '@supabase/supabase-js';

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);
const supabase = createClient(
    process.env.SUPABASE_URL,
    process.env.SUPABASE_SERVICE_ROLE_KEY // 使用 service role key
);

export default async function handler(req, res) {
    if (req.method !== 'POST') {
        return res.status(405).json({ error: 'Method not allowed' });
    }

    const sig = req.headers['stripe-signature'];
    let event;

    try {
        // 驗證 Stripe webhook 簽名
        event = stripe.webhooks.constructEvent(
            req.body,
            sig,
            process.env.STRIPE_WEBHOOK_SECRET
        );
    } catch (err) {
        return res.status(400).json({ error: `Webhook Error: ${err.message}` });
    }

    // 處理付款成功事件
    if (event.type === 'checkout.session.completed') {
        const session = event.data.object;
        const { order_data } = session.metadata; // 從 metadata 取得訂單資料

        // 建立訂單
        const { data, error } = await supabase.rpc('create_order_with_items', {
            p_session_token: null, // Stripe 付款不需要員工 token
            p_order_type: order_data.order_type,
            p_payment_method: 'stripe',
            p_items: JSON.parse(order_data.items),
            p_subtotal: order_data.subtotal,
            p_tax: order_data.tax,
            p_total_price: session.amount_total / 100, // Stripe 金額是分為單位
            p_stripe_payment_intent_id: session.payment_intent,
            p_stripe_checkout_session_id: session.id
        });

        if (error) {
            console.error('建立訂單失敗:', error);
            return res.status(500).json({ error: 'Failed to create order' });
        }

        console.log('✅ Stripe 訂單建立成功:', data);
    }

    res.status(200).json({ received: true });
}
```

#### Step 3: 前端整合 Stripe Checkout

修改 `pos.html`：

```javascript
// 新增 Stripe 付款按鈕
const handleStripeCheckout = async () => {
    const response = await fetch('/api/stripe/create-checkout', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
            items: cart,
            order_type: orderType,
            subtotal: cartStats.subtotal,
            tax: cartStats.tax,
            total: cartStats.total
        })
    });

    const { url } = await response.json();
    window.location.href = url; // 跳轉到 Stripe 付款頁面
};

// 付款按鈕
<button className="pay-btn stripe" onClick={handleStripeCheckout}>
    💳 Stripe 付款
</button>
```

#### Step 4: 建立 Checkout Session API

新增 `api/stripe/create-checkout.js`：

```javascript
import Stripe from 'stripe';
const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);

export default async function handler(req, res) {
    const { items, order_type, subtotal, tax, total } = req.body;

    // 建立 Stripe Checkout Session
    const session = await stripe.checkout.sessions.create({
        payment_method_types: ['card'],
        line_items: items.map(item => ({
            price_data: {
                currency: 'usd',
                product_data: {
                    name: item.name,
                },
                unit_amount: Math.round(item.price * 100), // 轉成分
            },
            quantity: item.quantity,
        })),
        mode: 'payment',
        success_url: `${process.env.VERCEL_URL}/order-success.html?session_id={CHECKOUT_SESSION_ID}`,
        cancel_url: `${process.env.VERCEL_URL}/pos.html`,
        metadata: {
            order_data: JSON.stringify({
                order_type,
                items,
                subtotal,
                tax
            })
        }
    });

    res.status(200).json({ url: session.url });
}
```

---

### 🔐 Stripe 環境變數設定

在 Vercel Dashboard 設定：

```env
STRIPE_SECRET_KEY=sk_live_xxxxxxxxxxxxx
STRIPE_WEBHOOK_SECRET=whsec_xxxxxxxxxxxxx
SUPABASE_URL=https://xxxxx.supabase.co
SUPABASE_SERVICE_ROLE_KEY=eyJxxx... (從 Supabase 取得)
```

---

### 📋 Stripe 整合 Checklist

- [ ] 註冊 Stripe 帳號（https://stripe.com）
- [ ] 取得 API Keys（Secret Key + Publishable Key）
- [ ] 在 Vercel 設定環境變數
- [ ] 建立 `/api/stripe/create-checkout.js`
- [ ] 建立 `/api/stripe/webhook.js`
- [ ] 在 Stripe Dashboard 設定 Webhook URL
  - URL: `https://你的網域.vercel.app/api/stripe/webhook`
  - 監聽事件: `checkout.session.completed`
- [ ] 修改 `pos.html` 加入 Stripe 付款按鈕
- [ ] 測試流程（使用 Stripe Test Mode）
- [ ] 上線前切換到 Live Mode

---

## 🔒 安全建議

### 目前系統的安全風險

1. **後台管理沒有登入系統** ⚠️
   - 任何人都能訪問 admin.html
   - 建議：加入管理員登入（PIN 或密碼）

2. **客人點餐使用 anon key** ⚠️
   - 可能被濫用（大量建立假訂單）
   - 建議：加入 Rate Limiting（限制每 IP 每分鐘建立訂單數）

3. **沒有 Realtime 同步** ⚠️
   - 需要手動刷新才能看到其他系統的更新
   - 建議：使用 Supabase Realtime 訂閱

### 推薦加強項目

```javascript
// 1. 加入 Rate Limiting (Supabase Edge Function)
export async function rateLimit(ip: string) {
    const count = await redis.incr(`rate:${ip}`);
    if (count === 1) await redis.expire(`rate:${ip}`, 60); // 1分鐘過期
    if (count > 10) throw new Error('Too many requests');
}

// 2. 加入訂單驗證
CREATE OR REPLACE FUNCTION validate_order_amount(
    p_items JSONB,
    p_total_price DECIMAL
) RETURNS BOOLEAN AS $$
DECLARE
    calculated_total DECIMAL;
BEGIN
    -- 計算實際總金額（防止前端竄改價格）
    SELECT SUM((item->>'price')::DECIMAL * (item->>'quantity')::INT)
    INTO calculated_total
    FROM jsonb_array_elements(p_items) AS item;

    RETURN ABS(calculated_total - p_total_price) < 0.01;
END;
$$ LANGUAGE plpgsql;
```

---

## 📊 資料庫表格關係圖

```
┌─────────────────┐
│   staff_users   │
│  ├─ id (PK)     │
│  ├─ username    │
│  ├─ pin_code    │◄─────────┐
│  └─ role        │          │
└─────────────────┘          │
                              │
┌─────────────────┐          │
│ staff_sessions  │          │
│  ├─ id (PK)     │          │
│  ├─ staff_id    │──────────┘
│  ├─ session_token
│  └─ expires_at  │
└─────────────────┘
        │
        │ (驗證)
        ▼
┌─────────────────┐       ┌─────────────────┐
│     orders      │       │   menu_items    │
│  ├─ id (PK)     │       │  ├─ id (PK)     │
│  ├─ staff_id    │       │  ├─ name        │
│  ├─ order_type  │       │  ├─ price       │
│  ├─ payment_... │       │  ├─ category    │
│  └─ total_price │       │  └─ available   │
└────────┬────────┘       └────────┬────────┘
         │                         │
         │ (1 對多)                │
         ▼                         │
┌─────────────────┐                │
│  order_items    │                │
│  ├─ id (PK)     │                │
│  ├─ order_id    │◄───────────────┘
│  ├─ item_id     │──────────────────┐
│  ├─ quantity    │                  │
│  └─ price       │                  ▼
└─────────────────┘       ┌─────────────────────┐
                          │ menu_packaging_map  │
                          │  ├─ menu_item_name  │
                          │  ├─ inventory_item_id│─┐
                          │  └─ qty_per_sale    │ │
                          └─────────────────────┘ │
                                                  │
                          ┌─────────────────────┐ │
                          │  inventory_items    │◄┘
                          │  ├─ id (PK)         │
                          │  ├─ name            │
                          │  ├─ quantity        │
                          │  └─ unit            │
                          └─────────────────────┘
```

---

## 🚀 未來擴充方向

1. **實時訂單更新**
   - 使用 Supabase Realtime
   - 廚房顯示自動更新

2. **會員系統**
   - 客人註冊/登入
   - 累積點數/優惠券

3. **報表分析**
   - 每日/每月營收報表
   - 熱銷商品分析
   - 庫存警報

4. **多語系支援**
   - 英文/中文切換
   - 儲存在 Supabase

5. **行動 App**
   - React Native
   - 使用相同 Supabase API

---

**📝 文件版本：** v1.0
**📅 最後更新：** 2026-02-20
**👨‍💻 維護者：** Lee's POS Team
