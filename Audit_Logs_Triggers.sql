-- Drop existing function
DROP FUNCTION IF EXISTS audit_trigger_function() CASCADE;

-- Create fixed audit function with correct enum values
CREATE OR REPLACE FUNCTION audit_trigger_function()
RETURNS TRIGGER AS $$
DECLARE
    v_user_id UUID;
    v_old_json JSONB;
    v_new_json JSONB;
    v_changes JSONB;
    v_entity_id UUID;
    v_action audit_action;
    v_ip INET;
    v_user_agent TEXT;
BEGIN
    -- Determine action based on operation (using LOWERCASE values)
    IF TG_OP = 'INSERT' THEN
        v_action := 'create';  -- lowercase to match enum
    ELSIF TG_OP = 'UPDATE' THEN
        v_action := 'update';  -- lowercase to match enum
    ELSIF TG_OP = 'DELETE' THEN
        v_action := 'delete';  -- lowercase to match enum
    END IF;

    -- Try to get user_id from multiple sources
    v_user_id := COALESCE(
        -- From the record itself (if table has user_id)
        CASE WHEN TG_OP IN ('INSERT', 'UPDATE') 
             THEN NEW.user_id 
             ELSE OLD.user_id 
        END,
        -- From session setting (set by application)
        current_setting('app.current_user_id', TRUE)::UUID,
        -- From connection
        NULL
    );

    -- Get entity ID
    v_entity_id := COALESCE(
        CASE WHEN TG_OP IN ('INSERT', 'UPDATE') 
             THEN NEW.id 
             ELSE OLD.id 
        END,
        gen_random_uuid()
    );

    -- Convert records to JSONB
    IF TG_OP IN ('UPDATE', 'DELETE') THEN
        v_old_json := to_jsonb(OLD);
    END IF;
    
    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        v_new_json := to_jsonb(NEW);
    END IF;

    -- Calculate changes for UPDATE (excluding unchanged fields)
    IF TG_OP = 'UPDATE' THEN
        WITH changed_fields AS (
            SELECT key, value
            FROM jsonb_each(v_new_json)
            WHERE v_old_json->key IS DISTINCT FROM value
              AND key NOT IN ('updated_at', 'last_activity_at', 'created_at')
        )
        SELECT jsonb_object_agg(key, value)
        INTO v_changes
        FROM changed_fields;
    END IF;

    -- Insert audit record
    INSERT INTO audit_logs (
        id,
        user_id,
        action,
        entity_type,
        entity_id,
        old_values,
        new_values,
        changes,
        ip_address,
        user_agent,
        request_id,
        created_at
    ) VALUES (
        gen_random_uuid(),
        v_user_id,
        v_action,
        TG_TABLE_NAME,
        v_entity_id,
        v_old_json,
        v_new_json,
        v_changes,
        current_setting('app.current_ip', TRUE)::INET,
        current_setting('app.current_user_agent', TRUE),
        current_setting('app.current_request_id', TRUE)::UUID,
        NOW()
    );
    
    RETURN COALESCE(NEW, OLD);
EXCEPTION WHEN OTHERS THEN
    -- Log error but don't fail the main operation
    RAISE WARNING 'Audit trigger failed for table %: %', TG_TABLE_NAME, SQLERRM;
    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;












-- =========================================================
-- TRIGGERS FOR ALL TABLES (RUN THIS COMPLETE SCRIPT)
-- =========================================================

-- First, drop existing triggers to avoid conflicts
DO $$ 
DECLARE
    trigger_record RECORD;
BEGIN
    FOR trigger_record IN 
        SELECT tgname, relname 
        FROM pg_trigger 
        JOIN pg_class ON pg_trigger.tgrelid = pg_class.oid
        WHERE tgname LIKE 'trg_audit_%'
    LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS %I ON %I CASCADE', 
                      trigger_record.tgname, trigger_record.relname);
    END LOOP;
END $$;

-- =========================================================
-- CORE FINANCIAL TABLES
-- =========================================================

