BEGIN;

-- ============================================================
-- VALIDACIÓN FINAL OLTP -> OLAP INCREMENTAL
--
-- Uso:
-- psql -v set_code=SYNTH_SET_01 ...
--
-- Valida:
--   * estado del dataset y batch
--   * volumen OLTP vs OLAP
--   * monto total
--   * unicidad
--   * estados
--   * geografía / international_flag
--   * KPI internacional
--   * flags
--   * dimensión fecha
--   * customer/card/merchant/location/MCC
--   * decline reason
--   * entry mode
--   * primary error
--   * preservación IBM_CORE
--
-- Si todo pasa:
--   olap_status -> VALIDATED
-- ============================================================


-- ------------------------------------------------------------
-- 1. CONTEXTO
-- ------------------------------------------------------------

CREATE TEMP TABLE tmp_ctx
ON COMMIT DROP
AS
SELECT
    d.set_code,
    d.source_system_code,
    d.key_prefix,
    d.target_transactions,
    d.oltp_status,
    d.olap_status,
    d.olap_last_batch_id,
    ss.source_system_id
FROM ctl.synthetic_dataset d
JOIN oltp.source_system ss
  ON ss.source_code = d.source_system_code
WHERE d.set_code = UPPER(BTRIM(:'set_code'));


DO $$
DECLARE
    v_count INTEGER;
BEGIN
    SELECT COUNT(*)
    INTO v_count
    FROM tmp_ctx;

    IF v_count <> 1 THEN
        RAISE EXCEPTION
            'Expected exactly one dataset context, found %',
            v_count;
    END IF;
END;
$$;


-- ------------------------------------------------------------
-- 2. ESTADO
-- ------------------------------------------------------------

DO $$
DECLARE
    x RECORD;
    v_batch_status VARCHAR;
BEGIN

    SELECT *
    INTO x
    FROM tmp_ctx;

    IF x.oltp_status <> 'VALIDATED' THEN
        RAISE EXCEPTION
            'OLTP status must be VALIDATED. Current=%',
            x.oltp_status;
    END IF;

    IF x.olap_status <> 'LOADING' THEN
        RAISE EXCEPTION
            'OLAP status must be LOADING. Current=%',
            x.olap_status;
    END IF;

    SELECT status
    INTO v_batch_status
    FROM ctl.etl_batch
    WHERE batch_id = x.olap_last_batch_id;

    IF v_batch_status <> 'RUNNING' THEN
        RAISE EXCEPTION
            'OLAP batch % must be RUNNING. Current=%',
            x.olap_last_batch_id,
            v_batch_status;
    END IF;

END;
$$;


-- ------------------------------------------------------------
-- 3. PRIMARY ERROR ESPERADO DESDE OLTP
-- ------------------------------------------------------------

CREATE TEMP TABLE tmp_expected_primary_error
ON COMMIT DROP
AS
SELECT
    q.transaction_id,
    q.error_code
FROM (
    SELECT
        te.transaction_id,
        ec.error_code,

        ROW_NUMBER() OVER (
            PARTITION BY te.transaction_id
            ORDER BY
                CASE ec.error_code
                    WHEN 'TECHNICAL_ERROR'     THEN 10
                    WHEN 'INVALID_CARD'        THEN 20
                    WHEN 'EXPIRED_CARD'        THEN 30
                    WHEN 'BAD_PIN'             THEN 40
                    WHEN 'BAD_CVV'             THEN 50
                    WHEN 'BAD_ZIPCODE'         THEN 60
                    WHEN 'INSUFFICIENT_FUNDS'  THEN 70
                    ELSE 999
                END,
                ec.error_code
        ) AS rn

    FROM tmp_ctx x

    JOIN oltp.card_transaction t
      ON t.source_system_id = x.source_system_id
     AND t.source_transaction_key
         LIKE x.key_prefix || ':TX:%'

    JOIN oltp.transaction_error te
      ON te.transaction_id = t.transaction_id

    JOIN oltp.error_catalog ec
      ON ec.error_id = te.error_id
) q
WHERE q.rn = 1;


