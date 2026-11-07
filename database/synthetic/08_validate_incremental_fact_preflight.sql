BEGIN;

-- ============================================================
-- SYNTHETIC INCREMENTAL OLAP - FACT PREFLIGHT
--
-- Uso:
--
-- psql -v set_code=SYNTH_SET_01 ...
--
-- Comprueba antes de cargar fact_transaction:
--
--   - dataset OLTP = VALIDATED
--   - dataset OLAP = LOADING
--   - batch OLAP = RUNNING
--   - cantidad de dimensiones incrementales
--   - cobertura de TODAS las surrogate keys
--   - selección determinística de primary error
--   - ausencia de hechos previos del set
--
-- NO modifica datos permanentes.
-- ============================================================


-- ------------------------------------------------------------
-- 1. CONTEXTO DEL DATASET
-- ------------------------------------------------------------

CREATE TEMP TABLE tmp_fact_preflight_context
ON COMMIT DROP
AS
SELECT
    d.set_code,
    d.source_system_code,
    d.key_prefix,

    d.target_customers,
    d.target_cards,
    d.target_merchants,
    d.target_locations,
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
    FROM tmp_fact_preflight_context;

    IF v_count <> 1 THEN
        RAISE EXCEPTION
            'Expected exactly one dataset context, found %',
            v_count;
    END IF;

END;
$$;


-- ------------------------------------------------------------
-- 2. ESTADO DEL DATASET Y BATCH
-- ------------------------------------------------------------

DO $$
DECLARE
    v_set_code       VARCHAR;
    v_oltp_status    VARCHAR;
    v_olap_status    VARCHAR;
    v_batch_id       BIGINT;
    v_batch_status   VARCHAR;
BEGIN

    SELECT
        set_code,
        oltp_status,
        olap_status,
        olap_last_batch_id
    INTO
        v_set_code,
        v_oltp_status,
        v_olap_status,
        v_batch_id
    FROM tmp_fact_preflight_context;


    IF v_oltp_status <> 'VALIDATED' THEN
        RAISE EXCEPTION
            'Dataset % OLTP status must be VALIDATED. Current: %',
            v_set_code,
            v_oltp_status;
    END IF;


    IF v_olap_status <> 'LOADING' THEN
        RAISE EXCEPTION
            'Dataset % OLAP status must be LOADING. Current: %',
            v_set_code,
            v_olap_status;
    END IF;


    IF v_batch_id IS NULL THEN
        RAISE EXCEPTION
            'Dataset % has no OLAP batch',
            v_set_code;
    END IF;


    SELECT status
    INTO v_batch_status
    FROM ctl.etl_batch
    WHERE batch_id = v_batch_id;


    IF v_batch_status <> 'RUNNING' THEN
        RAISE EXCEPTION
            'OLAP batch % must be RUNNING. Current: %',
            v_batch_id,
            v_batch_status;
    END IF;

END;
$$;


-- ------------------------------------------------------------
-- 3. DIMENSIONES INCREMENTALES
-- ------------------------------------------------------------

CREATE TEMP TABLE tmp_incremental_dimension_counts
ON COMMIT DROP
AS
SELECT

    (
        SELECT COUNT(*)
        FROM olap.dim_customer d
        CROSS JOIN tmp_fact_preflight_context x
        WHERE d.source_system_code = x.source_system_code
          AND d.source_customer_key
              LIKE x.key_prefix || ':CUSTOMER:%'
    ) AS customers,

    (
        SELECT COUNT(*)
        FROM olap.dim_card d
        CROSS JOIN tmp_fact_preflight_context x
        WHERE d.source_system_code = x.source_system_code
          AND d.source_card_key
              LIKE x.key_prefix || ':CARD:%'
    ) AS cards,

    (
        SELECT COUNT(*)
        FROM olap.dim_merchant d
        CROSS JOIN tmp_fact_preflight_context x
        WHERE d.source_system_code = x.source_system_code
          AND d.source_merchant_key
              LIKE x.key_prefix || ':MERCHANT:%'
    ) AS merchants,

    (
        SELECT COUNT(*)
        FROM olap.dim_merchant_location d
        CROSS JOIN tmp_fact_preflight_context x
        WHERE d.source_system_code = x.source_system_code
          AND d.source_location_key
              LIKE x.key_prefix || ':LOCATION:%'
    ) AS locations;


