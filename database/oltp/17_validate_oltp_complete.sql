/*
===============================================================================
17_validate_oltp_complete.sql

Objetivo:
    Validación integral del modelo OLTP IBM antes de iniciar la construcción
    del modelo dimensional OLAP.

Valida:
    1. Volumetría de entidades principales.
    2. Estado de los batches ETL.
    3. Integridad de card_transaction.
    4. Coherencia status / decline_reason.
    5. Integridad de transaction_error.
    6. Distribución de autorizaciones.
    7. Línea base de transacciones internacionales.
===============================================================================
*/


/*
===============================================================================
1. VOLUMETRÍA DEL OLTP
===============================================================================
*/

SELECT 'customer' AS entity, COUNT(*) AS rows
FROM oltp.customer

UNION ALL

SELECT 'customer_address', COUNT(*)
FROM oltp.customer_address

UNION ALL

SELECT 'customer_financial_profile', COUNT(*)
FROM oltp.customer_financial_profile

UNION ALL

SELECT 'card', COUNT(*)
FROM oltp.card

UNION ALL

SELECT 'merchant_category', COUNT(*)
FROM oltp.merchant_category

UNION ALL

SELECT 'merchant', COUNT(*)
FROM oltp.merchant

UNION ALL

SELECT 'merchant_location', COUNT(*)
FROM oltp.merchant_location

UNION ALL

SELECT 'error_catalog', COUNT(*)
FROM oltp.error_catalog

UNION ALL

SELECT 'transaction_error', COUNT(*)
FROM oltp.transaction_error

ORDER BY entity;


/*
===============================================================================
2. TRAZABILIDAD DE BATCHES ETL
===============================================================================
*/

SELECT
    batch_id,
    process_name,
    source_system,
    status,
    rows_read,
    rows_loaded,
    rows_rejected,
    start_ts,
    end_ts
FROM ctl.etl_batch
ORDER BY batch_id;


/*
===============================================================================
3. VALIDACIÓN INTEGRAL DE CARD_TRANSACTION

Esta consulta realiza un recorrido importante sobre card_transaction.
===============================================================================
*/

SELECT
    COUNT(*) AS total_transactions,

    COUNT(*) FILTER (
        WHERE t.amount = 0
    ) AS zero_amount_transactions,

    COUNT(*) FILTER (
        WHERE t.card_id IS NULL
    ) AS null_card_id,

    COUNT(*) FILTER (
        WHERE t.merchant_location_id IS NULL
    ) AS null_merchant_location_id,

    COUNT(*) FILTER (
        WHERE t.authorization_status_id IS NULL
    ) AS null_authorization_status_id,

    COUNT(*) FILTER (
        WHERE
            (
                s.status_code = 'DECLINED'
                AND t.decline_reason_id IS NULL
            )
            OR
            (
                s.status_code <> 'DECLINED'
                AND t.decline_reason_id IS NOT NULL
            )
    ) AS invalid_decline_reason_rules,

    COUNT(*) FILTER (
        WHERE c.issuer_country_code <> ml.country_code
    ) AS international_transactions,

    COUNT(*) FILTER (
        WHERE c.issuer_country_code <> ml.country_code
          AND s.status_code = 'DECLINED'
    ) AS international_declined_transactions,

    ROUND(
        100.0
        *
        COUNT(*) FILTER (
            WHERE c.issuer_country_code <> ml.country_code
              AND s.status_code = 'DECLINED'
        )
        /
        NULLIF(
            COUNT(*) FILTER (
                WHERE c.issuer_country_code <> ml.country_code
            ),
            0
        ),
        4
    ) AS international_decline_rate_pct

FROM oltp.card_transaction t

JOIN oltp.card c
  ON c.card_id = t.card_id

JOIN oltp.merchant_location ml
  ON ml.location_id = t.merchant_location_id

JOIN oltp.authorization_status s
  ON s.authorization_status_id = t.authorization_status_id;


/*
===============================================================================
4. DISTRIBUCIÓN DE ESTADOS Y MOTIVOS
===============================================================================
*/

SELECT
    s.status_code,

    COALESCE(
        d.reason_code,
        '<NULL>'
    ) AS decline_reason_code,

    COUNT(*) AS transactions

FROM oltp.card_transaction t

JOIN oltp.authorization_status s
  ON s.authorization_status_id = t.authorization_status_id

LEFT JOIN oltp.decline_reason d
  ON d.decline_reason_id = t.decline_reason_id

GROUP BY
    s.status_code,
    d.reason_code

ORDER BY
    CASE s.status_code
        WHEN 'APPROVED' THEN 1
        WHEN 'DECLINED' THEN 2
        WHEN 'ERROR' THEN 3
        WHEN 'REVERSED' THEN 4
        WHEN 'PENDING' THEN 5
        WHEN 'UNKNOWN' THEN 6
        ELSE 7
    END,
    transactions DESC;


/*
===============================================================================
5. VALIDACIÓN DE TRANSACTION_ERROR
===============================================================================
*/

SELECT
    COUNT(*) AS transaction_errors,

    COUNT(DISTINCT transaction_id)
        AS transactions_with_error,

    COUNT(*) FILTER (
        WHERE error_detail IS NULL
           OR BTRIM(error_detail) = ''
    ) AS blank_error_detail

FROM oltp.transaction_error;


/*
===============================================================================
6. DISTRIBUCIÓN DE ERRORES
===============================================================================
*/

SELECT
    ec.error_code,
    ec.error_description,
    COUNT(*) AS occurrences

FROM oltp.transaction_error te

JOIN oltp.error_catalog ec
  ON ec.error_id = te.error_id

GROUP BY
    ec.error_code,
    ec.error_description

ORDER BY occurrences DESC;


/*
===============================================================================
7. DISTRIBUCIÓN DOMÉSTICA / INTERNACIONAL POR ESTADO

Esta consulta será especialmente útil como línea base para comparar
posteriormente contra el modelo dimensional y Power BI.
===============================================================================
*/

SELECT
    CASE
        WHEN c.issuer_country_code <> ml.country_code
            THEN 'INTERNATIONAL'
        ELSE 'DOMESTIC'
    END AS transaction_scope,

    s.status_code,

    COUNT(*) AS transactions

FROM oltp.card_transaction t

JOIN oltp.card c
  ON c.card_id = t.card_id

JOIN oltp.merchant_location ml
  ON ml.location_id = t.merchant_location_id

JOIN oltp.authorization_status s
  ON s.authorization_status_id = t.authorization_status_id

GROUP BY
    CASE
        WHEN c.issuer_country_code <> ml.country_code
            THEN 'INTERNATIONAL'
        ELSE 'DOMESTIC'
    END,
    s.status_code

ORDER BY
    transaction_scope,
    transactions DESC;


/*
===============================================================================
8. DATA QUALITY DEL BATCH DE TRANSACCIONES
===============================================================================
*/

SELECT
    rule_code,
    severity,
    COUNT(*) AS issues

FROM ctl.data_quality_issue

WHERE batch_id = 15

GROUP BY
    rule_code,
    severity

ORDER BY issues DESC;