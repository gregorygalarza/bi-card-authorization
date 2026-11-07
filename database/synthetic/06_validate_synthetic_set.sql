BEGIN;

-- ============================================================
-- VALIDATE SYNTHETIC DATASET - OLTP
--
-- Ejecutar con:
--
-- psql -v set_code=SYNTH_SET_01 ...
--
-- Valida:
--   maestros
--   transacciones
--   estados
--   geografía
--   entry mode
--   decline reasons
--   fraude
--   errores
--   reglas semánticas
--   ausencia del set en OLAP
--
-- Si todo es correcto:
--   OLTP status -> VALIDATED
-- ============================================================


-- ------------------------------------------------------------
-- 1. CONTEXTO
-- ------------------------------------------------------------

CREATE TEMP TABLE tmp_synthetic_context
ON COMMIT DROP
AS
SELECT
    d.set_code,
    d.profile_code,
    d.source_system_code,
    ss.source_system_id,
    d.key_prefix,

    d.target_customers,
    d.target_cards,
    d.target_merchants,
    d.target_locations,
    d.target_transactions,

    d.transaction_date_from,
    d.transaction_date_to,

    d.oltp_status,
    d.olap_status,
    d.oltp_last_batch_id

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
    FROM tmp_synthetic_context;

    IF v_count <> 1 THEN
        RAISE EXCEPTION
            'Expected exactly one synthetic dataset context, found %',
            v_count;
    END IF;

END;
$$;


-- ------------------------------------------------------------
-- 2. ESTADO DEL DATASET Y BATCH
-- ------------------------------------------------------------

DO $$
DECLARE
    v_set_code      VARCHAR;
    v_oltp_status   VARCHAR;
    v_olap_status   VARCHAR;
    v_batch_id      BIGINT;
    v_batch_status  VARCHAR;
BEGIN

    SELECT
        set_code,
        oltp_status,
        olap_status,
        oltp_last_batch_id
    INTO
        v_set_code,
        v_oltp_status,
        v_olap_status,
        v_batch_id
    FROM tmp_synthetic_context;


    IF v_oltp_status <> 'LOADED' THEN
        RAISE EXCEPTION
            'Dataset % must be LOADED before validation. Current status: %',
            v_set_code,
            v_oltp_status;
    END IF;


    IF v_olap_status <> 'PENDING' THEN
        RAISE EXCEPTION
            'Dataset % OLAP status must be PENDING. Current status: %',
            v_set_code,
            v_olap_status;
    END IF;


    SELECT status
    INTO v_batch_status
    FROM ctl.etl_batch
    WHERE batch_id = v_batch_id;


    IF v_batch_status <> 'RUNNING' THEN
        RAISE EXCEPTION
            'Dataset % batch % must be RUNNING. Current status: %',
            v_set_code,
            v_batch_id,
            v_batch_status;
    END IF;

END;
$$;


-- ------------------------------------------------------------
-- 3. MAESTROS
-- ------------------------------------------------------------

