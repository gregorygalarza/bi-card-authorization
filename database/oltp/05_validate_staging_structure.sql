\echo '--- STAGING tables ---'
SELECT table_schema, table_name
FROM information_schema.tables
WHERE table_schema = 'stg'
ORDER BY table_name;

\echo '--- Column counts by STAGING table ---'
SELECT table_name, COUNT(*) AS column_count
FROM information_schema.columns
WHERE table_schema = 'stg'
GROUP BY table_name
ORDER BY table_name;

\echo '--- Foreign keys STAGING -> CTL ---'
SELECT tc.table_schema, tc.table_name, tc.constraint_name
FROM information_schema.table_constraints tc
WHERE tc.table_schema = 'stg'
  AND tc.constraint_type = 'FOREIGN KEY'
ORDER BY tc.table_name, tc.constraint_name;
