

-- =========================================================
-- CLEAN DROP FIRST
-- =========================================================

DROP FUNCTION IF EXISTS refresh_trading_views();

DROP MATERIALIZED VIEW IF EXISTS trade_statistics_mv CASCADE;
DROP MATERIALIZED VIEW IF EXISTS symbol_performance CASCADE;
DROP MATERIALIZED VIEW IF EXISTS monthly_performance CASCADE;

DROP VIEW IF EXISTS equity_curve_v CASCADE;
DROP VIEW IF EXISTS goal_progress_v CASCADE;
DROP VIEW IF EXISTS v_trader_dashboard CASCADE;
DROP VIEW IF EXISTS v_performance_attribution CASCADE;
DROP VIEW IF EXISTS v_strategy_performance_matrix CASCADE;
DROP VIEW IF EXISTS v_learning_curve CASCADE;
DROP VIEW IF EXISTS v_strategy_live_stats CASCADE;


-- =========================================================
-- MATERIALIZED VIEW: trade_statistics_mv
-- Replacement for deleted trade_statistics table
-- =========================================================

CREATE MATERIALIZED VIEW trade_statistics_mv AS
WITH closed_base AS (
    SELECT
        t.user_id,
        t.account_id,
        t.id,
        t.symbol,
        t.session,
        t.day_of_week,
        t.quantity,
        t.gross_profit,
        t.net_profit,
        t.pips_moved,
        t.duration_minutes,
        t.duration_hours,
        t.is_winning,
        t.is_losing,
        t.is_breakeven,
        t.exit_date::date AS exit_day
    FROM trades t
    WHERE t.deleted_at IS NULL
      AND t.status = 'closed'
      AND t.exit_date IS NOT NULL
),
closed_trades AS (
    SELECT
        cb.user_id,
        cb.account_id,
        'lifetime'::goal_type AS period_type,
        MIN(cb.exit_day) AS period_start,
        MAX(cb.exit_day) AS period_end,
        COUNT(*)::integer AS total_trades,
        COUNT(*) FILTER (WHERE cb.is_winning = true)::integer AS winning_trades,
        COUNT(*) FILTER (WHERE cb.is_losing = true)::integer AS losing_trades,
        COUNT(*) FILTER (WHERE cb.is_breakeven = true)::integer AS breakeven_trades,
        COALESCE(SUM(cb.quantity), 0)::numeric(20,4) AS total_volume,
        COALESCE(SUM(cb.gross_profit) FILTER (WHERE cb.is_winning = true), 0)::numeric(20,2) AS gross_profit,
        COALESCE(SUM(ABS(cb.gross_profit)) FILTER (WHERE cb.is_losing = true), 0)::numeric(20,2) AS gross_loss,
        COALESCE(SUM(cb.net_profit), 0)::numeric(20,2) AS net_profit,
        COALESCE(SUM(cb.pips_moved) FILTER (WHERE cb.pips_moved IS NOT NULL), 0)::numeric(20,2) AS total_pips,
        AVG(cb.duration_minutes)::integer AS avg_duration_minutes,
        ROUND(COALESCE(SUM(cb.duration_hours), 0), 2)::numeric(12,2) AS total_duration_hours
    FROM closed_base cb
    GROUP BY cb.user_id, cb.account_id
),
open_trades AS (
    SELECT
        t.user_id,
        t.account_id,
        COUNT(*)::integer AS open_trades
    FROM trades t
    WHERE t.deleted_at IS NULL
      AND t.status = 'open'
    GROUP BY t.user_id, t.account_id
),
session_stats AS (
    SELECT
        cb.user_id,
        cb.account_id,
        cb.session::text AS session_name,
        jsonb_build_object(
            'trades', COUNT(*),
            'wins', COUNT(*) FILTER (WHERE cb.is_winning = true),
            'losses', COUNT(*) FILTER (WHERE cb.is_losing = true),
            'breakeven', COUNT(*) FILTER (WHERE cb.is_breakeven = true),
            'net_profit', COALESCE(SUM(cb.net_profit), 0),
            'win_rate',
                CASE
                    WHEN COUNT(*) > 0 THEN ROUND((COUNT(*) FILTER (WHERE cb.is_winning = true)::numeric / COUNT(*)) * 100, 2)
                    ELSE 0
                END
        ) AS payload
    FROM closed_base cb
    WHERE cb.session IS NOT NULL
    GROUP BY cb.user_id, cb.account_id, cb.session
),
session_json AS (
    SELECT
        ss.user_id,
        ss.account_id,
        jsonb_object_agg(ss.session_name, ss.payload) AS session_performance
    FROM session_stats ss
    GROUP BY ss.user_id, ss.account_id
),
day_stats AS (
    SELECT
        cb.user_id,
        cb.account_id,
        CASE cb.day_of_week
            WHEN 0 THEN 'sunday'
            WHEN 1 THEN 'monday'
            WHEN 2 THEN 'tuesday'
            WHEN 3 THEN 'wednesday'
            WHEN 4 THEN 'thursday'
            WHEN 5 THEN 'friday'
            WHEN 6 THEN 'saturday'
        END AS day_name,
        jsonb_build_object(
            'trades', COUNT(*),
            'wins', COUNT(*) FILTER (WHERE cb.is_winning = true),
            'losses', COUNT(*) FILTER (WHERE cb.is_losing = true),
            'breakeven', COUNT(*) FILTER (WHERE cb.is_breakeven = true),
            'net_profit', COALESCE(SUM(cb.net_profit), 0),
            'win_rate',
                CASE
                    WHEN COUNT(*) > 0 THEN ROUND((COUNT(*) FILTER (WHERE cb.is_winning = true)::numeric / COUNT(*)) * 100, 2)
                    ELSE 0
                END
        ) AS payload
    FROM closed_base cb
    GROUP BY cb.user_id, cb.account_id, cb.day_of_week
),
day_json AS (
    SELECT
        ds.user_id,
        ds.account_id,
        jsonb_object_agg(ds.day_name, ds.payload) AS day_performance
    FROM day_stats ds
    GROUP BY ds.user_id, ds.account_id
),
top_symbol_rows AS (
    SELECT
        cb.user_id,
        cb.account_id,
        cb.symbol,
        COUNT(*)::integer AS trade_count,
        COALESCE(SUM(cb.net_profit), 0)::numeric(20,2) AS net_profit_sum,
        ROW_NUMBER() OVER (
            PARTITION BY cb.user_id, cb.account_id
            ORDER BY COALESCE(SUM(cb.net_profit), 0) DESC, cb.symbol
        ) AS rn
    FROM closed_base cb
    GROUP BY cb.user_id, cb.account_id, cb.symbol
),
top_symbols AS (
    SELECT
        tsr.user_id,
        tsr.account_id,
        jsonb_agg(
            jsonb_build_object(
                'symbol', tsr.symbol,
                'trades', tsr.trade_count,
                'net_profit', tsr.net_profit_sum
            )
            ORDER BY tsr.net_profit_sum DESC, tsr.symbol
        ) AS top_symbols
    FROM top_symbol_rows tsr
    WHERE tsr.rn <= 10
    GROUP BY tsr.user_id, tsr.account_id
)
SELECT
    ct.user_id,
    ct.account_id,
    ct.period_type,
    ct.period_start,
    ct.period_end,
    ct.total_trades,
    ct.winning_trades,
    ct.losing_trades,
    ct.breakeven_trades,
    COALESCE(ot.open_trades, 0) AS open_trades,
    ct.total_volume,
    CASE
        WHEN ct.total_trades > 0 THEN (ct.total_volume / ct.total_trades)::numeric(20,4)
        ELSE 0::numeric(20,4)
    END AS avg_volume_per_trade,
    ct.gross_profit,
    ct.gross_loss,
    ct.net_profit,
    ct.total_pips,
    CASE
        WHEN ct.total_trades > 0 THEN (ct.total_pips / ct.total_trades)::numeric(20,2)
        ELSE 0::numeric(20,2)
    END AS avg_pips_per_trade,
    CASE
        WHEN ct.winning_trades > 0 THEN (ct.gross_profit / ct.winning_trades)::numeric(20,2)
        ELSE 0::numeric(20,2)
    END AS avg_win,
    CASE
        WHEN ct.losing_trades > 0 THEN (ct.gross_loss / ct.losing_trades)::numeric(20,2)
        ELSE 0::numeric(20,2)
    END AS avg_loss,
    CASE
        WHEN ct.total_trades > 0 THEN ((ct.winning_trades::numeric / ct.total_trades) * 100)::numeric(5,2)
        ELSE 0::numeric(5,2)
    END AS win_rate,
    CASE
        WHEN ct.gross_loss > 0 THEN (ct.gross_profit / ct.gross_loss)::numeric(12,4)
        WHEN ct.gross_profit > 0 THEN 999999::numeric(12,4)
        ELSE 0::numeric(12,4)
    END AS profit_factor,
    CASE
        WHEN ct.winning_trades > 0 AND ct.losing_trades > 0 AND ct.gross_loss > 0
            THEN ((ct.gross_profit / ct.winning_trades) / (ct.gross_loss / ct.losing_trades))::numeric(12,4)
        ELSE 0::numeric(12,4)
    END AS payoff_ratio,
    CASE
        WHEN ct.total_trades > 0 THEN (ct.net_profit / ct.total_trades)::numeric(20,4)
        ELSE 0::numeric(20,4)
    END AS expectancy,
    ct.avg_duration_minutes,
    ct.total_duration_hours,
    COALESCE(sj.session_performance, '{}'::jsonb) AS session_performance,
    COALESCE(dj.day_performance, '{}'::jsonb) AS day_performance,
    COALESCE(ts.top_symbols, '[]'::jsonb) AS top_symbols,
    NOW() AS calculated_at