CREATE TEMP TABLE tmp_synthetic_master_summary
ON COMMIT DROP
AS
SELECT

    (
        SELECT COUNT(*)
        FROM oltp.customer c
        CROSS JOIN tmp_synthetic_context x
        WHERE c.source_system_id = x.source_system_id
          AND c.source_customer_key
              LIKE x.key_prefix || ':CUSTOMER:%'
    ) AS customers,

    (
        SELECT COUNT(*)
        FROM oltp.customer_address ca
        JOIN oltp.customer c
          ON c.customer_id = ca.customer_id
        CROSS JOIN tmp_synthetic_context x
        WHERE c.source_system_id = x.source_system_id
          AND c.source_customer_key
              LIKE x.key_prefix || ':CUSTOMER:%'
    ) AS addresses,

    (
        SELECT COUNT(*)
        FROM oltp.customer_financial_profile fp
        JOIN oltp.customer c
          ON c.customer_id = fp.customer_id
        CROSS JOIN tmp_synthetic_context x
        WHERE c.source_system_id = x.source_system_id
          AND c.source_customer_key
              LIKE x.key_prefix || ':CUSTOMER:%'
    ) AS financial_profiles,

    (
        SELECT COUNT(*)
        FROM oltp.card c
        CROSS JOIN tmp_synthetic_context x
        WHERE c.source_system_id = x.source_system_id
          AND c.source_card_key
              LIKE x.key_prefix || ':CARD:%'
    ) AS cards,

    (
        SELECT COUNT(*)
        FROM oltp.merchant m
        CROSS JOIN tmp_synthetic_context x
        WHERE m.source_system_id = x.source_system_id
          AND m.source_merchant_key
              LIKE x.key_prefix || ':MERCHANT:%'
    ) AS merchants,

    (
        SELECT COUNT(*)
        FROM oltp.merchant_location ml
        JOIN oltp.merchant m
          ON m.merchant_id = ml.merchant_id
        CROSS JOIN tmp_synthetic_context x
        WHERE m.source_system_id = x.source_system_id
          AND ml.source_location_key
              LIKE x.key_prefix || ':LOCATION:%'
    ) AS locations;


DO $$
DECLARE
    x RECORD;
    s RECORD;
BEGIN

    SELECT *
    INTO x
    FROM tmp_synthetic_context;

    SELECT *
    INTO s
    FROM tmp_synthetic_master_summary;


    IF s.customers <> x.target_customers THEN
        RAISE EXCEPTION
            'Customer count mismatch: expected %, found %',
            x.target_customers,
            s.customers;
    END IF;


    IF s.addresses <> x.target_customers THEN
        RAISE EXCEPTION
            'Address count mismatch: expected %, found %',
            x.target_customers,
            s.addresses;
    END IF;


    IF s.financial_profiles <> x.target_customers THEN
        RAISE EXCEPTION
            'Financial profile count mismatch: expected %, found %',
            x.target_customers,
            s.financial_profiles;
    END IF;


    IF s.cards <> x.target_cards THEN
        RAISE EXCEPTION
            'Card count mismatch: expected %, found %',
            x.target_cards,
            s.cards;
    END IF;


    IF s.merchants <> x.target_merchants THEN
        RAISE EXCEPTION
            'Merchant count mismatch: expected %, found %',
            x.target_merchants,
            s.merchants;
    END IF;


    IF s.locations <> x.target_locations THEN
        RAISE EXCEPTION
            'Location count mismatch: expected %, found %',
            x.target_locations,
            s.locations;
    END IF;

END;
$$;


-- ------------------------------------------------------------
-- 4. RESUMEN TRANSACCIONAL
-- ------------------------------------------------------------

