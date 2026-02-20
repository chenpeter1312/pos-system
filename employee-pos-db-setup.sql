-- ==========================================
-- 員工 POS 系統 - 數據庫擴展
-- ==========================================
-- 說明：此腳本為員工 POS 系統添加必要的數據庫字段和表

-- ==========================================
-- 1️⃣ 擴展 orders 表
-- ==========================================

-- 添加訂單來源字段（區分顧客前台 vs 員工 POS）
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'orders' AND column_name = 'order_source'
    ) THEN
        ALTER TABLE orders ADD COLUMN order_source TEXT DEFAULT 'customer' CHECK (order_source IN ('customer', 'staff_pos'));
        COMMENT ON COLUMN orders.order_source IS '訂單來源：customer=顧客前台, staff_pos=員工POS';
    END IF;
END $$;

-- 添加付款方式字段
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'orders' AND column_name = 'payment_method'
    ) THEN
        ALTER TABLE orders ADD COLUMN payment_method TEXT CHECK (payment_method IN ('cash', 'card', 'qr_code', null));
        COMMENT ON COLUMN orders.payment_method IS '付款方式：cash=現金, card=刷卡, qr_code=掃碼';
    END IF;
END $$;

-- 添加付款狀態字段
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'orders' AND column_name = 'payment_status'
    ) THEN
        ALTER TABLE orders ADD COLUMN payment_status TEXT DEFAULT 'unpaid' CHECK (payment_status IN ('paid', 'unpaid', 'refunded'));
        COMMENT ON COLUMN orders.payment_status IS '付款狀態：paid=已付款, unpaid=未付款, refunded=已退款';
    END IF;
END $$;

-- 添加員工操作者字段（記錄哪位員工創建/修改訂單）
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'orders' AND column_name = 'staff_name'
    ) THEN
        ALTER TABLE orders ADD COLUMN staff_name TEXT;
        COMMENT ON COLUMN orders.staff_name IS '操作員工姓名';
    END IF;
END $$;

-- 添加訂單編號字段（日序號，例如：001, 002）
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'orders' AND column_name = 'daily_order_number'
    ) THEN
        ALTER TABLE orders ADD COLUMN daily_order_number INTEGER;
        COMMENT ON COLUMN orders.daily_order_number IS '當日訂單序號（每日重置）';
    END IF;
END $$;

-- 添加訂單類型字段（如果不存在）
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'orders' AND column_name = 'order_type'
    ) THEN
        ALTER TABLE orders ADD COLUMN order_type TEXT DEFAULT 'dine_in' CHECK (order_type IN ('dine_in', 'takeout', 'scheduled'));
        COMMENT ON COLUMN orders.order_type IS '訂單類型：dine_in=內用, takeout=外帶, scheduled=預約';
    END IF;
END $$;

-- 創建索引以提升查詢性能
CREATE INDEX IF NOT EXISTS idx_orders_source ON orders(order_source);
CREATE INDEX IF NOT EXISTS idx_orders_payment_status ON orders(payment_status);
CREATE INDEX IF NOT EXISTS idx_orders_daily_number ON orders(daily_order_number);
CREATE INDEX IF NOT EXISTS idx_orders_order_type ON orders(order_type);
-- 注意：不能直接在 DATE(created_at) 上創建索引，因為函數必須是 IMMUTABLE
-- 改用直接在 created_at 上創建索引即可
CREATE INDEX IF NOT EXISTS idx_orders_created_at ON orders(created_at);

-- ==========================================
-- 2️⃣ 創建員工用戶表（可選，用於權限管理）
-- ==========================================

CREATE TABLE IF NOT EXISTS staff_users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username TEXT UNIQUE NOT NULL,
    display_name TEXT NOT NULL,
    pin_code TEXT NOT NULL, -- 4位數字PIN碼（建議加密存儲）
    role TEXT DEFAULT 'staff' CHECK (role IN ('staff', 'admin')),
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE staff_users IS '員工用戶表 - 用於POS登入和權限管理';
COMMENT ON COLUMN staff_users.pin_code IS '4位數字PIN碼，用於快速登入';
COMMENT ON COLUMN staff_users.role IS 'staff=一般員工（只能點餐結帳）, admin=管理員（所有權限）';