FROM closed_trades ct
LEFT JOIN open_trades ot
    ON ot.user_id = ct.user_id
   AND ot.account_id IS NOT DISTINCT FROM ct.account_id
LEFT JOIN session_json sj
    ON sj.user_id = ct.user_id
   AND sj.account_id IS NOT DISTINCT FROM ct.account_id
LEFT JOIN day_json dj
    ON dj.user_id = ct.user_id
   AND dj.account_id IS NOT DISTINCT FROM ct.account_id
LEFT JOIN top_symbols ts
    ON ts.user_id = ct.user_id
   AND ts.account_id IS NOT DISTINCT FROM ct.account_id;

CREATE UNIQUE INDEX uq_trade_statistics_mv
ON trade_statistics_mv (
    user_id,
    COALESCE(account_id, '00000000-0000-0000-0000-000000000000'::uuid),
    period_type
);

CREATE INDEX idx_trade_statistics_mv_user
ON trade_statistics_mv (user_id);

CREATE INDEX idx_trade_statistics_mv_account
ON trade_statistics_mv (account_id);

COMMENT ON MATERIALIZED VIEW trade_statistics_mv IS 'Replacement for deleted trade_statistics table';


-- =========================================================
-- VIEW: equity_curve_v
-- Replacement for deleted equity_curve table
-- =========================================================

CREATE VIEW equity_curve_v AS
WITH closed_trade_points AS (
    SELECT
        t.user_id,
        t.account_id,
        t.exit_date AS point_date,
        'trade_close'::varchar(20) AS point_type,
        t.id AS trade_id,
        t.entry_date AS trade_entry_date,
        t.net_profit AS pnl_change,
        t.notes
    FROM trades t
    WHERE t.deleted_at IS NULL
      AND t.status = 'closed'
      AND t.exit_date IS NOT NULL
),
ordered_points AS (
    SELECT
        ctp.*,
        SUM(ctp.pnl_change) OVER (
            PARTITION BY ctp.user_id, ctp.account_id
            ORDER BY ctp.point_date, ctp.trade_id
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS cumulative_pnl
    FROM closed_trade_points ctp
),
running_peaks AS (
    SELECT
        op.*,
        MAX(op.cumulative_pnl) OVER (
            PARTITION BY op.user_id, op.account_id
            ORDER BY op.point_date, op.trade_id
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS running_peak_pnl
    FROM ordered_points op
)
SELECT
    gen_random_uuid() AS id,
    rp.user_id,
    rp.account_id,
    rp.point_date,
    NULL::numeric(20,2) AS balance,
    NULL::numeric(20,2) AS equity,
    rp.cumulative_pnl::numeric(20,2) AS cumulative_pnl,
    CASE
        WHEN rp.running_peak_pnl > 0
            THEN (((rp.running_peak_pnl - rp.cumulative_pnl) / rp.running_peak_pnl) * 100)::numeric(10,4)
        ELSE 0::numeric(10,4)
    END AS drawdown,
    (rp.running_peak_pnl - rp.cumulative_pnl)::numeric(20,2) AS drawdown_amount,
    rp.point_type,
    rp.trade_id,
    rp.trade_entry_date,
    rp.notes,
    NOW()::timestamptz AS created_at
FROM running_peaks rp;

COMMENT ON VIEW equity_curve_v IS 'Derived equity curve from closed trades';


-- =========================================================
-- VIEW: goal_progress_v
-- Replacement for deleted goal_progress table
-- =========================================================

CREATE VIEW goal_progress_v AS
SELECT
    g.id AS goal_id,
    g.user_id,
    g.account_id,
    g.goal_type,
    g.goal_category,
    g.name,
    g.start_date AS tracked_date,
    g.starting_value,
    g.current_value AS cumulative_value,
    (g.current_value - g.starting_value)::numeric(20,4) AS tracked_value,
    g.progress_percentage,
    g.is_achieved,
    g.achieved_date,
    g.status,
    g.unit,
    g.created_at,
    g.updated_at
FROM goals g
WHERE g.deleted_at IS NULL;

COMMENT ON VIEW goal_progress_v IS 'Live derived goal progress from goals table';


-- =========================================================
-- VIEW: v_trader_dashboard
-- =========================================================
CREATE VIEW v_trader_dashboard AS
WITH open_positions AS (
    SELECT
        t.user_id,
        t.account_id,
        COUNT(*)::int AS open_positions,
        COALESCE(SUM(t.position_value), 0)::numeric(20,2) AS total_exposure
    FROM trades t
    WHERE t.deleted_at IS NULL
      AND t.status = 'open'
    GROUP BY t.user_id, t.account_id
),
closed_stats AS (
    SELECT
        t.user_id,
        t.account_id,
        COUNT(*)::int AS total_lifetime_trades,
        COALESCE(SUM(t.net_profit), 0)::numeric(20,2) AS lifetime_pnl,
        COALESCE(AVG(t.net_profit), 0)::numeric(20,2) AS avg_return_per_trade,
        CASE
            WHEN COUNT(*) > 0
                THEN ROUND((COUNT(*) FILTER (WHERE t.is_winning)::numeric / COUNT(*)::numeric) * 100, 2)
            ELSE 0
        END::numeric(10,2) AS win_rate
    FROM trades t
    WHERE t.deleted_at IS NULL
      AND t.status = 'closed'
      AND t.exit_date IS NOT NULL
    GROUP BY t.user_id, t.account_id
),
today_stats AS (
    SELECT
        t.user_id,
        t.account_id,
        COALESCE(SUM(t.net_profit), 0)::numeric(20,2) AS today_pnl,
        COUNT(*)::int AS today_trades
    FROM trades t
    WHERE t.deleted_at IS NULL
      AND t.status = 'closed'
      AND t.exit_date IS NOT NULL
      AND (t.exit_date AT TIME ZONE 'UTC')::date = (NOW() AT TIME ZONE 'UTC')::date
    GROUP BY t.user_id, t.account_id
)
SELECT
    u.id AS user_id,
    u.username,
    ta.id AS account_id,
    ta.account_name,
    ta.current_balance,
    COALESCE(op.open_positions, 0) AS open_positions,
    COALESCE(op.total_exposure, 0)::numeric(20,2) AS total_exposure,
    COALESCE(cs.total_lifetime_trades, 0) AS total_lifetime_trades,
    COALESCE(cs.lifetime_pnl, 0)::numeric(20,2) AS lifetime_pnl,
    COALESCE(cs.avg_return_per_trade, 0)::numeric(20,2) AS avg_return_per_trade,
    COALESCE(ts.today_pnl, 0)::numeric(20,2) AS today_pnl,
    COALESCE(ts.today_trades, 0) AS today_trades,
    COALESCE(cs.win_rate, 0)::numeric(10,2) AS win_rate,
    ROW_NUMBER() OVER (
        PARTITION BY u.id
        ORDER BY ta.current_balance DESC NULLS LAST, ta.account_name
    ) AS account_rank
FROM users u
JOIN trading_accounts ta
    ON u.id = ta.user_id
   AND ta.deleted_at IS NULL
LEFT JOIN open_positions op
    ON op.user_id = u.id
   AND op.account_id = ta.id
LEFT JOIN closed_stats cs
    ON cs.user_id = u.id
   AND cs.account_id = ta.id
LEFT JOIN today_stats ts
    ON ts.user_id = u.id
   AND ts.account_id = ta.id
WHERE u.deleted_at IS NULL;



COMMENT ON VIEW v_trader_dashboard IS 'Dashboard summary per user and account using live trade/account data';


-- =========================================================
-- VIEW: v_performance_attribution
-- =========================================================

CREATE VIEW v_performance_attribution AS
WITH account_scope AS (
    SELECT DISTINCT
        t.user_id,
        t.account_id
    FROM trades t
    WHERE t.deleted_at IS NULL
      AND t.status = 'closed'
),
symbol_contribution AS (
    SELECT
        t.user_id,
        t.account_id,
        t.symbol,
        COUNT(*)::integer AS symbol_trades,
        COALESCE(SUM(t.net_profit), 0)::numeric(20,2) AS symbol_pnl,
        CASE
            WHEN COALESCE(SUM(SUM(t.net_profit)) OVER (PARTITION BY t.user_id, t.account_id), 0) <> 0 THEN
                ROUND(
                    (
                        SUM(t.net_profit)::numeric
                        / NULLIF(SUM(SUM(t.net_profit)) OVER (PARTITION BY t.user_id, t.account_id), 0)
                    ) * 100,
                    2
                )
            ELSE 0
        END::numeric(10,2) AS pnl_contribution_pct
    FROM trades t
    WHERE t.deleted_at IS NULL
      AND t.status = 'closed'
    GROUP BY t.user_id, t.account_id, t.symbol
),
session_contribution AS (
    SELECT
        t.user_id,
        t.account_id,
        t.session,
        COUNT(*)::integer AS session_trades,
        COALESCE(SUM(t.net_profit), 0)::numeric(20,2) AS session_pnl,
        CASE
            WHEN COALESCE(SUM(SUM(t.net_profit)) OVER (PARTITION BY t.user_id, t.account_id), 0) <> 0 THEN
                ROUND(
                    (
                        SUM(t.net_profit)::numeric
                        / NULLIF(SUM(SUM(t.net_profit)) OVER (PARTITION BY t.user_id, t.account_id), 0)
                    ) * 100,
                    2
                )
            ELSE 0
        END::numeric(10,2) AS session_contribution_pct
    FROM trades t
    WHERE t.deleted_at IS NULL
      AND t.status = 'closed'
      AND t.session IS NOT NULL
    GROUP BY t.user_id, t.account_id, t.session
),
direction_contribution AS (
    SELECT
        t.user_id,
        t.account_id,
        t.trade_type,
        COUNT(*)::integer AS direction_trades,
        COALESCE(SUM(t.net_profit), 0)::numeric(20,2) AS direction_pnl,
        CASE
            WHEN COALESCE(SUM(SUM(t.net_profit)) OVER (PARTITION BY t.user_id, t.account_id), 0) <> 0 THEN
                ROUND(
                    (
                        SUM(t.net_profit)::numeric
                        / NULLIF(SUM(SUM(t.net_profit)) OVER (PARTITION BY t.user_id, t.account_id), 0)
                    ) * 100,
                    2
                )
            ELSE 0
        END::numeric(10,2) AS direction_contribution_pct
    FROM trades t
    WHERE t.deleted_at IS NULL
      AND t.status = 'closed'
    GROUP BY t.user_id, t.account_id, t.trade_type
)
SELECT
    a.user_id,
    a.account_id,
    jsonb_build_object(
        'symbols',
        COALESCE(
            (
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'symbol', sc.symbol,
                        'pnl', sc.symbol_pnl,
                        'trades', sc.symbol_trades,
                        'contribution_pct', sc.pnl_contribution_pct
                    )
                    ORDER BY sc.symbol_pnl DESC, sc.symbol
                )
                FROM symbol_contribution sc
                WHERE sc.user_id = a.user_id
                  AND sc.account_id = a.account_id
            ),
            '[]'::jsonb
        ),
        'sessions',
        COALESCE(
            (
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'session', ssc.session,
                        'pnl', ssc.session_pnl,
                        'trades', ssc.session_trades,
                        'contribution_pct', ssc.session_contribution_pct
                    )
                    ORDER BY ssc.session_pnl DESC, ssc.session::text
                )
                FROM session_contribution ssc
                WHERE ssc.user_id = a.user_id
                  AND ssc.account_id = a.account_id
            ),
            '[]'::jsonb
        ),
        'direction',
        COALESCE(
            (
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'direction', dc.trade_type,
                        'pnl', dc.direction_pnl,
                        'trades', dc.direction_trades,
                        'contribution_pct', dc.direction_contribution_pct
                    )
                    ORDER BY dc.direction_pnl DESC, dc.trade_type::text
                )
                FROM direction_contribution dc
                WHERE dc.user_id = a.user_id
                  AND dc.account_id = a.account_id
            ),
            '[]'::jsonb
        )
    ) AS attribution_data