CREATE TEMP TABLE tmp_synthetic_transaction_summary
ON COMMIT DROP
AS
SELECT
    COUNT(*) AS transactions,

    COUNT(DISTINCT t.source_transaction_key)
        AS distinct_source_keys,

    MIN(
        (t.transaction_datetime AT TIME ZONE 'UTC')::date
    ) AS min_transaction_date,

    MAX(
        (t.transaction_datetime AT TIME ZONE 'UTC')::date
    ) AS max_transaction_date,

    COUNT(*) FILTER (
        WHERE t.amount = 0
    ) AS zero_amounts,


    -- Estados

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


    -- Geografía

    COUNT(*) FILTER (
        WHERE ml.country_code = 'US'
    ) AS domestic,

    COUNT(*) FILTER (
        WHERE ml.country_code NOT IN ('US', 'ZZ')
    ) AS international,

    COUNT(*) FILTER (
        WHERE ml.country_code = 'ZZ'
    ) AS unknown_geography,


    -- KPI internacional

    COUNT(*) FILTER (
        WHERE ml.country_code NOT IN ('US', 'ZZ')
          AND aus.status_code = 'DECLINED'
    ) AS international_declined,


    -- Entry mode

    COUNT(*) FILTER (
        WHERE t.entry_mode = 'Swipe Transaction'
    ) AS swipe,

    COUNT(*) FILTER (
        WHERE t.entry_mode = 'Chip Transaction'
    ) AS chip,

    COUNT(*) FILTER (
        WHERE t.entry_mode = 'Online Transaction'
    ) AS online,


    -- Flags

    COUNT(*) FILTER (
        WHERE t.error_flag IS TRUE
    ) AS error_flagged,

    COUNT(*) FILTER (
        WHERE t.fraud_flag IS TRUE
    ) AS fraud_flagged,


    -- Reglas

    COUNT(*) FILTER (
        WHERE aus.status_code = 'REVERSED'
          AND t.amount >= 0
    ) AS invalid_reversed_amount,

    COUNT(*) FILTER (
        WHERE aus.status_code <> 'REVERSED'
          AND t.amount <= 0
    ) AS invalid_non_reversed_amount,

    COUNT(*) FILTER (
        WHERE aus.status_code = 'DECLINED'
          AND t.decline_reason_id IS NULL
    ) AS declined_without_reason,

    COUNT(*) FILTER (
        WHERE aus.status_code <> 'DECLINED'
          AND t.decline_reason_id IS NOT NULL
    ) AS non_declined_with_reason,

    COUNT(*) FILTER (
        WHERE dr.reason_code = 'CREDIT_LIMIT_EXCEEDED'
          AND t.amount <= c.credit_limit
    ) AS invalid_credit_limit_exceeded,

    COUNT(*) FILTER (
        WHERE dr.reason_code = 'EXPIRED_CARD'
          AND (
              c.expiration_year IS NULL
              OR c.expiration_month IS NULL
              OR make_date(
                    c.expiration_year,
                    c.expiration_month,
                    1
                 )
                 >=
                 date_trunc(
                    'month',
                    t.transaction_datetime AT TIME ZONE 'UTC'
                 )::date
          )
    ) AS invalid_expired_card

FROM tmp_synthetic_context x

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
     t.authorization_status_id

LEFT JOIN oltp.decline_reason dr
  ON dr.decline_reason_id =
     t.decline_reason_id;


-- ------------------------------------------------------------
-- 5. TARGETS PRINCIPALES
-- ------------------------------------------------------------

CREATE TEMP TABLE tmp_synthetic_targets
ON COMMIT DROP
AS
SELECT
    dt.set_code,

    MAX(target_count) FILTER (
        WHERE metric_group = 'AUTH_STATUS'
          AND metric_code = 'APPROVED'
    ) AS approved,

    MAX(target_count) FILTER (
        WHERE metric_group = 'AUTH_STATUS'
          AND metric_code = 'DECLINED'
    ) AS declined,

    MAX(target_count) FILTER (
        WHERE metric_group = 'AUTH_STATUS'
          AND metric_code = 'REVERSED'
    ) AS reversed,

    MAX(target_count) FILTER (
        WHERE metric_group = 'AUTH_STATUS'
          AND metric_code = 'ERROR'
    ) AS error_status,

    MAX(target_count) FILTER (
        WHERE metric_group = 'GEOGRAPHY'
          AND metric_code = 'DOMESTIC'
    ) AS domestic,

    MAX(target_count) FILTER (
        WHERE metric_group = 'GEOGRAPHY'
          AND metric_code = 'INTERNATIONAL'
    ) AS international,

    MAX(target_count) FILTER (
        WHERE metric_group = 'GEOGRAPHY'
          AND metric_code = 'UNKNOWN'
    ) AS unknown_geography,

    MAX(target_count) FILTER (
        WHERE metric_group = 'KPI'
          AND metric_code = 'INTERNATIONAL_DECLINED'
    ) AS international_declined,

    MAX(target_count) FILTER (
        WHERE metric_group = 'ENTRY_MODE'
          AND metric_code = 'SWIPE'
    ) AS swipe,

    MAX(target_count) FILTER (
        WHERE metric_group = 'ENTRY_MODE'
          AND metric_code = 'CHIP'
    ) AS chip,

    MAX(target_count) FILTER (
        WHERE metric_group = 'ENTRY_MODE'
          AND metric_code = 'ONLINE'
    ) AS online,

    MAX(target_count) FILTER (
        WHERE metric_group = 'ERROR_SUMMARY'
          AND metric_code = 'TRANSACTIONS_WITH_ERROR'
    ) AS error_flagged,

    MAX(target_count) FILTER (
        WHERE metric_group = 'FRAUD'
          AND metric_code = 'TRUE'
    ) AS fraud_flagged

