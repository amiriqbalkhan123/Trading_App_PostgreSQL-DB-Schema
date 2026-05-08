-- Table : Users

CREATE TABLE users (
	id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
	email VARCHAR(100) UNIQUE NOT NULL,
	username VARCHAR(50) UNIQUE NOT NULL,
	password_hash VARCHAR(255) NOT NULL,
	first_name VARCHAR(50) NOT NULL,
	last_name VARCHAR(50) NOT NULL,
	company_name VARCHAR(100), 
	country_code CHAR(2) NOT NULL DEFAULT 'US',
	timezone VARCHAR(50) NOT NULL DEFAULT 'UTC',
	preferred_currency CHAR(3) NOT NULL DEFAULT 'USD',


	-- Status Flags Here
	is_active BOOLEAN NOT NULL DEFAULT TRUE,
	is_verified BOOLEAN NOT NULL DEFAULT FALSE,
	email_verified_at TIMESTAMPTZ,
	role user_role NOT NULL DEFAULT 'user',

	-- Security Section Here
	two_factor_enabled BOOLEAN NOT NULL DEFAULT FALSE,
	two_factor_secret VARCHAR(100), 
	backup_codes TEXT[],
	last_login_at TIMESTAMPTZ,
	last_login_ip INET,
	failed_login_attempts INTEGER NOT NULL DEFAULT 0,
	locked_until TIMESTAMPTZ,

	-- Denormalized Fields for Performance
	package_code VARCHAR(20),
	max_accounts INTEGER NOT NULL DEFAULT 1,
	subscription_status subscription_status,
	subscription_end_date DATE,

	-- Metadata
	preferences JSONB NOT NULL DEFAULT '{}',
	notification_settings JSONB NOT NULL DEFAULT '{}',
	
	-- Timestamps
	created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
	updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
	deleted_at TIMESTAMPTZ,  -- soft delete

	-- Check Constraints
	CONSTRAINT check_email_format CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'),
	CONSTRAINT check_username_format CHECK(username ~* '^[A-Za-z0-9_]{3,50}$'),
	CONSTRAINT check_username_length CHECK(char_length(username) >= 3),
	CONSTRAINT check_name_length CHECK(char_length(first_name) >= 1 AND char_length(last_name) >= 1),
	CONSTRAINT check_country_code CHECK(country_code ~* '^[A-Z]{2}$'),
	CONSTRAINT check_currency_code CHECK(preferred_currency ~* '^[A-Z]{3}$'),
	CONSTRAINT check_failed_attempts_range CHECK(failed_login_attempts >= 0 AND failed_login_attempts <= 100),
	CONSTRAINT check_subscripion_dates CHECK(
						(subscription_end_date IS NULL) OR 
        				(subscription_end_date > created_at::DATE)
	)
);


-- Indexes of the Users Table
CREATE INDEX idx_users_email ON users(email) WHERE deleted_at IS NULL;
CREATE INDEX idx_users_username ON users(username) WHERE deleted_at IS NULL;
CREATE INDEX idx_users_role ON users(role) WHERE is_active = true;
CREATE INDEX idx_users_subscription ON users(subscription_status) WHERE is_active = true;
CREATE INDEX idx_users_created ON users(created_at);


-- Table : User_Sessions

CREATE TABLE user_sessions(
	id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
	user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
	session_token VARCHAR(500) UNIQUE NOT NULL,
	refresh_token VARCHAR(500) UNIQUE,
	device_name VARCHAR(100), 
	device_type VARCHAR(20), 
	browser VARCHAR(50),
	os VARCHAR(50),
	ip_address INET NOT NULL,
	user_agent TEXT,
	location_country VARCHAR(100),
	location_city VARCHAR(100),
	is_active BOOLEAN NOT NULL DEFAULT true,
	last_activity_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
	expires_at TIMESTAMPTZ NOT NULL,
	created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

	-- Check Constraints
	CONSTRAINT check_session_expiry CHECK (expires_at > created_at),
    CONSTRAINT check_session_token_length CHECK (char_length(session_token) >= 20)
);

-- Indexes of the User_Sessions Table
CREATE INDEX idx_sessions_users ON user_sessions(user_id, is_active);
CREATE INDEX idx_sessions_token ON user_sessions(session_token);
CREATE INDEX idx_sessions_expires ON user_sessions(expires_at) WHERE is_active = true;
CREATE INDEX idx_sessions_activity ON user_sessions(last_activity_at) WHERE is_active = true;




-- Table : login_history