-- trades table
CREATE TRIGGER trg_audit_trades_insert AFTER INSERT ON trades FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();
CREATE TRIGGER trg_audit_trades_update AFTER UPDATE ON trades FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();
CREATE TRIGGER trg_audit_trades_delete AFTER DELETE ON trades FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();

-- users table
CREATE TRIGGER trg_audit_users_insert AFTER INSERT ON users FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();
CREATE TRIGGER trg_audit_users_update AFTER UPDATE ON users FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();
CREATE TRIGGER trg_audit_users_delete AFTER DELETE ON users FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();

-- trading_accounts table
CREATE TRIGGER trg_audit_accounts_insert AFTER INSERT ON trading_accounts FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();
CREATE TRIGGER trg_audit_accounts_update AFTER UPDATE ON trading_accounts FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();
CREATE TRIGGER trg_audit_accounts_delete AFTER DELETE ON trading_accounts FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();

-- user_subscriptions table
CREATE TRIGGER trg_audit_subscriptions_insert AFTER INSERT ON user_subscriptions FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();
CREATE TRIGGER trg_audit_subscriptions_update AFTER UPDATE ON user_subscriptions FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();
CREATE TRIGGER trg_audit_subscriptions_delete AFTER DELETE ON user_subscriptions FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();

-- =========================================================
-- TRADING STRATEGY & ANALYSIS TABLES
-- =========================================================

-- strategies table
CREATE TRIGGER trg_audit_strategies_insert AFTER INSERT ON strategies FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();
CREATE TRIGGER trg_audit_strategies_update AFTER UPDATE ON strategies FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();
CREATE TRIGGER trg_audit_strategies_delete AFTER DELETE ON strategies FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();

-- goals table
CREATE TRIGGER trg_audit_goals_insert AFTER INSERT ON goals FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();
CREATE TRIGGER trg_audit_goals_update AFTER UPDATE ON goals FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();
CREATE TRIGGER trg_audit_goals_delete AFTER DELETE ON goals FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();

-- =========================================================
-- JOURNAL & INSIGHTS TABLES
-- =========================================================

-- journal_entries table
CREATE TRIGGER trg_audit_journal_insert AFTER INSERT ON journal_entries FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();
CREATE TRIGGER trg_audit_journal_update AFTER UPDATE ON journal_entries FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();
CREATE TRIGGER trg_audit_journal_delete AFTER DELETE ON journal_entries FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();

-- trading_insights table
CREATE TRIGGER trg_audit_insights_insert AFTER INSERT ON trading_insights FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();
CREATE TRIGGER trg_audit_insights_update AFTER UPDATE ON trading_insights FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();
CREATE TRIGGER trg_audit_insights_delete AFTER DELETE ON trading_insights FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();

-- =========================================================
-- TAGS & CATEGORIZATION TABLES
-- =========================================================

-- tags table
CREATE TRIGGER trg_audit_tags_insert AFTER INSERT ON tags FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();
CREATE TRIGGER trg_audit_tags_update AFTER UPDATE ON tags FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();
CREATE TRIGGER trg_audit_tags_delete AFTER DELETE ON tags FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();

-- trade_tags table
CREATE TRIGGER trg_audit_trade_tags_insert AFTER INSERT ON trade_tags FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();
CREATE TRIGGER trg_audit_trade_tags_delete AFTER DELETE ON trade_tags FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();

-- journal_entry_tags table
CREATE TRIGGER trg_audit_journal_tags_insert AFTER INSERT ON journal_entry_tags FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();
CREATE TRIGGER trg_audit_journal_tags_delete AFTER DELETE ON journal_entry_tags FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();

-- =========================================================
-- REPORTS & SCHEDULING TABLES
-- =========================================================

-- reports table
CREATE TRIGGER trg_audit_reports_insert AFTER INSERT ON reports FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();
CREATE TRIGGER trg_audit_reports_update AFTER UPDATE ON reports FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();
CREATE TRIGGER trg_audit_reports_delete AFTER DELETE ON reports FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();