-- ------------------------------------------------------------
-- 4. AGREGADO OLTP
-- ------------------------------------------------------------

CREATE TEMP TABLE tmp_oltp_summary
ON COMMIT DROP
AS
SELECT
    COUNT(*) AS transactions,
    COUNT(DISTINCT t.source_transaction_key)
        AS distinct_source_keys,

    ROUND(SUM(t.amount), 2) AS total_amount,

    COUNT(*) FILTER (
        WHERE aus.status_code = 'APPROVED'
    ) AS approved,

    COUNT(*) FILTER (
        WHERE aus.status_code = 'DECLINED'
    ) AS declined,

    COUNT(*) FILTER (
        WHERE aus.status_code = 'REVERSED'
    ) AS reversed,

    COUNT(*) FILTER (
        WHERE aus.status_code = 'ERROR'
    ) AS error_status,

    COUNT(*) FILTER (
        WHERE ml.country_code = 'US'
    ) AS domestic,

    COUNT(*) FILTER (
        WHERE ml.country_code NOT IN ('US','ZZ')
    ) AS international,

    COUNT(*) FILTER (
        WHERE ml.country_code = 'ZZ'
    ) AS unknown_geo,

    COUNT(*) FILTER (
        WHERE ml.country_code NOT IN ('US','ZZ')
          AND aus.status_code = 'DECLINED'
    ) AS international_declined,

    COUNT(*) FILTER (
        WHERE t.error_flag
    ) AS error_flagged,

    COUNT(*) FILTER (
        WHERE t.fraud_flag
    ) AS fraud_flagged

FROM tmp_ctx x

JOIN oltp.card_transaction t
  ON t.source_system_id = x.source_system_id
 AND t.source_transaction_key
     LIKE x.key_prefix || ':TX:%'

JOIN oltp.card c
  ON c.card_id = t.card_id

JOIN oltp.merchant_location ml
  ON ml.location_id = t.merchant_location_id

JOIN oltp.authorization_status aus
  ON aus.authorization_status_id =
     t.authorization_status_id;


-- ------------------------------------------------------------
-- 5. AGREGADO OLAP
-- ------------------------------------------------------------

CREATE TEMP TABLE tmp_olap_summary
ON COMMIT DROP
AS
SELECT
    COUNT(*) AS transactions,

    COUNT(DISTINCT f.source_transaction_key)
        AS distinct_source_keys,

    COUNT(DISTINCT f.oltp_transaction_id)
        AS distinct_oltp_ids,

    ROUND(SUM(f.amount), 2)
        AS total_amount,

    SUM(f.transaction_count)
        AS transaction_count_sum,

    COUNT(*) FILTER (
        WHERE f.approved_flag
    ) AS approved,

    COUNT(*) FILTER (
        WHERE f.declined_flag
    ) AS declined,

    COUNT(*) FILTER (
        WHERE f.reversed_flag
    ) AS reversed,

    COUNT(*) FILTER (
        WHERE das.status_code = 'ERROR'
    ) AS error_status,

    COUNT(*) FILTER (
        WHERE f.international_flag IS FALSE
    ) AS domestic,

    COUNT(*) FILTER (
        WHERE f.international_flag IS TRUE
    ) AS international,

    COUNT(*) FILTER (
        WHERE f.international_flag IS NULL
    ) AS unknown_geo,

    COUNT(*) FILTER (
        WHERE f.international_flag IS TRUE
          AND f.declined_flag
    ) AS international_declined,

    COUNT(*) FILTER (
        WHERE f.error_flag
    ) AS error_flagged,

    COUNT(*) FILTER (
        WHERE f.fraud_flag
    ) AS fraud_flagged

FROM tmp_ctx x

JOIN olap.fact_transaction f
  ON f.source_system_code = x.source_system_code
 AND f.source_transaction_key
     LIKE x.key_prefix || ':TX:%'

JOIN olap.dim_authorization_status das
  ON das.authorization_status_key =
     f.authorization_status_key;


-- ------------------------------------------------------------
-- 6. RECONCILIACIÓN FILA A FILA
-- ------------------------------------------------------------