CREATE TABLE login_history(
	id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
	user_id UUID REFERENCES users(id) ON DELETE SET NULL,
	email_attempted VARCHAR(100) NOT NULL,
	success BOOLEAN NOT NULL,
	ip_address INET NOT NULL,
	user_agent TEXT,
	location JSONB,
	failure_reason VARCHAR(100),
	created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes of the login_history Table
CREATE INDEX idx_login_user ON login_history(user_id, created_at DESC);
CREATE INDEX idx_login_email ON login_history(email_attempted, created_at);
CREATE INDEX idx_login_ip ON login_history(ip_address, created_at);
CREATE INDEX idx_login_created ON login_history(created_at);










-- Table : Packages

CREATE TABLE packages(
	id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
	package_name VARCHAR(50) UNIQUE NOT NULL,
	package_code VARCHAR(20) UNIQUE NOT NULL,
	description TEXT,

	-- Limits
	max_accounts INTEGER NOT NULL,
	max_trades_per_month INTEGER,
	max_symbols INTEGER,
	analytics_retention_days INTEGER NOT NULL DEFAULT 365,

	-- Features
	export_formats export_format[] NOT NULL DEFAULT ARRAY['pdf', 'excel', 'csv']::export_format[],
	api_access BOOLEAN NOT NULL DEFAULT FALSE,
	priority_support BOOLEAN NOT NULL DEFAULT FALSE,
	advanced_analytics BOOLEAN NOT NULL DEFAULT FALSE,

	-- Pricing
	price_monthly DECIMAL(10,2) NOT NULL,
	price_yearly DECIMAL(10,2) NOT NULL,
	currency CHAR(3) NOT NULL DEFAULT 'USD',

	-- Status
	is_active BOOLEAN NOT NULL DEFAULT TRUE,
	is_public BOOLEAN NOT NULL DEFAULT TRUE,
	display_order INTEGER NOT NULL DEFAULT 0,

	-- Features JSON for Flexibility
	features JSONB NOT NULL DEFAULT '{}',

	-- Timestamps
	created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
	updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes for Packages Table
CREATE INDEX idx_package_code ON packages(package_code);
CREATE INDEX idx_packages_active ON packages(is_active) WHERE is_active = TRUE;


-- Inserting default packages
INSERT INTO packages (package_name, package_code, max_accounts, max_trades_per_month, price_monthly, price_yearly, features) VALUES
('Basic', 'basic', 1, 100, 9.99, 99.99, '{"support": "email"}'::JSONB),
('Premium', 'premium', 3, 500, 19.99, 199.99, '{"support": "priority", "advanced_analytics": true}'::JSONB),
('Pro', 'pro', 5, NULL, 29.99, 299.99, '{"support": "priority", "advanced_analytics": true, "api_access": true}'::JSONB),
('Enterprise', 'enterprise', 10, NULL, 49.99, 499.99, '{"support": "dedicated", "advanced_analytics": true, "api_access": true, "team_features": true}'::JSONB);




-- Table : user_subscriptions

CREATE TABLE user_subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    package_id UUID NOT NULL REFERENCES packages(id),
    
    -- Subscription details
    subscription_status subscription_status NOT NULL DEFAULT 'trial',
    billing_cycle billing_cycle NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    trial_ends_at DATE,
    cancelled_at TIMESTAMPTZ,
    auto_renew BOOLEAN NOT NULL DEFAULT true,
    
    -- Payment info
    payment_method VARCHAR(50),
    payment_provider VARCHAR(50), 
    payment_provider_id VARCHAR(100),
    last_payment_date TIMESTAMPTZ,
    next_payment_date DATE,
    amount_paid DECIMAL(10,2),
    currency CHAR(3) NOT NULL DEFAULT 'USD',
    invoice_number VARCHAR(50),
    
    -- Metadata
    metadata JSONB NOT NULL DEFAULT '{}',
    
    -- Timestamps
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
	updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes
CREATE UNIQUE INDEX idx_subscriptions_active_user ON user_subscriptions(user_id) 
    WHERE subscription_status = 'active';
CREATE INDEX idx_subscriptions_user ON user_subscriptions(user_id);
CREATE INDEX idx_subscriptions_status ON user_subscriptions(subscription_status, end_date);

-- Table : subscription_history
CREATE TABLE subscription_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    old_package_id UUID REFERENCES packages(id),
    new_package_id UUID REFERENCES packages(id),
    change_type VARCHAR(20) NOT NULL,  -- upgrade, downgrade, cancel, renew
    change_reason VARCHAR(100),
    effective_date DATE NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_sub_history_user ON subscription_history(user_id, created_at DESC);

ALTER TABLE user_subscriptions
ADD CONSTRAINT chk_user_subscriptions_trial_after_start
    CHECK (
        trial_ends_at IS NULL
        OR trial_ends_at >= start_date
    );

ALTER TABLE user_subscriptions
ADD CONSTRAINT chk_user_subscriptions_dates
    CHECK (end_date >= start_date),

ADD CONSTRAINT chk_user_subscriptions_trial_end
    CHECK (
        trial_ends_at IS NULL
        OR trial_ends_at <= end_date
    ),

ADD CONSTRAINT chk_user_subscriptions_cancelled_at
    CHECK (
        cancelled_at IS NULL
        OR cancelled_at >= created_at
    ),

ADD CONSTRAINT chk_user_subscriptions_next_payment
    CHECK (
        next_payment_date IS NULL
        OR next_payment_date >= start_date
    ),

ADD CONSTRAINT chk_user_subscriptions_last_payment
    CHECK (
        last_payment_date IS NULL
        OR last_payment_date >= created_at
    ),

ADD CONSTRAINT chk_user_subscriptions_amount_paid
    CHECK (
        amount_paid IS NULL
        OR amount_paid >= 0
    ),

ADD CONSTRAINT chk_user_subscriptions_currency_code
    CHECK (
        currency ~* '^[A-Z]{3}$'
    ),

ADD CONSTRAINT chk_user_subscriptions_metadata_shape
    CHECK (
        jsonb_typeof(metadata) = 'object'
    );







-- Trigger to maintain consistency between the user_subscription table and the users table regarding the below 4 columns that brings denormalization:
-- 1. package_code 
-- 2. max_accounts
-- 3. subscription_status
-- 4. subscription_end_date


CREATE OR REPLACE FUNCTION sync_user_subscription_data()
RETURNS TRIGGER AS $$
DECLARE
	pkg_record RECORD;
BEGIN
	-- Get package details
	SELECT package_code, max_accounts INTO pkg_record
	FROM packages WHERE id = NEW.package_id;

	-- Update the users table
	UPDATE users SET
		package_code = pkg_record.package_code,
		max_accounts = pkg_record.max_accounts,
		subscription_status = NEW.subscription_status,
		subscription_end_date = NEW.end_date
	WHERE id = NEW.user_id;

	RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- Trigger for INSERT/UPDATE
CREATE TRIGGER trigger_sync_user_subscription
    AFTER INSERT OR UPDATE ON user_subscriptions
    FOR EACH ROW
    EXECUTE FUNCTION sync_user_subscription_data();

-- Trigger for DELETE (when subscription ends)
CREATE OR REPLACE FUNCTION sync_user_subscription_delete()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE users SET
        package_code = NULL,
        max_accounts = 1,  -- Default
        subscription_status = NULL,
        subscription_end_date = NULL
    WHERE id = OLD.user_id;
    
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_sync_user_subscription_delete
    AFTER DELETE ON user_subscriptions
    FOR EACH ROW
    EXECUTE FUNCTION sync_user_subscription_delete();

-- In your user registration code:
INSERT INTO users (
    email, username, password_hash, 
    first_name, last_name,
    package_code, max_accounts  -- These get defaults
) VALUES (
    'user@example.com', 'johndoe', 'hash',
    'John', 'Doe',
    NULL, 1  -- Default package_code NULL, max_accounts = 1
);










-- Trading Account Tables

CREATE TABLE trading_accounts(
	id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
	user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
	account_number VARCHAR(30) UNIQUE,

	-- Account Details
	account_name VARCHAR(50) NOT NULL,
	account_type account_type NOT NULL,
	broker_name VARCHAR(50),
	broker_account_id VARCHAR(50),
	platform platform_type,
	currency CHAR(3) NOT NULL DEFAULT 'USD',

	-- Financials
	initial_balance DECIMAL(15,2) NOT NULL DEFAULT 0,
	current_balance DECIMAL(15,2) NOT NULL DEFAULT 0,
	leverage INTEGER,

	-- Derived Stats (Updated Periodically)
	total_trades INTEGER NOT NULL DEFAULT 0,
	winning_trades INTEGER NOT NULL DEFAULT 0,
	losing_trades INTEGER NOT NULL DEFAULT 0,
	win_rate DECIMAL(5,2) GENERATED ALWAYS AS (
		CASE
			WHEN total_trades > 0 THEN (winning_trades::DECIMAL / total_trades) * 100
			ELSE 0
		END			
	) STORED,

	profit_factor DECIMAL(10,2) GENERATED ALWAYS AS (
		CASE WHEN total_loss > 0 THEN total_profit / total_loss ELSE 0 END
	) STORED,

	avg_win DECIMAL(15,2) GENERATED ALWAYS AS (
		CASE WHEN winning_trades > 0 THEN total_profit / winning_trades ELSE 0 END
	) STORED,

	avg_loss DECIMAL(15,2) GENERATED ALWAYS AS (
		CASE WHEN losing_trades > 0 THEN total_loss / losing_trades ELSE 0 END
	) STORED,

	total_return_percentage DECIMAL(10,2) GENERATED ALWAYS AS (
		CASE WHEN initial_balance > 0 
			THEN ((current_balance - initial_balance) / initial_balance) * 100
			ELSE 0
		END
	) STORED,
	
	total_profit DECIMAL(15,2) NOT NULL DEFAULT 0,
	total_loss DECIMAL(15,2) NOT NULL DEFAULT 0,
	net_profit DECIMAL(15,2) NOT NULL DEFAULT 0,

	-- Status Flags
	is_active BOOLEAN NOT NULL DEFAULT TRUE,
	is_default BOOLEAN NOT NULL DEFAULT FALSE,
	is_archived BOOLEAN NOT NULL DEFAULT FALSE,

	-- Notes
	description TEXT,
	notes TEXT,
	metadata JSONB NOT NULL DEFAULT '{}',

	-- Timestamps
	created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
	updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
	closed_at TIMESTAMPTZ,
	deleted_at TIMESTAMPTZ,


	CONSTRAINT check_trade_counts CHECK (winning_trades + losing_trades <= total_trades),
	CONSTRAINT check_balance_non_negative CHECK (current_balance >= 0),
	CONSTRAINT check_account_name_length CHECK (char_length(account_name) >= 1),
	CONSTRAINT check_initial_balance_non_negative CHECK(initial_balance >= 0),
	CONSTRAINT check_leverage_positive CHECK (leverage IS NULL OR leverage >= 1)
);



-- Indexes
CREATE INDEX idx_accounts_user ON trading_accounts(user_id, is_active) WHERE deleted_at IS NULL;
CREATE INDEX idx_accounts_default ON trading_accounts(user_id) WHERE is_default = true AND deleted_at IS NULL;
CREATE INDEX idx_accounts_type ON trading_accounts(user_id, account_type) WHERE deleted_at IS NULL;

CREATE UNIQUE INDEX idx_accounts_number
ON trading_accounts(account_number)
WHERE deleted_at IS NULL AND account_number IS NOT NULL;



-- Trigger to check account limits
CREATE OR REPLACE FUNCTION check_account_limit()
RETURNS TRIGGER AS $$
DECLARE
    account_limit INTEGER;
    current_count INTEGER;
BEGIN
    SELECT max_accounts INTO account_limit 
    FROM users WHERE id = NEW.user_id;
    
    SELECT COUNT(*) INTO current_count
    FROM trading_accounts
    WHERE user_id = NEW.user_id AND deleted_at IS NULL;
    
    IF current_count >= account_limit THEN
        RAISE EXCEPTION 'Account limit reached (max: %)', account_limit;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_account_limit
    BEFORE INSERT ON trading_accounts
    FOR EACH ROW
    EXECUTE FUNCTION check_account_limit();



-- Table : account_balance_history
CREATE TABLE account_balance_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id UUID NOT NULL REFERENCES trading_accounts(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    
    -- Balance data
    balance DECIMAL(15,2) NOT NULL,
    change_amount DECIMAL(15,2) NOT NULL,
    change_type VARCHAR(20) NOT NULL,  -- deposit, withdrawal, trade, adjustment
    reference_id UUID,  -- Related trade ID if applicable
    reference_type VARCHAR(20),  -- trade, deposit, etc.
    
    -- Timestamp
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_balance_account ON account_balance_history(account_id, recorded_at DESC);
CREATE INDEX idx_balance_user ON account_balance_history(user_id, recorded_at DESC);
CREATE INDEX idx_balance_date ON account_balance_history(recorded_at);











CREATE OR REPLACE FUNCTION trg_account_balance_history_check_ownership()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM trading_accounts
        WHERE id = NEW.account_id
          AND user_id = NEW.user_id
    ) THEN
        RAISE EXCEPTION 'User does not own the referenced trading account';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_account_balance_history_ownership
    BEFORE INSERT OR UPDATE ON account_balance_history
    FOR EACH ROW
    EXECUTE FUNCTION trg_account_balance_history_check_ownership();




	






-- Table : account_daily_snapshots
CREATE TABLE account_daily_snapshots (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    account_id UUID NOT NULL REFERENCES trading_accounts(id) ON DELETE CASCADE,
    snapshot_date DATE NOT NULL,
    
    -- Balance
    starting_balance DECIMAL(15,2) NOT NULL,
    ending_balance DECIMAL(15,2) NOT NULL,
    daily_pnl DECIMAL(15,2) GENERATED ALWAYS AS (ending_balance - starting_balance) STORED,
    
    -- Trade stats
    trades_count INTEGER NOT NULL DEFAULT 0,
    winning_trades INTEGER NOT NULL DEFAULT 0,
    losing_trades INTEGER NOT NULL DEFAULT 0,
    
    -- Profit stats
    total_profit DECIMAL(15,2) NOT NULL DEFAULT 0,
    total_loss DECIMAL(15,2) NOT NULL DEFAULT 0,
    net_profit DECIMAL(15,2) GENERATED ALWAYS AS (total_profit - total_loss) STORED,
    
    -- Pips
    total_pips DECIMAL(15,1) NOT NULL DEFAULT 0,
    
    -- Drawdown
    peak_balance DECIMAL(15,2),
    trough_balance DECIMAL(15,2),
    max_drawdown DECIMAL(5,2) GENERATED ALWAYS AS (
        CASE 
            WHEN peak_balance > 0 THEN ((peak_balance - trough_balance) / peak_balance) * 100
            ELSE 0
        END
    ) STORED,
    
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes
CREATE UNIQUE INDEX idx_snapshots_account_date ON account_daily_snapshots(user_id, account_id, snapshot_date);
CREATE INDEX idx_snapshots_date ON account_daily_snapshots(user_id, snapshot_date DESC);





-- Trade Management Tables
CREATE TABLE strategies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,

    strategy_name VARCHAR(100) NOT NULL,
    description TEXT,
    strategy_type strategy_type,
    timeframes TEXT[],
    indicators JSONB,
    rules JSONB,

    -- Status / flags
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    is_system BOOLEAN NOT NULL DEFAULT FALSE,

    -- Cached stats (managed by trigger/job/app, not generated by subquery)
    usage_count INTEGER NOT NULL DEFAULT 0,
    win_rate DECIMAL(5,2),
    total_trades INTEGER NOT NULL DEFAULT 0,
    net_profit DECIMAL(15,2),
    profit_factor DECIMAL(10,2),

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_strategies_name_length
        CHECK (char_length(trim(strategy_name)) >= 1),

    CONSTRAINT chk_strategies_usage_count
        CHECK (usage_count >= 0),

    CONSTRAINT chk_strategies_total_trades
        CHECK (total_trades >= 0),

    CONSTRAINT chk_strategies_win_rate
        CHECK (win_rate IS NULL OR (win_rate >= 0 AND win_rate <= 100)),

    CONSTRAINT chk_strategies_indicators_json
        CHECK (indicators IS NULL OR jsonb_typeof(indicators) IN ('object', 'array')),

    CONSTRAINT chk_strategies_rules_json
        CHECK (rules IS NULL OR jsonb_typeof(rules) IN ('object', 'array')),

    CONSTRAINT chk_strategies_system_user
        CHECK (
            (is_system = TRUE AND user_id IS NULL)
            OR
            (is_system = FALSE)
        )
);

CREATE UNIQUE INDEX idx_strategies_user_name
    ON strategies(user_id, lower(strategy_name))
    WHERE user_id IS NOT NULL;

CREATE INDEX idx_strategies_user
    ON strategies(user_id)
    WHERE is_active = TRUE;

CREATE INDEX idx_strategies_system
    ON strategies(is_system)
    WHERE is_system = TRUE;

CREATE TRIGGER trg_strategies_set_updated_at
    BEFORE UPDATE ON strategies
    FOR EACH ROW
    EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE strategies IS 'User-defined and system-defined trading strategies';
COMMENT ON COLUMN strategies.win_rate IS 'Cached win rate, maintained by app/job/trigger';
COMMENT ON COLUMN strategies.total_trades IS 'Cached trade count, maintained by app/job/trigger';
COMMENT ON COLUMN strategies.net_profit IS 'Cached net profit, maintained by app/job/trigger';
COMMENT ON COLUMN strategies.profit_factor IS 'Cached profit factor, maintained by app/job/trigger';






























-- A helper table for instrument specifications such as forex, crypto, and many more

CREATE TABLE instrument_specs(
	id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
	symbol_pattern VARCHAR(50),
	instrument_type instrument_type,
	contract_size DECIMAL(15,2),
	point_value DECIMAL(10,2),
	pip_location DECIMAL(10,5),
	tick_size DECIMAL(10,5),
	tick_value DECIMAL(10,2),
	is_jpy_pair BOOLEAN DEFAULT FALSE,
	created_at TIMESTAMPTZ DEFAULT NOW(),
	updated_at TIMESTAMPTZ DEFAULT NOW()
);



-- =========================================================
-- HARDEN instrument_specs
-- =========================================================

ALTER TABLE instrument_specs
    ALTER COLUMN symbol_pattern SET NOT NULL,
    ALTER COLUMN instrument_type SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_instrument_specs_symbol_type
ON instrument_specs (UPPER(symbol_pattern), instrument_type);

DROP TRIGGER IF EXISTS trg_instrument_specs_set_updated_at ON instrument_specs;

CREATE TRIGGER trg_instrument_specs_set_updated_at
    BEFORE UPDATE ON instrument_specs
    FOR EACH ROW
    EXECUTE FUNCTION set_updated_at();






SELECT * FROM instrument_specs;


-- Populating the table with common instruements

INSERT INTO instrument_specs (symbol_pattern, instrument_type, contract_size, point_value, pip_location, tick_size, tick_value, is_jpy_pair) VALUES
-- Forex Majors
('EURUSD', 'forex', 100000, 10.00, 0.0001, 0.00001, 1.00, FALSE),
('GBPUSD', 'forex', 100000, 10.00, 0.0001, 0.00001, 1.00, FALSE),
('USDJPY', 'forex', 100000, 9.50, 0.01, 0.001, 9.50, TRUE),
('AUDUSD', 'forex', 100000, 10.00, 0.0001, 0.00001, 1.00, FALSE),
('USDCAD', 'forex', 100000, 10.00, 0.0001, 0.00001, 1.00, FALSE),
('USDCHF', 'forex', 100000, 10.00, 0.0001, 0.00001, 1.00, FALSE),
('NZDUSD', 'forex', 100000, 10.00, 0.0001, 0.00001, 1.00, FALSE),

-- Forex Crosses
('EURGBP', 'forex', 100000, 10.00, 0.0001, 0.00001, 1.00, FALSE),
('EURJPY', 'forex', 100000, 9.50, 0.01, 0.001, 9.50, TRUE),
('GBPJPY', 'forex', 100000, 9.50, 0.01, 0.001, 9.50, TRUE),
('AUDJPY', 'forex', 100000, 9.50, 0.01, 0.001, 9.50, TRUE),

-- Indices
('US30', 'index', 1, 5.00, 1.0, 1.0, 5.00, FALSE),
('DJI', 'index', 1, 5.00, 1.0, 1.0, 5.00, FALSE),
('SPX', 'index', 1, 0.10, 0.1, 0.1, 0.10, FALSE),
('SP500', 'index', 1, 0.10, 0.1, 0.1, 0.10, FALSE),
('NAS100', 'index', 1, 0.25, 0.25, 0.25, 0.25, FALSE),
('NDX', 'index', 1, 0.25, 0.25, 0.25, 0.25, FALSE),
('JP225', 'index', 1, 1.00, 1.0, 1.0, 1.00, FALSE),
('NIKKEI', 'index', 1, 1.00, 1.0, 1.0, 1.00, FALSE),
('DE40', 'index', 1, 0.50, 0.5, 0.5, 0.50, FALSE),
('DAX', 'index', 1, 0.50, 0.5, 0.5, 0.50, FALSE),
('UK100', 'index', 1, 0.50, 0.5, 0.5, 0.50, FALSE),
('FTSE', 'index', 1, 0.50, 0.5, 0.5, 0.50, FALSE),

-- Crypto
('BTC', 'crypto', 1, 0.10, 0.1, 0.1, 0.10, FALSE),
('BITCOIN', 'crypto', 1, 0.10, 0.1, 0.1, 0.10, FALSE),
('ETH', 'crypto', 1, 0.01, 0.01, 0.01, 0.01, FALSE),
('ETHEREUM', 'crypto', 1, 0.01, 0.01, 0.01, 0.01, FALSE),
('LTC', 'crypto', 1, 0.001, 0.001, 0.001, 0.001, FALSE),
('XRP', 'crypto', 1, 0.0001, 0.0001, 0.0001, 0.0001, FALSE),

-- Commodities
('XAUUSD', 'commodity', 100, 0.10, 0.01, 0.01, 0.10, FALSE),
('GOLD', 'commodity', 100, 0.10, 0.01, 0.01, 0.10, FALSE),
('XAGUSD', 'commodity', 5000, 0.50, 0.001, 0.001, 0.50, FALSE),
('SILVER', 'commodity', 5000, 0.50, 0.001, 0.001, 0.50, FALSE),
('USOIL', 'commodity', 1000, 10.00, 0.01, 0.01, 10.00, FALSE),
('WTI', 'commodity', 1000, 10.00, 0.01, 0.01, 10.00, FALSE),
('BRENT', 'commodity', 1000, 10.00, 0.01, 0.01, 10.00, FALSE),
('NATGAS', 'commodity', 10000, 10.00, 0.001, 0.001, 10.00, FALSE),
('COPPER', 'commodity', 25000, 2.50, 0.001, 0.001, 2.50, FALSE),

-- Futures (E-mini)
('ES', 'future', 1, 50.00, 0.25, 0.25, 12.50, FALSE),    -- S&P 500 E-mini
('NQ', 'future', 1, 20.00, 0.25, 0.25, 5.00, FALSE),      -- Nasdaq E-mini
('YM', 'future', 1, 5.00, 1.0, 1.0, 5.00, FALSE),         -- Dow E-mini
('RTY', 'future', 1, 5.00, 0.10, 0.10, 0.50, FALSE),      -- Russell 2000
('CL', 'future', 1000, 10.00, 0.01, 0.01, 10.00, FALSE),  -- Crude Oil
('GC', 'future', 100, 10.00, 0.10, 0.10, 10.00, FALSE),   -- Gold
('SI', 'future', 5000, 5.00, 0.001, 0.001, 5.00, FALSE),  -- Silver
('ZC', 'future', 5000, 5.00, 0.01, 0.01, 5.00, FALSE);    -- Corn
























-- =========================================================
-- Table : trades
-- =========================================================
-- HELPER FUNCTIONS
-- =========================================================

-- 1) Contract size / exposure multiplier
CREATE OR REPLACE FUNCTION trade_contract_size(
    p_instrument_type instrument_type,
    p_symbol VARCHAR
)
RETURNS NUMERIC
LANGUAGE SQL
IMMUTABLE
AS $$
    SELECT CASE p_instrument_type
        WHEN 'forex' THEN 100000
        WHEN 'stock' THEN 1
        WHEN 'index' THEN 1
        WHEN 'crypto' THEN 1
        WHEN 'commodity' THEN
            CASE
                WHEN UPPER(p_symbol) IN ('XAUUSD', 'GOLD') THEN 100
                WHEN UPPER(p_symbol) IN ('XAGUSD', 'SILVER') THEN 5000
                WHEN UPPER(p_symbol) IN ('USOIL', 'WTI', 'BRENT') THEN 1000
                WHEN UPPER(p_symbol) = 'NATGAS' THEN 10000
                WHEN UPPER(p_symbol) = 'COPPER' THEN 25000
                ELSE 100
            END
        WHEN 'ETF' THEN 1
        WHEN 'bond' THEN 1000
        WHEN 'option' THEN 100
        WHEN 'future' THEN
            CASE
                WHEN UPPER(p_symbol) LIKE '%ES%' THEN 1
                WHEN UPPER(p_symbol) LIKE '%NQ%' THEN 1
                WHEN UPPER(p_symbol) LIKE '%YM%' THEN 1
                WHEN UPPER(p_symbol) LIKE '%RTY%' THEN 1
                WHEN UPPER(p_symbol) IN ('CL', 'CRUDE') THEN 1000
                WHEN UPPER(p_symbol) IN ('GC', 'GOLD') THEN 100
                WHEN UPPER(p_symbol) IN ('SI', 'SILVER') THEN 5000
                ELSE 1
            END
        WHEN 'CFD' THEN
            CASE
                WHEN UPPER(p_symbol) IN ('US30', 'DJI', 'SPX', 'SP500', 'NAS100', 'NDX') THEN 1
                WHEN UPPER(p_symbol) IN ('XAUUSD', 'GOLD') THEN 100
                WHEN UPPER(p_symbol) IN ('BTC', 'BITCOIN') THEN 1
                ELSE 1
            END
        ELSE 1
    END;
$$;


-- 2) Point-value multiplier for P/L
CREATE OR REPLACE FUNCTION trade_point_value(
    p_instrument_type instrument_type,
    p_symbol VARCHAR
)
RETURNS NUMERIC
LANGUAGE SQL
IMMUTABLE
AS $$
    SELECT CASE p_instrument_type
        WHEN 'forex' THEN 100000
        WHEN 'stock' THEN 1
        WHEN 'index' THEN
            CASE
                WHEN UPPER(p_symbol) IN ('US30', 'DJI') THEN 5
                WHEN UPPER(p_symbol) IN ('SPX', 'SP500') THEN 0.10
                WHEN UPPER(p_symbol) IN ('NAS100', 'NDX') THEN 0.25
                WHEN UPPER(p_symbol) IN ('JP225', 'NIKKEI') THEN 1
                WHEN UPPER(p_symbol) IN ('DE40', 'DAX') THEN 0.50
                WHEN UPPER(p_symbol) IN ('UK100', 'FTSE') THEN 0.50
                ELSE 1
            END
        WHEN 'crypto' THEN 1
        WHEN 'commodity' THEN
            CASE
                WHEN UPPER(p_symbol) IN ('XAUUSD', 'GOLD') THEN 100
                WHEN UPPER(p_symbol) IN ('XAGUSD', 'SILVER') THEN 5000
                WHEN UPPER(p_symbol) IN ('USOIL', 'WTI', 'BRENT') THEN 1000
                WHEN UPPER(p_symbol) = 'NATGAS' THEN 10000
                WHEN UPPER(p_symbol) = 'COPPER' THEN 25000
                ELSE 100
            END
        WHEN 'ETF' THEN 1
        WHEN 'bond' THEN 1000
        WHEN 'option' THEN 100
        WHEN 'future' THEN
            CASE
                WHEN UPPER(p_symbol) LIKE '%ES%' THEN 50
                WHEN UPPER(p_symbol) LIKE '%NQ%' THEN 20
                WHEN UPPER(p_symbol) LIKE '%YM%' THEN 5
                WHEN UPPER(p_symbol) LIKE '%RTY%' THEN 5
                WHEN UPPER(p_symbol) IN ('CL', 'CRUDE') THEN 1000
                WHEN UPPER(p_symbol) IN ('GC', 'GOLD') THEN 100
                WHEN UPPER(p_symbol) IN ('SI', 'SILVER') THEN 5000
                ELSE 1
            END
        WHEN 'CFD' THEN
            CASE
                WHEN UPPER(p_symbol) IN ('US30', 'DJI') THEN 5
                WHEN UPPER(p_symbol) IN ('SPX', 'SP500') THEN 0.10
                WHEN UPPER(p_symbol) IN ('NAS100', 'NDX') THEN 0.25
                WHEN UPPER(p_symbol) IN ('XAUUSD', 'GOLD') THEN 100
                WHEN UPPER(p_symbol) IN ('BTC', 'BITCOIN') THEN 1
                ELSE 1
            END
        ELSE 1
    END;
$$;


-- 3) Smallest meaningful price increment for each instrument
CREATE OR REPLACE FUNCTION trade_price_increment(
    p_instrument_type instrument_type,
    p_symbol VARCHAR
)
RETURNS NUMERIC
LANGUAGE SQL
IMMUTABLE
AS $$
    SELECT CASE p_instrument_type
        WHEN 'forex' THEN
            CASE
                WHEN UPPER(p_symbol) LIKE '%JPY' THEN 0.01
                ELSE 0.0001
            END
        WHEN 'stock' THEN 0.01
        WHEN 'index' THEN
            CASE
                WHEN UPPER(p_symbol) IN ('US30', 'DJI') THEN 1.0
                WHEN UPPER(p_symbol) IN ('SPX', 'SP500') THEN 0.1
                WHEN UPPER(p_symbol) IN ('NAS100', 'NDX') THEN 0.25
                WHEN UPPER(p_symbol) IN ('JP225', 'NIKKEI') THEN 1.0
                WHEN UPPER(p_symbol) IN ('DE40', 'DAX') THEN 0.5
                WHEN UPPER(p_symbol) IN ('UK100', 'FTSE') THEN 0.5
                ELSE 0.1
            END
        WHEN 'crypto' THEN
            CASE
                WHEN UPPER(p_symbol) IN ('BTC', 'BITCOIN') THEN 0.01
                WHEN UPPER(p_symbol) IN ('ETH', 'ETHEREUM') THEN 0.01
                ELSE 0.0001
            END
        WHEN 'commodity' THEN
            CASE
                WHEN UPPER(p_symbol) IN ('XAUUSD', 'GOLD') THEN 0.01
                WHEN UPPER(p_symbol) IN ('XAGUSD', 'SILVER') THEN 0.001
                WHEN UPPER(p_symbol) IN ('USOIL', 'WTI', 'BRENT') THEN 0.01
                WHEN UPPER(p_symbol) = 'NATGAS' THEN 0.001
                WHEN UPPER(p_symbol) = 'COPPER' THEN 0.0005
                ELSE 0.01
            END
        WHEN 'ETF' THEN 0.01
        WHEN 'bond' THEN 0.01
        WHEN 'option' THEN 0.01
        WHEN 'future' THEN
            CASE
                WHEN UPPER(p_symbol) LIKE '%ES%' THEN 0.25
                WHEN UPPER(p_symbol) LIKE '%NQ%' THEN 0.25
                WHEN UPPER(p_symbol) LIKE '%YM%' THEN 1.0
                WHEN UPPER(p_symbol) LIKE '%RTY%' THEN 0.10
                WHEN UPPER(p_symbol) IN ('CL', 'CRUDE') THEN 0.01
                WHEN UPPER(p_symbol) IN ('GC', 'GOLD') THEN 0.10
                WHEN UPPER(p_symbol) IN ('SI', 'SILVER') THEN 0.005
                ELSE 0.01
            END
        WHEN 'CFD' THEN
            CASE
                WHEN UPPER(p_symbol) IN ('US30', 'DJI') THEN 1.0
                WHEN UPPER(p_symbol) IN ('SPX', 'SP500') THEN 0.1
                WHEN UPPER(p_symbol) IN ('NAS100', 'NDX') THEN 0.25
                WHEN UPPER(p_symbol) IN ('XAUUSD', 'GOLD') THEN 0.01
                WHEN UPPER(p_symbol) IN ('BTC', 'BITCOIN') THEN 0.01
                ELSE 0.01
            END
        ELSE 0.01
    END;