FROM account_scope a;

COMMENT ON VIEW v_performance_attribution IS 'Attribution breakdown of closed-trade performance by symbol, session, and direction';


-- =========================================================
-- VIEW: v_strategy_performance_matrix
-- =========================================================

CREATE VIEW v_strategy_performance_matrix AS
WITH strategy_base AS (
    SELECT
        s.id AS strategy_id,
        s.user_id,
        s.strategy_name,
        s.strategy_type,
        t.id AS trade_id,
        t.net_profit,
        t.is_winning,
        t.instrument_type,
        t.session,
        t.day_of_week,
        t.risk_reward_ratio,
        t.duration_minutes,
        (t.entry_date AT TIME ZONE 'UTC')::date AS trade_date
    FROM strategies s
    JOIN trades t
        ON t.strategy_id = s.id
       AND t.status = 'closed'
       AND t.deleted_at IS NULL
),
strategy_metrics AS (
    SELECT
        sb.strategy_id,
        sb.user_id,
        sb.strategy_name,
        sb.strategy_type,
        COUNT(*)::integer AS total_trades,
        COALESCE(SUM(sb.net_profit), 0)::numeric(20,2) AS total_pnl,
        COALESCE(AVG(sb.net_profit), 0)::numeric(20,2) AS avg_trade,
        COALESCE(STDDEV(sb.net_profit), 0)::numeric(20,4) AS volatility,
        CASE
            WHEN COUNT(*) > 0 THEN
                ROUND(
                    (
                        COUNT(*) FILTER (WHERE sb.is_winning)::numeric
                        / NULLIF(COUNT(*), 0)
                    ) * 100,
                    2
                )
            ELSE 0
        END::numeric(5,2) AS win_rate,
        COALESCE(AVG(sb.risk_reward_ratio) FILTER (WHERE sb.is_winning), 0)::numeric(12,4) AS avg_win_rr,
        COALESCE(AVG(sb.duration_minutes), 0)::numeric(12,2) AS avg_duration,
        COALESCE(SUM(CASE WHEN EXTRACT(DOW FROM sb.trade_date) IN (0, 6) THEN sb.net_profit ELSE 0 END), 0)::numeric(20,2) AS weekend_pnl,
        COALESCE(SUM(CASE WHEN EXTRACT(DOW FROM sb.trade_date) BETWEEN 1 AND 5 THEN sb.net_profit ELSE 0 END), 0)::numeric(20,2) AS weekday_pnl
    FROM strategy_base sb
    GROUP BY sb.strategy_id, sb.user_id, sb.strategy_name, sb.strategy_type
),
instrument_breakdown AS (
    SELECT
        sb.strategy_id,
        sb.instrument_type,
        COUNT(*)::integer AS trades,
        COALESCE(SUM(sb.net_profit), 0)::numeric(20,2) AS pnl,
        CASE
            WHEN COUNT(*) > 0 THEN
                ROUND(
                    (
                        COUNT(*) FILTER (WHERE sb.is_winning)::numeric
                        / NULLIF(COUNT(*), 0)
                    ) * 100,
                    2
                )
            ELSE 0
        END::numeric(5,2) AS win_rate
    FROM strategy_base sb
    GROUP BY sb.strategy_id, sb.instrument_type
),
session_breakdown AS (
    SELECT
        sb.strategy_id,
        sb.session,
        COUNT(*)::integer AS trades,
        COALESCE(SUM(sb.net_profit), 0)::numeric(20,2) AS pnl
    FROM strategy_base sb
    WHERE sb.session IS NOT NULL
    GROUP BY sb.strategy_id, sb.session
)
SELECT
    sm.strategy_id,
    sm.user_id,
    sm.strategy_name,
    sm.strategy_type,
    sm.total_trades,
    sm.total_pnl,
    sm.avg_trade,
    sm.volatility,
    sm.win_rate,
    sm.avg_win_rr,
    sm.avg_duration,
    sm.weekend_pnl,
    sm.weekday_pnl,
    CASE
        WHEN sm.volatility <> 0 THEN (sm.total_pnl / sm.volatility)::numeric(20,4)
        ELSE 0
    END AS risk_adjusted_return,
    CASE
        WHEN sm.weekday_pnl <> 0
            THEN ((sm.weekend_pnl / ABS(sm.weekday_pnl)) * 100)::numeric(12,4)
        ELSE 0
    END AS weekend_performance_pct,
    COALESCE(
        (
            SELECT jsonb_agg(
                jsonb_build_object(
                    'instrument', ib.instrument_type,
                    'trades', ib.trades,
                    'pnl', ib.pnl,
                    'win_rate', ib.win_rate
                )
                ORDER BY ib.pnl DESC, ib.instrument_type::text
            )
            FROM instrument_breakdown ib
            WHERE ib.strategy_id = sm.strategy_id
        ),
        '[]'::jsonb
    ) AS instrument_performance,
    COALESCE(
        (
            SELECT jsonb_agg(
                jsonb_build_object(
                    'session', sb.session,
                    'trades', sb.trades,
                    'pnl', sb.pnl
                )
                ORDER BY sb.pnl DESC, sb.session::text
            )
            FROM session_breakdown sb
            WHERE sb.strategy_id = sm.strategy_id
        ),
        '[]'::jsonb
    ) AS session_performance,
    RANK() OVER (
        PARTITION BY sm.user_id
        ORDER BY sm.total_pnl DESC, sm.strategy_id
    ) AS rank_by_pnl,
    RANK() OVER (
        PARTITION BY sm.user_id
        ORDER BY sm.win_rate DESC, sm.strategy_id
    ) AS rank_by_win_rate