FROM ctl.synthetic_dataset_target dt

JOIN tmp_synthetic_context x
  ON x.set_code = dt.set_code

GROUP BY dt.set_code;


-- ------------------------------------------------------------
-- 6. COMPARAR TARGETS PRINCIPALES
-- ------------------------------------------------------------

DO $$
DECLARE
    x RECORD;
    s RECORD;
    t RECORD;
BEGIN

    SELECT *
    INTO x
    FROM tmp_synthetic_context;

    SELECT *
    INTO s
    FROM tmp_synthetic_transaction_summary;

    SELECT *
    INTO t
    FROM tmp_synthetic_targets;


    IF s.transactions <> x.target_transactions THEN
        RAISE EXCEPTION
            'Transaction count mismatch: expected %, found %',
            x.target_transactions,
            s.transactions;
    END IF;


    IF s.distinct_source_keys <> x.target_transactions THEN
        RAISE EXCEPTION
            'Distinct transaction key mismatch: expected %, found %',
            x.target_transactions,
            s.distinct_source_keys;
    END IF;


    IF s.min_transaction_date <> x.transaction_date_from
       OR s.max_transaction_date <> x.transaction_date_to
    THEN
        RAISE EXCEPTION
            'Transaction date range mismatch: expected % to %, found % to %',
            x.transaction_date_from,
            x.transaction_date_to,
            s.min_transaction_date,
            s.max_transaction_date;
    END IF;


    IF s.zero_amounts <> 0 THEN
        RAISE EXCEPTION
            'Zero amount transactions found: %',
            s.zero_amounts;
    END IF;


    IF s.approved <> t.approved
       OR s.declined <> t.declined
       OR s.reversed <> t.reversed
       OR s.error_status <> t.error_status
    THEN
        RAISE EXCEPTION
            'Authorization status targets do not match';
    END IF;


    IF s.domestic <> t.domestic
       OR s.international <> t.international
       OR s.unknown_geography <> t.unknown_geography
    THEN
        RAISE EXCEPTION
            'Geography targets do not match';
    END IF;


    IF s.international_declined
       <> t.international_declined
    THEN
        RAISE EXCEPTION
            'International declined target mismatch';
    END IF;


    IF s.swipe <> t.swipe
       OR s.chip <> t.chip
       OR s.online <> t.online
    THEN
        RAISE EXCEPTION
            'Entry mode targets do not match';
    END IF;


    IF s.error_flagged <> t.error_flagged THEN
        RAISE EXCEPTION
            'Error flag target mismatch: expected %, found %',
            t.error_flagged,
            s.error_flagged;
    END IF;


    IF s.fraud_flagged <> t.fraud_flagged THEN
        RAISE EXCEPTION
            'Fraud flag target mismatch: expected %, found %',
            t.fraud_flagged,
            s.fraud_flagged;
    END IF;


    IF s.invalid_reversed_amount <> 0
       OR s.invalid_non_reversed_amount <> 0
       OR s.declined_without_reason <> 0
       OR s.non_declined_with_reason <> 0
       OR s.invalid_credit_limit_exceeded <> 0
       OR s.invalid_expired_card <> 0
    THEN
        RAISE EXCEPTION
            'One or more transaction business rules failed';
    END IF;