$$;


-- 4) Generalized increment movement for all instruments
CREATE OR REPLACE FUNCTION trade_increments_moved(
    p_entry_price NUMERIC,
    p_exit_price NUMERIC,
    p_instrument_type instrument_type,
    p_symbol VARCHAR
)
RETURNS NUMERIC
LANGUAGE SQL
IMMUTABLE
AS $$
    SELECT CASE
        WHEN p_exit_price IS NULL THEN NULL
        ELSE ABS(p_exit_price - p_entry_price) / NULLIF(trade_price_increment(p_instrument_type, p_symbol), 0)
    END;
$$;


-- 5) Forex-only pips moved
CREATE OR REPLACE FUNCTION trade_pips_moved(
    p_entry_price NUMERIC,
    p_exit_price NUMERIC,
    p_instrument_type instrument_type,
    p_symbol VARCHAR
)
RETURNS NUMERIC
LANGUAGE SQL
IMMUTABLE
AS $$
    SELECT CASE
        WHEN p_exit_price IS NULL THEN NULL
        WHEN p_instrument_type = 'forex'
            THEN ABS(p_exit_price - p_entry_price) / NULLIF(trade_price_increment(p_instrument_type, p_symbol), 0)
        ELSE NULL
    END;
$$;



-- =========================================================
-- TABLE : trades
-- =========================================================

CREATE TABLE trades (
    id UUID NOT NULL DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    account_id UUID NOT NULL REFERENCES trading_accounts(id) ON DELETE CASCADE,

    -- References
    trade_number VARCHAR(30),
    trade_reference VARCHAR(50),
    strategy_id UUID REFERENCES strategies(id) ON DELETE SET NULL,

    -- Instrument
    symbol VARCHAR(20) NOT NULL,
    instrument_type instrument_type NOT NULL,
    instrument_category VARCHAR(30),

    -- Trade Details
    trade_type trade_direction NOT NULL,
    position_type position_type NOT NULL,
    quantity NUMERIC(20, 4) NOT NULL,

    -- Prices
    entry_price NUMERIC(20, 8) NOT NULL,
    exit_price NUMERIC(20, 8),
    stop_loss NUMERIC(20, 8),
    take_profit NUMERIC(20, 8),

    -- Financials
    fees NUMERIC(20, 2) NOT NULL DEFAULT 0,
    swap NUMERIC(20, 2) NOT NULL DEFAULT 0,
    taxes NUMERIC(20, 2) NOT NULL DEFAULT 0,

    -- =====================================================
    -- GENERATED FINANCIAL COLUMNS
    -- =====================================================

    contract_size NUMERIC(20, 4) GENERATED ALWAYS AS (
        trade_contract_size(instrument_type, symbol)
    ) STORED,

    gross_profit NUMERIC(20, 2) GENERATED ALWAYS AS (
        CASE
            WHEN exit_price IS NOT NULL THEN
                CASE
                    WHEN trade_type = 'buy' THEN
                        (exit_price - entry_price) * quantity * trade_point_value(instrument_type, symbol)
                    ELSE
                        (entry_price - exit_price) * quantity * trade_point_value(instrument_type, symbol)
                END
            ELSE NULL
        END
    ) STORED,

    net_profit NUMERIC(20, 2) GENERATED ALWAYS AS (
        CASE
            WHEN exit_price IS NOT NULL THEN
                (
                    CASE
                        WHEN trade_type = 'buy' THEN
                            (exit_price - entry_price) * quantity * trade_point_value(instrument_type, symbol)
                        ELSE
                            (entry_price - exit_price) * quantity * trade_point_value(instrument_type, symbol)
                    END
                ) - fees - swap - taxes
            ELSE NULL
        END
    ) STORED,

    profit_percentage NUMERIC(12, 4) GENERATED ALWAYS AS (
        CASE
            WHEN exit_price IS NOT NULL
                 AND entry_price > 0
                 AND quantity > 0
                 AND (entry_price * quantity * trade_contract_size(instrument_type, symbol)) > 0
            THEN
                (
                    (
                        (
                            CASE
                                WHEN trade_type = 'buy' THEN
                                    (exit_price - entry_price) * quantity * trade_point_value(instrument_type, symbol)
                                ELSE
                                    (entry_price - exit_price) * quantity * trade_point_value(instrument_type, symbol)
                            END
                        ) - fees - swap - taxes
                    )
                    /
                    NULLIF(entry_price * quantity * trade_contract_size(instrument_type, symbol), 0)
                ) * 100
            ELSE NULL
        END
    ) STORED,

    risk_amount NUMERIC(20, 2) GENERATED ALWAYS AS (
        CASE
            WHEN stop_loss IS NOT NULL THEN
                ABS(entry_price - stop_loss) * quantity * trade_point_value(instrument_type, symbol)
            ELSE 0
        END
    ) STORED,

    reward_amount NUMERIC(20, 2) GENERATED ALWAYS AS (
        CASE
            WHEN take_profit IS NOT NULL THEN
                ABS(take_profit - entry_price) * quantity * trade_point_value(instrument_type, symbol)
            ELSE 0
        END
    ) STORED,

    risk_reward_ratio NUMERIC(12, 4) GENERATED ALWAYS AS (
        CASE
            WHEN stop_loss IS NOT NULL
                 AND take_profit IS NOT NULL
                 AND (
                     ABS(entry_price - stop_loss) * quantity * trade_point_value(instrument_type, symbol)
                 ) > 0
            THEN
                (
                    ABS(take_profit - entry_price) * quantity * trade_point_value(instrument_type, symbol)
                ) /
                NULLIF(
                    ABS(entry_price - stop_loss) * quantity * trade_point_value(instrument_type, symbol),
                    0
                )
            ELSE NULL
        END
    ) STORED,

    position_value NUMERIC(20, 2) GENERATED ALWAYS AS (
        entry_price * quantity * trade_contract_size(instrument_type, symbol)
    ) STORED,

    -- Generalized price movement columns for all instruments
    price_increment NUMERIC(20, 8) GENERATED ALWAYS AS (
        trade_price_increment(instrument_type, symbol)
    ) STORED,

    increments_moved NUMERIC(20, 2) GENERATED ALWAYS AS (
        CASE
            WHEN exit_price IS NOT NULL THEN
                trade_increments_moved(entry_price, exit_price, instrument_type, symbol)
            ELSE NULL
        END
    ) STORED,

    -- Forex-only pips column
    pips_moved NUMERIC(20, 2) GENERATED ALWAYS AS (
        CASE
            WHEN exit_price IS NOT NULL AND instrument_type = 'forex' THEN
                trade_pips_moved(entry_price, exit_price, instrument_type, symbol)
            ELSE NULL
        END
    ) STORED,

    is_winning BOOLEAN GENERATED ALWAYS AS (
        CASE
            WHEN exit_price IS NOT NULL THEN
                (
                    (
                        CASE
                            WHEN trade_type = 'buy' THEN
                                (exit_price - entry_price) * quantity * trade_point_value(instrument_type, symbol)
                            ELSE
                                (entry_price - exit_price) * quantity * trade_point_value(instrument_type, symbol)
                        END
                    ) - fees - swap - taxes
                ) > 0
            ELSE NULL
        END
    ) STORED,

    is_losing BOOLEAN GENERATED ALWAYS AS (
        CASE
            WHEN exit_price IS NOT NULL THEN
                (
                    (
                        CASE
                            WHEN trade_type = 'buy' THEN
                                (exit_price - entry_price) * quantity * trade_point_value(instrument_type, symbol)
                            ELSE
                                (entry_price - exit_price) * quantity * trade_point_value(instrument_type, symbol)
                        END
                    ) - fees - swap - taxes
                ) < 0
            ELSE NULL
        END
    ) STORED,

    is_breakeven BOOLEAN GENERATED ALWAYS AS (
        CASE
            WHEN exit_price IS NOT NULL THEN
                (
                    (
                        CASE
                            WHEN trade_type = 'buy' THEN
                                (exit_price - entry_price) * quantity * trade_point_value(instrument_type, symbol)
                            ELSE
                                (entry_price - exit_price) * quantity * trade_point_value(instrument_type, symbol)
                        END
                    ) - fees - swap - taxes
                ) = 0
            ELSE NULL
        END
    ) STORED,

    -- =====================================================
    -- TIMING COLUMNS
    -- =====================================================

    entry_date TIMESTAMPTZ NOT NULL,
    exit_date TIMESTAMPTZ,

    duration_seconds BIGINT GENERATED ALWAYS AS (
        CASE
            WHEN exit_date IS NOT NULL THEN EXTRACT(EPOCH FROM (exit_date - entry_date))::BIGINT
            ELSE NULL
        END
    ) STORED,

    duration_minutes INTEGER GENERATED ALWAYS AS (
        CASE
            WHEN exit_date IS NOT NULL THEN (EXTRACT(EPOCH FROM (exit_date - entry_date)) / 60)::INTEGER
            ELSE NULL
        END
    ) STORED,

    duration_hours NUMERIC(12, 4) GENERATED ALWAYS AS (
        CASE
            WHEN exit_date IS NOT NULL THEN EXTRACT(EPOCH FROM (exit_date - entry_date)) / 3600.0
            ELSE NULL
        END
    ) STORED,

    -- Status
    status trade_status NOT NULL DEFAULT 'open',
    exit_reason exit_reason,

    -- =====================================================
    -- SESSION ANALYSIS
    -- =====================================================

    session trading_session GENERATED ALWAYS AS (
        CASE
            WHEN EXTRACT(ISODOW FROM entry_date AT TIME ZONE 'UTC') IN (6, 7) THEN 'weekend'::trading_session
            WHEN EXTRACT(HOUR FROM entry_date AT TIME ZONE 'UTC') BETWEEN 0 AND 2 THEN 'pacific'::trading_session
            WHEN EXTRACT(HOUR FROM entry_date AT TIME ZONE 'UTC') BETWEEN 3 AND 6 THEN 'tokyo'::trading_session
            WHEN EXTRACT(HOUR FROM entry_date AT TIME ZONE 'UTC') BETWEEN 7 AND 8 THEN 'frankfurt'::trading_session
            WHEN EXTRACT(HOUR FROM entry_date AT TIME ZONE 'UTC') BETWEEN 9 AND 12 THEN 'london'::trading_session
            WHEN EXTRACT(HOUR FROM entry_date AT TIME ZONE 'UTC') BETWEEN 13 AND 21 THEN 'new_york'::trading_session
            ELSE 'overnight'::trading_session
        END
    ) STORED,

    day_of_week INTEGER GENERATED ALWAYS AS (
        EXTRACT(DOW FROM entry_date AT TIME ZONE 'UTC')::INTEGER
    ) STORED,

    week_of_year INTEGER GENERATED ALWAYS AS (
        EXTRACT(WEEK FROM entry_date AT TIME ZONE 'UTC')::INTEGER
    ) STORED,

    month INTEGER GENERATED ALWAYS AS (
        EXTRACT(MONTH FROM entry_date AT TIME ZONE 'UTC')::INTEGER
    ) STORED,

    quarter INTEGER GENERATED ALWAYS AS (
        EXTRACT(QUARTER FROM entry_date AT TIME ZONE 'UTC')::INTEGER
    ) STORED,

    year INTEGER GENERATED ALWAYS AS (
        EXTRACT(YEAR FROM entry_date AT TIME ZONE 'UTC')::INTEGER
    ) STORED,

    -- =====================================================
    -- NOTES AND TAGS
    -- =====================================================

    strategy_name VARCHAR(100),
    notes TEXT,

    -- Timestamps
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ,

    PRIMARY KEY (id, entry_date),

    -- =====================================================
    -- CHECK CONSTRAINTS
    -- =====================================================

    CONSTRAINT chk_trades_quantity_positive
        CHECK (quantity > 0),

    CONSTRAINT chk_trades_entry_price_positive
        CHECK (entry_price > 0),

    CONSTRAINT chk_trades_exit_price_positive
        CHECK (exit_price IS NULL OR exit_price > 0),

    CONSTRAINT chk_trades_stop_loss_positive
        CHECK (stop_loss IS NULL OR stop_loss > 0),

    CONSTRAINT chk_trades_take_profit_positive
        CHECK (take_profit IS NULL OR take_profit > 0),

    CONSTRAINT chk_trades_fees_non_negative
        CHECK (fees >= 0),

    CONSTRAINT chk_trades_taxes_non_negative
        CHECK (taxes >= 0),

    CONSTRAINT chk_trades_exit_after_entry
        CHECK (exit_date IS NULL OR exit_date >= entry_date),

    CONSTRAINT chk_trades_direction_position_match
        CHECK (
            (trade_type = 'buy' AND position_type = 'long')
            OR
            (trade_type = 'sell' AND position_type = 'short')
        ),

    CONSTRAINT chk_trades_status_consistency
        CHECK (
            (status IN ('open', 'pending', 'cancelled') AND exit_price IS NULL AND exit_date IS NULL)
            OR
            (status = 'closed' AND exit_price IS NOT NULL AND exit_date IS NOT NULL)
        ),

    CONSTRAINT chk_trades_exit_reason_consistency
        CHECK (
            (status IN ('open', 'pending') AND exit_reason IS NULL)
            OR
            (status IN ('closed', 'cancelled') AND exit_reason IS NOT NULL)
        )
) PARTITION BY RANGE (entry_date);


-- =========================================================
-- TRIGGER
-- =========================================================

CREATE TRIGGER trg_trades_set_updated_at
BEFORE UPDATE ON trades
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();


-- =========================================================
-- INDEXES
-- =========================================================

CREATE INDEX idx_trades_user_id ON trades (user_id);
CREATE INDEX idx_trades_account_id ON trades (account_id);
CREATE INDEX idx_trades_strategy_id ON trades (strategy_id);
CREATE INDEX idx_trades_symbol ON trades (symbol);
CREATE INDEX idx_trades_status ON trades (status);
CREATE INDEX idx_trades_entry_date ON trades (entry_date);
CREATE INDEX idx_trades_exit_date ON trades (exit_date) WHERE exit_date IS NOT NULL;
CREATE INDEX idx_trades_user_account_entry_date ON trades (user_id, account_id, entry_date DESC);
CREATE INDEX idx_trades_user_status_entry_date ON trades (user_id, status, entry_date DESC);
CREATE INDEX idx_trades_is_winning ON trades (user_id, is_winning) WHERE is_winning IS NOT NULL;
CREATE INDEX idx_trades_strategy_name ON trades (strategy_name) WHERE strategy_name IS NOT NULL;


-- =========================================================
-- COMMENTS
-- =========================================================

COMMENT ON TABLE trades IS 'Core trading records table with comprehensive generated columns';
COMMENT ON COLUMN trades.contract_size IS 'Number of units per 1 lot/contract';
COMMENT ON COLUMN trades.gross_profit IS 'Profit before fees, swap, and taxes';
COMMENT ON COLUMN trades.net_profit IS 'Profit after all costs';
COMMENT ON COLUMN trades.profit_percentage IS 'Return on notional exposure percentage';
COMMENT ON COLUMN trades.risk_amount IS 'Potential loss if stop loss is hit';
COMMENT ON COLUMN trades.reward_amount IS 'Potential profit if take profit is hit';
COMMENT ON COLUMN trades.risk_reward_ratio IS 'Reward divided by risk';
COMMENT ON COLUMN trades.position_value IS 'Total notional exposure';
COMMENT ON COLUMN trades.price_increment IS 'Smallest meaningful price movement unit for the instrument';
COMMENT ON COLUMN trades.increments_moved IS 'Number of price increments moved between entry and exit for all instruments';
COMMENT ON COLUMN trades.pips_moved IS 'Forex-only pip movement';
COMMENT ON COLUMN trades.is_winning IS 'True if net profit is greater than zero';
COMMENT ON COLUMN trades.is_losing IS 'True if net profit is less than zero';
COMMENT ON COLUMN trades.is_breakeven IS 'True if net profit equals zero';





























































































-- =========================================================
-- TABLE: tags
-- =========================================================

CREATE TABLE tags (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Tag details
    name VARCHAR(50) NOT NULL,
    color VARCHAR(7) NOT NULL DEFAULT '#808080',
    description VARCHAR(200),

    -- Usage tracking
    usage_count INTEGER NOT NULL DEFAULT 0,

    -- Timestamps
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ,

    -- Constraints
    CONSTRAINT chk_tags_name_length CHECK (char_length(trim(name)) >= 1),
    CONSTRAINT chk_tags_color_format CHECK (color ~* '^#[0-9A-F]{6}$'),
    CONSTRAINT chk_tags_usage_count CHECK (usage_count >= 0)
);

-- Partial unique index for active tags only, case-insensitive
CREATE UNIQUE INDEX uq_tags_user_name_active
ON tags (user_id, lower(name))
WHERE deleted_at IS NULL;