FROM strategy_metrics sm;

COMMENT ON VIEW v_strategy_performance_matrix IS 'Strategy-level performance matrix with instrument and session breakdowns';


-- =========================================================
-- VIEW: v_learning_curve
-- =========================================================

CREATE VIEW v_learning_curve AS
WITH trade_buckets AS (
    SELECT
        t.user_id,
        t.account_id,
        NTILE(10) OVER (
            PARTITION BY t.user_id, t.account_id
            ORDER BY t.exit_date, t.id
        ) AS experience_decile,
        t.net_profit,
        t.is_winning,
        t.risk_reward_ratio,
        t.duration_minutes,
        t.exit_date
    FROM trades t
    WHERE t.status = 'closed'
      AND t.deleted_at IS NULL
      AND t.exit_date IS NOT NULL
),
decile_metrics AS (
    SELECT
        tb.user_id,
        tb.account_id,
        tb.experience_decile,
        COUNT(*)::integer AS trades_in_decile,
        COALESCE(AVG(tb.net_profit), 0)::numeric(20,2) AS avg_pnl,
        COALESCE(SUM(tb.net_profit), 0)::numeric(20,2) AS total_pnl,
        CASE
            WHEN COUNT(*) > 0 THEN
                ROUND(
                    (
                        COUNT(*) FILTER (WHERE tb.is_winning)::numeric
                        / NULLIF(COUNT(*), 0)
                    ) * 100,
                    2
                )
            ELSE 0
        END::numeric(5,2) AS win_rate,
        COALESCE(AVG(tb.risk_reward_ratio), 0)::numeric(12,4) AS avg_rr,
        COALESCE(AVG(tb.duration_minutes), 0)::numeric(12,2) AS avg_duration,
        MIN(tb.exit_date) AS decile_start,
        MAX(tb.exit_date) AS decile_end
    FROM trade_buckets tb
    GROUP BY tb.user_id, tb.account_id, tb.experience_decile
),
improvement_metrics AS (
    SELECT
        dm.*,
        LAG(dm.avg_pnl) OVER (
            PARTITION BY dm.user_id, dm.account_id
            ORDER BY dm.experience_decile
        ) AS prev_avg_pnl,
        LAG(dm.win_rate) OVER (
            PARTITION BY dm.user_id, dm.account_id
            ORDER BY dm.experience_decile
        ) AS prev_win_rate,
        LAG(dm.avg_rr) OVER (
            PARTITION BY dm.user_id, dm.account_id
            ORDER BY dm.experience_decile
        ) AS prev_avg_rr,
        AVG(dm.avg_pnl) OVER (
            PARTITION BY dm.user_id, dm.account_id
            ORDER BY dm.experience_decile
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        )::numeric(20,2) AS moving_avg_pnl_3
    FROM decile_metrics dm
)
SELECT
    im.user_id,
    im.account_id,
    im.experience_decile,
    im.trades_in_decile,
    im.avg_pnl,
    im.total_pnl,
    im.win_rate,
    im.avg_rr,
    im.avg_duration,
    im.decile_start,
    im.decile_end,
    im.prev_avg_pnl,
    im.prev_win_rate,
    im.prev_avg_rr,
    im.moving_avg_pnl_3,
    CASE
        WHEN im.prev_avg_pnl IS NOT NULL AND ABS(im.prev_avg_pnl) > 0
            THEN (((im.avg_pnl - im.prev_avg_pnl) / ABS(im.prev_avg_pnl)) * 100)::numeric(12,4)
        ELSE 0
    END AS pnl_improvement_pct,
    CASE
        WHEN im.prev_win_rate IS NOT NULL
            THEN (im.win_rate - im.prev_win_rate)::numeric(12,4)
        ELSE 0
    END AS win_rate_improvement,
    CASE
        WHEN im.experience_decile = 10 THEN 'master'
        WHEN im.experience_decile >= 7 THEN 'advanced'
        WHEN im.experience_decile >= 4 THEN 'intermediate'
        ELSE 'beginner'
    END AS skill_level,
    RANK() OVER (
        PARTITION BY im.user_id, im.account_id
        ORDER BY im.moving_avg_pnl_3 DESC, im.experience_decile DESC
    ) AS current_form_rank
FROM improvement_metrics im;

COMMENT ON VIEW v_learning_curve IS 'Learning progression and improvement by trade-experience decile';


-- =========================================================
-- MATERIALIZED VIEW: symbol_performance
-- =========================================================








-- Create symbol_performance if missing
CREATE MATERIALIZED VIEW symbol_performance AS
WITH closed_trades AS (
    SELECT
        t.user_id,
        t.account_id,
        t.symbol,
        date_trunc('month', t.exit_date)::date AS month,
        t.net_profit,
        t.pips_moved
    FROM trades t
    WHERE t.deleted_at IS NULL
      AND t.status = 'closed'
      AND t.exit_date IS NOT NULL
)
SELECT
    ct.user_id,
    ct.account_id,
    ct.symbol,
    ct.month,
    COUNT(*)::int AS trades_count,
    COUNT(*) FILTER (WHERE ct.net_profit > 0)::int AS winning_trades,
    COUNT(*) FILTER (WHERE ct.net_profit < 0)::int AS losing_trades,
    COUNT(*) FILTER (WHERE ct.net_profit = 0)::int AS breakeven_trades,
    COALESCE(SUM(ct.net_profit), 0)::numeric(20,2) AS net_profit,
    COALESCE(SUM(ct.pips_moved), 0)::numeric(20,2) AS total_pips,
    COALESCE(AVG(ct.net_profit), 0)::numeric(20,2) AS avg_profit_per_trade,
    COALESCE(AVG(ct.pips_moved), 0)::numeric(20,2) AS avg_pips_per_trade,
    COALESCE(AVG(ct.net_profit) FILTER (WHERE ct.net_profit > 0), 0)::numeric(20,2) AS avg_win,
    COALESCE(AVG(ABS(ct.net_profit)) FILTER (WHERE ct.net_profit < 0), 0)::numeric(20,2) AS avg_loss,
    COALESCE(MAX(ct.net_profit), 0)::numeric(20,2) AS best_trade,
    COALESCE(MIN(ct.net_profit), 0)::numeric(20,2) AS worst_trade,
    CASE
        WHEN COUNT(*) > 0
            THEN ROUND((COUNT(*) FILTER (WHERE ct.net_profit > 0)::numeric / COUNT(*)::numeric) * 100, 2)
        ELSE 0
    END::numeric(10,2) AS win_rate,
    RANK() OVER (
        PARTITION BY ct.user_id, ct.account_id, ct.month
        ORDER BY COALESCE(SUM(ct.net_profit), 0) DESC, ct.symbol
    ) AS rank_by_profit
FROM closed_trades ct
GROUP BY ct.user_id, ct.account_id, ct.symbol, ct.month;

CREATE UNIQUE INDEX uq_symbol_performance ON symbol_performance (user_id, COALESCE(account_id, '00000000-0000-0000-0000-000000000000'::uuid), symbol, month);














CREATE INDEX idx_symbol_performance_user ON symbol_performance(user_id);
CREATE INDEX idx_symbol_performance_account ON symbol_performance(account_id);
CREATE INDEX idx_symbol_performance_symbol ON symbol_performance(symbol);
CREATE INDEX idx_symbol_performance_month ON symbol_performance(month);

COMMENT ON MATERIALIZED VIEW symbol_performance IS 'Pre-aggregated symbol performance by month';


-- =========================================================
-- MATERIALIZED VIEW: monthly_performance
-- =========================================================