DO $$
DECLARE
    x RECORD;
    d RECORD;
BEGIN

    SELECT *
    INTO x
    FROM tmp_fact_preflight_context;

    SELECT *
    INTO d
    FROM tmp_incremental_dimension_counts;


    IF d.customers <> x.target_customers THEN
        RAISE EXCEPTION
            'dim_customer mismatch. Expected %, found %',
            x.target_customers,
            d.customers;
    END IF;


    IF d.cards <> x.target_cards THEN
        RAISE EXCEPTION
            'dim_card mismatch. Expected %, found %',
            x.target_cards,
            d.cards;
    END IF;


    IF d.merchants <> x.target_merchants THEN
        RAISE EXCEPTION
            'dim_merchant mismatch. Expected %, found %',
            x.target_merchants,
            d.merchants;
    END IF;


    IF d.locations <> x.target_locations THEN
        RAISE EXCEPTION
            'dim_merchant_location mismatch. Expected %, found %',
            x.target_locations,
            d.locations;
    END IF;

END;
$$;


-- ------------------------------------------------------------
-- 4. PRIMARY ERROR DETERMINÍSTICO
--
-- Una transacción puede tener múltiples errores.
--
-- Orden de precedencia para fact_transaction:
--
-- 10 TECHNICAL_ERROR
-- 20 INVALID_CARD
-- 30 EXPIRED_CARD
-- 40 BAD_PIN
-- 50 BAD_CVV
-- 60 BAD_ZIPCODE
-- 70 INSUFFICIENT_FUNDS
--
-- Las transacciones sin error usarán NOT_APPLICABLE.
-- ------------------------------------------------------------

CREATE TEMP TABLE tmp_primary_error
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
                    WHEN 'TECHNICAL_ERROR'
                        THEN 10
                    WHEN 'INVALID_CARD'
                        THEN 20
                    WHEN 'EXPIRED_CARD'
                        THEN 30
                    WHEN 'BAD_PIN'
                        THEN 40
                    WHEN 'BAD_CVV'
                        THEN 50
                    WHEN 'BAD_ZIPCODE'
                        THEN 60
                    WHEN 'INSUFFICIENT_FUNDS'
                        THEN 70
                    ELSE 999
                END,

                ec.error_code
        ) AS rn

    FROM tmp_fact_preflight_context x

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
-- 5. COBERTURA DE SURROGATE KEYS
-- ------------------------------------------------------------

CREATE TEMP TABLE tmp_fact_preflight_summary
ON COMMIT DROP
AS
SELECT

    COUNT(*) AS source_transactions,

    COUNT(DISTINCT t.source_transaction_key)
        AS distinct_source_transaction_keys,


    -- --------------------------------------------------------
    -- Ya existentes en fact
    -- --------------------------------------------------------

    COUNT(*) FILTER (
        WHERE f.transaction_fact_key IS NOT NULL
    ) AS already_in_fact,


    -- --------------------------------------------------------
    -- Dimensiones
    -- --------------------------------------------------------

    COUNT(*) FILTER (
        WHERE dd.date_key IS NULL
    ) AS missing_date_key,

    COUNT(*) FILTER (
        WHERE dcu.customer_key IS NULL
    ) AS missing_customer_key,

    COUNT(*) FILTER (
        WHERE dca.card_key IS NULL
    ) AS missing_card_key,

    COUNT(*) FILTER (
        WHERE dm.merchant_key IS NULL
    ) AS missing_merchant_key,

    COUNT(*) FILTER (
        WHERE dml.merchant_location_key IS NULL
    ) AS missing_merchant_location_key,

    COUNT(*) FILTER (
        WHERE dmc.merchant_category_key IS NULL
    ) AS missing_merchant_category_key,

    COUNT(*) FILTER (
        WHERE das.authorization_status_key IS NULL
    ) AS missing_authorization_status_key,

    COUNT(*) FILTER (
        WHERE ddr.decline_reason_key IS NULL
    ) AS missing_decline_reason_key,

    COUNT(*) FILTER (
        WHERE dem.entry_mode_key IS NULL
    ) AS missing_entry_mode_key,

    COUNT(*) FILTER (
        WHERE de.error_key IS NULL
    ) AS missing_primary_error_key,


    -- --------------------------------------------------------
    -- Información complementaria
    -- --------------------------------------------------------

    COUNT(*) FILTER (
        WHERE pe.transaction_id IS NOT NULL
    ) AS transactions_with_primary_error,

    COUNT(*) FILTER (
        WHERE pe.transaction_id IS NULL
    ) AS transactions_without_error,


    -- Geografía esperada del hecho

    COUNT(*) FILTER (
        WHERE ml.country_code = 'US'
    ) AS domestic_transactions,

    COUNT(*) FILTER (
        WHERE ml.country_code NOT IN ('US', 'ZZ')
    ) AS international_transactions,

    COUNT(*) FILTER (
        WHERE ml.country_code = 'ZZ'
    ) AS unknown_geography_transactions,


    -- internacional_flag esperado

    COUNT(*) FILTER (
        WHERE
            c.issuer_country_code IS NOT NULL
            AND c.issuer_country_code <> 'ZZ'
            AND ml.country_code IS NOT NULL
            AND ml.country_code <> 'ZZ'
            AND c.issuer_country_code <> ml.country_code
    ) AS international_flag_true,

    COUNT(*) FILTER (
        WHERE
            c.issuer_country_code IS NOT NULL
            AND c.issuer_country_code <> 'ZZ'
            AND ml.country_code IS NOT NULL
            AND ml.country_code <> 'ZZ'
            AND c.issuer_country_code = ml.country_code
    ) AS international_flag_false,

    COUNT(*) FILTER (
        WHERE
            c.issuer_country_code IS NULL
            OR c.issuer_country_code = 'ZZ'
            OR ml.country_code IS NULL
            OR ml.country_code = 'ZZ'
    ) AS international_flag_null


