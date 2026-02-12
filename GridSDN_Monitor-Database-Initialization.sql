-- GridSDN Monitor - Database Initialization Script

-- Enable TimescaleDB extension
CREATE EXTENSION IF NOT EXISTS timescaledb;

-- Enable PostGIS for geospatial features (optional, for location-based queries)
CREATE EXTENSION IF NOT EXISTS postgis;

-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Create schemas
CREATE SCHEMA IF NOT EXISTS network;
CREATE SCHEMA IF NOT EXISTS measurements;
CREATE SCHEMA IF NOT EXISTS analytics;
CREATE SCHEMA IF NOT EXISTS alerts;

-- Set search path
SET search_path TO public, network, measurements, analytics, alerts;

-- Network Elements Table
CREATE TABLE IF NOT EXISTS network.elements (
    element_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    element_type VARCHAR(50) NOT NULL CHECK (element_type IN ('substation', 'transformer', 'feeder', 'breaker', 'line', 'bus', 'generator', 'load')),
    name VARCHAR(255) NOT NULL,
    description TEXT,
    location GEOGRAPHY(POINT, 4326),
    rated_capacity FLOAT,
    voltage_level VARCHAR(50) CHECK (voltage_level IN ('transmission', 'distribution', 'low')),
    parent_id UUID REFERENCES network.elements(element_id),
    metadata JSONB,
    status VARCHAR(20) DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'maintenance')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_elements_type ON network.elements(element_type);
CREATE INDEX idx_elements_parent ON network.elements(parent_id);
CREATE INDEX idx_elements_location ON network.elements USING GIST(location);

-- Measurement Points Table
CREATE TABLE IF NOT EXISTS measurements.points (
    point_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    element_id UUID NOT NULL REFERENCES network.elements(element_id) ON DELETE CASCADE,
    measurement_type VARCHAR(50) NOT NULL CHECK (measurement_type IN ('voltage', 'current', 'power', 'frequency', 'temperature', 'power_factor', 'harmonic')),
    unit VARCHAR(20) NOT NULL,
    sampling_rate INTEGER NOT NULL DEFAULT 1, -- samples per second
    alarm_low FLOAT,
    alarm_high FLOAT,
    alarm_critical_low FLOAT,
    alarm_critical_high FLOAT,
    metadata JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_points_element ON measurements.points(element_id);
CREATE INDEX idx_points_type ON measurements.points(measurement_type);

-- Time-Series Measurements (Hypertable)
CREATE TABLE IF NOT EXISTS measurements.timeseries (
    time TIMESTAMP WITH TIME ZONE NOT NULL,
    point_id UUID NOT NULL REFERENCES measurements.points(point_id) ON DELETE CASCADE,
    value DOUBLE PRECISION NOT NULL,
    quality VARCHAR(20) DEFAULT 'good' CHECK (quality IN ('good', 'suspect', 'bad')),
    flags JSONB
);

-- Convert to hypertable with 1-day chunks
SELECT create_hypertable('measurements.timeseries', 'time', 
    chunk_time_interval => INTERVAL '1 day',
    if_not_exists => TRUE
);

-- Create indexes on hypertable
CREATE INDEX IF NOT EXISTS idx_timeseries_point_time ON measurements.timeseries (point_id, time DESC);

-- Compression policy: compress chunks older than 7 days
ALTER TABLE measurements.timeseries SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'point_id',
    timescaledb.compress_orderby = 'time DESC'
);

SELECT add_compression_policy('measurements.timeseries', INTERVAL '7 days', if_not_exists => TRUE);

-- Retention policy: drop chunks older than 2 years
SELECT add_retention_policy('measurements.timeseries', INTERVAL '2 years', if_not_exists => TRUE);