-- Create monthly_performance if missing
CREATE MATERIALIZED VIEW monthly_performance AS
WITH closed_trades AS (
    SELECT
        t.user_id,
        t.account_id,
        date_trunc('month', t.exit_date)::date AS month,
        t.symbol,
        t.net_profit,
        t.pips_moved,
        t.fees,
        t.swap
    FROM trades t
    WHERE t.deleted_at IS NULL
      AND t.status = 'closed'
      AND t.exit_date IS NOT NULL
)
SELECT
    ct.user_id,
    ct.account_id,
    ct.month,
    EXTRACT(YEAR FROM ct.month)::int AS year,
    EXTRACT(MONTH FROM ct.month)::int AS month_num,
    TO_CHAR(ct.month, 'YYYY-MM') AS month_key,
    COUNT(*)::int AS trades_count,
    COUNT(*) FILTER (WHERE ct.net_profit > 0)::int AS winning_trades,
    COUNT(*) FILTER (WHERE ct.net_profit < 0)::int AS losing_trades,
    COUNT(*) FILTER (WHERE ct.net_profit = 0)::int AS breakeven_trades,
    COALESCE(SUM(ct.net_profit), 0)::numeric(20,2) AS net_profit,
    COALESCE(SUM(ct.pips_moved), 0)::numeric(20,2) AS total_pips,
    COALESCE(AVG(ct.net_profit), 0)::numeric(20,2) AS avg_trade,
    COALESCE(SUM(ct.fees), 0)::numeric(20,2) AS total_fees,
    COALESCE(SUM(ct.swap), 0)::numeric(20,2) AS total_swap,
    COALESCE(AVG(ct.net_profit) FILTER (WHERE ct.net_profit > 0), 0)::numeric(20,2) AS avg_win,
    COALESCE(AVG(ABS(ct.net_profit)) FILTER (WHERE ct.net_profit < 0), 0)::numeric(20,2) AS avg_loss,
    COALESCE(MAX(ct.net_profit), 0)::numeric(20,2) AS best_trade,
    COALESCE(MIN(ct.net_profit), 0)::numeric(20,2) AS worst_trade,
    COUNT(DISTINCT ct.symbol)::int AS symbols_traded,
    CASE
        WHEN COUNT(*) > 0
            THEN ROUND((COUNT(*) FILTER (WHERE ct.net_profit > 0)::numeric / COUNT(*)::numeric) * 100, 2)
        ELSE 0
    END::numeric(10,2) AS win_rate
FROM closed_trades ct
GROUP BY ct.user_id, ct.account_id, ct.month;

CREATE UNIQUE INDEX uq_monthly_performance ON monthly_performance (user_id, COALESCE(account_id, '00000000-0000-0000-0000-000000000000'::uuid), month);









CREATE INDEX idx_monthly_performance_user ON monthly_performance(user_id);
CREATE INDEX idx_monthly_performance_account ON monthly_performance(account_id);
CREATE INDEX idx_monthly_performance_month ON monthly_performance(month);
CREATE INDEX idx_monthly_performance_year ON monthly_performance(year, month_num);

COMMENT ON MATERIALIZED VIEW monthly_performance IS 'Monthly trading performance summary';


-- =========================================================
-- VIEW: v_strategy_live_stats
-- =========================================================

CREATE VIEW v_strategy_live_stats AS
SELECT
    s.id AS strategy_id,
    s.user_id,
    s.strategy_name,
    s.strategy_type,
    COUNT(t.id)::integer AS total_trades,
    COALESCE(SUM(t.net_profit), 0)::decimal(15,2) AS net_profit,
    CASE
        WHEN COUNT(t.id) > 0 THEN
            ROUND(
                (
                    COUNT(*) FILTER (WHERE t.is_winning = TRUE)::numeric
                    / NULLIF(COUNT(t.id), 0)
                ) * 100,
                2
            )
        ELSE 0
    END::decimal(5,2) AS win_rate,
    CASE
        WHEN COALESCE(SUM(ABS(t.net_profit)) FILTER (WHERE t.is_losing = TRUE), 0) > 0 THEN
            ROUND(
                COALESCE(SUM(t.net_profit) FILTER (WHERE t.is_winning = TRUE), 0)
                /
                NULLIF(COALESCE(SUM(ABS(t.net_profit)) FILTER (WHERE t.is_losing = TRUE), 0), 0),
                2
            )
        ELSE 0
    END::decimal(10,2) AS profit_factor
FROM strategies s
LEFT JOIN trades t
    ON t.strategy_id = s.id
   AND t.status = 'closed'
   AND t.deleted_at IS NULL
GROUP BY s.id, s.user_id, s.strategy_name, s.strategy_type;

COMMENT ON VIEW v_strategy_live_stats IS 'Live calculated strategy statistics derived from trades';


-- =========================================================
-- REFRESH FUNCTION
-- =========================================================

CREATE OR REPLACE FUNCTION refresh_trading_views()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY trade_statistics_mv;
    REFRESH MATERIALIZED VIEW CONCURRENTLY symbol_performance;
    REFRESH MATERIALIZED VIEW CONCURRENTLY monthly_performance;
END;
$$;

COMMENT ON FUNCTION refresh_trading_views() IS 'Refresh all trading materialized views';
































SELECT column_name, data_type, is_nullable
FROM information_schema.columns 
WHERE table_name = 'goals'
ORDER BY ordinal_position;




SELECT column_name, data_type, is_nullable
FROM information_schema.columns 
WHERE table_name = 'journal_entries'
ORDER BY ordinal_position;

SELECT column_name, data_type, is_nullable
FROM information_schema.columns 
WHERE table_name = 'strategies'
ORDER BY ordinal_position;







SELECT column_name, data_type, is_nullable
FROM information_schema.columns 
WHERE table_name = 'users'
ORDER BY ordinal_position;




SELECT column_name, data_type, is_nullable
FROM information_schema.columns 
WHERE table_name = 'trading_accounts'
ORDER BY ordinal_position;




-- Run this in PostgreSQL to get trades table info
SELECT column_name, data_type, is_nullable
FROM information_schema.columns 
WHERE table_name = 'trades'
ORDER BY ordinal_position;







SELECT * FROM trades;




























-- =========================================================
-- CLEAN DROP
-- =========================================================

DROP FUNCTION IF EXISTS refresh_trading_views();

DROP MATERIALIZED VIEW IF EXISTS trade_statistics_mv CASCADE;
DROP MATERIALIZED VIEW IF EXISTS symbol_performance CASCADE;
DROP MATERIALIZED VIEW IF EXISTS monthly_performance CASCADE;

DROP VIEW IF EXISTS v_trader_dashboard CASCADE;
DROP VIEW IF EXISTS equity_curve_v CASCADE;


-- =========================================================
-- MATERIALIZED VIEW: trade_statistics_mv (FIXED)
-- =========================================================

