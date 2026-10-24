\echo '--- OLTP tables ---'
SELECT table_schema, table_name
FROM information_schema.tables
WHERE table_schema = 'oltp'
ORDER BY table_name;

\echo '--- OLTP views ---'
SELECT table_schema, table_name
FROM information_schema.views
WHERE table_schema = 'oltp'
ORDER BY table_name;

\echo '--- Seed counts ---'
SELECT 'source_system' AS object_name, COUNT(*) AS row_count FROM oltp.source_system
UNION ALL
SELECT 'country', COUNT(*) FROM oltp.country
UNION ALL
SELECT 'authorization_status', COUNT(*) FROM oltp.authorization_status
UNION ALL
SELECT 'decline_reason', COUNT(*) FROM oltp.decline_reason
UNION ALL
SELECT 'error_catalog', COUNT(*) FROM oltp.error_catalog
ORDER BY object_name;

\echo '--- Authorization statuses ---'
SELECT authorization_status_id, status_code, status_name
FROM oltp.authorization_status
ORDER BY authorization_status_id;

\echo '--- Core relationship count ---'
SELECT COUNT(*) AS foreign_key_count
FROM information_schema.table_constraints
WHERE table_schema = 'oltp'
  AND constraint_type = 'FOREIGN KEY';

\echo '--- Verify international derivation view exists ---'
SELECT table_schema, table_name
FROM information_schema.views
WHERE table_schema = 'oltp'
  AND table_name = 'vw_transaction_enriched';