-- Indexes
CREATE INDEX idx_tags_user ON tags(user_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_tags_usage ON tags(user_id, usage_count DESC) WHERE deleted_at IS NULL;
CREATE INDEX idx_tags_name ON tags(user_id, lower(name)) WHERE deleted_at IS NULL;

-- Trigger for updated_at
CREATE TRIGGER trg_tags_set_updated_at
    BEFORE UPDATE ON tags
    FOR EACH ROW
    EXECUTE FUNCTION set_updated_at();

-- Comments
COMMENT ON TABLE tags IS 'User-defined tags for categorizing trades and journal content';
COMMENT ON COLUMN tags.name IS 'Tag name such as Scalping, News, Breakout';
COMMENT ON COLUMN tags.color IS 'HEX color code for UI display';
COMMENT ON COLUMN tags.usage_count IS 'Number of linked records using this tag';


-- =========================================================
-- TABLE: trade_tags
-- =========================================================

CREATE TABLE trade_tags (
    trade_id UUID NOT NULL,
    trade_entry_date TIMESTAMPTZ NOT NULL,
    tag_id UUID NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    PRIMARY KEY (trade_id, trade_entry_date, tag_id),

    FOREIGN KEY (trade_id, trade_entry_date)
        REFERENCES trades(id, entry_date) ON DELETE CASCADE
);

-- Indexes
CREATE INDEX idx_trade_tags_tag ON trade_tags(tag_id, trade_id, trade_entry_date);
CREATE INDEX idx_trade_tags_user ON trade_tags(user_id, created_at DESC);
CREATE INDEX idx_trade_tags_trade ON trade_tags(trade_id, trade_entry_date);

-- Trigger function to update tag usage count
CREATE OR REPLACE FUNCTION update_tag_usage_count()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE tags
        SET usage_count = usage_count + 1
        WHERE id = NEW.tag_id;
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE tags
        SET usage_count = GREATEST(usage_count - 1, 0)
        WHERE id = OLD.tag_id;
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Triggers for maintaining usage_count
CREATE TRIGGER trg_trade_tags_insert
    AFTER INSERT ON trade_tags
    FOR EACH ROW
    EXECUTE FUNCTION update_tag_usage_count();

CREATE TRIGGER trg_trade_tags_delete
    AFTER DELETE ON trade_tags
    FOR EACH ROW
    EXECUTE FUNCTION update_tag_usage_count();

-- Comments
COMMENT ON TABLE trade_tags IS 'Junction table linking trades to user-defined tags';
COMMENT ON COLUMN trade_tags.trade_id IS 'References trades.id';
COMMENT ON COLUMN trade_tags.trade_entry_date IS 'References trades.entry_date for partition-aware foreign key';
COMMENT ON COLUMN trade_tags.user_id IS 'Owner of the trade-tag relationship; should match both trade owner and tag owner';


-- =========================================================
-- OPTIONAL ENUM FOR TRADE ANNOTATIONS
-- =========================================================
-- Recommended:
-- CREATE TYPE trade_annotation_type AS ENUM
-- ('entry_note', 'exit_note', 'lesson', 'reminder', 'analysis', 'observation');


-- =========================================================
-- TABLE: trade_annotations
-- =========================================================

CREATE TABLE trade_annotations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    trade_id UUID NOT NULL,
    trade_entry_date TIMESTAMPTZ NOT NULL,

    -- Annotation details
    annotation_type VARCHAR(30) NOT NULL,
    title VARCHAR(200),
    content TEXT NOT NULL,
    color VARCHAR(7),

    -- Flags
    is_pinned BOOLEAN NOT NULL DEFAULT false,

    -- Attachments
    attachments TEXT[],

    -- Timestamps
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ,

    FOREIGN KEY (trade_id, trade_entry_date)
        REFERENCES trades(id, entry_date) ON DELETE CASCADE,

    -- Constraints
    CONSTRAINT chk_trade_annotations_type CHECK (
        annotation_type IN ('entry_note', 'exit_note', 'lesson', 'reminder', 'analysis', 'observation')
    ),
    CONSTRAINT chk_trade_annotations_title_length CHECK (
        title IS NULL OR char_length(trim(title)) >= 1
    ),
    CONSTRAINT chk_trade_annotations_color CHECK (
        color IS NULL OR color ~* '^#[0-9A-F]{6}$'
    ),
    CONSTRAINT chk_trade_annotations_content CHECK (
        char_length(trim(content)) >= 1
    )
);

-- Indexes
CREATE INDEX idx_trade_annotations_trade
    ON trade_annotations(user_id, trade_id, trade_entry_date)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_trade_annotations_type
    ON trade_annotations(user_id, annotation_type)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_trade_annotations_pinned
    ON trade_annotations(user_id, is_pinned)
    WHERE is_pinned = true AND deleted_at IS NULL;

CREATE INDEX idx_trade_annotations_created
    ON trade_annotations(user_id, created_at DESC)
    WHERE deleted_at IS NULL;

-- Trigger for updated_at
CREATE TRIGGER trg_trade_annotations_set_updated_at
    BEFORE UPDATE ON trade_annotations
    FOR EACH ROW
    EXECUTE FUNCTION set_updated_at();

-- Comments
COMMENT ON TABLE trade_annotations IS 'Personal notes and annotations attached to specific trades';
COMMENT ON COLUMN trade_annotations.annotation_type IS 'Type of annotation such as entry_note, exit_note, lesson, reminder, analysis, observation';
COMMENT ON COLUMN trade_annotations.title IS 'Optional title for the annotation';
COMMENT ON COLUMN trade_annotations.content IS 'Main annotation content';
COMMENT ON COLUMN trade_annotations.color IS 'Optional HEX color for visual distinction';
COMMENT ON COLUMN trade_annotations.is_pinned IS 'Whether annotation is pinned to top';
COMMENT ON COLUMN trade_annotations.attachments IS 'Array of file URLs or file paths';


-- =========================================================
-- TABLE: journal_entries
-- =========================================================

CREATE TABLE journal_entries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    account_id UUID REFERENCES trading_accounts(id) ON DELETE SET NULL,

    -- Entry details
    entry_type journal_type NOT NULL,
    entry_date DATE NOT NULL,
    title VARCHAR(200) NOT NULL,
    content TEXT NOT NULL,

    -- Psychological tracking
    mood mood_type,
    energy_level INTEGER CHECK (energy_level BETWEEN 1 AND 10),
    focus_level INTEGER CHECK (focus_level BETWEEN 1 AND 10),
    confidence_level INTEGER CHECK (confidence_level BETWEEN 1 AND 10),
    stress_level INTEGER CHECK (stress_level BETWEEN 1 AND 10),
    sleep_hours NUMERIC(3,1) CHECK (sleep_hours BETWEEN 0 AND 24),

    -- Reflection
    lessons TEXT,
    mistakes TEXT,
    improvements TEXT,
    goals_for_next TEXT,

    -- Metadata
    is_pinned BOOLEAN NOT NULL DEFAULT false,
    attachments TEXT[],

    -- Timestamps
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ,

    -- Constraints
    CONSTRAINT chk_journal_title_length CHECK (char_length(trim(title)) >= 1),
    CONSTRAINT chk_journal_content_length CHECK (char_length(trim(content)) >= 1)
);

-- Indexes
CREATE INDEX idx_journal_entries_user_date
    ON journal_entries(user_id, entry_date DESC)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_journal_entries_type
    ON journal_entries(user_id, entry_type)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_journal_entries_mood
    ON journal_entries(user_id, mood)
    WHERE mood IS NOT NULL AND deleted_at IS NULL;

CREATE INDEX idx_journal_entries_pinned
    ON journal_entries(user_id, is_pinned)
    WHERE is_pinned = true AND deleted_at IS NULL;

CREATE INDEX idx_journal_entries_account
    ON journal_entries(account_id)
    WHERE account_id IS NOT NULL AND deleted_at IS NULL;

-- Trigger for updated_at
CREATE TRIGGER trg_journal_entries_set_updated_at
    BEFORE UPDATE ON journal_entries
    FOR EACH ROW
    EXECUTE FUNCTION set_updated_at();

-- Comments
COMMENT ON TABLE journal_entries IS 'Personal trading journal and diary entries for daily, weekly, monthly, pre-trade, and post-trade reflections';
COMMENT ON COLUMN journal_entries.entry_type IS 'Entry type such as daily, weekly, monthly, pre_trade, post_trade';
COMMENT ON COLUMN journal_entries.mood IS 'Emotional state during trading';
COMMENT ON COLUMN journal_entries.energy_level IS 'Energy level from 1 to 10';
COMMENT ON COLUMN journal_entries.focus_level IS 'Focus level from 1 to 10';
COMMENT ON COLUMN journal_entries.confidence_level IS 'Confidence level from 1 to 10';
COMMENT ON COLUMN journal_entries.stress_level IS 'Stress level from 1 to 10';
COMMENT ON COLUMN journal_entries.sleep_hours IS 'Hours of sleep before trading';
COMMENT ON COLUMN journal_entries.lessons IS 'Key lessons learned';
COMMENT ON COLUMN journal_entries.mistakes IS 'Mistakes made';
COMMENT ON COLUMN journal_entries.improvements IS 'Areas for improvement';
COMMENT ON COLUMN journal_entries.goals_for_next IS 'Goals for next session';


-- =========================================================
-- TABLE: journal_entry_tags
-- =========================================================

CREATE TABLE journal_entry_tags (
    journal_entry_id UUID NOT NULL REFERENCES journal_entries(id) ON DELETE CASCADE,
    tag_id UUID NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    PRIMARY KEY (journal_entry_id, tag_id)
);

CREATE INDEX idx_journal_entry_tags_tag ON journal_entry_tags(tag_id, journal_entry_id);
CREATE INDEX idx_journal_entry_tags_user ON journal_entry_tags(user_id, created_at DESC);

COMMENT ON TABLE journal_entry_tags IS 'Junction table linking journal entries to tags';


-- =========================================================
-- TABLE: journal_templates
-- =========================================================

CREATE TABLE journal_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,

    template_name VARCHAR(100) NOT NULL,
    template_type journal_type NOT NULL,
    content_template TEXT NOT NULL,
    questions JSONB,

    is_system BOOLEAN NOT NULL DEFAULT false,
    is_default BOOLEAN NOT NULL DEFAULT false,
    usage_count INTEGER NOT NULL DEFAULT 0,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ,

    CONSTRAINT chk_journal_template_name CHECK (char_length(trim(template_name)) >= 1),
    CONSTRAINT chk_journal_template_content CHECK (char_length(trim(content_template)) >= 1),
    CONSTRAINT chk_journal_template_questions_array CHECK (
        questions IS NULL OR jsonb_typeof(questions) = 'array'
    ),
    CONSTRAINT chk_journal_template_usage_count CHECK (usage_count >= 0),
    CONSTRAINT chk_journal_template_system_user CHECK (
        (is_system = true AND user_id IS NULL)
        OR
        (is_system = false)
    )
);

-- Partial unique indexes
CREATE UNIQUE INDEX uq_journal_templates_system_name_active
ON journal_templates(lower(template_name))
WHERE is_system = true AND deleted_at IS NULL;

CREATE UNIQUE INDEX uq_journal_templates_user_name_active
ON journal_templates(user_id, lower(template_name))
WHERE is_system = false AND deleted_at IS NULL;

-- Indexes
CREATE INDEX idx_journal_templates_user
    ON journal_templates(user_id)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_journal_templates_type
    ON journal_templates(template_type)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_journal_templates_system
    ON journal_templates(is_system, is_default)
    WHERE deleted_at IS NULL;

-- Trigger for updated_at
CREATE TRIGGER trg_journal_templates_set_updated_at
    BEFORE UPDATE ON journal_templates
    FOR EACH ROW
    EXECUTE FUNCTION set_updated_at();

-- Default system templates
INSERT INTO journal_templates (
    template_name,
    template_type,
    content_template,
    questions,
    is_system,
    is_default
) VALUES
(
    'Daily Trading Review',
    'daily',
    'Today''s Trading Summary:\n\nTrades Taken: {trade_count}\nWinners: {win_count}\nLosers: {loss_count}\nNet P&L: {net_pnl}\n\nReflection:\n{reflection}\n\nEmotions:\n{emotions}\n\nLessons Learned:\n{lessons}\n\nTomorrow''s Focus:\n{focus}',
    '["What went well today?", "What could I improve?", "Did I follow my trading plan?", "How was my emotional state?"]'::jsonb,
    true,
    true
),
(
    'Pre-Trade Checklist',
    'pre_trade',
    'Pre-Trade Preparation:\n\nMarket Analysis:\n{market_analysis}\n\nSetup Identified:\n{setup}\n\nEntry Price:\n{entry}\n\nStop Loss:\n{stop_loss}\n\nTake Profit:\n{take_profit}\n\nRisk Amount:\n{risk}\n\nWhy This Trade?\n{reason}',
    '["Is this my setup?", "What is the risk/reward?", "Am I forcing this trade?", "What is my confidence level (1-10)?"]'::jsonb,
    true,
    false
),
(
    'Weekly Performance Review',
    'weekly',
    'Week {week_number} Summary:\n\nTotal Trades: {total_trades}\nWin Rate: {win_rate}%\nNet Profit: {net_profit}\n\nBest Trade:\n{best_trade}\n\nWorst Trade:\n{worst_trade}\n\nKey Patterns Observed:\n{patterns}\n\nGoals for Next Week:\n{goals}',
    '["What patterns did I notice this week?", "Did I stick to my strategy?", "What was my biggest lesson?", "What needs improvement?"]'::jsonb,
    true,
    false
);

-- Comments
COMMENT ON TABLE journal_templates IS 'Reusable journal entry templates, both system-provided and user-defined';
COMMENT ON COLUMN journal_templates.questions IS 'JSONB array of prompt questions';





CREATE OR REPLACE FUNCTION trg_trade_tags_check_ownership()
RETURNS TRIGGER AS $$
BEGIN
    -- Check that the user owns the trade
    IF NOT EXISTS (
        SELECT 1
        FROM trades
        WHERE id = NEW.trade_id
          AND entry_date = NEW.trade_entry_date
          AND user_id = NEW.user_id
    ) THEN
        RAISE EXCEPTION 'User does not own the referenced trade';
    END IF;

    -- Check that the user owns the tag
    IF NOT EXISTS (
        SELECT 1
        FROM tags
        WHERE id = NEW.tag_id
          AND user_id = NEW.user_id
    ) THEN
        RAISE EXCEPTION 'User does not own the referenced tag';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_trade_tags_ownership
    BEFORE INSERT OR UPDATE ON trade_tags
    FOR EACH ROW
    EXECUTE FUNCTION trg_trade_tags_check_ownership();





CREATE OR REPLACE FUNCTION trg_trade_annotations_check_ownership()
RETURNS TRIGGER AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM trades
        WHERE id = NEW.trade_id
          AND entry_date = NEW.trade_entry_date
          AND user_id = NEW.user_id
    ) THEN
        RAISE EXCEPTION 'User does not own the referenced trade';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_trade_annotations_ownership
    BEFORE INSERT OR UPDATE ON trade_annotations
    FOR EACH ROW
    EXECUTE FUNCTION trg_trade_annotations_check_ownership();





CREATE OR REPLACE FUNCTION trg_account_daily_snapshots_check_ownership()
RETURNS TRIGGER AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM trading_accounts
        WHERE id = NEW.account_id
          AND user_id = NEW.user_id
    ) THEN
        RAISE EXCEPTION 'User does not own the referenced trading account';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_account_daily_snapshots_ownership
    BEFORE INSERT OR UPDATE ON account_daily_snapshots
    FOR EACH ROW
    EXECUTE FUNCTION trg_account_daily_snapshots_check_ownership();



-- Adding Ownership trigger for journal_entry_tags
CREATE OR REPLACE FUNCTION trg_journal_entry_tags_check_ownership()
RETURNS TRIGGER AS $$
BEGIN
    -- Check that the user owns the journal entry
    IF NOT EXISTS (
        SELECT 1 FROM journal_entries 
        WHERE id = NEW.journal_entry_id AND user_id = NEW.user_id
    ) THEN
        RAISE EXCEPTION 'User does not own the journal entry';
    END IF;
    
    -- Check that the user owns the tag
    IF NOT EXISTS (
        SELECT 1 FROM tags WHERE id = NEW.tag_id AND user_id = NEW.user_id
    ) THEN
        RAISE EXCEPTION 'User does not own the tag';
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_journal_entry_tags_ownership
    BEFORE INSERT OR UPDATE ON journal_entry_tags
    FOR EACH ROW
    EXECUTE FUNCTION trg_journal_entry_tags_check_ownership();

































































































































-- =========================================================
-- ONLY NEW ENUMS THAT DO NOT ALREADY EXIST IN YOUR SCHEMA
-- =========================================================

DO $$ BEGIN
    CREATE TYPE insight_importance AS ENUM ('low', 'medium', 'high', 'critical');
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    CREATE TYPE custom_field_type AS ENUM ('text', 'number', 'decimal', 'date', 'boolean', 'dropdown', 'multiselect');
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;


-- =========================================================
-- HELPER FUNCTIONS
-- =========================================================

-- Safe updated_at trigger function
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;


-- =========================================================
-- TABLE: trading_insights
-- Uses existing enums: insight_type, insight_category
-- =========================================================

CREATE TABLE trading_insights (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Insight details
    insight_type insight_type NOT NULL,
    insight_category insight_category,
    title VARCHAR(200) NOT NULL,
    description TEXT NOT NULL,

    -- Importance and impact
    importance insight_importance NOT NULL DEFAULT 'medium',
    impact_rating INTEGER CHECK (impact_rating BETWEEN 1 AND 10),

    -- Related trade (optional)
    related_trade_id UUID,
    related_trade_date TIMESTAMPTZ,

    -- Implementation tracking
    is_implemented BOOLEAN NOT NULL DEFAULT false,
    implemented_date DATE,
    review_count INTEGER NOT NULL DEFAULT 0,
    last_reviewed_at TIMESTAMPTZ,

    -- Metadata
    tags UUID[],
    notes TEXT,

    -- Timestamps
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ,

    FOREIGN KEY (related_trade_id, related_trade_date)
        REFERENCES trades(id, entry_date) ON DELETE SET NULL,

    CONSTRAINT chk_trading_insights_title
        CHECK (char_length(trim(title)) >= 3),

    CONSTRAINT chk_trading_insights_description
        CHECK (char_length(trim(description)) >= 5),

    CONSTRAINT chk_trading_insights_review
        CHECK (review_count >= 0),

    CONSTRAINT chk_trading_insights_implemented
        CHECK (
            (is_implemented = true AND implemented_date IS NOT NULL)
            OR
            (is_implemented = false AND implemented_date IS NULL)
        )
);

CREATE INDEX idx_trading_insights_user
    ON trading_insights(user_id)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_trading_insights_type
    ON trading_insights(user_id, insight_type)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_trading_insights_category
    ON trading_insights(user_id, insight_category)
    WHERE insight_category IS NOT NULL AND deleted_at IS NULL;