FROM tmp_fact_preflight_context x


-- ============================================================
-- OLTP SOURCE
-- ============================================================

JOIN oltp.card_transaction t
  ON t.source_system_id = x.source_system_id
 AND t.source_transaction_key
     LIKE x.key_prefix || ':TX:%'


JOIN oltp.card c
  ON c.card_id = t.card_id


JOIN oltp.customer cu
  ON cu.customer_id = c.customer_id


JOIN oltp.merchant_location ml
  ON ml.location_id = t.merchant_location_id


JOIN oltp.merchant m
  ON m.merchant_id = ml.merchant_id


LEFT JOIN oltp.merchant_category mc
  ON mc.category_id = t.category_id


JOIN oltp.authorization_status aus
  ON aus.authorization_status_id =
     t.authorization_status_id


LEFT JOIN oltp.decline_reason dr
  ON dr.decline_reason_id =
     t.decline_reason_id


LEFT JOIN tmp_primary_error pe
  ON pe.transaction_id = t.transaction_id


-- ============================================================
-- OLAP LOOKUPS
-- ============================================================

LEFT JOIN olap.dim_date dd
  ON dd.full_date =
     (
        t.transaction_datetime
        AT TIME ZONE 'UTC'
     )::date


LEFT JOIN olap.dim_customer dcu
  ON dcu.source_system_code = x.source_system_code
 AND dcu.source_customer_key = cu.source_customer_key


LEFT JOIN olap.dim_card dca
  ON dca.source_system_code = x.source_system_code
 AND dca.source_card_key = c.source_card_key


LEFT JOIN olap.dim_merchant dm
  ON dm.source_system_code = x.source_system_code
 AND dm.source_merchant_key = m.source_merchant_key


LEFT JOIN olap.dim_merchant_location dml
  ON dml.source_system_code = x.source_system_code
 AND dml.source_location_key = ml.source_location_key


LEFT JOIN olap.dim_merchant_category dmc
  ON dmc.category_scheme = mc.category_scheme
 AND dmc.mcc_code = mc.category_code


LEFT JOIN olap.dim_authorization_status das
  ON das.status_code = aus.status_code


LEFT JOIN olap.dim_decline_reason ddr
  ON ddr.reason_code =
     COALESCE(
        dr.reason_code,
        'NOT_APPLICABLE'
     )


LEFT JOIN olap.dim_entry_mode dem
  ON dem.entry_mode_code =
     CASE
        WHEN UPPER(BTRIM(COALESCE(t.entry_mode, '')))
             IN ('SWIPE', 'SWIPE TRANSACTION')
            THEN 'SWIPE'

        WHEN UPPER(BTRIM(COALESCE(t.entry_mode, '')))
             IN ('CHIP', 'CHIP TRANSACTION')
            THEN 'CHIP'

        WHEN UPPER(BTRIM(COALESCE(t.entry_mode, '')))
             IN ('ONLINE', 'ONLINE TRANSACTION')
            THEN 'ONLINE'

        ELSE 'UNKNOWN'
     END