CREATE TEMP TABLE tmp_row_reconciliation
ON COMMIT DROP
AS
SELECT

    COUNT(*) AS matched_rows,

    COUNT(*) FILTER (
        WHERE t.transaction_id IS NULL
    ) AS missing_oltp_transaction,

    COUNT(*) FILTER (
        WHERE f.amount IS DISTINCT FROM t.amount
    ) AS amount_mismatch,

    COUNT(*) FILTER (
        WHERE f.transaction_datetime
              IS DISTINCT FROM t.transaction_datetime
    ) AS datetime_mismatch,

    COUNT(*) FILTER (
        WHERE f.transaction_hour
              IS DISTINCT FROM
              EXTRACT(
                  HOUR FROM
                  (t.transaction_datetime AT TIME ZONE 'UTC')
              )::smallint
    ) AS hour_mismatch,

    COUNT(*) FILTER (
        WHERE dd.full_date
              IS DISTINCT FROM
              (t.transaction_datetime AT TIME ZONE 'UTC')::date
    ) AS date_mismatch,

    COUNT(*) FILTER (
        WHERE dcu.source_customer_key
              IS DISTINCT FROM cu.source_customer_key
    ) AS customer_mismatch,

    COUNT(*) FILTER (
        WHERE dca.source_card_key
              IS DISTINCT FROM c.source_card_key
    ) AS card_mismatch,

    COUNT(*) FILTER (
        WHERE dm.source_merchant_key
              IS DISTINCT FROM m.source_merchant_key
    ) AS merchant_mismatch,

    COUNT(*) FILTER (
        WHERE dml.source_location_key
              IS DISTINCT FROM ml.source_location_key
    ) AS location_mismatch,

    COUNT(*) FILTER (
        WHERE dmc.category_scheme
              IS DISTINCT FROM mc.category_scheme
           OR dmc.mcc_code
              IS DISTINCT FROM mc.category_code
    ) AS mcc_mismatch,

    COUNT(*) FILTER (
        WHERE das.status_code
              IS DISTINCT FROM aus.status_code
    ) AS status_mismatch,

    COUNT(*) FILTER (
        WHERE ddr.reason_code
              IS DISTINCT FROM
              COALESCE(dr.reason_code, 'NOT_APPLICABLE')
    ) AS decline_reason_mismatch,

    COUNT(*) FILTER (
        WHERE dem.entry_mode_code
              IS DISTINCT FROM
              CASE
                  WHEN UPPER(BTRIM(COALESCE(t.entry_mode,'')))
                       IN ('SWIPE','SWIPE TRANSACTION')
                      THEN 'SWIPE'

                  WHEN UPPER(BTRIM(COALESCE(t.entry_mode,'')))
                       IN ('CHIP','CHIP TRANSACTION')
                      THEN 'CHIP'

                  WHEN UPPER(BTRIM(COALESCE(t.entry_mode,'')))
                       IN ('ONLINE','ONLINE TRANSACTION')
                      THEN 'ONLINE'

                  ELSE 'UNKNOWN'
              END
    ) AS entry_mode_mismatch,

    COUNT(*) FILTER (
        WHERE de.error_code
              IS DISTINCT FROM
              COALESCE(pe.error_code, 'NOT_APPLICABLE')
    ) AS primary_error_mismatch,

    COUNT(*) FILTER (
        WHERE f.international_flag
              IS DISTINCT FROM
              CASE
                  WHEN c.issuer_country_code IS NULL
                    OR BTRIM(c.issuer_country_code) = 'ZZ'
                    OR ml.country_code IS NULL
                    OR BTRIM(ml.country_code) = 'ZZ'
                      THEN NULL

                  WHEN BTRIM(c.issuer_country_code)
                       <> BTRIM(ml.country_code)
                      THEN TRUE

                  ELSE FALSE
              END
    ) AS international_flag_mismatch,

    COUNT(*) FILTER (
        WHERE f.approved_flag
              IS DISTINCT FROM
              (aus.status_code = 'APPROVED')
    ) AS approved_flag_mismatch,

    COUNT(*) FILTER (
        WHERE f.declined_flag
              IS DISTINCT FROM
              (aus.status_code = 'DECLINED')
    ) AS declined_flag_mismatch,

    COUNT(*) FILTER (
        WHERE f.reversed_flag
              IS DISTINCT FROM
              (aus.status_code = 'REVERSED')
    ) AS reversed_flag_mismatch,

    COUNT(*) FILTER (
        WHERE f.error_flag
              IS DISTINCT FROM t.error_flag
    ) AS error_flag_mismatch,

    COUNT(*) FILTER (
        WHERE f.fraud_flag
              IS DISTINCT FROM t.fraud_flag
    ) AS fraud_flag_mismatch,

    COUNT(*) FILTER (
        WHERE f.transaction_count <> 1
    ) AS invalid_transaction_count

