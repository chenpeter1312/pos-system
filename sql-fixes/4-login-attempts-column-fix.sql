-- ==========================================
-- 🔒 修復 login_attempts.success 欄位命名
-- ==========================================
-- 問題：success 是太常見的名稱，容易與函數返回值衝突
-- 解決：重命名為 is_success，並更新所有相關函數
-- ==========================================

-- 1. 重命名欄位
ALTER TABLE login_attempts 
RENAME COLUMN success TO is_success;

-- 2. 更新 attempt_staff_login 函數（修正所有 success 參考）
CREATE OR REPLACE FUNCTION attempt_staff_login(
    p_username TEXT,
    p_pin_code TEXT,
    p_ip_address TEXT DEFAULT NULL,
    p_device_info TEXT DEFAULT NULL
) RETURNS TABLE (
    success BOOLEAN,
    message TEXT,
    session_token TEXT,
    staff_id UUID,
    staff_role TEXT,
    staff_name TEXT,
    expires_at TIMESTAMPTZ
) AS $$
DECLARE
    v_staff RECORD;
    v_failed_attempts INT;
    v_blocked_until TIMESTAMPTZ;
    v_new_token TEXT;
    v_expires_at TIMESTAMPTZ;
BEGIN
    -- 1. 檢查是否被鎖定（✅ 明確使用 login_attempts.is_success）
    SELECT login_attempts.blocked_until INTO v_blocked_until
    FROM login_attempts
    WHERE (login_attempts.username = p_pin_code OR login_attempts.ip_address = p_ip_address)
      AND login_attempts.blocked_until > NOW()
    ORDER BY login_attempts.blocked_until DESC
    LIMIT 1;

    IF FOUND THEN
        RETURN QUERY SELECT
            FALSE,
            '帳號已鎖定，請於 ' || to_char(v_blocked_until, 'HH24:MI') || ' 後再試',
            NULL::TEXT,
            NULL::UUID,
            NULL::TEXT,
            NULL::TEXT,
            NULL::TIMESTAMPTZ;
        RETURN;
    END IF;

    -- 2. 檢查失敗次數（✅ 使用 is_success）
    SELECT COUNT(*) INTO v_failed_attempts
    FROM login_attempts
    WHERE (login_attempts.username = p_pin_code OR login_attempts.ip_address = p_ip_address)
      AND login_attempts.attempt_time > NOW() - INTERVAL '15 minutes'
      AND login_attempts.is_success = FALSE;

    IF v_failed_attempts >= 5 THEN
        v_blocked_until := NOW() + INTERVAL '15 minutes';
        INSERT INTO login_attempts (username, ip_address, is_success, blocked_until)
        VALUES (p_pin_code, p_ip_address, FALSE, v_blocked_until);

        RETURN QUERY SELECT
            FALSE,
            '登入失敗次數過多，帳號已鎖定 15 分鐘',
            NULL::TEXT,
            NULL::UUID,
            NULL::TEXT,
            NULL::TEXT,
            v_blocked_until;
        RETURN;
    END IF;

    -- 3. 驗證 PIN（✅ 只用 pin_code 查詢）
    SELECT * INTO v_staff
    FROM staff_users
    WHERE staff_users.pin_code = p_pin_code
      AND staff_users.is_active = TRUE;

    IF NOT FOUND THEN
        INSERT INTO login_attempts (username, ip_address, attempt_time, is_success)
        VALUES (p_pin_code, p_ip_address, NOW(), FALSE);

        RETURN QUERY SELECT
            FALSE,
            '帳號或密碼錯誤（剩餘嘗試次數：' || (5 - v_failed_attempts - 1) || '）',
            NULL::TEXT,
            NULL::UUID,
            NULL::TEXT,
            NULL::TEXT,
            NULL::TIMESTAMPTZ;
        RETURN;
    END IF;

    -- 4. 登入成功，創建 session
    v_new_token := encode(gen_random_bytes(32), 'base64');
    v_expires_at := NOW() + INTERVAL '12 hours';

    INSERT INTO staff_sessions (
        staff_id,
        session_token,
        device_info,
        ip_address,
        expires_at
    ) VALUES (
        v_staff.id,
        v_new_token,
        p_device_info,
        p_ip_address,
        v_expires_at
    );

    -- 記錄成功登入（✅ 使用 is_success）
    INSERT INTO login_attempts (username, ip_address, attempt_time, is_success)
    VALUES (p_pin_code, p_ip_address, NOW(), TRUE);

    -- 清理失敗記錄（✅ 使用 is_success）
    DELETE FROM login_attempts
    WHERE login_attempts.username = p_pin_code
      AND login_attempts.is_success = FALSE
      AND login_attempts.attempt_time > NOW() - INTERVAL '15 minutes';

    RETURN QUERY SELECT
        TRUE,
        '登入成功',
        v_new_token,
        v_staff.id,
        v_staff.role,
        v_staff.display_name,
        v_expires_at;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. 註解
COMMENT ON COLUMN login_attempts.is_success IS '登入是否成功（改名避免與函數返回值衝突）';

-- ✅ 修復完成！不再有 "ambiguous column" 錯誤
