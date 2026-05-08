-- =========================================================
-- ENUM VALUE CLEANUP TO LOWERCASE
-- Run this on the existing database
-- =========================================================

-- platform_type
ALTER TYPE platform_type RENAME VALUE 'MT4' TO 'mt4';
ALTER TYPE platform_type RENAME VALUE 'MT5' TO 'mt5';
ALTER TYPE platform_type RENAME VALUE 'cTrader' TO 'ctrader';
ALTER TYPE platform_type RENAME VALUE 'TradingView' TO 'tradingview';
ALTER TYPE platform_type RENAME VALUE 'NinjaTrader' TO 'ninjatrader';
ALTER TYPE platform_type RENAME VALUE 'Thinkorswim' TO 'thinkorswim';
ALTER TYPE platform_type RENAME VALUE 'SaxoTraderGO' TO 'saxotradersgo';
ALTER TYPE platform_type RENAME VALUE 'MetaTraderWeb' TO 'metatraderweb';

-- instrument_type
ALTER TYPE instrument_type RENAME VALUE 'ETF' TO 'etf';
ALTER TYPE instrument_type RENAME VALUE 'CFD' TO 'cfd';

-- audit_action
ALTER TYPE audit_action RENAME VALUE 'CREATE' TO 'create';
ALTER TYPE audit_action RENAME VALUE 'UPDATE' TO 'update';
ALTER TYPE audit_action RENAME VALUE 'DELETE' TO 'delete';
ALTER TYPE audit_action RENAME VALUE 'EXPORT' TO 'export';
ALTER TYPE audit_action RENAME VALUE 'LOGIN' TO 'login';
ALTER TYPE audit_action RENAME VALUE 'LOGOUT' TO 'logout';
ALTER TYPE audit_action RENAME VALUE 'IMPORT' TO 'import';
ALTER TYPE audit_action RENAME VALUE 'VIEW' TO 'view';
ALTER TYPE audit_action RENAME VALUE 'DOWNLOAD' TO 'download';
ALTER TYPE audit_action RENAME VALUE 'ARCHIVE' TO 'archive';
ALTER TYPE audit_action RENAME VALUE 'RESTORE' TO 'restore';









DELETE FROM account_balance_history;
DELETE FROM account_daily_snapshots;
DELETE FROM trading_accounts;
DELETE FROM user_preferences;
DELETE FROM user_sessions;
DELETE FROM login_history;
DELETE FROM users;



DELETE FROM trading_accounts;
DELETE FROM account_balance_history;




DELETE FROM trading_accounts
WHERE user_id = '04b018b2-0fc0-48bd-82b9-32af603be3ae';




SELECT * FROM trading_accounts;
SELECT * FROM account_balance_history;


SELECT
    id,
    user_id,
    account_name,
    account_type,
    is_active,
    is_archived,
    deleted_at,
    created_at
FROM trading_accounts
WHERE user_id = '04b018b2-0fc0-48bd-82b9-32af603be3ae';