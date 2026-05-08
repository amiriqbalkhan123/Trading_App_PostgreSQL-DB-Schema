

-- Calculate expected backoff times
SELECT 
    retry_count,
    POWER(2, retry_count) * 60 as backoff_seconds,
    (POWER(2, retry_count) * 60) / 60 as backoff_minutes,
    CASE 
        WHEN retry_count = 0 THEN 'First attempt'
        WHEN retry_count = 1 THEN '2^1 × 60 = 120 seconds (2 minutes)'
        WHEN retry_count = 2 THEN '2^2 × 60 = 240 seconds (4 minutes)'
        WHEN retry_count = 3 THEN '2^3 × 60 = 480 seconds (8 minutes)'
        ELSE 'Max retries reached'
    END as description
FROM generate_series(0, 3) as retry_count;







-- Simulate job execution time calculation
WITH job_timing AS (
    SELECT 
        '2024-03-20 10:00:00'::timestamp as started_at,
        '2024-03-20 10:00:05'::timestamp as completed_at  -- 5 seconds later
)
SELECT 
    started_at,
    completed_at,
    EXTRACT(EPOCH FROM (completed_at - started_at)) as seconds,
    EXTRACT(EPOCH FROM (completed_at - started_at)) * 1000 as execution_time_ms,
    CASE 
        WHEN EXTRACT(EPOCH FROM (completed_at - started_at)) * 1000 = 5000 
        THEN '✅ CORRECT'
        ELSE '❌ INCORRECT'
    END as verification
FROM job_timing;
















-- Insert test jobs with different priorities
INSERT INTO background_jobs (
    id, job_type, priority, status, scheduled_at, created_at
) VALUES 
    (gen_random_uuid(), 'low_priority_job', 'low', 'pending', NOW(), NOW()),
    (gen_random_uuid(), 'normal_priority_job', 'normal', 'pending', NOW(), NOW()),
    (gen_random_uuid(), 'high_priority_job', 'high', 'pending', NOW(), NOW()),
    (gen_random_uuid(), 'critical_priority_job', 'critical', 'pending', NOW(), NOW());

-- Check order (critical should be first)
SELECT 
    priority,
    job_type,
    scheduled_at,
    created_at,
    CASE priority
        WHEN 'critical' THEN 1
        WHEN 'high' THEN 2
        WHEN 'normal' THEN 3
        WHEN 'low' THEN 4
    END as priority_order
FROM background_jobs
WHERE status = 'pending'
ORDER BY priority_order, scheduled_at, created_at;




























WITH transitions AS (
    SELECT 
        'pending' as from_status,
        'running' as to_status,
        true as should_work
    UNION ALL
    SELECT 'running', 'completed', true
    UNION ALL
    SELECT 'running', 'failed', true
    UNION ALL
    SELECT 'pending', 'cancelled', true
    UNION ALL
    SELECT 'pending', 'completed', false  -- Invalid!
    UNION ALL
    SELECT 'pending', 'failed', false      -- Invalid!
    UNION ALL
    SELECT 'completed', 'running', false    -- Invalid!
)
SELECT 
    from_status,
    to_status,
    should_work,
    CASE 
        WHEN should_work THEN '✅ ALLOWED'
        ELSE '❌ BLOCKED'
    END as validation
FROM transitions
ORDER BY should_work DESC;


















-- Simulate job failures and retries
WITH retry_scenario AS (
    SELECT 
        1 as current_retry,
        3 as max_retries
    UNION ALL
    SELECT 2, 3
    UNION ALL
    SELECT 3, 3
    UNION ALL
    SELECT 4, 3  -- Exceeds max
)
SELECT 
    current_retry,
    max_retries,
    CASE 
        WHEN current_retry <= max_retries THEN '🔄 Can retry'
        ELSE '❌ Permanently failed'
    END as retry_status,
    CASE 
        WHEN current_retry <= max_retries 
        THEN POWER(2, current_retry) * 60 || ' seconds backoff'
        ELSE 'No more retries'
    END as backoff
FROM retry_scenario;






















-- Create jobs with different scheduled times
INSERT INTO background_jobs (
    id, job_type, scheduled_at, status, created_at
) VALUES 
    (gen_random_uuid(), 'past_job', NOW() - INTERVAL '1 hour', 'pending', NOW()),
    (gen_random_uuid(), 'now_job', NOW(), 'pending', NOW()),
    (gen_random_uuid(), 'future_job', NOW() + INTERVAL '1 hour', 'pending', NOW());

-- Check which jobs are eligible to run
SELECT 
    job_type,
    scheduled_at,
    CASE 
        WHEN scheduled_at <= NOW() THEN '✅ Eligible to run'
        ELSE '⏳ Scheduled for future'
    END as run_eligibility,
    EXTRACT(EPOCH FROM (scheduled_at - NOW()))/60 as minutes_until_run
FROM background_jobs
WHERE status = 'pending'
ORDER BY scheduled_at;


