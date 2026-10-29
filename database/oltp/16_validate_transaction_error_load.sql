/*
===============================================================================
16_validate_transaction_error_load.sql

Objetivo:
    Validar la futura carga de oltp.transaction_error.

Criterios:
    - Solo considerar transacciones que realmente existen en
      oltp.card_transaction.
    - Separar errors_raw cuando contiene múltiples errores.
    - Resolver cada error individual contra ctl.source_error_mapping.
    - Verificar que exista su correspondiente error_catalog.
    - Detectar duplicados potenciales para la PK:
          (transaction_id, error_id)
===============================================================================
*/

WITH source_errors AS (
    SELECT
        f.file_hash_sha256
            || ':'
            || t.source_row_number::text
            AS source_transaction_key,

        BTRIM(e.error_text) AS source_error_pattern

    FROM stg.ibm_transactions_raw t

    JOIN ctl.etl_file f
      ON f.etl_file_id = t.etl_file_id

    CROSS JOIN LATERAL unnest(
        string_to_array(t.errors_raw, ',')
    ) AS e(error_text)

    WHERE t.etl_file_id = 4
      AND NULLIF(BTRIM(t.errors_raw), '') IS NOT NULL
),

resolved AS (
    SELECT
        ct.transaction_id,
        se.source_transaction_key,
        se.source_error_pattern,

        m.response_code AS error_code,
        ec.error_id

    FROM source_errors se

    /*
        Esta unión excluye automáticamente las filas fuente que no llegaron
        a card_transaction, por ejemplo amount = 0.
    */
    JOIN oltp.card_transaction ct
      ON ct.source_system_id = 1
     AND ct.source_transaction_key = se.source_transaction_key

    LEFT JOIN ctl.source_error_mapping m
      ON m.source_system_code = 'IBM_CORE'
     AND m.source_error_pattern = se.source_error_pattern
     AND m.active_flag = TRUE

    LEFT JOIN oltp.error_catalog ec
      ON ec.error_code = m.response_code
     AND ec.active_flag = TRUE
),

summary AS (
    SELECT
        COUNT(*) AS total_error_occurrences,

        COUNT(DISTINCT transaction_id)
            AS transactions_with_error,

        COUNT(*) FILTER (
            WHERE error_code IS NULL
        ) AS unmapped_source_errors,

        COUNT(*) FILTER (
            WHERE error_code IS NOT NULL
              AND error_id IS NULL
        ) AS missing_error_catalog

    FROM resolved
),

duplicates AS (
    SELECT
        COUNT(*) AS duplicate_transaction_error_pairs
    FROM (
        SELECT
            transaction_id,
            error_id
        FROM resolved
        WHERE error_id IS NOT NULL
        GROUP BY
            transaction_id,
            error_id
        HAVING COUNT(*) > 1
    ) d
)

SELECT
    s.total_error_occurrences,
    s.transactions_with_error,
    s.unmapped_source_errors,
    s.missing_error_catalog,
    d.duplicate_transaction_error_pairs
FROM summary s
CROSS JOIN duplicates d;


/*
===============================================================================
Distribución por tipo de error
===============================================================================
*/

WITH source_errors AS (
    SELECT
        f.file_hash_sha256
            || ':'
            || t.source_row_number::text
            AS source_transaction_key,

        BTRIM(e.error_text) AS source_error_pattern

    FROM stg.ibm_transactions_raw t

    JOIN ctl.etl_file f
      ON f.etl_file_id = t.etl_file_id

    CROSS JOIN LATERAL unnest(
        string_to_array(t.errors_raw, ',')
    ) AS e(error_text)

    WHERE t.etl_file_id = 4
      AND NULLIF(BTRIM(t.errors_raw), '') IS NOT NULL
)

SELECT
    se.source_error_pattern,
    m.response_code AS error_code,
    COUNT(*) AS occurrences

FROM source_errors se

JOIN oltp.card_transaction ct
  ON ct.source_system_id = 1
 AND ct.source_transaction_key = se.source_transaction_key

LEFT JOIN ctl.source_error_mapping m
  ON m.source_system_code = 'IBM_CORE'
 AND m.source_error_pattern = se.source_error_pattern
 AND m.active_flag = TRUE

GROUP BY
    se.source_error_pattern,
    m.response_code

ORDER BY
    occurrences DESC,
    se.source_error_pattern;