CREATE MATERIALIZED VIEW trade_statistics_mv AS
WITH closed_base AS (
    SELECT
        t.user_id,
        t.account_id,
        t.id,
        t.symbol,
        t.status,
        t.quantity,
        t.net_profit,
        t.pips_moved,
        t.duration_minutes,
        t.session,
        EXTRACT(DOW FROM t.entry_date AT TIME ZONE 'UTC')::int AS day_of_week,
        t.entry_date,
        t.exit_date,
        t.exit_date::date AS exit_day
    FROM trades t
    WHERE t.deleted_at IS NULL
      AND t.status = 'closed'
      AND t.exit_date IS NOT NULL
),
open_trade_counts AS (
    SELECT
        t.user_id,
        t.account_id,
        COUNT(*)::int AS open_trades
    FROM trades t
    WHERE t.deleted_at IS NULL
      AND t.status = 'open'
    GROUP BY t.user_id, t.account_id
),
lifetime_stats AS (
    SELECT
        cb.user_id,
        cb.account_id,
        'lifetime'::varchar AS period_type,
        MIN(cb.exit_day) AS period_start,
        MAX(cb.exit_day) AS period_end,
        COUNT(*)::int AS total_trades,
        COUNT(*) FILTER (WHERE cb.net_profit > 0)::int AS winning_trades,
        COUNT(*) FILTER (WHERE cb.net_profit < 0)::int AS losing_trades,
        COUNT(*) FILTER (WHERE cb.net_profit = 0)::int AS breakeven_trades,
        COALESCE(SUM(cb.quantity), 0)::numeric(20,4) AS total_volume,
        COALESCE(AVG(cb.quantity), 0)::numeric(20,4) AS avg_volume_per_trade,
        COALESCE(SUM(cb.net_profit) FILTER (WHERE cb.net_profit > 0), 0)::numeric(20,2) AS gross_profit,
        COALESCE(SUM(ABS(cb.net_profit)) FILTER (WHERE cb.net_profit < 0), 0)::numeric(20,2) AS gross_loss,
        COALESCE(SUM(cb.net_profit), 0)::numeric(20,2) AS net_profit,
        COALESCE(SUM(cb.pips_moved) FILTER (WHERE cb.pips_moved IS NOT NULL), 0)::numeric(20,2) AS total_pips,
        COALESCE(AVG(cb.pips_moved) FILTER (WHERE cb.pips_moved IS NOT NULL), 0)::numeric(20,2) AS avg_pips_per_trade,
        COALESCE(AVG(cb.net_profit) FILTER (WHERE cb.net_profit > 0), 0)::numeric(20,2) AS avg_win,
        COALESCE(AVG(ABS(cb.net_profit)) FILTER (WHERE cb.net_profit < 0), 0)::numeric(20,2) AS avg_loss,
        CASE
            WHEN COUNT(*) > 0
                THEN ROUND((COUNT(*) FILTER (WHERE cb.net_profit > 0)::numeric / COUNT(*)::numeric) * 100, 2)
            ELSE 0
        END::numeric(10,2) AS win_rate,
        CASE
            WHEN COALESCE(SUM(ABS(cb.net_profit)) FILTER (WHERE cb.net_profit < 0), 0) > 0
                THEN ROUND(
                    COALESCE(SUM(cb.net_profit) FILTER (WHERE cb.net_profit > 0), 0)
                    /
                    NULLIF(COALESCE(SUM(ABS(cb.net_profit)) FILTER (WHERE cb.net_profit < 0), 0), 0),
                    4
                )
            WHEN COALESCE(SUM(cb.net_profit) FILTER (WHERE cb.net_profit > 0), 0) > 0
                THEN 999999::numeric
            ELSE 0
        END::numeric(12,4) AS profit_factor,
        CASE
            WHEN COALESCE(AVG(ABS(cb.net_profit)) FILTER (WHERE cb.net_profit < 0), 0) > 0
                THEN ROUND(
                    COALESCE(AVG(cb.net_profit) FILTER (WHERE cb.net_profit > 0), 0)
                    /
                    NULLIF(COALESCE(AVG(ABS(cb.net_profit)) FILTER (WHERE cb.net_profit < 0), 0), 0),
                    4
                )
            ELSE 0
        END::numeric(12,4) AS payoff_ratio,
        COALESCE(AVG(cb.net_profit), 0)::numeric(20,4) AS expectancy,
        COALESCE(AVG(cb.duration_minutes), 0)::int AS avg_duration_minutes,
        COALESCE(SUM(cb.duration_minutes) / 60.0, 0)::numeric(20,2) AS total_duration_hours
    FROM closed_base cb
    GROUP BY cb.user_id, cb.account_id
),
monthly_stats AS (
    SELECT
        cb.user_id,
        cb.account_id,
        'monthly'::varchar AS period_type,
        date_trunc('month', cb.exit_date)::date AS period_start,
        (date_trunc('month', cb.exit_date) + interval '1 month - 1 day')::date AS period_end,
        COUNT(*)::int AS total_trades,
        COUNT(*) FILTER (WHERE cb.net_profit > 0)::int AS winning_trades,
        COUNT(*) FILTER (WHERE cb.net_profit < 0)::int AS losing_trades,
        COUNT(*) FILTER (WHERE cb.net_profit = 0)::int AS breakeven_trades,
        COALESCE(SUM(cb.quantity), 0)::numeric(20,4) AS total_volume,
        COALESCE(AVG(cb.quantity), 0)::numeric(20,4) AS avg_volume_per_trade,
        COALESCE(SUM(cb.net_profit) FILTER (WHERE cb.net_profit > 0), 0)::numeric(20,2) AS gross_profit,
        COALESCE(SUM(ABS(cb.net_profit)) FILTER (WHERE cb.net_profit < 0), 0)::numeric(20,2) AS gross_loss,
        COALESCE(SUM(cb.net_profit), 0)::numeric(20,2) AS net_profit,
        COALESCE(SUM(cb.pips_moved) FILTER (WHERE cb.pips_moved IS NOT NULL), 0)::numeric(20,2) AS total_pips,
        COALESCE(AVG(cb.pips_moved) FILTER (WHERE cb.pips_moved IS NOT NULL), 0)::numeric(20,2) AS avg_pips_per_trade,
        COALESCE(AVG(cb.net_profit) FILTER (WHERE cb.net_profit > 0), 0)::numeric(20,2) AS avg_win,
        COALESCE(AVG(ABS(cb.net_profit)) FILTER (WHERE cb.net_profit < 0), 0)::numeric(20,2) AS avg_loss,
        CASE
            WHEN COUNT(*) > 0
                THEN ROUND((COUNT(*) FILTER (WHERE cb.net_profit > 0)::numeric / COUNT(*)::numeric) * 100, 2)
            ELSE 0
        END::numeric(10,2) AS win_rate,
        CASE
            WHEN COALESCE(SUM(ABS(cb.net_profit)) FILTER (WHERE cb.net_profit < 0), 0) > 0
                THEN ROUND(
                    COALESCE(SUM(cb.net_profit) FILTER (WHERE cb.net_profit > 0), 0)
                    /
                    NULLIF(COALESCE(SUM(ABS(cb.net_profit)) FILTER (WHERE cb.net_profit < 0), 0), 0),
                    4
                )
            WHEN COALESCE(SUM(cb.net_profit) FILTER (WHERE cb.net_profit > 0), 0) > 0
                THEN 999999::numeric
            ELSE 0
        END::numeric(12,4) AS profit_factor,
        CASE
            WHEN COALESCE(AVG(ABS(cb.net_profit)) FILTER (WHERE cb.net_profit < 0), 0) > 0
                THEN ROUND(
                    COALESCE(AVG(cb.net_profit) FILTER (WHERE cb.net_profit > 0), 0)
                    /
                    NULLIF(COALESCE(AVG(ABS(cb.net_profit)) FILTER (WHERE cb.net_profit < 0), 0), 0),
                    4
                )
            ELSE 0
        END::numeric(12,4) AS payoff_ratio,
        COALESCE(AVG(cb.net_profit), 0)::numeric(20,4) AS expectancy,
        COALESCE(AVG(cb.duration_minutes), 0)::int AS avg_duration_minutes,
        COALESCE(SUM(cb.duration_minutes) / 60.0, 0)::numeric(20,2) AS total_duration_hours
    FROM closed_base cb
    GROUP BY cb.user_id, cb.account_id, date_trunc('month', cb.exit_date)
),
all_periods AS (
    SELECT * FROM lifetime_stats
    UNION ALL
    SELECT * FROM monthly_stats
),
session_stats AS (
    SELECT
        cb.user_id,
        cb.account_id,
        cb.session,
        COUNT(*) AS session_trades,
        COUNT(*) FILTER (WHERE cb.net_profit > 0) AS session_wins,
        COUNT(*) FILTER (WHERE cb.net_profit < 0) AS session_losses,
        COUNT(*) FILTER (WHERE cb.net_profit = 0) AS session_breakeven,
        COALESCE(SUM(cb.net_profit), 0) AS session_net_profit,
        CASE
            WHEN COUNT(*) > 0
                THEN ROUND((COUNT(*) FILTER (WHERE cb.net_profit > 0)::numeric / COUNT(*)::numeric) * 100, 2)
            ELSE 0
        END AS session_win_rate
    FROM closed_base cb
    WHERE cb.session IS NOT NULL
    GROUP BY cb.user_id, cb.account_id, cb.session
),
session_lifetime AS (
    SELECT
        ss.user_id,
        ss.account_id,
        jsonb_object_agg(
            ss.session::text,
            jsonb_build_object(
                'trades', ss.session_trades,
                'wins', ss.session_wins,
                'losses', ss.session_losses,
                'breakeven', ss.session_breakeven,
                'net_profit', ss.session_net_profit,
                'win_rate', ss.session_win_rate
            )
        ) AS session_performance
    FROM session_stats ss
    GROUP BY ss.user_id, ss.account_id
),
day_lifetime_rows AS (
    SELECT
        cb.user_id,
        cb.account_id,
        CASE cb.day_of_week
            WHEN 0 THEN 'sunday'
            WHEN 1 THEN 'monday'
            WHEN 2 THEN 'tuesday'
            WHEN 3 THEN 'wednesday'
            WHEN 4 THEN 'thursday'
            WHEN 5 THEN 'friday'
            WHEN 6 THEN 'saturday'
        END AS day_name,
        COUNT(*) AS trades,
        COUNT(*) FILTER (WHERE cb.net_profit > 0) AS wins,
        COUNT(*) FILTER (WHERE cb.net_profit < 0) AS losses,
        COUNT(*) FILTER (WHERE cb.net_profit = 0) AS breakeven,
        COALESCE(SUM(cb.net_profit), 0) AS net_profit,
        CASE
            WHEN COUNT(*) > 0
                THEN ROUND((COUNT(*) FILTER (WHERE cb.net_profit > 0)::numeric / COUNT(*)::numeric) * 100, 2)
            ELSE 0
        END AS win_rate
    FROM closed_base cb
    GROUP BY cb.user_id, cb.account_id, cb.day_of_week
),
day_lifetime AS (
    SELECT
        dlr.user_id,
        dlr.account_id,
        jsonb_object_agg(
            dlr.day_name,
            jsonb_build_object(
                'trades', dlr.trades,
                'wins', dlr.wins,
                'losses', dlr.losses,
                'breakeven', dlr.breakeven,
                'net_profit', dlr.net_profit,
                'win_rate', dlr.win_rate
            )
        ) AS day_performance
    FROM day_lifetime_rows dlr
    GROUP BY dlr.user_id, dlr.account_id
),
top_symbols_lifetime_rows AS (
    SELECT
        cb.user_id,
        cb.account_id,
        cb.symbol,
        COUNT(*)::int AS trades,
        COALESCE(SUM(cb.net_profit), 0)::numeric(20,2) AS net_profit,
        ROW_NUMBER() OVER (
            PARTITION BY cb.user_id, cb.account_id
            ORDER BY COALESCE(SUM(cb.net_profit), 0) DESC, cb.symbol
        ) AS rn
    FROM closed_base cb
    GROUP BY cb.user_id, cb.account_id, cb.symbol
),
top_symbols_lifetime AS (
    SELECT
        tslr.user_id,
        tslr.account_id,
        jsonb_agg(
            jsonb_build_object(
                'symbol', tslr.symbol,
                'trades', tslr.trades,
                'net_profit', tslr.net_profit
            )
            ORDER BY tslr.net_profit DESC, tslr.symbol
        ) AS top_symbols
    FROM top_symbols_lifetime_rows tslr
    WHERE tslr.rn <= 10
    GROUP BY tslr.user_id, tslr.account_id
)
SELECT
    ap.user_id,
    ap.account_id,
    ap.period_type,
    ap.period_start,
    ap.period_end,
    ap.total_trades,
    ap.winning_trades,
    ap.losing_trades,
    ap.breakeven_trades,
    CASE
        WHEN ap.period_type = 'lifetime' THEN COALESCE(otc.open_trades, 0)
        ELSE 0
    END AS open_trades,
    ap.total_volume,
    ap.avg_volume_per_trade,
    ap.gross_profit,
    ap.gross_loss,
    ap.net_profit,
    ap.total_pips,
    ap.avg_pips_per_trade,
    ap.avg_win,
    ap.avg_loss,
    ap.win_rate,
    ap.profit_factor,
    ap.payoff_ratio,
    ap.expectancy,
    ap.avg_duration_minutes,
    ap.total_duration_hours,
    CASE
        WHEN ap.period_type = 'lifetime' THEN COALESCE(sl.session_performance, '{}'::jsonb)
        ELSE '{}'::jsonb
    END AS session_performance,
    CASE
        WHEN ap.period_type = 'lifetime' THEN COALESCE(dl.day_performance, '{}'::jsonb)
        ELSE '{}'::jsonb
    END AS day_performance,
    CASE
        WHEN ap.period_type = 'lifetime' THEN COALESCE(ts.top_symbols, '[]'::jsonb)
        ELSE '[]'::jsonb
    END AS top_symbols,
    NOW() AS calculated_at