END;
$$;


-- ------------------------------------------------------------
-- 7. DECLINE REASON DISTRIBUTION
-- ------------------------------------------------------------

CREATE TEMP TABLE tmp_actual_decline_reason
ON COMMIT DROP
AS
SELECT
    dr.reason_code AS metric_code,
    COUNT(*) AS actual_count

FROM tmp_synthetic_context x

JOIN oltp.card_transaction t
  ON t.source_system_id = x.source_system_id
 AND t.source_transaction_key
     LIKE x.key_prefix || ':TX:%'

JOIN oltp.decline_reason dr
  ON dr.decline_reason_id =
     t.decline_reason_id

GROUP BY dr.reason_code;


DO $$
BEGIN

    IF EXISTS (
        SELECT 1

        FROM ctl.synthetic_dataset_target dt

        JOIN tmp_synthetic_context x
          ON x.set_code = dt.set_code

        LEFT JOIN tmp_actual_decline_reason a
          ON a.metric_code = dt.metric_code

        WHERE dt.metric_group = 'DECLINE_REASON'
          AND COALESCE(a.actual_count, 0)
              <> dt.target_count
    )
    THEN
        RAISE EXCEPTION
            'Decline reason distribution does not match target';
    END IF;

END;
$$;


-- ------------------------------------------------------------
-- 8. ERROR OCCURRENCES
-- ------------------------------------------------------------

CREATE TEMP TABLE tmp_actual_error_occurrence
ON COMMIT DROP
AS
SELECT
    ec.error_code AS metric_code,
    COUNT(*) AS actual_count

FROM tmp_synthetic_context x

JOIN oltp.card_transaction t
  ON t.source_system_id = x.source_system_id
 AND t.source_transaction_key
     LIKE x.key_prefix || ':TX:%'

JOIN oltp.transaction_error te
  ON te.transaction_id = t.transaction_id

JOIN oltp.error_catalog ec
  ON ec.error_id = te.error_id

GROUP BY ec.error_code;


DO $$
DECLARE
    v_occurrences       BIGINT;
    v_transactions      BIGINT;
    v_target_occurrences BIGINT;
    v_target_transactions BIGINT;
BEGIN

    SELECT
        COUNT(*),
        COUNT(DISTINCT te.transaction_id)

    INTO
        v_occurrences,
        v_transactions

    FROM tmp_synthetic_context x

    JOIN oltp.card_transaction t
      ON t.source_system_id = x.source_system_id
     AND t.source_transaction_key
         LIKE x.key_prefix || ':TX:%'

    JOIN oltp.transaction_error te
      ON te.transaction_id = t.transaction_id;


    SELECT
        MAX(target_count)
            FILTER (
                WHERE metric_code = 'ERROR_OCCURRENCES'
            ),

        MAX(target_count)
            FILTER (
                WHERE metric_code = 'TRANSACTIONS_WITH_ERROR'
            )

    INTO
        v_target_occurrences,
        v_target_transactions

    FROM ctl.synthetic_dataset_target dt

    JOIN tmp_synthetic_context x
      ON x.set_code = dt.set_code

    WHERE dt.metric_group = 'ERROR_SUMMARY';


    IF v_occurrences <> v_target_occurrences THEN
        RAISE EXCEPTION
            'Error occurrence target mismatch: expected %, found %',
            v_target_occurrences,
            v_occurrences;
    END IF;


    IF v_transactions <> v_target_transactions THEN
        RAISE EXCEPTION
            'Transactions-with-error target mismatch: expected %, found %',
            v_target_transactions,
            v_transactions;
    END IF;


    IF EXISTS (
        SELECT 1

        FROM ctl.synthetic_dataset_target dt

        JOIN tmp_synthetic_context x
          ON x.set_code = dt.set_code

        LEFT JOIN tmp_actual_error_occurrence a
          ON a.metric_code = dt.metric_code

        WHERE dt.metric_group = 'ERROR_OCCURRENCE'
          AND COALESCE(a.actual_count, 0)
              <> dt.target_count
    )
    THEN
        RAISE EXCEPTION
            'Error occurrence distribution does not match target';
    END IF;