FROM tmp_ctx x

JOIN olap.fact_transaction f
  ON f.source_system_code = x.source_system_code
 AND f.source_transaction_key
     LIKE x.key_prefix || ':TX:%'

LEFT JOIN oltp.card_transaction t
  ON t.transaction_id = f.oltp_transaction_id

LEFT JOIN oltp.card c
  ON c.card_id = t.card_id

LEFT JOIN oltp.customer cu
  ON cu.customer_id = c.customer_id

LEFT JOIN oltp.merchant_location ml
  ON ml.location_id = t.merchant_location_id

LEFT JOIN oltp.merchant m
  ON m.merchant_id = ml.merchant_id

LEFT JOIN oltp.merchant_category mc
  ON mc.category_id = t.category_id

LEFT JOIN oltp.authorization_status aus
  ON aus.authorization_status_id =
     t.authorization_status_id

LEFT JOIN oltp.decline_reason dr
  ON dr.decline_reason_id =
     t.decline_reason_id

LEFT JOIN tmp_expected_primary_error pe
  ON pe.transaction_id = t.transaction_id


LEFT JOIN olap.dim_date dd
  ON dd.date_key = f.date_key

LEFT JOIN olap.dim_customer dcu
  ON dcu.customer_key = f.customer_key

LEFT JOIN olap.dim_card dca
  ON dca.card_key = f.card_key

LEFT JOIN olap.dim_merchant dm
  ON dm.merchant_key = f.merchant_key

LEFT JOIN olap.dim_merchant_location dml
  ON dml.merchant_location_key =
     f.merchant_location_key

LEFT JOIN olap.dim_merchant_category dmc
  ON dmc.merchant_category_key =
     f.merchant_category_key

LEFT JOIN olap.dim_authorization_status das
  ON das.authorization_status_key =
     f.authorization_status_key

LEFT JOIN olap.dim_decline_reason ddr
  ON ddr.decline_reason_key =
     f.decline_reason_key

LEFT JOIN olap.dim_entry_mode dem
  ON dem.entry_mode_key =
     f.entry_mode_key

LEFT JOIN olap.dim_error de
  ON de.error_key =
     f.primary_error_key;


-- ------------------------------------------------------------
-- 7. VALIDACIÓN DE AGREGADOS
-- ------------------------------------------------------------

DO $$
DECLARE
    x RECORD;
    o RECORD;
    w RECORD;
    r RECORD;