CREATE INDEX idx_trading_insights_importance
    ON trading_insights(user_id, importance)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_trading_insights_implemented
    ON trading_insights(user_id, is_implemented)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_trading_insights_trade
    ON trading_insights(related_trade_id, related_trade_date)
    WHERE related_trade_id IS NOT NULL;

CREATE INDEX idx_trading_insights_tags
    ON trading_insights USING GIN (tags)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_trading_insights_created
    ON trading_insights(user_id, created_at DESC)
    WHERE deleted_at IS NULL;

CREATE TRIGGER trg_trading_insights_set_updated_at
    BEFORE UPDATE ON trading_insights
    FOR EACH ROW
    EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE trading_insights IS 'Personal database of trading lessons, mistakes, rules, and observations';
COMMENT ON COLUMN trading_insights.tags IS 'Array of tag UUIDs for categorization';


-- Ownership validation for related trade
CREATE OR REPLACE FUNCTION validate_trading_insights_ownership()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_trade_user_id UUID;
BEGIN
    IF NEW.related_trade_id IS NULL AND NEW.related_trade_date IS NULL THEN
        RETURN NEW;
    END IF;

    IF NEW.related_trade_id IS NULL OR NEW.related_trade_date IS NULL THEN
        RAISE EXCEPTION 'Both related_trade_id and related_trade_date must be provided together';
    END IF;

    SELECT t.user_id
    INTO v_trade_user_id
    FROM trades t
    WHERE t.id = NEW.related_trade_id
      AND t.entry_date = NEW.related_trade_date;

    IF v_trade_user_id IS NULL THEN
        RAISE EXCEPTION 'Referenced trade does not exist';
    END IF;

    IF v_trade_user_id <> NEW.user_id THEN
        RAISE EXCEPTION 'trading_insights.user_id must match the related trade owner';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_trading_insights_validate_ownership
    BEFORE INSERT OR UPDATE ON trading_insights
    FOR EACH ROW
    EXECUTE FUNCTION validate_trading_insights_ownership();


-- =========================================================
-- TABLE: goals
-- Uses existing enums: goal_type, goal_category, goal_status
-- =========================================================

CREATE TABLE goals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    account_id UUID REFERENCES trading_accounts(id) ON DELETE CASCADE,

    -- Goal definition
    goal_type goal_type NOT NULL,
    goal_category goal_category NOT NULL,
    name VARCHAR(100) NOT NULL,
    description TEXT,

    -- Targets and progress
    target_value NUMERIC(20,4) NOT NULL,
    current_value NUMERIC(20,4) NOT NULL DEFAULT 0,
    starting_value NUMERIC(20,4) NOT NULL DEFAULT 0,
    unit VARCHAR(20) NOT NULL,

    -- Dates
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,

    -- Recurrence
    is_recurring BOOLEAN NOT NULL DEFAULT false,
    recurrence_pattern goal_type,
    parent_goal_id UUID REFERENCES goals(id) ON DELETE CASCADE,

    -- Status and tracking
    status goal_status NOT NULL DEFAULT 'active',
    priority INTEGER NOT NULL DEFAULT 3 CHECK (priority BETWEEN 1 AND 5),

    progress_percentage NUMERIC(7,2) GENERATED ALWAYS AS (
        CASE
            WHEN target_value > starting_value THEN
                ((current_value - starting_value) / NULLIF(target_value - starting_value, 0)) * 100
            WHEN target_value < starting_value THEN
                ((starting_value - current_value) / NULLIF(starting_value - target_value, 0)) * 100
            ELSE
                CASE
                    WHEN current_value = target_value THEN 100
                    ELSE 0
                END
        END
    ) STORED,

    is_achieved BOOLEAN GENERATED ALWAYS AS (
        CASE
            WHEN target_value > starting_value THEN current_value >= target_value
            WHEN target_value < starting_value THEN current_value <= target_value
            ELSE current_value = target_value
        END
    ) STORED,

    achieved_date DATE,

    -- Milestones
    milestones JSONB,

    -- Metadata
    tags UUID[],
    notes TEXT,

    -- Timestamps
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ,

    CONSTRAINT chk_goal_name
        CHECK (char_length(trim(name)) >= 1),

    CONSTRAINT chk_goal_dates
        CHECK (end_date >= start_date),

    CONSTRAINT chk_goal_unit
        CHECK (char_length(trim(unit)) >= 1),

    CONSTRAINT chk_goal_recurrence
        CHECK (
            (is_recurring = true AND recurrence_pattern IS NOT NULL)
            OR
            (is_recurring = false AND recurrence_pattern IS NULL)
        ),

    CONSTRAINT chk_goal_milestones_json
        CHECK (milestones IS NULL OR jsonb_typeof(milestones) = 'array')
);

CREATE INDEX idx_goals_user
    ON goals(user_id)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_goals_account
    ON goals(account_id)
    WHERE account_id IS NOT NULL AND deleted_at IS NULL;

CREATE INDEX idx_goals_status
    ON goals(user_id, status)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_goals_type
    ON goals(user_id, goal_type)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_goals_category
    ON goals(user_id, goal_category)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_goals_dates
    ON goals(user_id, start_date, end_date)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_goals_achieved
    ON goals(user_id, is_achieved)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_goals_priority
    ON goals(user_id, priority DESC)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_goals_parent
    ON goals(parent_goal_id)
    WHERE parent_goal_id IS NOT NULL;

CREATE INDEX idx_goals_tags
    ON goals USING GIN (tags)
    WHERE deleted_at IS NULL;

CREATE TRIGGER trg_goals_set_updated_at
    BEFORE UPDATE ON goals
    FOR EACH ROW
    EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE goals IS 'User-defined trading goals and performance targets';
COMMENT ON COLUMN goals.goal_type IS 'Uses existing goal_type enum';
COMMENT ON COLUMN goals.goal_category IS 'Uses existing goal_category enum';
COMMENT ON COLUMN goals.tags IS 'Array of tag UUIDs';
COMMENT ON COLUMN goals.progress_percentage IS 'Works for both increasing and decreasing goals';

-- Keep achieved_date in sync
CREATE OR REPLACE FUNCTION sync_goals_achieved_date()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_is_achieved BOOLEAN;
BEGIN
    v_is_achieved :=
        CASE
            WHEN NEW.target_value > NEW.starting_value THEN NEW.current_value >= NEW.target_value
            WHEN NEW.target_value < NEW.starting_value THEN NEW.current_value <= NEW.target_value
            ELSE NEW.current_value = NEW.target_value
        END;

    IF v_is_achieved THEN
        NEW.achieved_date := COALESCE(NEW.achieved_date, CURRENT_DATE);
    ELSE
        NEW.achieved_date := NULL;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_goals_sync_achieved_date
    BEFORE INSERT OR UPDATE ON goals
    FOR EACH ROW
    EXECUTE FUNCTION sync_goals_achieved_date();

-- Ownership validation for account and parent goal
CREATE OR REPLACE FUNCTION validate_goals_ownership()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_account_user_id UUID;
    v_parent_user_id UUID;
BEGIN
    IF NEW.account_id IS NOT NULL THEN
        SELECT ta.user_id
        INTO v_account_user_id
        FROM trading_accounts ta
        WHERE ta.id = NEW.account_id;

        IF v_account_user_id IS NULL THEN
            RAISE EXCEPTION 'Referenced account does not exist';
        END IF;

        IF v_account_user_id <> NEW.user_id THEN
            RAISE EXCEPTION 'goals.user_id must match account owner';
        END IF;
    END IF;

    IF NEW.parent_goal_id IS NOT NULL THEN
        SELECT g.user_id
        INTO v_parent_user_id
        FROM goals g
        WHERE g.id = NEW.parent_goal_id;

        IF v_parent_user_id IS NULL THEN
            RAISE EXCEPTION 'Referenced parent goal does not exist';
        END IF;

        IF v_parent_user_id <> NEW.user_id THEN
            RAISE EXCEPTION 'Parent goal must belong to the same user';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_goals_validate_ownership
    BEFORE INSERT OR UPDATE ON goals
    FOR EACH ROW
    EXECUTE FUNCTION validate_goals_ownership();


-- =========================================================
-- TABLE: user_preferences
-- =========================================================

CREATE TABLE user_preferences (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,

    -- Appearance
    theme VARCHAR(20) NOT NULL DEFAULT 'light',
    primary_color VARCHAR(20) NOT NULL DEFAULT 'blue',
    font_size VARCHAR(10) NOT NULL DEFAULT 'medium',
    compact_mode BOOLEAN NOT NULL DEFAULT false,

    -- Dashboard layout
    dashboard_layout JSONB,
    chart_preferences JSONB,
    table_preferences JSONB,

    -- Defaults
    default_account_id UUID REFERENCES trading_accounts(id) ON DELETE SET NULL,
    default_date_range VARCHAR(20) NOT NULL DEFAULT 'month',
    default_chart_type VARCHAR(20) NOT NULL DEFAULT 'line',

    -- Notifications
    email_notifications JSONB NOT NULL DEFAULT '{
        "trade_confirmation": true,
        "goal_achieved": true,
        "weekly_report": true,
        "monthly_report": true,
        "marketing": false
    }'::jsonb,

    push_notifications JSONB NOT NULL DEFAULT '{
        "trade_closed": false,
        "goal_progress": true,
        "insight_reminder": false
    }'::jsonb,

    -- Accessibility
    reduce_animation BOOLEAN NOT NULL DEFAULT false,
    high_contrast BOOLEAN NOT NULL DEFAULT false,

    -- Timestamps
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_user_preferences_theme
        CHECK (theme IN ('light', 'dark', 'system')),

    CONSTRAINT chk_user_preferences_font_size
        CHECK (font_size IN ('small', 'medium', 'large')),

    CONSTRAINT chk_user_preferences_date_range
        CHECK (default_date_range IN ('day', 'week', 'month', 'quarter', 'year', 'all')),

    CONSTRAINT chk_user_preferences_chart_type
        CHECK (default_chart_type IN ('line', 'bar', 'pie', 'doughnut', 'area')),

    CONSTRAINT chk_user_preferences_dashboard_layout
        CHECK (dashboard_layout IS NULL OR jsonb_typeof(dashboard_layout) = 'object'),

    CONSTRAINT chk_user_preferences_chart_preferences
        CHECK (chart_preferences IS NULL OR jsonb_typeof(chart_preferences) = 'object'),

    CONSTRAINT chk_user_preferences_table_preferences
        CHECK (table_preferences IS NULL OR jsonb_typeof(table_preferences) = 'object'),

    CONSTRAINT chk_user_preferences_email_notifications
        CHECK (jsonb_typeof(email_notifications) = 'object'),

    CONSTRAINT chk_user_preferences_push_notifications
        CHECK (jsonb_typeof(push_notifications) = 'object')
);

CREATE TRIGGER trg_user_preferences_set_updated_at
    BEFORE UPDATE ON user_preferences
    FOR EACH ROW
    EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE user_preferences IS 'User interface and application preferences';

-- Create preferences automatically for each new user
CREATE OR REPLACE FUNCTION trg_users_create_preferences()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO user_preferences (user_id)
    VALUES (NEW.id)
    ON CONFLICT (user_id) DO NOTHING;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_users_after_insert ON users;

CREATE TRIGGER trg_users_after_insert
    AFTER INSERT ON users
    FOR EACH ROW
    EXECUTE FUNCTION trg_users_create_preferences();

-- Validate default account ownership
CREATE OR REPLACE FUNCTION validate_user_preferences_account()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_account_user_id UUID;
BEGIN
    IF NEW.default_account_id IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT ta.user_id
    INTO v_account_user_id
    FROM trading_accounts ta
    WHERE ta.id = NEW.default_account_id;

    IF v_account_user_id IS NULL THEN
        RAISE EXCEPTION 'Referenced default account does not exist';
    END IF;

    IF v_account_user_id <> NEW.user_id THEN
        RAISE EXCEPTION 'default_account_id must belong to the same user';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_user_preferences_validate_account
    BEFORE INSERT OR UPDATE ON user_preferences
    FOR EACH ROW
    EXECUTE FUNCTION validate_user_preferences_account();


-- =========================================================
-- TABLE: custom_fields
-- =========================================================

CREATE TABLE custom_fields (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    field_name VARCHAR(50) NOT NULL,
    field_type custom_field_type NOT NULL,
    field_description VARCHAR(200),

    field_options JSONB,
    is_required BOOLEAN NOT NULL DEFAULT false,
    default_value JSONB,
    min_value NUMERIC(20,4),
    max_value NUMERIC(20,4),
    regex_pattern VARCHAR(200),

    display_order INTEGER NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT true,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ,

    CONSTRAINT chk_custom_field_name
        CHECK (char_length(trim(field_name)) >= 2),

    CONSTRAINT chk_custom_field_options_shape
        CHECK (
            (field_type IN ('dropdown', 'multiselect') AND field_options IS NOT NULL AND jsonb_typeof(field_options) = 'array')
            OR
            (field_type NOT IN ('dropdown', 'multiselect') AND field_options IS NULL)
        ),

    CONSTRAINT chk_custom_field_numeric_range
        CHECK (
            (
                field_type IN ('number', 'decimal')
                AND (min_value IS NULL OR max_value IS NULL OR min_value <= max_value)
            )
            OR
            (
                field_type NOT IN ('number', 'decimal')
                AND min_value IS NULL
                AND max_value IS NULL
            )
        ),

    CONSTRAINT chk_custom_field_regex_usage
        CHECK (
            (field_type = 'text')
            OR
            (field_type <> 'text' AND regex_pattern IS NULL)
        )
);

CREATE UNIQUE INDEX uq_custom_fields_user_name_active
    ON custom_fields(user_id, lower(field_name))
    WHERE deleted_at IS NULL;

CREATE INDEX idx_custom_fields_user
    ON custom_fields(user_id)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_custom_fields_active
    ON custom_fields(user_id, is_active)
    WHERE is_active = true AND deleted_at IS NULL;

CREATE INDEX idx_custom_fields_order
    ON custom_fields(user_id, display_order)
    WHERE deleted_at IS NULL;

CREATE TRIGGER trg_custom_fields_set_updated_at
    BEFORE UPDATE ON custom_fields
    FOR EACH ROW
    EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE custom_fields IS 'User-defined custom fields for extending trade data';


-- =========================================================
-- TABLE: custom_field_values
-- =========================================================

CREATE TABLE custom_field_values (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    field_id UUID NOT NULL REFERENCES custom_fields(id) ON DELETE CASCADE,
    trade_id UUID NOT NULL,
    trade_entry_date TIMESTAMPTZ NOT NULL,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    field_value JSONB NOT NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    FOREIGN KEY (trade_id, trade_entry_date)
        REFERENCES trades(id, entry_date) ON DELETE CASCADE,

    CONSTRAINT uq_custom_field_trade UNIQUE (field_id, trade_id, trade_entry_date)
);

CREATE INDEX idx_custom_field_values_field
    ON custom_field_values(field_id, trade_id, trade_entry_date);

CREATE INDEX idx_custom_field_values_trade
    ON custom_field_values(trade_id, trade_entry_date);

CREATE INDEX idx_custom_field_values_user
    ON custom_field_values(user_id, created_at DESC);

CREATE TRIGGER trg_custom_field_values_set_updated_at
    BEFORE UPDATE ON custom_field_values
    FOR EACH ROW
    EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE custom_field_values IS 'Values for custom fields on specific trades';
COMMENT ON COLUMN custom_field_values.field_value IS 'Actual value stored as JSONB';

-- Validate ownership and basic type compatibility
CREATE OR REPLACE FUNCTION validate_custom_field_value()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_field_user_id UUID;
    v_trade_user_id UUID;
    v_field_type custom_field_type;
BEGIN
    SELECT cf.user_id, cf.field_type
    INTO v_field_user_id, v_field_type
    FROM custom_fields cf
    WHERE cf.id = NEW.field_id;

    IF v_field_user_id IS NULL THEN
        RAISE EXCEPTION 'Referenced custom field does not exist';
    END IF;

    SELECT t.user_id
    INTO v_trade_user_id
    FROM trades t
    WHERE t.id = NEW.trade_id
      AND t.entry_date = NEW.trade_entry_date;

    IF v_trade_user_id IS NULL THEN
        RAISE EXCEPTION 'Referenced trade does not exist';
    END IF;

    IF NEW.user_id <> v_field_user_id OR NEW.user_id <> v_trade_user_id THEN
        RAISE EXCEPTION 'custom_field_values.user_id must match both custom field owner and trade owner';
    END IF;

    -- Basic JSON type validation
    IF v_field_type = 'text' AND jsonb_typeof(NEW.field_value) <> 'string' THEN
        RAISE EXCEPTION 'field_value must be a JSON string for text field';
    ELSIF v_field_type IN ('number', 'decimal') AND jsonb_typeof(NEW.field_value) <> 'number' THEN
        RAISE EXCEPTION 'field_value must be a JSON number for number/decimal field';
    ELSIF v_field_type = 'date' AND jsonb_typeof(NEW.field_value) <> 'string' THEN
        RAISE EXCEPTION 'field_value must be a JSON string for date field';
    ELSIF v_field_type = 'boolean' AND jsonb_typeof(NEW.field_value) <> 'boolean' THEN
        RAISE EXCEPTION 'field_value must be a JSON boolean for boolean field';
    ELSIF v_field_type = 'dropdown' AND jsonb_typeof(NEW.field_value) <> 'string' THEN
        RAISE EXCEPTION 'field_value must be a JSON string for dropdown field';
    ELSIF v_field_type = 'multiselect' AND jsonb_typeof(NEW.field_value) <> 'array' THEN
        RAISE EXCEPTION 'field_value must be a JSON array for multiselect field';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_custom_field_values_validate
    BEFORE INSERT OR UPDATE ON custom_field_values
    FOR EACH ROW
    EXECUTE FUNCTION validate_custom_field_value();









-- =========================================================
-- ONLY NEW ENUMS NOT ALREADY IN YOUR EXISTING DB
-- =========================================================