END;
$$;


-- ------------------------------------------------------------
-- 9. FLAG <-> TRANSACTION_ERROR
-- ------------------------------------------------------------

DO $$
DECLARE
    v_flagged_without_error BIGINT;
    v_unflagged_with_error  BIGINT;
BEGIN

    SELECT
        COUNT(*) FILTER (
            WHERE t.error_flag IS TRUE
              AND e.transaction_id IS NULL
        ),

        COUNT(*) FILTER (
            WHERE t.error_flag IS FALSE
              AND e.transaction_id IS NOT NULL
        )

    INTO
        v_flagged_without_error,
        v_unflagged_with_error

    FROM tmp_synthetic_context x

    JOIN oltp.card_transaction t
      ON t.source_system_id = x.source_system_id
     AND t.source_transaction_key
         LIKE x.key_prefix || ':TX:%'

    LEFT JOIN (
        SELECT DISTINCT transaction_id
        FROM oltp.transaction_error
    ) e
      ON e.transaction_id = t.transaction_id;


    IF v_flagged_without_error <> 0
       OR v_unflagged_with_error <> 0
    THEN
        RAISE EXCEPTION
            'Error flag/detail mismatch. flagged_without_error=%, unflagged_with_error=%',
            v_flagged_without_error,
            v_unflagged_with_error;
    END IF;

END;
$$;


-- ------------------------------------------------------------
-- 10. EL SET AÚN NO DEBE ESTAR EN OLAP
-- ------------------------------------------------------------

DO $$
DECLARE
    v_olap_rows BIGINT;
BEGIN

    SELECT COUNT(*)
    INTO v_olap_rows

    FROM olap.fact_transaction f

    CROSS JOIN tmp_synthetic_context x

    WHERE f.source_system_code = x.source_system_code
      AND f.source_transaction_key
          LIKE x.key_prefix || ':TX:%';


    IF v_olap_rows <> 0 THEN
        RAISE EXCEPTION
            'Synthetic dataset already exists in OLAP. Fact rows: %',
            v_olap_rows;
    END IF;

END;
$$;


-- ------------------------------------------------------------
-- 11. VALIDATED
-- ------------------------------------------------------------

UPDATE ctl.synthetic_dataset d

SET
    oltp_status = 'VALIDATED',
    oltp_validated_at = CURRENT_TIMESTAMP,
    updated_at = CURRENT_TIMESTAMP

FROM tmp_synthetic_context x

WHERE d.set_code = x.set_code
  AND d.oltp_status = 'LOADED';


-- ------------------------------------------------------------
-- 12. RESULTADOS
-- ------------------------------------------------------------

SELECT
    x.set_code,
    d.oltp_status,
    d.olap_status,
    d.oltp_last_batch_id,

    s.transactions,
    s.approved,
    s.declined,
    s.reversed,
    s.error_status,

    s.domestic,
    s.international,
    s.unknown_geography,

    s.international_declined,

    ROUND(
        100.0
        * s.international_declined
        / NULLIF(s.international, 0),
        4
    ) AS international_denial_rate_pct,

    s.error_flagged,
    s.fraud_flagged

FROM tmp_synthetic_context x

JOIN ctl.synthetic_dataset d
  ON d.set_code = x.set_code

CROSS JOIN tmp_synthetic_transaction_summary s;


SELECT
    metric_code AS reason_code,
    actual_count AS transactions
FROM tmp_actual_decline_reason
ORDER BY actual_count DESC;


SELECT
    metric_code AS error_code,
    actual_count AS occurrences
FROM tmp_actual_error_occurrence
ORDER BY actual_count DESC;


COMMIT;