BEGIN

    SELECT *
    INTO x
    FROM tmp_ctx;

    SELECT *
    INTO o
    FROM tmp_oltp_summary;

    SELECT *
    INTO w
    FROM tmp_olap_summary;

    SELECT *
    INTO r
    FROM tmp_row_reconciliation;


    IF o.transactions <> x.target_transactions THEN
        RAISE EXCEPTION
            'OLTP transaction count mismatch: expected %, found %',
            x.target_transactions,
            o.transactions;
    END IF;


    IF w.transactions <> x.target_transactions THEN
        RAISE EXCEPTION
            'OLAP fact count mismatch: expected %, found %',
            x.target_transactions,
            w.transactions;
    END IF;


    IF w.distinct_source_keys <> x.target_transactions
       OR w.distinct_oltp_ids <> x.target_transactions
    THEN
        RAISE EXCEPTION
            'OLAP uniqueness validation failed';
    END IF;


    IF w.transaction_count_sum <> x.target_transactions THEN
        RAISE EXCEPTION
            'transaction_count sum mismatch';
    END IF;


    IF o.total_amount <> w.total_amount THEN
        RAISE EXCEPTION
            'Amount mismatch: OLTP %, OLAP %',
            o.total_amount,
            w.total_amount;
    END IF;


    IF o.approved <> w.approved
       OR o.declined <> w.declined
       OR o.reversed <> w.reversed
       OR o.error_status <> w.error_status
    THEN
        RAISE EXCEPTION
            'Authorization status reconciliation failed';
    END IF;


    IF o.domestic <> w.domestic
       OR o.international <> w.international
       OR o.unknown_geo <> w.unknown_geo
    THEN
        RAISE EXCEPTION
            'Geography reconciliation failed';
    END IF;


    IF o.international_declined
       <> w.international_declined
    THEN
        RAISE EXCEPTION
            'International declined reconciliation failed';
    END IF;


    IF o.error_flagged <> w.error_flagged
       OR o.fraud_flagged <> w.fraud_flagged
    THEN
        RAISE EXCEPTION
            'Flag reconciliation failed';
    END IF;


    IF
        r.missing_oltp_transaction <> 0
        OR r.amount_mismatch <> 0
        OR r.datetime_mismatch <> 0
        OR r.hour_mismatch <> 0
        OR r.date_mismatch <> 0
        OR r.customer_mismatch <> 0
        OR r.card_mismatch <> 0
        OR r.merchant_mismatch <> 0
        OR r.location_mismatch <> 0
        OR r.mcc_mismatch <> 0
        OR r.status_mismatch <> 0
        OR r.decline_reason_mismatch <> 0
        OR r.entry_mode_mismatch <> 0
        OR r.primary_error_mismatch <> 0
        OR r.international_flag_mismatch <> 0
        OR r.approved_flag_mismatch <> 0
        OR r.declined_flag_mismatch <> 0
        OR r.reversed_flag_mismatch <> 0
        OR r.error_flag_mismatch <> 0
        OR r.fraud_flag_mismatch <> 0
        OR r.invalid_transaction_count <> 0
    THEN
        RAISE EXCEPTION
            'One or more row-level reconciliation controls failed';
    END IF;

END;
$$;


-- ------------------------------------------------------------
-- 8. DECLINE REASON OLTP vs OLAP
-- ------------------------------------------------------------

CREATE TEMP TABLE tmp_decline_compare
ON COMMIT DROP
AS
WITH oltp_counts AS (
    SELECT
        COALESCE(dr.reason_code, 'NOT_APPLICABLE')
            AS reason_code,
        COUNT(*) AS oltp_count

    FROM tmp_ctx x

    JOIN oltp.card_transaction t
      ON t.source_system_id = x.source_system_id
     AND t.source_transaction_key
         LIKE x.key_prefix || ':TX:%'

    LEFT JOIN oltp.decline_reason dr
      ON dr.decline_reason_id =
         t.decline_reason_id

    GROUP BY 1
),

olap_counts AS (
    SELECT
        ddr.reason_code,
        COUNT(*) AS olap_count

    FROM tmp_ctx x

    JOIN olap.fact_transaction f
      ON f.source_system_code = x.source_system_code
     AND f.source_transaction_key
         LIKE x.key_prefix || ':TX:%'

    JOIN olap.dim_decline_reason ddr
      ON ddr.decline_reason_key =
         f.decline_reason_key

    GROUP BY 1
)

SELECT
    COALESCE(o.reason_code, w.reason_code) AS reason_code,
    COALESCE(o.oltp_count, 0) AS oltp_count,
    COALESCE(w.olap_count, 0) AS olap_count

FROM oltp_counts o

FULL OUTER JOIN olap_counts w
  ON w.reason_code = o.reason_code;


DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM tmp_decline_compare
        WHERE oltp_count <> olap_count
    )
    THEN
        RAISE EXCEPTION
            'Decline reason distribution mismatch';
    END IF;
END;
$$;


-- ------------------------------------------------------------
-- 9. PRIMARY ERROR OLTP vs OLAP
-- ------------------------------------------------------------