-- 創建索引
CREATE INDEX IF NOT EXISTS idx_staff_username ON staff_users(username);
CREATE INDEX IF NOT EXISTS idx_staff_active ON staff_users(is_active);

-- 插入預設員工賬號（密碼：1234）
INSERT INTO staff_users (username, display_name, pin_code, role) VALUES
    ('admin', '管理員', '1234', 'admin'),
    ('staff1', '員工一號', '1111', 'staff'),
    ('staff2', '員工二號', '2222', 'staff')
ON CONFLICT (username) DO NOTHING;

-- ==========================================
-- 3️⃣ 更新現有訂單數據（向後兼容）
-- ==========================================

-- 將所有現有訂單標記為顧客前台訂單
UPDATE orders
SET order_source = 'customer',
    payment_status = 'unpaid'
WHERE order_source IS NULL;

-- ==========================================
-- 4️⃣ 創建輔助函數 - 生成當日訂單編號
-- ==========================================

CREATE OR REPLACE FUNCTION get_next_daily_order_number()
RETURNS INTEGER AS $$
DECLARE
    next_number INTEGER;
BEGIN
    -- 獲取今天最大的訂單編號
    SELECT COALESCE(MAX(daily_order_number), 0) + 1
    INTO next_number
    FROM orders
    WHERE DATE(created_at) = CURRENT_DATE;

    RETURN next_number;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION get_next_daily_order_number IS '獲取當日下一個訂單編號（每日從1開始）';

-- ==========================================
-- 5️⃣ 創建觸發器 - 自動設置訂單編號
-- ==========================================

CREATE OR REPLACE FUNCTION set_daily_order_number()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.daily_order_number IS NULL THEN
        NEW.daily_order_number := get_next_daily_order_number();
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_set_daily_order_number ON orders;
CREATE TRIGGER trg_set_daily_order_number
    BEFORE INSERT ON orders
    FOR EACH ROW
    EXECUTE FUNCTION set_daily_order_number();

-- ==========================================
-- 6️⃣ 創建視圖 - 員工 POS 訂單列表
-- ==========================================

CREATE OR REPLACE VIEW v_staff_pos_orders AS
SELECT
    o.id,
    o.daily_order_number AS "單號",
    o.order_type AS "類型",
    CASE o.order_type
        WHEN 'dine_in' THEN '內用'
        WHEN 'takeout' THEN '外帶'
        WHEN 'scheduled' THEN '預約'
    END AS "類型顯示",
    o.items::TEXT AS "品項",
    o.total_price AS "金額",
    o.payment_method AS "付款方式",
    CASE o.payment_method
        WHEN 'cash' THEN '現金'
        WHEN 'card' THEN '刷卡'
        WHEN 'qr_code' THEN '掃碼'
    END AS "付款方式顯示",
    o.payment_status AS "付款狀態",
    CASE o.payment_status
        WHEN 'paid' THEN '✅ 已付款'
        WHEN 'unpaid' THEN '⏳ 未付款'
        WHEN 'refunded' THEN '🔙 已退款'
    END AS "付款狀態顯示",
    o.status AS "訂單狀態",
    CASE o.status
        WHEN 'pending' THEN '📝 待處理'
        WHEN 'accepted' THEN '👨‍🍳 製作中'
        WHEN 'completed' THEN '✅ 已完成'
        WHEN 'cancelled' THEN '❌ 已取消'
    END AS "訂單狀態顯示",
    o.staff_name AS "員工",
    o.customer_name AS "顧客",
    o.phone AS "電話",
    o.created_at AS "建單時間",
    o.updated_at AS "更新時間",
    TO_CHAR(o.created_at, 'HH24:MI') AS "建單時刻"