FROM all_periods ap
LEFT JOIN open_trade_counts otc
    ON ap.user_id = otc.user_id
   AND ap.account_id IS NOT DISTINCT FROM otc.account_id
LEFT JOIN session_lifetime sl
    ON ap.user_id = sl.user_id
   AND ap.account_id IS NOT DISTINCT FROM sl.account_id
LEFT JOIN day_lifetime dl
    ON ap.user_id = dl.user_id
   AND ap.account_id IS NOT DISTINCT FROM dl.account_id
LEFT JOIN top_symbols_lifetime ts
    ON ap.user_id = ts.user_id
   AND ap.account_id IS NOT DISTINCT FROM ts.account_id;


-- Required unique index for refresh safety / uniqueness
CREATE UNIQUE INDEX uq_trade_statistics_mv
ON trade_statistics_mv (
    user_id,
    COALESCE(account_id, '00000000-0000-0000-0000-000000000000'::uuid),
    period_type,
    period_start
);

CREATE INDEX idx_trade_statistics_mv_user
ON trade_statistics_mv (user_id);

CREATE INDEX idx_trade_statistics_mv_account
ON trade_statistics_mv (account_id);

CREATE INDEX idx_trade_statistics_mv_period
ON trade_statistics_mv (period_type);


-- =========================================================
-- MATERIALIZED VIEW: symbol_performance
-- =========================================================

CREATE MATERIALIZED VIEW symbol_performance AS
WITH closed_trades AS (
    SELECT
        t.user_id,
        t.account_id,
        t.symbol,
        date_trunc('month', t.exit_date)::date AS month,
        t.net_profit,
        t.pips_moved
    FROM trades t
    WHERE t.deleted_at IS NULL
      AND t.status = 'closed'
      AND t.exit_date IS NOT NULL
)
SELECT
    ct.user_id,
    ct.account_id,
    ct.symbol,
    ct.month,
    COUNT(*)::int AS trades_count,
    COUNT(*) FILTER (WHERE ct.net_profit > 0)::int AS winning_trades,
    COUNT(*) FILTER (WHERE ct.net_profit < 0)::int AS losing_trades,
    COUNT(*) FILTER (WHERE ct.net_profit = 0)::int AS breakeven_trades,
    COALESCE(SUM(ct.net_profit), 0)::numeric(20,2) AS net_profit,
    COALESCE(SUM(ct.pips_moved), 0)::numeric(20,2) AS total_pips,
    COALESCE(AVG(ct.net_profit), 0)::numeric(20,2) AS avg_profit_per_trade,
    COALESCE(AVG(ct.pips_moved), 0)::numeric(20,2) AS avg_pips_per_trade,
    COALESCE(AVG(ct.net_profit) FILTER (WHERE ct.net_profit > 0), 0)::numeric(20,2) AS avg_win,
    COALESCE(AVG(ABS(ct.net_profit)) FILTER (WHERE ct.net_profit < 0), 0)::numeric(20,2) AS avg_loss,
    COALESCE(MAX(ct.net_profit), 0)::numeric(20,2) AS best_trade,
    COALESCE(MIN(ct.net_profit), 0)::numeric(20,2) AS worst_trade,
    CASE
        WHEN COUNT(*) > 0
            THEN ROUND((COUNT(*) FILTER (WHERE ct.net_profit > 0)::numeric / COUNT(*)::numeric) * 100, 2)
        ELSE 0
    END::numeric(10,2) AS win_rate,
    RANK() OVER (
        PARTITION BY ct.user_id, ct.account_id, ct.month
        ORDER BY COALESCE(SUM(ct.net_profit), 0) DESC, ct.symbol
    ) AS rank_by_profit
FROM closed_trades ct
GROUP BY ct.user_id, ct.account_id, ct.symbol, ct.month;


CREATE UNIQUE INDEX uq_symbol_performance
ON symbol_performance (
    user_id,
    COALESCE(account_id, '00000000-0000-0000-0000-000000000000'::uuid),
    symbol,
    month
);

CREATE INDEX idx_symbol_performance_user
ON symbol_performance (user_id);

CREATE INDEX idx_symbol_performance_account
ON symbol_performance (account_id);

CREATE INDEX idx_symbol_performance_symbol
ON symbol_performance (symbol);

CREATE INDEX idx_symbol_performance_month
ON symbol_performance (month);


-- =========================================================
-- MATERIALIZED VIEW: monthly_performance
-- =========================================================

CREATE MATERIALIZED VIEW monthly_performance AS
WITH closed_trades AS (
    SELECT
        t.user_id,
        t.account_id,
        date_trunc('month', t.exit_date)::date AS month,
        t.symbol,
        t.net_profit,
        t.pips_moved,
        t.fees,
        t.swap
    FROM trades t
    WHERE t.deleted_at IS NULL
      AND t.status = 'closed'
      AND t.exit_date IS NOT NULL
)
SELECT
    ct.user_id,
    ct.account_id,
    ct.month,
    EXTRACT(YEAR FROM ct.month)::int AS year,
    EXTRACT(MONTH FROM ct.month)::int AS month_num,
    TO_CHAR(ct.month, 'YYYY-MM') AS month_key,
    COUNT(*)::int AS trades_count,
    COUNT(*) FILTER (WHERE ct.net_profit > 0)::int AS winning_trades,
    COUNT(*) FILTER (WHERE ct.net_profit < 0)::int AS losing_trades,
    COUNT(*) FILTER (WHERE ct.net_profit = 0)::int AS breakeven_trades,
    COALESCE(SUM(ct.net_profit), 0)::numeric(20,2) AS net_profit,
    COALESCE(SUM(ct.pips_moved), 0)::numeric(20,2) AS total_pips,
    COALESCE(AVG(ct.net_profit), 0)::numeric(20,2) AS avg_trade,
    COALESCE(SUM(ct.fees), 0)::numeric(20,2) AS total_fees,
    COALESCE(SUM(ct.swap), 0)::numeric(20,2) AS total_swap,
    COALESCE(AVG(ct.net_profit) FILTER (WHERE ct.net_profit > 0), 0)::numeric(20,2) AS avg_win,
    COALESCE(AVG(ABS(ct.net_profit)) FILTER (WHERE ct.net_profit < 0), 0)::numeric(20,2) AS avg_loss,
    COALESCE(MAX(ct.net_profit), 0)::numeric(20,2) AS best_trade,
    COALESCE(MIN(ct.net_profit), 0)::numeric(20,2) AS worst_trade,
    COUNT(DISTINCT ct.symbol)::int AS symbols_traded,
    CASE
        WHEN COUNT(*) > 0
            THEN ROUND((COUNT(*) FILTER (WHERE ct.net_profit > 0)::numeric / COUNT(*)::numeric) * 100, 2)
        ELSE 0
    END::numeric(10,2) AS win_rate