-- scheduled_reports table
CREATE TRIGGER trg_audit_scheduled_reports_insert AFTER INSERT ON scheduled_reports FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();
CREATE TRIGGER trg_audit_scheduled_reports_update AFTER UPDATE ON scheduled_reports FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();
CREATE TRIGGER trg_audit_scheduled_reports_delete AFTER DELETE ON scheduled_reports FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();

-- =========================================================
-- BACKGROUND JOBS TABLE
-- =========================================================

-- background_jobs table
CREATE TRIGGER trg_audit_background_jobs_insert AFTER INSERT ON background_jobs FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();
CREATE TRIGGER trg_audit_background_jobs_update AFTER UPDATE ON background_jobs FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();
CREATE TRIGGER trg_audit_background_jobs_delete AFTER DELETE ON background_jobs FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();

-- =========================================================
-- CUSTOM FIELDS TABLES (if used)
-- =========================================================

-- custom_fields table
CREATE TRIGGER trg_audit_custom_fields_insert AFTER INSERT ON custom_fields FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();
CREATE TRIGGER trg_audit_custom_fields_update AFTER UPDATE ON custom_fields FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();
CREATE TRIGGER trg_audit_custom_fields_delete AFTER DELETE ON custom_fields FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();

-- custom_field_values table
CREATE TRIGGER trg_audit_custom_values_insert AFTER INSERT ON custom_field_values FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();
CREATE TRIGGER trg_audit_custom_values_update AFTER UPDATE ON custom_field_values FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();
CREATE TRIGGER trg_audit_custom_values_delete AFTER DELETE ON custom_field_values FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();

-- =========================================================
-- SYSTEM TABLES
-- =========================================================

-- packages table
CREATE TRIGGER trg_audit_packages_insert AFTER INSERT ON packages FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();
CREATE TRIGGER trg_audit_packages_update AFTER UPDATE ON packages FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();
CREATE TRIGGER trg_audit_packages_delete AFTER DELETE ON packages FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();

-- instrument_specs table
CREATE TRIGGER trg_audit_instrument_specs_insert AFTER INSERT ON instrument_specs FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();
CREATE TRIGGER trg_audit_instrument_specs_update AFTER UPDATE ON instrument_specs FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();
CREATE TRIGGER trg_audit_instrument_specs_delete AFTER DELETE ON instrument_specs FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();

-- system_settings table
CREATE TRIGGER trg_audit_system_settings_insert AFTER INSERT ON system_settings FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();
CREATE TRIGGER trg_audit_system_settings_update AFTER UPDATE ON system_settings FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();
CREATE TRIGGER trg_audit_system_settings_delete AFTER DELETE ON system_settings FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();






















select * from audit_logs;















-- =========================================================
-- FIXED TEST SCRIPT - PART 2 (Reports section fixed)
-- =========================================================

