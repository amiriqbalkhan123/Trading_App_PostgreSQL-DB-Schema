

-- Enum Types for all the Tables of the Trading MIS Database

-- User Related Enums
CREATE TYPE user_role AS ENUM ('user', 'premium', 'admin', 'support', 'superadmin');
CREATE TYPE account_status AS ENUM ('active','inactive', 'suspended', 'closed');


-- Package Related Enums
CREATE TYPE billing_cycle AS ENUM ('monthly','quarterly', 'semiannual', 'yearly');
CREATE TYPE subscription_status AS ENUM ('active', 'expired', 'cancelled', 'trial', 'past_due');

-- Trading Account Enums
CREATE TYPE account_type AS ENUM ('demo', 'micro', 'real', 'prop_firm', 'challenge', 'islamic_swap_free', 'ecn', 'stp', 'corporate', 'vip', 'managed');
CREATE TYPE platform_type AS ENUM ('MT4', 'MT5', 'cTrader', 'TradingView', 'NinjaTrader', 'Thinkorswim', 'SaxoTraderGO', 'MetaTraderWeb');


-- Trade Enums
CREATE TYPE instrument_type AS ENUM ('forex', 'stock', 'index', 'crypto', 'commodity', 'ETF', 'bond', 'option', 'future', 'CFD');
CREATE TYPE trade_direction AS ENUM ('buy', 'sell');
CREATE TYPE position_type AS ENUM ('long', 'short');
CREATE TYPE trade_status AS ENUM ('open', 'closed', 'cancelled', 'pending');
CREATE TYPE exit_reason AS ENUM ('tp_hit', 'sl_hit', 'manual', 'signal', 'news', 'margin_call');

-- Session Enums
CREATE TYPE trading_session AS ENUM ('asian', 'london', 'new_york','frankfurt', 'pacific','weekend','tokyo', 'overnight');

-- Journal Enums
CREATE TYPE journal_type AS ENUM ('daily', 'weekly', 'monthly', 'pre_trade', 'post_trade');
CREATE TYPE mood_type AS ENUM ('happy', 'sad', 'neutral', 'anxious', 'confident', 
								'overconfident', 'fearful', 'greedy', 'frustrated',
								'calm', 'stressed', 'focused', 'distracted');



-- Insight Enum
CREATE TYPE insight_type AS ENUM ('rule', 'lesson', 'mistake', 'improvement', 'observation');
CREATE TYPE insight_category AS ENUM ('psychology', 'risk', 'strategy', 'execution', 'analysis');

-- Strategy Enums
CREATE TYPE strategy_type AS ENUM ('scalping', 'day_trading', 'swing', 'position', 'algorithmic', 'hedging', 'arbitrage', 'grid_trading', 'martingale', 'breakout','news_trading');

-- Goal Enums
CREATE TYPE goal_type AS ENUM ('daily', 'weekly', 'quarterly', 'lifetime', 'bi_weekly', 'monthly', 'yearly', 'custom');
CREATE TYPE goal_category AS ENUM ('profit', 'trades', 'win_rate', 'pips', 'risk', 'consistency', 'discipline', 'volume', 'exposure');
CREATE TYPE goal_status AS ENUM ('active', 'completed', 'failed', 'paused');


-- Export Enums
CREATE TYPE export_format AS ENUM ('pdf', 'excel', 'csv');
CREATE TYPE export_type AS ENUM ('trades', 'analytics', 'journal', 'goals');

-- Audit Enums
CREATE TYPE audit_action AS ENUM ('CREATE', 'UPDATE', 'DELETE', 'EXPORT', 'LOGIN', 'LOGOUT', 'IMPORT', 'VIEW', 'DOWNLOAD');




