DO $$ BEGIN
    CREATE TYPE job_status AS ENUM ('pending', 'running', 'completed', 'failed', 'cancelled');
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    CREATE TYPE job_priority AS ENUM ('low', 'normal', 'high', 'critical');
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

-- IMPORTANT:
-- Uses your existing enums:
--   export_format
--   export_type
--   audit_action
--
-- If you need extra audit_action values, run these once:
ALTER TYPE audit_action ADD VALUE IF NOT EXISTS 'ARCHIVE';
ALTER TYPE audit_action ADD VALUE IF NOT EXISTS 'RESTORE';


-- =========================================================
-- TABLE: audit_logs
-- Uses existing audit_action enum
-- =========================================================

CREATE TABLE audit_logs (
    id UUID DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    session_id UUID REFERENCES user_sessions(id) ON DELETE SET NULL,

    -- Action details
    action audit_action NOT NULL,
    entity_type VARCHAR(50) NOT NULL,
    entity_id UUID,
    entity_details JSONB,

    -- Before/after values
    old_values JSONB,
    new_values JSONB,
    changes JSONB,

    -- Request context
    ip_address INET,
    user_agent TEXT,
    request_id UUID,
    request_path TEXT,
    request_method VARCHAR(10),

    -- Response info
    response_status INTEGER,
    response_time_ms INTEGER,

    -- Error info
    error_message TEXT,
    error_details JSONB,

    -- Timestamp
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    PRIMARY KEY (id, created_at),

    CONSTRAINT chk_audit_logs_entity_type
        CHECK (char_length(trim(entity_type)) >= 1),

    CONSTRAINT chk_audit_logs_request_method
        CHECK (
            request_method IS NULL
            OR request_method IN ('GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS', 'HEAD')
        ),

    CONSTRAINT chk_audit_logs_response_status
        CHECK (response_status IS NULL OR (response_status >= 100 AND response_status <= 599)),

    CONSTRAINT chk_audit_logs_response_time
        CHECK (response_time_ms IS NULL OR response_time_ms >= 0),

    CONSTRAINT chk_audit_logs_json_shapes
        CHECK (
            (entity_details IS NULL OR jsonb_typeof(entity_details) = 'object')
            AND (old_values IS NULL OR jsonb_typeof(old_values) = 'object')
            AND (new_values IS NULL OR jsonb_typeof(new_values) = 'object')
            AND (changes IS NULL OR jsonb_typeof(changes) = 'object')
            AND (error_details IS NULL OR jsonb_typeof(error_details) = 'object')
        )
) PARTITION BY RANGE (created_at);

-- Example partitions only; production should automate future partition creation
CREATE TABLE IF NOT EXISTS audit_logs_2024_01 PARTITION OF audit_logs
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');
CREATE TABLE IF NOT EXISTS audit_logs_2024_02 PARTITION OF audit_logs
    FOR VALUES FROM ('2024-02-01') TO ('2024-03-01');
CREATE TABLE IF NOT EXISTS audit_logs_2024_03 PARTITION OF audit_logs
    FOR VALUES FROM ('2024-03-01') TO ('2024-04-01');

CREATE INDEX idx_audit_logs_user ON audit_logs(user_id, created_at DESC);
CREATE INDEX idx_audit_logs_action ON audit_logs(action, created_at DESC);
CREATE INDEX idx_audit_logs_entity ON audit_logs(entity_type, entity_id, created_at DESC);
CREATE INDEX idx_audit_logs_request ON audit_logs(request_id) WHERE request_id IS NOT NULL;
CREATE INDEX idx_audit_logs_ip ON audit_logs(ip_address, created_at DESC);

COMMENT ON TABLE audit_logs IS 'Comprehensive audit trail for compliance and debugging';
COMMENT ON COLUMN audit_logs.entity_details IS 'Snapshot of entity state at time of action';
COMMENT ON COLUMN audit_logs.changes IS 'Summary of what changed';


-- =========================================================
-- TABLE: reports
-- Uses existing enums: export_type, export_format
-- =========================================================

CREATE TABLE reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    account_id UUID REFERENCES trading_accounts(id) ON DELETE SET NULL,

    -- Report metadata
    report_name VARCHAR(200) NOT NULL,
    report_type export_type NOT NULL,
    report_format export_format NOT NULL,

    -- Parameters used to generate the report
    parameters JSONB NOT NULL DEFAULT '{}'::jsonb,

    -- File information
    file_path VARCHAR(500) NOT NULL,
    file_size BIGINT NOT NULL,
    file_hash VARCHAR(64),

    -- Sharing
    is_public BOOLEAN NOT NULL DEFAULT false,
    public_token UUID UNIQUE,
    download_count INTEGER NOT NULL DEFAULT 0,

    -- Timestamps
    generated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ,

    CONSTRAINT chk_reports_name
        CHECK (char_length(trim(report_name)) >= 1),

    CONSTRAINT chk_reports_file_path
        CHECK (char_length(trim(file_path)) >= 1),

    CONSTRAINT chk_reports_file_size
        CHECK (file_size >= 0),

    CONSTRAINT chk_reports_downloads
        CHECK (download_count >= 0),

    CONSTRAINT chk_reports_public_token
        CHECK (
            (is_public = true AND public_token IS NOT NULL)
            OR
            (is_public = false AND public_token IS NULL)
        ),

    CONSTRAINT chk_reports_parameters_shape
        CHECK (jsonb_typeof(parameters) = 'object')
);

CREATE INDEX idx_reports_user ON reports(user_id, generated_at DESC) WHERE deleted_at IS NULL;
CREATE INDEX idx_reports_account ON reports(account_id) WHERE account_id IS NOT NULL AND deleted_at IS NULL;
CREATE INDEX idx_reports_type ON reports(report_type) WHERE deleted_at IS NULL;
CREATE INDEX idx_reports_expires ON reports(expires_at) WHERE expires_at IS NOT NULL;
CREATE INDEX idx_reports_public_token ON reports(public_token) WHERE is_public = true;

COMMENT ON TABLE reports IS 'Stored generated reports metadata';
COMMENT ON COLUMN reports.parameters IS 'JSON of parameters used to generate the report';
COMMENT ON COLUMN reports.public_token IS 'Token for public sharing access';


-- =========================================================
-- TABLE: scheduled_reports
-- Uses existing enums: export_type, export_format
-- =========================================================

CREATE TABLE scheduled_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    account_id UUID REFERENCES trading_accounts(id) ON DELETE SET NULL,

    -- Report definition
    report_name VARCHAR(200) NOT NULL,
    report_type export_type NOT NULL,
    report_format export_format NOT NULL,
    parameters JSONB NOT NULL DEFAULT '{}'::jsonb,

    -- Schedule
    frequency VARCHAR(20) NOT NULL,
    day_of_week INTEGER CHECK (day_of_week BETWEEN 0 AND 6),
    day_of_month INTEGER CHECK (day_of_month BETWEEN 1 AND 31),
    time_of_day TIME NOT NULL,
    timezone VARCHAR(50) NOT NULL DEFAULT 'UTC',

    -- Recipients
    email_recipients TEXT[] NOT NULL DEFAULT '{}',

    -- Status
    is_active BOOLEAN NOT NULL DEFAULT true,
    last_generated_at TIMESTAMPTZ,
    next_generation_at TIMESTAMPTZ,
    error_count INTEGER NOT NULL DEFAULT 0,
    last_error TEXT,

    -- Timestamps
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ,

    CONSTRAINT chk_scheduled_reports_name
        CHECK (char_length(trim(report_name)) >= 1),

    CONSTRAINT chk_scheduled_reports_frequency
        CHECK (frequency IN ('daily', 'weekly', 'monthly', 'quarterly')),

    CONSTRAINT chk_scheduled_reports_weekly
        CHECK (
            (frequency = 'weekly' AND day_of_week IS NOT NULL AND day_of_month IS NULL)
            OR
            (frequency <> 'weekly')
        ),

    CONSTRAINT chk_scheduled_reports_monthly
        CHECK (
            (frequency IN ('monthly', 'quarterly') AND day_of_month IS NOT NULL)
            OR
            (frequency NOT IN ('monthly', 'quarterly'))
        ),

    CONSTRAINT chk_scheduled_reports_daily
        CHECK (
            (frequency = 'daily' AND day_of_week IS NULL AND day_of_month IS NULL)
            OR
            (frequency <> 'daily')
        ),

    CONSTRAINT chk_scheduled_reports_errors
        CHECK (error_count >= 0),

    CONSTRAINT chk_scheduled_reports_parameters_shape
        CHECK (jsonb_typeof(parameters) = 'object')
);

CREATE INDEX idx_scheduled_reports_user ON scheduled_reports(user_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_scheduled_reports_active ON scheduled_reports(is_active, next_generation_at)
    WHERE is_active = true AND deleted_at IS NULL;
CREATE INDEX idx_scheduled_reports_next ON scheduled_reports(next_generation_at)
    WHERE is_active = true AND deleted_at IS NULL;

CREATE TRIGGER trg_scheduled_reports_set_updated_at
    BEFORE UPDATE ON scheduled_reports
    FOR EACH ROW
    EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE scheduled_reports IS 'User-defined automated report schedules';
COMMENT ON COLUMN scheduled_reports.parameters IS 'JSON of parameters for report generation';
COMMENT ON COLUMN scheduled_reports.email_recipients IS 'Array of email addresses to send reports to';


-- =========================================================
-- FUNCTION: calculate_next_generation
-- Fixed to STABLE, safer logic
-- =========================================================

CREATE OR REPLACE FUNCTION calculate_next_generation(
    p_frequency VARCHAR,
    p_day_of_week INTEGER,
    p_day_of_month INTEGER,
    p_time_of_day TIME,
    p_timezone VARCHAR,
    p_from_date TIMESTAMPTZ DEFAULT NOW()
)
RETURNS TIMESTAMPTZ
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_local_timestamp TIMESTAMP;
    v_local_date DATE;
    v_days_in_month INTEGER;
    v_target_day INTEGER;
BEGIN
    IF p_frequency NOT IN ('daily', 'weekly', 'monthly', 'quarterly') THEN
        RAISE EXCEPTION 'Unsupported frequency: %', p_frequency;
    END IF;

    v_local_timestamp := p_from_date AT TIME ZONE p_timezone;
    v_local_date := v_local_timestamp::date;

    IF p_frequency = 'daily' THEN
        RETURN ((CASE
            WHEN (v_local_date + p_time_of_day) > v_local_timestamp
                THEN (v_local_date + p_time_of_day)
            ELSE ((v_local_date + 1) + p_time_of_day)
        END) AT TIME ZONE p_timezone);
    END IF;

    IF p_frequency = 'weekly' THEN
        RETURN (
            (
                (
                    v_local_date
                    + ((p_day_of_week - EXTRACT(DOW FROM v_local_date)::integer + 7) % 7)
                )::date
                + p_time_of_day
                + CASE
                    WHEN (
                        (
                            v_local_date
                            + ((p_day_of_week - EXTRACT(DOW FROM v_local_date)::integer + 7) % 7)
                        )::date
                        + p_time_of_day
                    ) <= v_local_timestamp
                    THEN INTERVAL '7 days'
                    ELSE INTERVAL '0 days'
                  END
            ) AT TIME ZONE p_timezone
        );
    END IF;

    IF p_frequency = 'monthly' THEN
        v_days_in_month := EXTRACT(DAY FROM (date_trunc('month', v_local_date) + INTERVAL '1 month - 1 day'))::integer;
        v_target_day := LEAST(p_day_of_month, v_days_in_month);

        RETURN (
            (
                make_date(EXTRACT(YEAR FROM v_local_date)::integer, EXTRACT(MONTH FROM v_local_date)::integer, v_target_day)
                + p_time_of_day
                + CASE
                    WHEN (make_date(EXTRACT(YEAR FROM v_local_date)::integer, EXTRACT(MONTH FROM v_local_date)::integer, v_target_day) + p_time_of_day) <= v_local_timestamp
                    THEN INTERVAL '1 month'
                    ELSE INTERVAL '0'
                  END
            ) AT TIME ZONE p_timezone
        );
    END IF;

    -- quarterly
    v_days_in_month := EXTRACT(DAY FROM (date_trunc('month', v_local_date) + INTERVAL '1 month - 1 day'))::integer;
    v_target_day := LEAST(p_day_of_month, v_days_in_month);

    RETURN (
        (
            make_date(EXTRACT(YEAR FROM v_local_date)::integer, EXTRACT(MONTH FROM v_local_date)::integer, v_target_day)
            + p_time_of_day
            + CASE
                WHEN (make_date(EXTRACT(YEAR FROM v_local_date)::integer, EXTRACT(MONTH FROM v_local_date)::integer, v_target_day) + p_time_of_day) <= v_local_timestamp
                THEN INTERVAL '3 month'
                ELSE INTERVAL '0'
              END
        ) AT TIME ZONE p_timezone
    );
END;
$$;


-- =========================================================
-- TABLE: system_settings
-- =========================================================

CREATE TABLE system_settings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Setting key-value
    setting_key VARCHAR(100) UNIQUE NOT NULL,
    setting_value JSONB NOT NULL,
    setting_type VARCHAR(20) NOT NULL DEFAULT 'string',

    -- Metadata
    description TEXT,
    category VARCHAR(50) NOT NULL DEFAULT 'general',
    is_public BOOLEAN NOT NULL DEFAULT false,
    is_editable BOOLEAN NOT NULL DEFAULT true,
    validation_rules JSONB,

    -- Version tracking
    version INTEGER NOT NULL DEFAULT 1,
    changed_by UUID REFERENCES users(id) ON DELETE SET NULL,

    -- Timestamps
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_system_settings_key
        CHECK (char_length(trim(setting_key)) >= 1),

    CONSTRAINT chk_system_settings_type
        CHECK (setting_type IN ('string', 'number', 'boolean', 'json', 'array')),

    CONSTRAINT chk_system_settings_version
        CHECK (version >= 1),

    CONSTRAINT chk_system_settings_validation_rules_shape
        CHECK (validation_rules IS NULL OR jsonb_typeof(validation_rules) = 'object'),

    CONSTRAINT chk_system_settings_value_type_match
        CHECK (
            (setting_type = 'string'  AND jsonb_typeof(setting_value) = 'string')
            OR
            (setting_type = 'number'  AND jsonb_typeof(setting_value) = 'number')
            OR
            (setting_type = 'boolean' AND jsonb_typeof(setting_value) = 'boolean')
            OR
            (setting_type = 'json'    AND jsonb_typeof(setting_value) = 'object')
            OR
            (setting_type = 'array'   AND jsonb_typeof(setting_value) = 'array')
        )
);

CREATE INDEX idx_system_settings_category ON system_settings(category);
CREATE INDEX idx_system_settings_public ON system_settings(is_public) WHERE is_public = true;

CREATE TRIGGER trg_system_settings_set_updated_at
    BEFORE UPDATE ON system_settings
    FOR EACH ROW
    EXECUTE FUNCTION set_updated_at();

INSERT INTO system_settings (setting_key, setting_value, setting_type, description, category, is_public) VALUES
    ('app.name', '"Trading MIS"'::jsonb, 'string', 'Application name', 'general', true),
    ('app.version', '"1.0.0"'::jsonb, 'string', 'Application version', 'general', true),
    ('app.support_email', '"support@tradingmis.com"'::jsonb, 'string', 'Support email address', 'general', true),
    ('security.max_login_attempts', '5'::jsonb, 'number', 'Maximum failed login attempts before lockout', 'security', false),
    ('security.session_timeout_minutes', '60'::jsonb, 'number', 'Session timeout in minutes', 'security', false),
    ('security.password_min_length', '8'::jsonb, 'number', 'Minimum password length', 'security', false),
    ('security.require_2fa', 'false'::jsonb, 'boolean', 'Require two-factor authentication for all users', 'security', false),
    ('email.from_address', '"noreply@tradingmis.com"'::jsonb, 'string', 'Default from email address', 'email', false),
    ('email.smtp_host', '""'::jsonb, 'string', 'SMTP server host', 'email', false),
    ('email.smtp_port', '587'::jsonb, 'number', 'SMTP server port', 'email', false),
    ('billing.currency', '"USD"'::jsonb, 'string', 'Default billing currency', 'billing', true),
    ('billing.tax_rate', '0.0'::jsonb, 'number', 'Default tax rate percentage', 'billing', false),
    ('features.allow_custom_fields', 'true'::jsonb, 'boolean', 'Allow users to create custom fields', 'features', true),
    ('features.max_tags_per_user', '100'::jsonb, 'number', 'Maximum number of tags per user', 'features', false),
    ('features.max_goals_per_user', '50'::jsonb, 'number', 'Maximum number of active goals per user', 'features', false)
ON CONFLICT (setting_key) DO NOTHING;

COMMENT ON TABLE system_settings IS 'Global system configuration settings';
COMMENT ON COLUMN system_settings.setting_value IS 'JSON value matching setting_type';
COMMENT ON COLUMN system_settings.validation_rules IS 'JSON schema or validation rules';


-- =========================================================
-- TABLE: background_jobs
-- =========================================================