FROM closed_trades ct
GROUP BY ct.user_id, ct.account_id, ct.month;


CREATE UNIQUE INDEX uq_monthly_performance
ON monthly_performance (
    user_id,
    COALESCE(account_id, '00000000-0000-0000-0000-000000000000'::uuid),
    month
);

CREATE INDEX idx_monthly_performance_user
ON monthly_performance (user_id);

CREATE INDEX idx_monthly_performance_account
ON monthly_performance (account_id);

CREATE INDEX idx_monthly_performance_month
ON monthly_performance (month);


-- =========================================================
-- VIEW: v_trader_dashboard
-- =========================================================

CREATE VIEW v_trader_dashboard AS
WITH open_positions AS (
    SELECT
        t.user_id,
        t.account_id,
        COUNT(*)::int AS open_positions,
        COALESCE(SUM(t.position_value), 0)::numeric(20,2) AS total_exposure
    FROM trades t
    WHERE t.deleted_at IS NULL
      AND t.status = 'open'
    GROUP BY t.user_id, t.account_id
),
closed_stats AS (
    SELECT
        t.user_id,
        t.account_id,
        COUNT(*)::int AS total_lifetime_trades,
        COALESCE(SUM(t.net_profit), 0)::numeric(20,2) AS lifetime_pnl,
        COALESCE(AVG(t.net_profit), 0)::numeric(20,2) AS avg_pnl_per_trade,
        CASE
            WHEN COUNT(*) > 0
                THEN ROUND((COUNT(*) FILTER (WHERE t.net_profit > 0)::numeric / COUNT(*)::numeric) * 100, 2)
            ELSE 0
        END::numeric(10,2) AS win_rate
    FROM trades t
    WHERE t.deleted_at IS NULL
      AND t.status = 'closed'
      AND t.exit_date IS NOT NULL
    GROUP BY t.user_id, t.account_id
),
today_stats AS (
    SELECT
        t.user_id,
        t.account_id,
        COALESCE(SUM(t.net_profit), 0)::numeric(20,2) AS today_pnl,
        COUNT(*)::int AS today_trades
    FROM trades t
    WHERE t.deleted_at IS NULL
      AND t.status = 'closed'
      AND t.exit_date IS NOT NULL
      AND (t.exit_date AT TIME ZONE 'UTC')::date = (NOW() AT TIME ZONE 'UTC')::date
    GROUP BY t.user_id, t.account_id
)
SELECT
    u.id AS user_id,
    u.username,
    ta.id AS account_id,
    ta.account_name,
    ta.current_balance,
    COALESCE(op.open_positions, 0) AS open_positions,
    COALESCE(op.total_exposure, 0)::numeric(20,2) AS total_exposure,
    COALESCE(cs.total_lifetime_trades, 0) AS total_lifetime_trades,
    COALESCE(cs.lifetime_pnl, 0)::numeric(20,2) AS lifetime_pnl,
    COALESCE(cs.avg_pnl_per_trade, 0)::numeric(20,2) AS avg_return_per_trade,
    COALESCE(ts.today_pnl, 0)::numeric(20,2) AS today_pnl,
    COALESCE(ts.today_trades, 0) AS today_trades,
    COALESCE(cs.win_rate, 0)::numeric(10,2) AS win_rate,
    ROW_NUMBER() OVER (
        PARTITION BY u.id
        ORDER BY ta.current_balance DESC NULLS LAST, ta.account_name
    ) AS account_rank
FROM users u
JOIN trading_accounts ta
    ON u.id = ta.user_id
   AND ta.deleted_at IS NULL
LEFT JOIN open_positions op
    ON op.user_id = u.id
   AND op.account_id = ta.id
LEFT JOIN closed_stats cs
    ON cs.user_id = u.id
   AND cs.account_id = ta.id
LEFT JOIN today_stats ts
    ON ts.user_id = u.id
   AND ts.account_id = ta.id
WHERE u.deleted_at IS NULL;


-- =========================================================
-- VIEW: equity_curve_v
-- =========================================================
CREATE VIEW equity_curve_v AS
WITH closed_trades AS (
    SELECT
        t.id AS trade_id,
        t.user_id,
        t.account_id,
        t.exit_date AS point_date,
        t.entry_date AS trade_entry_date,
        t.net_profit,
        t.notes,
        t.created_at
    FROM trades t
    WHERE t.deleted_at IS NULL
      AND t.status = 'closed'
      AND t.exit_date IS NOT NULL
),
ordered_curve AS (
    SELECT
        ct.trade_id,
        ct.user_id,
        ct.account_id,
        ct.point_date,
        ct.trade_entry_date,
        ct.net_profit,
        ct.notes,
        ct.created_at,
        SUM(ct.net_profit) OVER (
            PARTITION BY ct.user_id, ct.account_id
            ORDER BY ct.point_date, ct.trade_id
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        )::numeric(20,2) AS cumulative_pnl
    FROM closed_trades ct
),
balances AS (
    SELECT
        oc.trade_id,
        oc.user_id,
        oc.account_id,
        oc.point_date,
        oc.trade_entry_date,
        oc.net_profit,
        oc.notes,
        oc.created_at,
        oc.cumulative_pnl,
        (ta.initial_balance + oc.cumulative_pnl)::numeric(20,2) AS balance
    FROM ordered_curve oc
    JOIN trading_accounts ta
      ON ta.id = oc.account_id
),
peaks AS (
    SELECT
        b.*,
        MAX(b.balance) OVER (
            PARTITION BY b.user_id, b.account_id
            ORDER BY b.point_date, b.trade_id
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        )::numeric(20,2) AS running_peak_balance
    FROM balances b
)
SELECT
    p.trade_id AS id,
    p.user_id,
    p.account_id,
    p.point_date,
    p.balance,
    NULL::numeric(20,2) AS equity,
    p.cumulative_pnl,
    CASE
        WHEN p.running_peak_balance > 0
            THEN ROUND(((p.running_peak_balance - p.balance) / p.running_peak_balance) * 100, 4)
        ELSE 0
    END::numeric(10,4) AS drawdown,
    (p.running_peak_balance - p.balance)::numeric(20,2) AS drawdown_amount,
    'trade_close'::varchar AS point_type,
    p.trade_id,
    p.trade_entry_date,
    p.notes,
    p.created_at
FROM peaks p;

-- =========================================================
-- REFRESH FUNCTION
-- =========================================================

CREATE OR REPLACE FUNCTION refresh_trading_views()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY trade_statistics_mv;
    REFRESH MATERIALIZED VIEW CONCURRENTLY symbol_performance;
    REFRESH MATERIALIZED VIEW CONCURRENTLY monthly_performance;
END;
$$;




REFRESH MATERIALIZED VIEW CONCURRENTLY trade_statistics_mv;
REFRESH MATERIALIZED VIEW CONCURRENTLY symbol_performance;
REFRESH MATERIALIZED VIEW CONCURRENTLY monthly_performance;








-- Check ALL materialized views
SELECT 
    schemaname,
    matviewname as view_name,
    'MATERIALIZED' as type,
    ispopulated
FROM pg_matviews
WHERE matviewname IN (
    'trade_statistics_mv', 
    'symbol_performance', 
    'monthly_performance'
)
UNION ALL
-- Check ALL regular views (including the ones you added)
SELECT 
    schemaname,
    viewname,
    'REGULAR',
    NULL as ispopulated
FROM pg_views
WHERE viewname IN (
    'v_trader_dashboard',
    'equity_curve_v', 
    'goal_progress_v',
    'v_performance_attribution',
    'v_strategy_performance_matrix',
    'v_learning_curve',
    'v_strategy_live_stats'
)
ORDER BY type, view_name;