FROM orders o
WHERE o.order_source = 'staff_pos'
ORDER BY o.created_at DESC;

COMMENT ON VIEW v_staff_pos_orders IS '員工POS訂單列表視圖 - 優化顯示格式';

-- ==========================================
-- 7️⃣ 驗證數據
-- ==========================================

-- 查看 orders 表新增的字段
SELECT
    column_name AS "字段名",
    data_type AS "數據類型",
    is_nullable AS "可為空",
    column_default AS "默認值"
FROM information_schema.columns
WHERE table_name = 'orders'
  AND column_name IN ('order_source', 'order_type', 'payment_method', 'payment_status', 'staff_name', 'daily_order_number', 'has_custom_items')
ORDER BY ordinal_position;

-- 查看員工用戶表
SELECT
    username AS "用戶名",
    display_name AS "顯示名稱",
    role AS "角色",
    is_active AS "啟用",
    created_at AS "創建時間"
FROM staff_users
ORDER BY role DESC, username;

-- 測試訂單編號函數
SELECT get_next_daily_order_number() AS "下一個訂單編號";

-- ==========================================
-- 📝 使用說明
-- ==========================================

-- ✅ 步驟 1：在 Supabase Dashboard → SQL Editor 執行本腳本
-- ✅ 步驟 2：查看「驗證數據」部分的查詢結果，確認字段和表已創建
-- ✅ 步驟 3：測試預設員工賬號（用戶名：staff1, PIN: 1111）
-- ✅ 步驟 4：開始開發員工 POS 前端界面

-- ⚠️ 注意事項：
-- 1. PIN 碼目前以明文存儲，生產環境建議使用加密（例如 pgcrypto 擴展）
-- 2. daily_order_number 每日從 1 開始重置
-- 3. 現有訂單會自動標記為 'customer' 來源
-- 4. staff_users 表的 RLS 策略需要單獨配置（建議只允許 admin 角色訪問）

-- ==========================================
-- 8️⃣ 支持自定義金額項目
-- ==========================================

-- 說明：items 字段是 JSONB 數組，每個項目可以包含：
-- {
--   "id": "menu_item_id",  // 如果是菜單項目
--   "name": "商品名稱",
--   "price": 150,
--   "quantity": 2,
--   "options": [...],
--   "is_custom": true,      // 標記為自定義項目
--   "custom_amount": 50     // 自定義金額（可以是正數或負數）
-- }

-- 自定義項目範例：
-- {
--   "name": "折扣",
--   "is_custom": true,
--   "custom_amount": -20,
--   "quantity": 1,
--   "price": -20
-- }

-- 添加字段記錄是否包含自定義項目（用於篩選和報表）
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'orders' AND column_name = 'has_custom_items'
    ) THEN
        ALTER TABLE orders ADD COLUMN has_custom_items BOOLEAN DEFAULT false;
        COMMENT ON COLUMN orders.has_custom_items IS '是否包含自定義金額項目';
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_orders_has_custom ON orders(has_custom_items);

-- ==========================================
-- 9️⃣ RLS 策略設置（Row Level Security）
-- ==========================================

-- 啟用 RLS
ALTER TABLE staff_users ENABLE ROW LEVEL SECURITY;

-- 策略 1：所有人可以查詢啟用的員工（用於登入驗證）
CREATE POLICY "Anyone can read active staff"
    ON staff_users FOR SELECT
    USING (is_active = true);

-- 策略 2：只有在特定條件下可以插入/更新（需要根據實際認證方案調整）
-- 註：這裡暫時允許所有操作，實際部署時需要結合 Supabase Auth 調整
CREATE POLICY "Allow all operations for now"
    ON staff_users FOR ALL
    USING (true)
    WITH CHECK (true);

-- 確保 orders 表的 RLS 也支持新字段
-- 如果之前已經設置了 RLS，確保策略包含新字段