CREATE TABLE background_jobs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,

    -- Job identification
    job_type VARCHAR(100) NOT NULL,
    job_name VARCHAR(200),

    -- Job data
    job_data JSONB NOT NULL DEFAULT '{}'::jsonb,
    priority job_priority NOT NULL DEFAULT 'normal',

    -- Status tracking
    status job_status NOT NULL DEFAULT 'pending',
    progress INTEGER NOT NULL DEFAULT 0 CHECK (progress BETWEEN 0 AND 100),

    -- Timing
    scheduled_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,

    -- Result/Error
    result JSONB,
    error_message TEXT,
    error_details JSONB,
    retry_count INTEGER NOT NULL DEFAULT 0,
    max_retries INTEGER NOT NULL DEFAULT 3,

    -- Execution context
    worker_id VARCHAR(100),
    execution_time_ms INTEGER,

    -- Dependencies
    depends_on_job_id UUID REFERENCES background_jobs(id) ON DELETE SET NULL,
    job_queue VARCHAR(50) NOT NULL DEFAULT 'default',

    -- Timestamps
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_background_jobs_job_type
        CHECK (char_length(trim(job_type)) >= 1),

    CONSTRAINT chk_background_jobs_queue
        CHECK (char_length(trim(job_queue)) >= 1),

    CONSTRAINT chk_background_jobs_retries
        CHECK (retry_count >= 0 AND max_retries >= 0 AND retry_count <= max_retries),

    CONSTRAINT chk_background_jobs_execution_time
        CHECK (execution_time_ms IS NULL OR execution_time_ms >= 0),

    CONSTRAINT chk_background_jobs_json_shapes
        CHECK (
            jsonb_typeof(job_data) = 'object'
            AND (result IS NULL OR jsonb_typeof(result) IN ('object', 'array', 'string', 'number', 'boolean', 'null'))
            AND (error_details IS NULL OR jsonb_typeof(error_details) = 'object')
        ),

    CONSTRAINT chk_background_jobs_timing
        CHECK (
            (status = 'pending'   AND started_at IS NULL     AND completed_at IS NULL)
            OR
            (status = 'running'   AND started_at IS NOT NULL AND completed_at IS NULL)
            OR
            (status = 'completed' AND started_at IS NOT NULL AND completed_at IS NOT NULL)
            OR
            (status = 'failed'    AND started_at IS NOT NULL AND completed_at IS NOT NULL)
            OR
            (status = 'cancelled' AND completed_at IS NOT NULL)
        )
);

CREATE INDEX idx_background_jobs_status ON background_jobs(status, scheduled_at) WHERE status = 'pending';
CREATE INDEX idx_background_jobs_user ON background_jobs(user_id, created_at DESC);
CREATE INDEX idx_background_jobs_type ON background_jobs(job_type, status);
CREATE INDEX idx_background_jobs_worker ON background_jobs(worker_id) WHERE worker_id IS NOT NULL;
CREATE INDEX idx_background_jobs_dependency ON background_jobs(depends_on_job_id) WHERE depends_on_job_id IS NOT NULL;
CREATE INDEX idx_background_jobs_queue ON background_jobs(job_queue, priority, scheduled_at)
    WHERE status = 'pending';

CREATE TRIGGER trg_background_jobs_set_updated_at
    BEFORE UPDATE ON background_jobs
    FOR EACH ROW
    EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE background_jobs IS 'Asynchronous job queue and tracking';
COMMENT ON COLUMN background_jobs.job_data IS 'JSON parameters for the job';
COMMENT ON COLUMN background_jobs.result IS 'JSON result of successful job execution';
COMMENT ON COLUMN background_jobs.error_details IS 'Detailed error information for debugging';
COMMENT ON COLUMN background_jobs.depends_on_job_id IS 'Optional dependency on another job';


-- =========================================================
-- FUNCTION: claim_next_pending_job
-- =========================================================

CREATE OR REPLACE FUNCTION claim_next_pending_job(
    p_worker_id VARCHAR,
    p_queues TEXT[] DEFAULT ARRAY['default'],
    p_job_types TEXT[] DEFAULT NULL
)
RETURNS background_jobs
LANGUAGE plpgsql
AS $$
DECLARE
    v_job background_jobs;
BEGIN
    WITH next_job AS (
        SELECT bj.id
        FROM background_jobs bj
        WHERE bj.status = 'pending'
          AND bj.scheduled_at <= NOW()
          AND bj.job_queue = ANY(p_queues)
          AND (p_job_types IS NULL OR bj.job_type = ANY(p_job_types))
          AND (
              bj.depends_on_job_id IS NULL
              OR EXISTS (
                  SELECT 1
                  FROM background_jobs dep
                  WHERE dep.id = bj.depends_on_job_id
                    AND dep.status = 'completed'
              )
          )
        ORDER BY
            CASE bj.priority
                WHEN 'critical' THEN 1
                WHEN 'high' THEN 2
                WHEN 'normal' THEN 3
                WHEN 'low' THEN 4
            END,
            bj.scheduled_at,
            bj.created_at
        LIMIT 1
        FOR UPDATE SKIP LOCKED
    )
    UPDATE background_jobs bj
    SET
        status = 'running',
        started_at = NOW(),
        worker_id = p_worker_id,
        updated_at = NOW()
    FROM next_job
    WHERE bj.id = next_job.id
    RETURNING bj.* INTO v_job;

    RETURN v_job;
END;
$$;


-- =========================================================
-- FUNCTION: complete_job
-- =========================================================

