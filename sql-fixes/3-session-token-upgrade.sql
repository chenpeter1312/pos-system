-- ==========================================
-- 🔒 Session Token 安全升級
-- ==========================================

-- 新增安全欄位
ALTER TABLE staff_sessions 
ADD COLUMN IF NOT EXISTS revoked_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS last_seen_at TIMESTAMPTZ DEFAULT NOW(),
ADD COLUMN IF NOT EXISTS device_id TEXT;

-- 建立索引加速查詢
CREATE INDEX IF NOT EXISTS idx_sessions_token_active 
ON staff_sessions(session_token) 
WHERE revoked_at IS NULL AND expires_at > NOW();

CREATE INDEX IF NOT EXISTS idx_sessions_staff_active
ON staff_sessions(staff_id)
WHERE revoked_at IS NULL;

-- 註解
COMMENT ON COLUMN staff_sessions.revoked_at IS '撤銷時間（用於登出或強制失效）';
COMMENT ON COLUMN staff_sessions.last_seen_at IS '最後活動時間（每次 API 請求更新）';
COMMENT ON COLUMN staff_sessions.device_id IS '設備識別碼（用於多設備管理）';