DO $$
DECLARE
    test_user_id UUID := '14261423-180e-4f43-82bb-f187ad438ead'::uuid;
    test_account_id UUID;
    test_trade_id UUID;
    test_strategy_id UUID;
    test_journal_id UUID;
    test_goal_id UUID;
    test_tag_id UUID;
    test_insight_id UUID;
    test_report_id UUID;
    test_job_id UUID;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'STARTING AUDIT TRIGGER TESTS';
    RAISE NOTICE '========================================';

    -- =====================================================
    -- TEST 1: trading_accounts table
    -- =====================================================
    RAISE NOTICE 'TEST 1: trading_accounts - INSERT';
    INSERT INTO trading_accounts (id, user_id, account_name, account_type, currency, initial_balance, current_balance)
    VALUES (gen_random_uuid(), test_user_id, 'Audit Test Account', 'real', 'USD', 10000, 10000)
    RETURNING id INTO test_account_id;
    
    RAISE NOTICE 'TEST 1: trading_accounts - UPDATE';
    UPDATE trading_accounts SET account_name = 'Updated Audit Account' WHERE id = test_account_id;
    
    -- =====================================================
    -- TEST 2: trades table
    -- =====================================================
    RAISE NOTICE 'TEST 2: trades - INSERT';
    INSERT INTO trades (
        id, user_id, account_id, symbol, instrument_type, 
        trade_type, position_type, quantity, entry_price, entry_date, status
    ) VALUES (
        gen_random_uuid(), test_user_id, test_account_id, 'EURUSD', 'forex',
        'buy', 'long', 10000, 1.0850, NOW(), 'open'
    ) RETURNING id INTO test_trade_id;
    
    RAISE NOTICE 'TEST 2: trades - UPDATE (notes)';
    UPDATE trades SET notes = 'Audit test note' WHERE id = test_trade_id;
    
    RAISE NOTICE 'TEST 2: trades - CLOSE (with proper fields)';
    UPDATE trades 
    SET status = 'closed', 
        exit_price = 1.0950, 
        exit_date = NOW(),
        exit_reason = 'tp_hit'
    WHERE id = test_trade_id;
    
    -- =====================================================
    -- TEST 3: strategies table
    -- =====================================================
    RAISE NOTICE 'TEST 3: strategies - INSERT';
    INSERT INTO strategies (id, user_id, strategy_name, is_active)
    VALUES (gen_random_uuid(), test_user_id, 'Audit Test Strategy', true)
    RETURNING id INTO test_strategy_id;
    
    RAISE NOTICE 'TEST 3: strategies - UPDATE';
    UPDATE strategies SET description = 'Added via audit test' WHERE id = test_strategy_id;
    
    -- =====================================================
    -- TEST 4: journal_entries table
    -- =====================================================
    RAISE NOTICE 'TEST 4: journal_entries - INSERT';
    INSERT INTO journal_entries (id, user_id, account_id, entry_type, entry_date, title, content)
    VALUES (gen_random_uuid(), test_user_id, test_account_id, 'daily', CURRENT_DATE, 'Audit Test', 'Test content')
    RETURNING id INTO test_journal_id;
    
    RAISE NOTICE 'TEST 4: journal_entries - UPDATE';
    UPDATE journal_entries SET mood = 'happy' WHERE id = test_journal_id;
    
    -- =====================================================
    -- TEST 5: goals table
    -- =====================================================
    RAISE NOTICE 'TEST 5: goals - INSERT';
    INSERT INTO goals (id, user_id, account_id, goal_type, goal_category, name, target_value, unit, start_date, end_date)
    VALUES (gen_random_uuid(), test_user_id, test_account_id, 'monthly', 'profit', 'Audit Goal', 1000, 'USD', CURRENT_DATE, CURRENT_DATE + 30)
    RETURNING id INTO test_goal_id;
    
    RAISE NOTICE 'TEST 5: goals - UPDATE';
    UPDATE goals SET current_value = 500 WHERE id = test_goal_id;
    
    -- =====================================================
    -- TEST 6: tags table
    -- =====================================================
    RAISE NOTICE 'TEST 6: tags - INSERT';
    INSERT INTO tags (id, user_id, name, color)
    VALUES (gen_random_uuid(), test_user_id, 'audit-tag', '#FF0000')
    RETURNING id INTO test_tag_id;
    
    RAISE NOTICE 'TEST 6: tags - UPDATE';
    UPDATE tags SET color = '#00FF00' WHERE id = test_tag_id;
    
    -- =====================================================
    -- TEST 7: trading_insights table
    -- =====================================================
    RAISE NOTICE 'TEST 7: trading_insights - INSERT';
    INSERT INTO trading_insights (id, user_id, insight_type, title, description)
    VALUES (gen_random_uuid(), test_user_id, 'lesson', 'Audit Insight', 'Test insight')
    RETURNING id INTO test_insight_id;
    
    RAISE NOTICE 'TEST 7: trading_insights - UPDATE';
    UPDATE trading_insights SET importance = 'high' WHERE id = test_insight_id;
    
    -- =====================================================
    -- TEST 8: reports table - FIXED with public_token
    -- =====================================================
    RAISE NOTICE 'TEST 8: reports - INSERT';
    INSERT INTO reports (id, user_id, account_id, report_name, report_type, report_format, file_path, file_size)
    VALUES (gen_random_uuid(), test_user_id, test_account_id, 'Audit Report', 'trades', 'csv', '/tmp/test.csv', 100)
    RETURNING id INTO test_report_id;
    
    RAISE NOTICE 'TEST 8: reports - UPDATE (with proper public token)';
    UPDATE reports 
    SET is_public = true, 
        public_token = gen_random_uuid()  -- ✅ FIXED: Added required public_token
    WHERE id = test_report_id;
    
    -- =====================================================
    -- TEST 9: background_jobs table
    -- =====================================================
    RAISE NOTICE 'TEST 9: background_jobs - INSERT';
    INSERT INTO background_jobs (id, user_id, job_type, job_data)
    VALUES (gen_random_uuid(), test_user_id, 'test_job', '{}')
    RETURNING id INTO test_job_id;
    
    RAISE NOTICE 'TEST 9: background_jobs - UPDATE';
    UPDATE background_jobs SET progress = 50 WHERE id = test_job_id;
    
    -- =====================================================
    -- TEST 10: user_subscriptions table (if exists)
    -- =====================================================
    RAISE NOTICE 'TEST 10: user_subscriptions - INSERT (if table exists)';
    BEGIN
        INSERT INTO user_subscriptions (id, user_id, package_id, billing_cycle, start_date, end_date)
        SELECT gen_random_uuid(), test_user_id, id, 'monthly', CURRENT_DATE, CURRENT_DATE + 30
        FROM packages LIMIT 1;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'user_subscriptions table not available';
    END;
    
    -- =====================================================
    -- TEST 11: Delete operations (with proper order due to FKs)
    -- =====================================================
    RAISE NOTICE 'TEST 11: DELETE operations';
    
    -- Delete in correct order (child tables first)
    BEGIN
        DELETE FROM trade_tags WHERE tag_id = test_tag_id;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'No trade_tags to delete';
    END;
    
    BEGIN
        DELETE FROM journal_entry_tags WHERE tag_id = test_tag_id;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'No journal_entry_tags to delete';
    END;
    
    DELETE FROM tags WHERE id = test_tag_id;
    DELETE FROM journal_entries WHERE id = test_journal_id;
    DELETE FROM goals WHERE id = test_goal_id;
    DELETE FROM trading_insights WHERE id = test_insight_id;
    DELETE FROM reports WHERE id = test_report_id;
    DELETE FROM background_jobs WHERE id = test_job_id;
    DELETE FROM trades WHERE id = test_trade_id;
    DELETE FROM strategies WHERE id = test_strategy_id;
    DELETE FROM trading_accounts WHERE id = test_account_id;
    
    RAISE NOTICE '========================================';
    RAISE NOTICE 'ALL TESTS COMPLETED SUCCESSFULLY';
    RAISE NOTICE '========================================';
END $$;

-- =========================================================
-- VERIFY AUDIT LOGS
-- =========================================================

-- Count audit records by action and table
SELECT 
    action,
    entity_type,
    COUNT(*) as record_count
FROM audit_logs
WHERE created_at > NOW() - INTERVAL '10 minutes'
GROUP BY action, entity_type
ORDER BY entity_type, action;

-- View detailed audit log with changes
SELECT 
    created_at,
    action,
    entity_type,
    entity_id,
    user_id,
    CASE 
        WHEN changes IS NOT NULL THEN jsonb_pretty(changes)
        ELSE NULL
    END as changed_fields
FROM audit_logs
WHERE created_at > NOW() - INTERVAL '10 minutes'
ORDER BY created_at DESC
LIMIT 30;

-- Check specific table audits
SELECT 
    entity_type,
    action,
    COUNT(*) as changes,
    MIN(created_at) as first_change,
    MAX(created_at) as last_change
FROM audit_logs
WHERE created_at > NOW() - INTERVAL '10 minutes'
GROUP BY entity_type, action
ORDER BY entity_type, action;