CREATE OR REPLACE FUNCTION complete_job(
    p_job_id UUID,
    p_result JSONB DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE background_jobs
    SET
        status = 'completed',
        completed_at = NOW(),
        result = p_result,
        progress = 100,
        execution_time_ms = (EXTRACT(EPOCH FROM (NOW() - started_at)) * 1000)::INTEGER,
        updated_at = NOW()
    WHERE id = p_job_id
      AND status = 'running';
END;
$$;


-- =========================================================
-- FUNCTION: fail_job
-- =========================================================

CREATE OR REPLACE FUNCTION fail_job(
    p_job_id UUID,
    p_error_message TEXT,
    p_error_details JSONB DEFAULT NULL,
    p_retry BOOLEAN DEFAULT true
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_job background_jobs;
BEGIN
    SELECT *
    INTO v_job
    FROM background_jobs
    WHERE id = p_job_id;

    IF v_job.id IS NULL THEN
        RAISE EXCEPTION 'Job not found: %', p_job_id;
    END IF;

    IF p_retry AND v_job.retry_count < v_job.max_retries THEN
        UPDATE background_jobs
        SET
            status = 'pending',
            retry_count = retry_count + 1,
            error_message = p_error_message,
            error_details = p_error_details,
            worker_id = NULL,
            started_at = NULL,
            completed_at = NULL,
            scheduled_at = NOW() + (power(2, retry_count + 1) * INTERVAL '1 minute'),
            updated_at = NOW()
        WHERE id = p_job_id;
    ELSE
        UPDATE background_jobs
        SET
            status = 'failed',
            completed_at = NOW(),
            error_message = p_error_message,
            error_details = p_error_details,
            execution_time_ms = CASE
                WHEN started_at IS NOT NULL
                    THEN (EXTRACT(EPOCH FROM (NOW() - started_at)) * 1000)::INTEGER
                ELSE NULL
            END,
            updated_at = NOW()
        WHERE id = p_job_id;
    END IF;
END;
$$;
































































-- =========================================================
-- UNIFIED INSTRUMENT CLASSIFICATION
-- Safe for generated columns
-- =========================================================

CREATE OR REPLACE FUNCTION normalize_symbol(p_symbol VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
IMMUTABLE
AS $$
    SELECT UPPER(BTRIM(COALESCE(p_symbol, '')));
$$;

CREATE OR REPLACE FUNCTION trade_symbol_class(
    p_instrument_type instrument_type,
    p_symbol VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
IMMUTABLE
AS $$
    SELECT CASE
        WHEN p_instrument_type = 'forex' THEN
            CASE
                WHEN normalize_symbol(p_symbol) LIKE '%JPY' THEN 'FOREX_JPY'
                ELSE 'FOREX_STD'
            END

        WHEN p_instrument_type = 'stock' THEN 'STOCK_STD'

        WHEN p_instrument_type = 'index' THEN
            CASE
                WHEN normalize_symbol(p_symbol) IN ('US30', 'DJI') THEN 'INDEX_US30'
                WHEN normalize_symbol(p_symbol) IN ('SPX', 'SP500') THEN 'INDEX_SPX'
                WHEN normalize_symbol(p_symbol) IN ('NAS100', 'NDX') THEN 'INDEX_NAS100'
                WHEN normalize_symbol(p_symbol) IN ('JP225', 'NIKKEI') THEN 'INDEX_JP225'
                WHEN normalize_symbol(p_symbol) IN ('DE40', 'DAX') THEN 'INDEX_DE40'
                WHEN normalize_symbol(p_symbol) IN ('UK100', 'FTSE') THEN 'INDEX_UK100'
                ELSE 'INDEX_STD'
            END

        WHEN p_instrument_type = 'crypto' THEN
            CASE
                WHEN normalize_symbol(p_symbol) IN ('BTC', 'BITCOIN') THEN 'CRYPTO_BTC'
                WHEN normalize_symbol(p_symbol) IN ('ETH', 'ETHEREUM') THEN 'CRYPTO_ETH'
                ELSE 'CRYPTO_STD'
            END

        WHEN p_instrument_type = 'commodity' THEN
            CASE
                WHEN normalize_symbol(p_symbol) IN ('XAUUSD', 'GOLD') THEN 'CMDTY_GOLD'
                WHEN normalize_symbol(p_symbol) IN ('XAGUSD', 'SILVER') THEN 'CMDTY_SILVER'
                WHEN normalize_symbol(p_symbol) IN ('USOIL', 'WTI', 'BRENT') THEN 'CMDTY_OIL'
                WHEN normalize_symbol(p_symbol) = 'NATGAS' THEN 'CMDTY_NATGAS'
                WHEN normalize_symbol(p_symbol) = 'COPPER' THEN 'CMDTY_COPPER'
                ELSE 'CMDTY_STD'
            END

        WHEN p_instrument_type = 'ETF' THEN 'ETF_STD'
        WHEN p_instrument_type = 'bond' THEN 'BOND_STD'
        WHEN p_instrument_type = 'option' THEN 'OPTION_STD'

        WHEN p_instrument_type = 'future' THEN
            CASE
                WHEN normalize_symbol(p_symbol) LIKE '%ES%' THEN 'FUT_ES'
                WHEN normalize_symbol(p_symbol) LIKE '%NQ%' THEN 'FUT_NQ'
                WHEN normalize_symbol(p_symbol) LIKE '%YM%' THEN 'FUT_YM'
                WHEN normalize_symbol(p_symbol) LIKE '%RTY%' THEN 'FUT_RTY'
                WHEN normalize_symbol(p_symbol) IN ('CL', 'CRUDE') THEN 'FUT_CL'
                WHEN normalize_symbol(p_symbol) IN ('GC', 'GOLD') THEN 'FUT_GC'
                WHEN normalize_symbol(p_symbol) IN ('SI', 'SILVER') THEN 'FUT_SI'
                ELSE 'FUT_STD'
            END

        WHEN p_instrument_type = 'CFD' THEN
            CASE
                WHEN normalize_symbol(p_symbol) IN ('US30', 'DJI') THEN 'CFD_US30'
                WHEN normalize_symbol(p_symbol) IN ('SPX', 'SP500') THEN 'CFD_SPX'
                WHEN normalize_symbol(p_symbol) IN ('NAS100', 'NDX') THEN 'CFD_NAS100'
                WHEN normalize_symbol(p_symbol) IN ('XAUUSD', 'GOLD') THEN 'CFD_GOLD'
                WHEN normalize_symbol(p_symbol) IN ('BTC', 'BITCOIN') THEN 'CFD_BTC'
                ELSE 'CFD_STD'
            END

        ELSE 'GENERIC_STD'
    END;
$$;




























-- =========================================================
-- RECREATE UNIFIED TRADE HELPER FUNCTIONS
-- =========================================================

CREATE OR REPLACE FUNCTION trade_contract_size(
    p_instrument_type instrument_type,
    p_symbol VARCHAR
)
RETURNS NUMERIC
LANGUAGE SQL
IMMUTABLE
AS $$
    SELECT CASE trade_symbol_class(p_instrument_type, p_symbol)
        WHEN 'FOREX_STD' THEN 100000
        WHEN 'FOREX_JPY' THEN 100000
        WHEN 'STOCK_STD' THEN 1
        WHEN 'INDEX_US30' THEN 1
        WHEN 'INDEX_SPX' THEN 1
        WHEN 'INDEX_NAS100' THEN 1
        WHEN 'INDEX_JP225' THEN 1
        WHEN 'INDEX_DE40' THEN 1
        WHEN 'INDEX_UK100' THEN 1
        WHEN 'INDEX_STD' THEN 1
        WHEN 'CRYPTO_BTC' THEN 1
        WHEN 'CRYPTO_ETH' THEN 1
        WHEN 'CRYPTO_STD' THEN 1
        WHEN 'CMDTY_GOLD' THEN 100
        WHEN 'CMDTY_SILVER' THEN 5000
        WHEN 'CMDTY_OIL' THEN 1000
        WHEN 'CMDTY_NATGAS' THEN 10000
        WHEN 'CMDTY_COPPER' THEN 25000
        WHEN 'CMDTY_STD' THEN 100
        WHEN 'ETF_STD' THEN 1
        WHEN 'BOND_STD' THEN 1000
        WHEN 'OPTION_STD' THEN 100
        WHEN 'FUT_ES' THEN 1
        WHEN 'FUT_NQ' THEN 1
        WHEN 'FUT_YM' THEN 1
        WHEN 'FUT_RTY' THEN 1
        WHEN 'FUT_CL' THEN 1000
        WHEN 'FUT_GC' THEN 100
        WHEN 'FUT_SI' THEN 5000
        WHEN 'FUT_STD' THEN 1
        WHEN 'CFD_US30' THEN 1
        WHEN 'CFD_SPX' THEN 1
        WHEN 'CFD_NAS100' THEN 1
        WHEN 'CFD_GOLD' THEN 100
        WHEN 'CFD_BTC' THEN 1
        WHEN 'CFD_STD' THEN 1
        ELSE 1
    END;
$$;

CREATE OR REPLACE FUNCTION trade_point_value(
    p_instrument_type instrument_type,
    p_symbol VARCHAR
)
RETURNS NUMERIC
LANGUAGE SQL
IMMUTABLE
AS $$
    SELECT CASE trade_symbol_class(p_instrument_type, p_symbol)
        WHEN 'FOREX_STD' THEN 100000
        WHEN 'FOREX_JPY' THEN 100000
        WHEN 'STOCK_STD' THEN 1
        WHEN 'INDEX_US30' THEN 5
        WHEN 'INDEX_SPX' THEN 0.10
        WHEN 'INDEX_NAS100' THEN 0.25
        WHEN 'INDEX_JP225' THEN 1
        WHEN 'INDEX_DE40' THEN 0.50
        WHEN 'INDEX_UK100' THEN 0.50
        WHEN 'INDEX_STD' THEN 1
        WHEN 'CRYPTO_BTC' THEN 1
        WHEN 'CRYPTO_ETH' THEN 1
        WHEN 'CRYPTO_STD' THEN 1
        WHEN 'CMDTY_GOLD' THEN 100
        WHEN 'CMDTY_SILVER' THEN 5000
        WHEN 'CMDTY_OIL' THEN 1000
        WHEN 'CMDTY_NATGAS' THEN 10000
        WHEN 'CMDTY_COPPER' THEN 25000
        WHEN 'CMDTY_STD' THEN 100
        WHEN 'ETF_STD' THEN 1
        WHEN 'BOND_STD' THEN 1000
        WHEN 'OPTION_STD' THEN 100
        WHEN 'FUT_ES' THEN 50
        WHEN 'FUT_NQ' THEN 20
        WHEN 'FUT_YM' THEN 5
        WHEN 'FUT_RTY' THEN 5
        WHEN 'FUT_CL' THEN 1000
        WHEN 'FUT_GC' THEN 100
        WHEN 'FUT_SI' THEN 5000
        WHEN 'FUT_STD' THEN 1
        WHEN 'CFD_US30' THEN 5
        WHEN 'CFD_SPX' THEN 0.10
        WHEN 'CFD_NAS100' THEN 0.25
        WHEN 'CFD_GOLD' THEN 100
        WHEN 'CFD_BTC' THEN 1
        WHEN 'CFD_STD' THEN 1
        ELSE 1
    END;
$$;

CREATE OR REPLACE FUNCTION trade_price_increment(
    p_instrument_type instrument_type,
    p_symbol VARCHAR
)
RETURNS NUMERIC
LANGUAGE SQL
IMMUTABLE
AS $$
    SELECT CASE trade_symbol_class(p_instrument_type, p_symbol)
        WHEN 'FOREX_STD' THEN 0.0001
        WHEN 'FOREX_JPY' THEN 0.01
        WHEN 'STOCK_STD' THEN 0.01
        WHEN 'INDEX_US30' THEN 1.0
        WHEN 'INDEX_SPX' THEN 0.1
        WHEN 'INDEX_NAS100' THEN 0.25
        WHEN 'INDEX_JP225' THEN 1.0
        WHEN 'INDEX_DE40' THEN 0.5
        WHEN 'INDEX_UK100' THEN 0.5
        WHEN 'INDEX_STD' THEN 0.1
        WHEN 'CRYPTO_BTC' THEN 0.01
        WHEN 'CRYPTO_ETH' THEN 0.01
        WHEN 'CRYPTO_STD' THEN 0.0001
        WHEN 'CMDTY_GOLD' THEN 0.01
        WHEN 'CMDTY_SILVER' THEN 0.001
        WHEN 'CMDTY_OIL' THEN 0.01
        WHEN 'CMDTY_NATGAS' THEN 0.001
        WHEN 'CMDTY_COPPER' THEN 0.0005
        WHEN 'CMDTY_STD' THEN 0.01
        WHEN 'ETF_STD' THEN 0.01
        WHEN 'BOND_STD' THEN 0.01
        WHEN 'OPTION_STD' THEN 0.01
        WHEN 'FUT_ES' THEN 0.25
        WHEN 'FUT_NQ' THEN 0.25
        WHEN 'FUT_YM' THEN 1.0
        WHEN 'FUT_RTY' THEN 0.10
        WHEN 'FUT_CL' THEN 0.01
        WHEN 'FUT_GC' THEN 0.10
        WHEN 'FUT_SI' THEN 0.005
        WHEN 'FUT_STD' THEN 0.01
        WHEN 'CFD_US30' THEN 1.0
        WHEN 'CFD_SPX' THEN 0.1
        WHEN 'CFD_NAS100' THEN 0.25
        WHEN 'CFD_GOLD' THEN 0.01
        WHEN 'CFD_BTC' THEN 0.01
        WHEN 'CFD_STD' THEN 0.01
        ELSE 0.01
    END;
$$;



















-- =========================================================
-- DEFAULT PARTITIONS AS SAFETY NET
-- =========================================================

CREATE TABLE IF NOT EXISTS trades_default
PARTITION OF trades DEFAULT;

CREATE TABLE IF NOT EXISTS audit_logs_default
PARTITION OF audit_logs DEFAULT;






-- =========================================================
-- MONTHLY PARTITION CREATION HELPERS
-- =========================================================

CREATE OR REPLACE FUNCTION ensure_trades_partition(p_month_date DATE)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_start DATE;
    v_end DATE;
    v_partition_name TEXT;
BEGIN
    v_start := date_trunc('month', p_month_date)::date;
    v_end := (v_start + INTERVAL '1 month')::date;
    v_partition_name := format('trades_%s', to_char(v_start, 'YYYY_MM'));

    EXECUTE format(
        'CREATE TABLE IF NOT EXISTS %I PARTITION OF trades FOR VALUES FROM (%L) TO (%L)',
        v_partition_name,
        v_start,
        v_end
    );
END;
$$;

CREATE OR REPLACE FUNCTION ensure_audit_logs_partition(p_month_date DATE)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_start DATE;
    v_end DATE;
    v_partition_name TEXT;
BEGIN
    v_start := date_trunc('month', p_month_date)::date;
    v_end := (v_start + INTERVAL '1 month')::date;
    v_partition_name := format('audit_logs_%s', to_char(v_start, 'YYYY_MM'));

    EXECUTE format(
        'CREATE TABLE IF NOT EXISTS %I PARTITION OF audit_logs FOR VALUES FROM (%L) TO (%L)',
        v_partition_name,
        v_start,
        v_end
    );
END;
$$;

CREATE OR REPLACE FUNCTION ensure_future_partitions(
    p_months_back INTEGER DEFAULT 1,
    p_months_ahead INTEGER DEFAULT 12
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    i INTEGER;
    v_month DATE;
BEGIN
    FOR i IN -p_months_back .. p_months_ahead LOOP
        v_month := (date_trunc('month', CURRENT_DATE) + make_interval(months => i))::date;
        PERFORM ensure_trades_partition(v_month);
        PERFORM ensure_audit_logs_partition(v_month);
    END LOOP;
END;
$$;


SELECT ensure_future_partitions(1, 18);






-- =========================================================
-- STATS REFRESH FUNCTIONS
-- =========================================================

CREATE OR REPLACE FUNCTION refresh_trading_account_stats(p_account_id UUID)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_total_trades INTEGER;
    v_winning_trades INTEGER;
    v_losing_trades INTEGER;
    v_total_profit NUMERIC(15,2);
    v_total_loss NUMERIC(15,2);
    v_net_profit NUMERIC(15,2);
BEGIN
    SELECT
        COUNT(*)::INTEGER,
        COUNT(*) FILTER (WHERE is_winning = TRUE)::INTEGER,
        COUNT(*) FILTER (WHERE is_losing = TRUE)::INTEGER,
        COALESCE(SUM(net_profit) FILTER (WHERE is_winning = TRUE), 0)::NUMERIC(15,2),
        COALESCE(SUM(ABS(net_profit)) FILTER (WHERE is_losing = TRUE), 0)::NUMERIC(15,2),
        COALESCE(SUM(net_profit), 0)::NUMERIC(15,2)
    INTO
        v_total_trades,
        v_winning_trades,
        v_losing_trades,
        v_total_profit,
        v_total_loss,
        v_net_profit
    FROM trades
    WHERE account_id = p_account_id
      AND status = 'closed'
      AND deleted_at IS NULL;

    UPDATE trading_accounts
    SET
        total_trades = COALESCE(v_total_trades, 0),
        winning_trades = COALESCE(v_winning_trades, 0),
        losing_trades = COALESCE(v_losing_trades, 0),
        total_profit = COALESCE(v_total_profit, 0),
        total_loss = COALESCE(v_total_loss, 0),
        net_profit = COALESCE(v_net_profit, 0),
        updated_at = NOW()
    WHERE id = p_account_id;
END;
$$;

CREATE OR REPLACE FUNCTION refresh_strategy_stats(p_strategy_id UUID)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_usage_count INTEGER;
    v_total_trades INTEGER;
    v_win_rate NUMERIC(5,2);
    v_net_profit NUMERIC(15,2);
    v_profit_factor NUMERIC(10,2);
BEGIN
    SELECT
        COUNT(*)::INTEGER,
        COUNT(*) FILTER (WHERE status = 'closed' AND deleted_at IS NULL)::INTEGER,
        CASE
            WHEN COUNT(*) FILTER (WHERE status = 'closed' AND deleted_at IS NULL) > 0
                THEN ROUND(
                    (
                        COUNT(*) FILTER (
                            WHERE status = 'closed'
                              AND deleted_at IS NULL
                              AND is_winning = TRUE
                        )::NUMERIC
                        /
                        NULLIF(COUNT(*) FILTER (WHERE status = 'closed' AND deleted_at IS NULL), 0)
                    ) * 100,
                    2
                )
            ELSE 0
        END::NUMERIC(5,2),
        COALESCE(SUM(net_profit) FILTER (WHERE status = 'closed' AND deleted_at IS NULL), 0)::NUMERIC(15,2),
        CASE
            WHEN COALESCE(SUM(ABS(net_profit)) FILTER (
                WHERE status = 'closed'
                  AND deleted_at IS NULL
                  AND is_losing = TRUE
            ), 0) > 0
                THEN ROUND(
                    COALESCE(SUM(net_profit) FILTER (
                        WHERE status = 'closed'
                          AND deleted_at IS NULL
                          AND is_winning = TRUE
                    ), 0)
                    /
                    NULLIF(COALESCE(SUM(ABS(net_profit)) FILTER (
                        WHERE status = 'closed'
                          AND deleted_at IS NULL
                          AND is_losing = TRUE
                    ), 0), 0),
                    2
                )
            ELSE 0
        END::NUMERIC(10,2)
    INTO
        v_usage_count,
        v_total_trades,
        v_win_rate,
        v_net_profit,
        v_profit_factor
    FROM trades
    WHERE strategy_id = p_strategy_id;

    UPDATE strategies
    SET
        usage_count = COALESCE(v_usage_count, 0),
        total_trades = COALESCE(v_total_trades, 0),
        win_rate = COALESCE(v_win_rate, 0),
        net_profit = COALESCE(v_net_profit, 0),
        profit_factor = COALESCE(v_profit_factor, 0),
        updated_at = NOW()
    WHERE id = p_strategy_id;
END;
$$;



-- =========================================================
-- DEDUP PENDING/RUNNING STATS JOBS
-- =========================================================

CREATE UNIQUE INDEX IF NOT EXISTS uq_bg_jobs_pending_account_stats
ON background_jobs (
    job_type,
    user_id,
    (job_data->>'account_id')
)
WHERE status IN ('pending', 'running')
  AND job_type = 'refresh_account_stats';

CREATE UNIQUE INDEX IF NOT EXISTS uq_bg_jobs_pending_strategy_stats
ON background_jobs (
    job_type,
    user_id,
    (job_data->>'strategy_id')
)
WHERE status IN ('pending', 'running')
  AND job_type = 'refresh_strategy_stats';

CREATE UNIQUE INDEX IF NOT EXISTS uq_bg_jobs_pending_partition_maintenance
ON background_jobs (job_type)
WHERE status IN ('pending', 'running')
  AND job_type = 'ensure_future_partitions';

CREATE UNIQUE INDEX IF NOT EXISTS uq_bg_jobs_pending_mv_refresh
ON background_jobs (job_type)
WHERE status IN ('pending', 'running')
  AND job_type = 'refresh_trading_views';








  -- =========================================================
-- QUEUE HELPERS
-- =========================================================

CREATE OR REPLACE FUNCTION enqueue_account_stats_job(
    p_user_id UUID,
    p_account_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO background_jobs (
        user_id,
        job_type,
        job_name,
        job_data,
        priority,
        status,
        scheduled_at
    )
    VALUES (
        p_user_id,
        'refresh_account_stats',
        'Refresh trading account stats',
        jsonb_build_object('account_id', p_account_id),
        'normal',
        'pending',
        NOW()
    )
    ON CONFLICT ON CONSTRAINT uq_bg_jobs_pending_account_stats DO NOTHING;
EXCEPTION
    WHEN undefined_object THEN
        -- fallback if index-backed ON CONFLICT ON CONSTRAINT is unavailable
        IF NOT EXISTS (
            SELECT 1
            FROM background_jobs
            WHERE job_type = 'refresh_account_stats'
              AND user_id = p_user_id
              AND job_data->>'account_id' = p_account_id::text
              AND status IN ('pending', 'running')
        ) THEN
            INSERT INTO background_jobs (
                user_id, job_type, job_name, job_data, priority, status, scheduled_at
            ) VALUES (
                p_user_id,
                'refresh_account_stats',
                'Refresh trading account stats',
                jsonb_build_object('account_id', p_account_id),
                'normal',
                'pending',
                NOW()
            );
        END IF;
END;
$$;

CREATE OR REPLACE FUNCTION enqueue_strategy_stats_job(
    p_user_id UUID,
    p_strategy_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_strategy_id IS NULL THEN
        RETURN;
    END IF;

    INSERT INTO background_jobs (
        user_id,
        job_type,
        job_name,
        job_data,
        priority,
        status,
        scheduled_at
    )
    VALUES (
        p_user_id,
        'refresh_strategy_stats',
        'Refresh strategy stats',
        jsonb_build_object('strategy_id', p_strategy_id),
        'normal',
        'pending',
        NOW()
    )
    ON CONFLICT ON CONSTRAINT uq_bg_jobs_pending_strategy_stats DO NOTHING;
EXCEPTION
    WHEN undefined_object THEN
        IF NOT EXISTS (
            SELECT 1
            FROM background_jobs
            WHERE job_type = 'refresh_strategy_stats'
              AND user_id = p_user_id
              AND job_data->>'strategy_id' = p_strategy_id::text
              AND status IN ('pending', 'running')
        ) THEN
            INSERT INTO background_jobs (
                user_id, job_type, job_name, job_data, priority, status, scheduled_at
            ) VALUES (
                p_user_id,
                'refresh_strategy_stats',
                'Refresh strategy stats',
                jsonb_build_object('strategy_id', p_strategy_id),
                'normal',
                'pending',
                NOW()
            );
        END IF;
END;
$$;

CREATE OR REPLACE FUNCTION enqueue_partition_maintenance_job()
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM background_jobs
        WHERE job_type = 'ensure_future_partitions'
          AND status IN ('pending', 'running')
    ) THEN
        INSERT INTO background_jobs (
            job_type,
            job_name,
            job_data,
            priority,
            status,
            scheduled_at
        )
        VALUES (
            'ensure_future_partitions',
            'Ensure future partitions',
            jsonb_build_object('months_back', 1, 'months_ahead', 18),
            'high',
            'pending',
            NOW()
        );
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION enqueue_mv_refresh_job()
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM background_jobs
        WHERE job_type = 'refresh_trading_views'
          AND status IN ('pending', 'running')
    ) THEN
        INSERT INTO background_jobs (
            job_type,
            job_name,
            job_data,
            priority,
            status,
            scheduled_at
        )
        VALUES (
            'refresh_trading_views',
            'Refresh trading materialized views',
            '{}'::jsonb,
            'normal',
            'pending',
            NOW()
        );
    END IF;
END;
$$;




-- =========================================================
-- TRADE CHANGE -> QUEUE STATS JOBS
-- =========================================================

CREATE OR REPLACE FUNCTION trg_trades_enqueue_stats_jobs()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        PERFORM enqueue_account_stats_job(NEW.user_id, NEW.account_id);
        PERFORM enqueue_strategy_stats_job(NEW.user_id, NEW.strategy_id);
        PERFORM enqueue_mv_refresh_job();
        RETURN NEW;
    ELSIF TG_OP = 'UPDATE' THEN
        PERFORM enqueue_account_stats_job(NEW.user_id, NEW.account_id);
        PERFORM enqueue_mv_refresh_job();

        IF OLD.account_id IS DISTINCT FROM NEW.account_id THEN
            PERFORM enqueue_account_stats_job(OLD.user_id, OLD.account_id);
        END IF;

        IF OLD.strategy_id IS DISTINCT FROM NEW.strategy_id THEN
            PERFORM enqueue_strategy_stats_job(OLD.user_id, OLD.strategy_id);
        END IF;

        PERFORM enqueue_strategy_stats_job(NEW.user_id, NEW.strategy_id);
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        PERFORM enqueue_account_stats_job(OLD.user_id, OLD.account_id);
        PERFORM enqueue_strategy_stats_job(OLD.user_id, OLD.strategy_id);
        PERFORM enqueue_mv_refresh_job();
        RETURN OLD;
    END IF;

    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_trades_enqueue_stats_jobs ON trades;

CREATE TRIGGER trg_trades_enqueue_stats_jobs
    AFTER INSERT OR UPDATE OR DELETE ON trades
    FOR EACH ROW
    EXECUTE FUNCTION trg_trades_enqueue_stats_jobs();



-- =========================================================
-- JOB PROCESSOR FOR STATS / MAINTENANCE
-- =========================================================

CREATE OR REPLACE FUNCTION process_internal_maintenance_job(p_job_id UUID)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_job background_jobs;
    v_job_type TEXT;
    v_account_id UUID;
    v_strategy_id UUID;
    v_months_back INTEGER;
    v_months_ahead INTEGER;
BEGIN
    SELECT *
    INTO v_job
    FROM background_jobs
    WHERE id = p_job_id;

    IF v_job.id IS NULL THEN
        RAISE EXCEPTION 'Job not found: %', p_job_id;
    END IF;

    v_job_type := v_job.job_type;

    IF v_job_type = 'refresh_account_stats' THEN
        v_account_id := (v_job.job_data->>'account_id')::uuid;
        PERFORM refresh_trading_account_stats(v_account_id);

    ELSIF v_job_type = 'refresh_strategy_stats' THEN
        v_strategy_id := (v_job.job_data->>'strategy_id')::uuid;
        PERFORM refresh_strategy_stats(v_strategy_id);

    ELSIF v_job_type = 'ensure_future_partitions' THEN
        v_months_back := COALESCE((v_job.job_data->>'months_back')::integer, 1);
        v_months_ahead := COALESCE((v_job.job_data->>'months_ahead')::integer, 12);
        PERFORM ensure_future_partitions(v_months_back, v_months_ahead);

    ELSIF v_job_type = 'refresh_trading_views' THEN
        PERFORM refresh_trading_views();

    ELSE
        RAISE EXCEPTION 'Unsupported internal job_type: %', v_job_type;
    END IF;
END;
$$;


-- =========================================================
-- JOB PROCESSOR FOR STATS / MAINTENANCE
-- =========================================================

CREATE OR REPLACE FUNCTION process_internal_maintenance_job(p_job_id UUID)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_job background_jobs;
    v_job_type TEXT;
    v_account_id UUID;
    v_strategy_id UUID;
    v_months_back INTEGER;
    v_months_ahead INTEGER;
BEGIN
    SELECT *
    INTO v_job
    FROM background_jobs
    WHERE id = p_job_id;

    IF v_job.id IS NULL THEN
        RAISE EXCEPTION 'Job not found: %', p_job_id;
    END IF;

    v_job_type := v_job.job_type;

    IF v_job_type = 'refresh_account_stats' THEN
        v_account_id := (v_job.job_data->>'account_id')::uuid;
        PERFORM refresh_trading_account_stats(v_account_id);

    ELSIF v_job_type = 'refresh_strategy_stats' THEN
        v_strategy_id := (v_job.job_data->>'strategy_id')::uuid;
        PERFORM refresh_strategy_stats(v_strategy_id);

    ELSIF v_job_type = 'ensure_future_partitions' THEN
        v_months_back := COALESCE((v_job.job_data->>'months_back')::integer, 1);
        v_months_ahead := COALESCE((v_job.job_data->>'months_ahead')::integer, 12);
        PERFORM ensure_future_partitions(v_months_back, v_months_ahead);

    ELSIF v_job_type = 'refresh_trading_views' THEN
        PERFORM refresh_trading_views();

    ELSE
        RAISE EXCEPTION 'Unsupported internal job_type: %', v_job_type;
    END IF;
END;
$$;




	-- =========================================================
-- ONE-TIME BACKFILL OF CACHED STATS
-- =========================================================

DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT id FROM trading_accounts
    LOOP
        PERFORM refresh_trading_account_stats(r.id);
    END LOOP;

    FOR r IN
        SELECT id FROM strategies
    LOOP
        PERFORM refresh_strategy_stats(r.id);
    END LOOP;
END;
$$;


























-- Create function to log subscription changes
CREATE OR REPLACE FUNCTION log_subscription_changes()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO subscription_history (
        id,
        user_id,
        old_package_id,
        new_package_id,
        change_type,
        change_reason,
        effective_date,
        created_at
    ) VALUES (
        gen_random_uuid(),
        NEW.user_id,
        OLD.package_id,
        NEW.package_id,
        CASE 
            WHEN OLD.package_id IS NULL AND NEW.package_id IS NOT NULL THEN 'upgrade'
            WHEN OLD.package_id <> NEW.package_id AND 
                 (SELECT max_accounts FROM packages WHERE id = NEW.package_id) > 
                 (SELECT max_accounts FROM packages WHERE id = OLD.package_id) THEN 'upgrade'
            WHEN OLD.package_id <> NEW.package_id THEN 'downgrade'
            ELSE 'change'
        END,
        'Subscription package changed',
        CURRENT_DATE,
        NOW()
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for UPDATE operations
CREATE TRIGGER trigger_subscription_history
    AFTER UPDATE ON user_subscriptions
    FOR EACH ROW
    WHEN (OLD.package_id IS DISTINCT FROM NEW.package_id)
    EXECUTE FUNCTION log_subscription_changes();

-- Create trigger for INSERT operations (initial subscription)
CREATE OR REPLACE FUNCTION log_subscription_creation()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO subscription_history (
        id,
        user_id,
        old_package_id,
        new_package_id,
        change_type,
        change_reason,
        effective_date,
        created_at
    ) VALUES (
        gen_random_uuid(),
        NEW.user_id,
        NULL,
        NEW.package_id,
        'upgrade',
        'New subscription created',
        NEW.start_date,
        NOW()
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_subscription_history_insert
    AFTER INSERT ON user_subscriptions
    FOR EACH ROW
    EXECUTE FUNCTION log_subscription_creation();