-- Alerts Table
CREATE TABLE IF NOT EXISTS alerts.alerts (
    alert_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    timestamp TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    severity VARCHAR(20) NOT NULL CHECK (severity IN ('info', 'warning', 'critical')),
    element_id UUID REFERENCES network.elements(element_id) ON DELETE SET NULL,
    point_id UUID REFERENCES measurements.points(point_id) ON DELETE SET NULL,
    alert_type VARCHAR(50) NOT NULL,
    message TEXT NOT NULL,
    details JSONB,
    acknowledged BOOLEAN DEFAULT FALSE,
    acknowledged_by VARCHAR(255),
    acknowledged_at TIMESTAMP WITH TIME ZONE,
    cleared BOOLEAN DEFAULT FALSE,
    cleared_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Convert alerts to hypertable
SELECT create_hypertable('alerts.alerts', 'timestamp',
    chunk_time_interval => INTERVAL '7 days',
    if_not_exists => TRUE
);

CREATE INDEX IF NOT EXISTS idx_alerts_severity ON alerts.alerts(severity);
CREATE INDEX IF NOT EXISTS idx_alerts_element ON alerts.alerts(element_id);
CREATE INDEX IF NOT EXISTS idx_alerts_unacknowledged ON alerts.alerts(acknowledged) WHERE NOT acknowledged;

-- Equipment Health Tracking
CREATE TABLE IF NOT EXISTS analytics.equipment_health (
    health_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    element_id UUID NOT NULL REFERENCES network.elements(element_id) ON DELETE CASCADE,
    timestamp TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    health_score FLOAT CHECK (health_score >= 0 AND health_score <= 100),
    predicted_failure_date DATE,
    remaining_useful_life_days INTEGER,
    maintenance_priority VARCHAR(20) CHECK (maintenance_priority IN ('low', 'medium', 'high', 'critical')),
    indicators JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

SELECT create_hypertable('analytics.equipment_health', 'timestamp',
    chunk_time_interval => INTERVAL '30 days',
    if_not_exists => TRUE
);

CREATE INDEX IF NOT EXISTS idx_health_element ON analytics.equipment_health(element_id, timestamp DESC);

-- Load Forecasts
CREATE TABLE IF NOT EXISTS analytics.load_forecasts (
    forecast_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    element_id UUID NOT NULL REFERENCES network.elements(element_id) ON DELETE CASCADE,
    forecast_timestamp TIMESTAMP WITH TIME ZONE NOT NULL,
    generated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    predicted_load FLOAT NOT NULL,
    confidence_interval_lower FLOAT,
    confidence_interval_upper FLOAT,
    model_version VARCHAR(50),
    metadata JSONB
);

SELECT create_hypertable('analytics.load_forecasts', 'forecast_timestamp',
    chunk_time_interval => INTERVAL '7 days',
    if_not_exists => TRUE
);

CREATE INDEX IF NOT EXISTS idx_forecasts_element ON analytics.load_forecasts(element_id, forecast_timestamp DESC);

-- Users Table (for authentication)
CREATE TABLE IF NOT EXISTS public.users (
    user_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    hashed_password VARCHAR(255) NOT NULL,
    full_name VARCHAR(255),
    role VARCHAR(50) DEFAULT 'operator' CHECK (role IN ('admin', 'engineer', 'operator', 'viewer')),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_users_username ON public.users(username);
CREATE INDEX idx_users_email ON public.users(email);

-- Continuous Aggregates for performance

-- 5-minute average aggregation
CREATE MATERIALIZED VIEW IF NOT EXISTS measurements.timeseries_5min
WITH (timescaledb.continuous) AS
SELECT
    time_bucket('5 minutes', time) AS bucket,
    point_id,
    AVG(value) AS avg_value,
    MIN(value) AS min_value,
    MAX(value) AS max_value,
    COUNT(*) AS sample_count
FROM measurements.timeseries
GROUP BY bucket, point_id
WITH NO DATA;

-- Refresh policy for 5-minute aggregates
SELECT add_continuous_aggregate_policy('measurements.timeseries_5min',
    start_offset => INTERVAL '1 hour',
    end_offset => INTERVAL '5 minutes',
    schedule_interval => INTERVAL '5 minutes',
    if_not_exists => TRUE
);

-- Hourly aggregation
CREATE MATERIALIZED VIEW IF NOT EXISTS measurements.timeseries_hourly
WITH (timescaledb.continuous) AS
SELECT
    time_bucket('1 hour', time) AS bucket,
    point_id,
    AVG(value) AS avg_value,
    MIN(value) AS min_value,
    MAX(value) AS max_value,
    COUNT(*) AS sample_count
FROM measurements.timeseries
GROUP BY bucket, point_id
WITH NO DATA;

SELECT add_continuous_aggregate_policy('measurements.timeseries_hourly',
    start_offset => INTERVAL '3 hours',
    end_offset => INTERVAL '1 hour',
    schedule_interval => INTERVAL '1 hour',
    if_not_exists => TRUE
);

-- Utility Functions

-- Function to calculate equipment health score
CREATE OR REPLACE FUNCTION analytics.calculate_health_score(
    p_element_id UUID,
    p_lookback_hours INTEGER DEFAULT 24
) RETURNS FLOAT AS $$
DECLARE
    v_health_score FLOAT;
BEGIN
    -- Simplified health calculation based on alarm violations
    -- In production, this would use ML models
    SELECT 
        100 - (COUNT(*) * 5) -- Deduct 5 points per violation
    INTO v_health_score
    FROM measurements.timeseries ts
    JOIN measurements.points p ON ts.point_id = p.point_id
    WHERE p.element_id = p_element_id
        AND ts.time >= NOW() - (p_lookback_hours || ' hours')::INTERVAL
        AND (
            ts.value < p.alarm_critical_low OR
            ts.value > p.alarm_critical_high
        );
    
    RETURN GREATEST(0, COALESCE(v_health_score, 100));
END;
$$ LANGUAGE plpgsql;

-- Function to get latest measurement
CREATE OR REPLACE FUNCTION measurements.get_latest_value(p_point_id UUID)
RETURNS TABLE (
    time TIMESTAMP WITH TIME ZONE,
    value DOUBLE PRECISION,
    quality VARCHAR
) AS $$
BEGIN
    RETURN QUERY
    SELECT ts.time, ts.value, ts.quality
    FROM measurements.timeseries ts
    WHERE ts.point_id = p_point_id
    ORDER BY ts.time DESC
    LIMIT 1;
END;
$$ LANGUAGE plpgsql;

-- Trigger to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_elements_updated_at
    BEFORE UPDATE ON network.elements
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_users_updated_at
    BEFORE UPDATE ON public.users
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Grant permissions (adjust as needed for production)
GRANT USAGE ON SCHEMA network, measurements, analytics, alerts TO gridsdn_user;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA network, measurements, analytics, alerts TO gridsdn_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA network, measurements, analytics, alerts TO gridsdn_user;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA network, measurements, analytics, alerts TO gridsdn_user;

-- Insert initial admin user (password: admin123 - CHANGE IN PRODUCTION!)
-- Password hash generated with bcrypt
INSERT INTO public.users (username, email, hashed_password, full_name, role)
VALUES (
    'admin',
    'admin@gridsdn.local',
    '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5lJ4NQqLyqKZe',
    'System Administrator',
    'admin'
) ON CONFLICT DO NOTHING;

-- Create sample network topology for testing
INSERT INTO network.elements (element_id, element_type, name, voltage_level, rated_capacity) VALUES
    ('00000000-0000-0000-0000-000000000001', 'substation', 'Main Substation A', 'transmission', 500000),
    ('00000000-0000-0000-0000-000000000002', 'transformer', 'Transformer T1', 'transmission', 150000),
    ('00000000-0000-0000-0000-000000000003', 'feeder', 'Feeder F1', 'distribution', 10000),
    ('00000000-0000-0000-0000-000000000004', 'breaker', 'Circuit Breaker CB1', 'distribution', 5000)
ON CONFLICT DO NOTHING;

-- Create sample measurement points
INSERT INTO measurements.points (point_id, element_id, measurement_type, unit, sampling_rate, alarm_low, alarm_high) VALUES
    ('00000000-0000-0000-0000-000000000101', '00000000-0000-0000-0000-000000000001', 'voltage', 'kV', 1, 110, 130),
    ('00000000-0000-0000-0000-000000000102', '00000000-0000-0000-0000-000000000002', 'current', 'A', 1, 0, 800),
    ('00000000-0000-0000-0000-000000000103', '00000000-0000-0000-0000-000000000003', 'power', 'MW', 1, 0, 8)
ON CONFLICT DO NOTHING;

COMMIT;