CREATE TEMP TABLE tmp_primary_error_compare
ON COMMIT DROP
AS
WITH oltp_counts AS (
    SELECT
        COALESCE(pe.error_code, 'NOT_APPLICABLE')
            AS error_code,
        COUNT(*) AS oltp_count

    FROM tmp_ctx x

    JOIN oltp.card_transaction t
      ON t.source_system_id = x.source_system_id
     AND t.source_transaction_key
         LIKE x.key_prefix || ':TX:%'

    LEFT JOIN tmp_expected_primary_error pe
      ON pe.transaction_id = t.transaction_id

    GROUP BY 1
),

olap_counts AS (
    SELECT
        de.error_code,
        COUNT(*) AS olap_count

    FROM tmp_ctx x

    JOIN olap.fact_transaction f
      ON f.source_system_code = x.source_system_code
     AND f.source_transaction_key
         LIKE x.key_prefix || ':TX:%'

    JOIN olap.dim_error de
      ON de.error_key = f.primary_error_key

    GROUP BY 1
)

SELECT
    COALESCE(o.error_code, w.error_code)
        AS error_code,

    COALESCE(o.oltp_count, 0)
        AS oltp_count,

    COALESCE(w.olap_count, 0)
        AS olap_count

FROM oltp_counts o

FULL OUTER JOIN olap_counts w
  ON w.error_code = o.error_code;


DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM tmp_primary_error_compare
        WHERE oltp_count <> olap_count
    )
    THEN
        RAISE EXCEPTION
            'Primary error distribution mismatch';
    END IF;
END;
$$;


-- ------------------------------------------------------------
-- 10. PRESERVACIÓN IBM_CORE
-- ------------------------------------------------------------

DO $$
DECLARE
    v_ibm_facts BIGINT;
BEGIN

    SELECT COUNT(*)
    INTO v_ibm_facts
    FROM olap.fact_transaction
    WHERE source_system_code = 'IBM_CORE';


    IF v_ibm_facts <> 24366687 THEN
        RAISE EXCEPTION
            'IBM_CORE fact count changed. Expected 24366687, found %',
            v_ibm_facts;
    END IF;

END;
$$;


-- ------------------------------------------------------------
-- 11. MARCAR OLAP VALIDATED
-- ------------------------------------------------------------

UPDATE ctl.synthetic_dataset d
SET
    olap_status = 'VALIDATED',
    updated_at = CURRENT_TIMESTAMP
FROM tmp_ctx x
WHERE d.set_code = x.set_code
  AND d.olap_status = 'LOADING';


-- ------------------------------------------------------------
-- 12. RESULTADO PRINCIPAL
-- ------------------------------------------------------------

SELECT
    x.set_code,
    d.oltp_status,
    d.olap_status,
    d.oltp_last_batch_id,
    d.olap_last_batch_id,

    o.transactions AS oltp_transactions,
    w.transactions AS olap_transactions,

    o.total_amount AS oltp_amount,
    w.total_amount AS olap_amount,

    w.approved,
    w.declined,
    w.reversed,
    w.error_status,

    w.domestic,
    w.international,
    w.unknown_geo,

    w.international_declined,

    ROUND(
        100.0
        * w.international_declined
        / NULLIF(w.international, 0),
        4
    ) AS international_denial_rate_pct,

    w.error_flagged,
    w.fraud_flagged

FROM tmp_ctx x

JOIN ctl.synthetic_dataset d
  ON d.set_code = x.set_code

CROSS JOIN tmp_oltp_summary o

CROSS JOIN tmp_olap_summary w;


-- ------------------------------------------------------------
-- 13. FILA-A-FILA
-- ------------------------------------------------------------

SELECT *
FROM tmp_row_reconciliation;


-- ------------------------------------------------------------
-- 14. DECLINE REASONS
-- ------------------------------------------------------------

SELECT *
FROM tmp_decline_compare
ORDER BY olap_count DESC;


-- ------------------------------------------------------------
-- 15. PRIMARY ERRORS
-- ------------------------------------------------------------

SELECT *
FROM tmp_primary_error_compare
ORDER BY olap_count DESC;


COMMIT;