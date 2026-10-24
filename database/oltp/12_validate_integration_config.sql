\echo '--- Integration parameters ---'
SELECT parameter_code, parameter_value, data_type
FROM ctl.integration_parameter
ORDER BY parameter_code;

\echo '--- source_user_id technical column ---'
SELECT table_schema, table_name, column_name, data_type
FROM information_schema.columns
WHERE table_schema='stg' AND table_name='ibm_users_raw' AND column_name='source_user_id';

\echo '--- US state/territory codes ---'
SELECT COUNT(*) AS us_state_code_count FROM ctl.us_state_code;

\echo '--- Merchant country bucket coverage ---'
WITH bucket_coverage AS (
    SELECT g.bucket, COUNT(m.bucket_from) AS matches
    FROM generate_series(0,99) AS g(bucket)
    LEFT JOIN ctl.merchant_country_bucket m
      ON g.bucket BETWEEN m.bucket_from AND m.bucket_to
    GROUP BY g.bucket
)
SELECT
    COUNT(*) FILTER (WHERE matches=1) AS buckets_valid,
    COUNT(*) FILTER (WHERE matches=0) AS buckets_missing,
    COUNT(*) FILTER (WHERE matches>1) AS buckets_overlapped
FROM bucket_coverage;

\echo '--- Source error mappings ---'
SELECT source_system_code, source_error_pattern, priority,
       target_status_code, target_decline_reason_code, response_code
FROM ctl.source_error_mapping
ORDER BY priority;

\echo '--- Determinism smoke test ---'
SELECT
    ctl.fn_sha256_hex('IBM_TEST') AS hash_1,
    ctl.fn_sha256_hex('IBM_TEST') AS hash_2,
    ctl.fn_bucket_100('IBM_TEST') AS bucket_1,
    ctl.fn_bucket_100('IBM_TEST') AS bucket_2;

\echo '--- Expected counts ---'
SELECT 'integration_parameter' AS object_name, COUNT(*) AS row_count FROM ctl.integration_parameter
UNION ALL SELECT 'us_state_code', COUNT(*) FROM ctl.us_state_code
UNION ALL SELECT 'merchant_country_bucket', COUNT(*) FROM ctl.merchant_country_bucket
UNION ALL SELECT 'source_error_mapping', COUNT(*) FROM ctl.source_error_mapping
ORDER BY object_name;