LEFT JOIN olap.dim_error de
  ON de.error_code =
     COALESCE(
        pe.error_code,
        'NOT_APPLICABLE'
     )


LEFT JOIN olap.fact_transaction f
  ON f.source_system_code = x.source_system_code
 AND f.source_transaction_key =
     t.source_transaction_key;


-- ------------------------------------------------------------
-- 6. VALIDACIÓN FINAL
-- ------------------------------------------------------------

DO $$
DECLARE
    x RECORD;
    s RECORD;
BEGIN

    SELECT *
    INTO x
    FROM tmp_fact_preflight_context;

    SELECT *
    INTO s
    FROM tmp_fact_preflight_summary;


    IF s.source_transactions <> x.target_transactions THEN
        RAISE EXCEPTION
            'Source transaction mismatch. Expected %, found %',
            x.target_transactions,
            s.source_transactions;
    END IF;


    IF s.distinct_source_transaction_keys
       <> x.target_transactions
    THEN
        RAISE EXCEPTION
            'Source transaction keys are not unique. Expected %, found %',
            x.target_transactions,
            s.distinct_source_transaction_keys;
    END IF;


    IF s.already_in_fact <> 0 THEN
        RAISE EXCEPTION
            'Dataset already has % rows in fact_transaction',
            s.already_in_fact;
    END IF;


    IF
        s.missing_date_key <> 0
        OR s.missing_customer_key <> 0
        OR s.missing_card_key <> 0
        OR s.missing_merchant_key <> 0
        OR s.missing_merchant_location_key <> 0
        OR s.missing_merchant_category_key <> 0
        OR s.missing_authorization_status_key <> 0
        OR s.missing_decline_reason_key <> 0
        OR s.missing_entry_mode_key <> 0
        OR s.missing_primary_error_key <> 0
    THEN

        RAISE EXCEPTION
            'Fact dimensional coverage failed:
             date=%,
             customer=%,
             card=%,
             merchant=%,
             location=%,
             mcc=%,
             status=%,
             decline=%,
             entry=%,
             error=%',

            s.missing_date_key,
            s.missing_customer_key,
            s.missing_card_key,
            s.missing_merchant_key,
            s.missing_merchant_location_key,
            s.missing_merchant_category_key,
            s.missing_authorization_status_key,
            s.missing_decline_reason_key,
            s.missing_entry_mode_key,
            s.missing_primary_error_key;
    END IF;


    IF s.transactions_with_primary_error <> 15936 THEN
        RAISE EXCEPTION
            'Expected 15936 transactions with primary error, found %',
            s.transactions_with_primary_error;
    END IF;


    IF s.domestic_transactions <> 881883
       OR s.international_transactions <> 6456
       OR s.unknown_geography_transactions <> 111661
    THEN
        RAISE EXCEPTION
            'Geography distribution changed unexpectedly';
    END IF;

END;
$$;


-- ------------------------------------------------------------
-- 7. RESULTADO
-- ------------------------------------------------------------

SELECT
    x.set_code,
    x.oltp_status,
    x.olap_status,
    x.olap_last_batch_id,

    d.customers AS dim_customers,
    d.cards AS dim_cards,
    d.merchants AS dim_merchants,
    d.locations AS dim_locations,

    s.source_transactions,
    s.distinct_source_transaction_keys,

    s.already_in_fact,

    s.missing_date_key,
    s.missing_customer_key,
    s.missing_card_key,
    s.missing_merchant_key,
    s.missing_merchant_location_key,
    s.missing_merchant_category_key,
    s.missing_authorization_status_key,
    s.missing_decline_reason_key,
    s.missing_entry_mode_key,
    s.missing_primary_error_key,

    s.transactions_with_primary_error,
    s.transactions_without_error,

    s.domestic_transactions,
    s.international_transactions,
    s.unknown_geography_transactions,

    s.international_flag_true,
    s.international_flag_false,
    s.international_flag_null

FROM tmp_fact_preflight_context x

CROSS JOIN tmp_incremental_dimension_counts d

CROSS JOIN tmp_fact_preflight_summary s;


COMMIT;