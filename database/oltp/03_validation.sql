\echo '--- Schemas ---'
SELECT schema_name
FROM information_schema.schemata
WHERE schema_name IN ('ctl','stg','oltp')
ORDER BY schema_name;

\echo '--- Control tables ---'
SELECT table_schema, table_name
FROM information_schema.tables
WHERE table_schema = 'ctl'
ORDER BY table_name;

\echo '--- Smoke test: etl_batch ---'
INSERT INTO ctl.etl_batch (
    process_name,
    source_system,
    status
)
VALUES (
    'SMOKE_TEST',
    'MANUAL',
    'SUCCESS'
)
RETURNING batch_id, process_name, status, start_ts;

SELECT *
FROM ctl.etl_batch
ORDER BY batch_id DESC
LIMIT 5;
