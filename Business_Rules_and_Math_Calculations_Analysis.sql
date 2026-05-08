-- Check if any snapshots exist
SELECT * FROM account_daily_snapshots 
WHERE account_id = 'c5857653-9a9b-48d8-86bc-fcc327f33063'::uuid
ORDER BY snapshot_date;

-- If no snapshots, let's create them manually via SQL (for testing)
INSERT INTO account_daily_snapshots (
    id, user_id, account_id, snapshot_date,
    starting_balance, ending_balance, trades_count,
    winning_trades, losing_trades, total_profit, total_loss,
    total_pips, peak_balance, trough_balance, created_at
)
SELECT 
    gen_random_uuid(),
    '14261423-180e-4f43-82bb-f187ad438ead'::uuid,
    'c5857653-9a9b-48d8-86bc-fcc327f33063'::uuid,
    DATE(t.entry_date),
    COALESCE(MIN(balance), 10000) as starting_balance,
    COALESCE(MAX(balance), 10000) as ending_balance,
    COUNT(*) as trades_count,
    COUNT(*) FILTER (WHERE is_winning) as winning_trades,
    COUNT(*) FILTER (WHERE is_losing) as losing_trades,
    COALESCE(SUM(net_profit) FILTER (WHERE is_winning), 0) as total_profit,
    COALESCE(SUM(ABS(net_profit)) FILTER (WHERE is_losing), 0) as total_loss,
    COALESCE(SUM(pips_moved), 0) as total_pips,
    MAX(balance) as peak_balance,
    MIN(balance) as trough_balance,
    NOW()
FROM (
    SELECT 
        t.*,
        10000 + SUM(t.net_profit) OVER (ORDER BY t.entry_date) as balance
    FROM trades t
    WHERE t.account_id = 'c5857653-9a9b-48d8-86bc-fcc327f33063'::uuid
        AND t.deleted_at IS NULL
) t
GROUP BY DATE(t.entry_date);






































WITH daily_trades AS (
    SELECT 
        DATE(entry_date) as trade_date,
        COUNT(*) as trade_count,
        SUM(CASE WHEN is_winning THEN 1 ELSE 0 END) as wins,
        SUM(CASE WHEN is_losing THEN 1 ELSE 0 END) as losses,
        SUM(net_profit) as total_pnl
    FROM trades
    WHERE account_id = 'c5857653-9a9b-48d8-86bc-fcc327f33063'::uuid
        AND deleted_at IS NULL
    GROUP BY DATE(entry_date)
)
SELECT 
    ds.snapshot_date,
    ds.trades_count as snapshot_trades,
    dt.trade_count as actual_trades,
    ds.winning_trades as snapshot_wins,
    dt.wins as actual_wins,
    ds.losing_trades as snapshot_losses,
    dt.losses as actual_losses,
    ds.net_profit as snapshot_pnl,
    dt.total_pnl as actual_pnl,
    ds.daily_pnl,
    ds.max_drawdown,
    -- Verify calculations
    CASE 
        WHEN ds.net_profit = dt.total_pnl THEN '✅ P&L MATCH'
        ELSE '❌ P&L MISMATCH'
    END as pnl_verification,
    CASE 
        WHEN ds.daily_pnl = (ds.ending_balance - ds.starting_balance) 
        THEN '✅ DAILY P&L CORRECT'
        ELSE '❌ DAILY P&L INCORRECT'
    END as daily_pnl_verification
FROM account_daily_snapshots ds
LEFT JOIN daily_trades dt ON ds.snapshot_date = dt.trade_date
WHERE ds.account_id = 'c5857653-9a9b-48d8-86bc-fcc327f33063'::uuid
ORDER BY ds.snapshot_date;






















































WITH balance_flow AS (
    SELECT 
        snapshot_date,
        starting_balance,
        ending_balance,
        LAG(ending_balance) OVER (ORDER BY snapshot_date) as prev_ending
    FROM account_daily_snapshots
    WHERE account_id = 'c5857653-9a9b-48d8-86bc-fcc327f33063'::uuid
)
SELECT 
    snapshot_date,
    starting_balance,
    prev_ending,
    CASE 
        WHEN snapshot_date = (SELECT MIN(snapshot_date) FROM account_daily_snapshots) 
             AND starting_balance = 10000 THEN '✅ INITIAL CORRECT'
        WHEN starting_balance = prev_ending THEN '✅ CONTINUITY CORRECT'
        ELSE '❌ BALANCE GAP DETECTED'
    END as balance_verification
FROM balance_flow
ORDER BY snapshot_date;

















WITH balance_flow AS (
    SELECT 
        ds.snapshot_date,
        ds.starting_balance,
        ds.ending_balance,
        LAG(ds.ending_balance) OVER (ORDER BY ds.snapshot_date) as prev_ending
    FROM account_daily_snapshots ds
    WHERE ds.account_id = 'c5857653-9a9b-48d8-86bc-fcc327f33063'::uuid
)
SELECT 
    snapshot_date,
    starting_balance,
    prev_ending,
    (starting_balance - prev_ending) as balance_gap,
    CASE 
        WHEN snapshot_date = (SELECT MIN(snapshot_date) FROM account_daily_snapshots 
                              WHERE account_id = 'c5857653-9a9b-48d8-86bc-fcc327f33063'::uuid) 
             AND starting_balance = 10000 THEN '✅ FIRST DAY OK'
        WHEN starting_balance = prev_ending THEN '✅ CONTINUITY OK'
        ELSE '❌ BALANCE GAP: ' || (starting_balance - prev_ending)::text
    END as balance_verification
FROM balance_flow
ORDER BY snapshot_date;