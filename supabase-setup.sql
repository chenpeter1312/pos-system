-- Supabase 数据库设置脚本
-- Lee's Taiwanese Comfort Food POS System

-- ==========================================
-- 1. 菜单表 (menu)
-- ==========================================
CREATE TABLE IF NOT EXISTS menu (
    id BIGSERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    english_name TEXT,
    price NUMERIC(10, 2) NOT NULL,
    category TEXT NOT NULL,
    emoji TEXT,
    image TEXT,
    description TEXT,
    available BOOLEAN DEFAULT true,
    applied_option_ids INTEGER[],
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 菜单表索引
CREATE INDEX IF NOT EXISTS idx_menu_category ON menu(category);
CREATE INDEX IF NOT EXISTS idx_menu_available ON menu(available);

-- ==========================================
-- 2. 选项库表 (options_library)
-- ==========================================
CREATE TABLE IF NOT EXISTS options_library (
    id BIGSERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    type TEXT NOT NULL CHECK (type IN ('single', 'multiple')),
    required BOOLEAN DEFAULT false,
    is_enabled BOOLEAN DEFAULT true,
    categories TEXT[],
    choices JSONB NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 选项库表索引
CREATE INDEX IF NOT EXISTS idx_options_enabled ON options_library(is_enabled);

-- ==========================================
-- 3. 订单表 (orders)
-- ==========================================
CREATE TABLE IF NOT EXISTS orders (
    id BIGSERIAL PRIMARY KEY,
    customer_name TEXT,
    phone TEXT,
    service_mode TEXT,
    items JSONB NOT NULL,
    total NUMERIC(10, 2) NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'completed', 'cancelled')),
    notes TEXT,
    scheduled_time TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 订单表索引
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status);
CREATE INDEX IF NOT EXISTS idx_orders_created ON orders(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_orders_phone ON orders(phone);

-- ==========================================
-- 4. 启用 Row Level Security (RLS)
-- ==========================================

-- 启用 RLS
ALTER TABLE menu ENABLE ROW LEVEL SECURITY;
ALTER TABLE options_library ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;

-- ==========================================
-- 5. RLS 策略 (允许匿名读取和写入 - 开发阶段)
-- ==========================================

-- 菜单表策略
CREATE POLICY "Enable read access for all users" ON menu
    FOR SELECT USING (true);

CREATE POLICY "Enable insert for all users" ON menu
    FOR INSERT WITH CHECK (true);

CREATE POLICY "Enable update for all users" ON menu
    FOR UPDATE USING (true);

CREATE POLICY "Enable delete for all users" ON menu
    FOR DELETE USING (true);

-- 选项库表策略
CREATE POLICY "Enable read access for all users" ON options_library
    FOR SELECT USING (true);

CREATE POLICY "Enable insert for all users" ON options_library
    FOR INSERT WITH CHECK (true);

CREATE POLICY "Enable update for all users" ON options_library
    FOR UPDATE USING (true);

CREATE POLICY "Enable delete for all users" ON options_library
    FOR DELETE USING (true);

-- 订单表策略
CREATE POLICY "Enable read access for all users" ON orders
    FOR SELECT USING (true);

CREATE POLICY "Enable insert for all users" ON orders
    FOR INSERT WITH CHECK (true);

CREATE POLICY "Enable update for all users" ON orders
    FOR UPDATE USING (true);

CREATE POLICY "Enable delete for all users" ON orders
    FOR DELETE USING (true);

-- ==========================================
-- 6. 自动更新 updated_at 触发器
-- ==========================================

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 为每个表创建触发器
CREATE TRIGGER update_menu_updated_at
    BEFORE UPDATE ON menu
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_options_updated_at
    BEFORE UPDATE ON options_library
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_orders_updated_at
    BEFORE UPDATE ON orders
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ==========================================
-- 完成！
-- ==========================================
