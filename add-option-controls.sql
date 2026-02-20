-- ==========================================
-- 为选项和选项值添加启用/禁用控制
-- ==========================================

-- 1. 检查 is_enabled 字段是否存在（选项级别）
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'options_library' AND column_name = 'is_enabled'
    ) THEN
        ALTER TABLE options_library ADD COLUMN is_enabled BOOLEAN DEFAULT true;
        CREATE INDEX IF NOT EXISTS idx_options_enabled ON options_library(is_enabled);
    END IF;
END $$;

-- 2. 更新现有 choices 数据结构，为每个选项值添加 enabled 字段
-- 注意：这个脚本会为所有现有的选项值添加 enabled: true

DO $$
DECLARE
    opt RECORD;
    updated_choices JSONB;
    choice JSONB;
BEGIN
    FOR opt IN SELECT id, choices FROM options_library LOOP
        updated_choices := '[]'::JSONB;

        -- 遍历每个选项值
        FOR choice IN SELECT * FROM jsonb_array_elements(opt.choices) LOOP
            -- 如果选项值还没有 enabled 字段，添加它
            IF NOT choice ? 'enabled' THEN
                choice := choice || jsonb_build_object('enabled', true);
            END IF;

            updated_choices := updated_choices || jsonb_build_array(choice);
        END LOOP;

        -- 更新选项的 choices
        UPDATE options_library
        SET choices = updated_choices
        WHERE id = opt.id;
    END LOOP;
END $$;

-- 3. 查看更新后的数据
SELECT
    id,
    name,
    type,
    is_enabled AS 选项启用状态,
    jsonb_pretty(choices) AS 选项值详情
FROM options_library
ORDER BY id;

-- ==========================================
-- 使用说明
-- ==========================================

-- 禁用整个选项（例如：辣度选项暂时不提供）
-- UPDATE options_library SET is_enabled = false WHERE name = '辣度';

-- 禁用某个选项值（例如：超辣暂时缺货）
-- UPDATE options_library
-- SET choices = jsonb_set(
--     choices,
--     '{2,enabled}',  -- 数组索引，0-based
--     'false'::jsonb
-- )
-- WHERE name = '辣度';

-- 启用所有选项
-- UPDATE options_library SET is_enabled = true;
