BEGIN;

-- ============================================================
-- PREPARE SYNTHETIC INCREMENTAL OLAP LOAD
--
-- Valida que:
--   - OLTP esté VALIDATED
--   - batch OLTP esté SUCCESS
--   - OLAP esté PENDING
--   - el set todavía no exista en dimensiones/fact
--   - dimensiones estáticas tengan cobertura
--
-- Si todo pasa:
--   - abre ctl.etl_batch
--   - cambia olap_status a LOADING
--   - registra olap_last_batch_id
-- ============================================================


CREATE OR REPLACE FUNCTION ctl.fn_prepare_synthetic_olap_load(
    p_set_code VARCHAR
)
RETURNS TABLE (
    set_code                    VARCHAR,
    source_system_code          VARCHAR,
    key_prefix                  VARCHAR,
    target_customers            INTEGER,
    target_cards                INTEGER,
    target_merchants            INTEGER,
    target_locations            INTEGER,
    target_transactions         BIGINT,
    existing_dim_customers      BIGINT,
    existing_dim_cards          BIGINT,
    existing_dim_merchants      BIGINT,
    existing_dim_locations      BIGINT,
    existing_facts              BIGINT,
    olap_batch_id               BIGINT,
    olap_status                 VARCHAR
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_set                       ctl.synthetic_dataset%ROWTYPE;

    v_oltp_batch_status         VARCHAR;

    v_dim_customers             BIGINT;
    v_dim_cards                 BIGINT;
    v_dim_merchants             BIGINT;
    v_dim_locations             BIGINT;
    v_facts                     BIGINT;

    v_missing_dates             BIGINT;
    v_missing_statuses          BIGINT;
    v_missing_decline_reasons   BIGINT;
    v_missing_entry_modes       BIGINT;
    v_missing_errors            BIGINT;
    v_missing_mcc               BIGINT;

    v_batch_id                  BIGINT;
BEGIN

    -- --------------------------------------------------------
    -- 1. Dataset
    -- --------------------------------------------------------

    SELECT *
    INTO v_set
    FROM ctl.synthetic_dataset d
    WHERE d.set_code = UPPER(BTRIM(p_set_code))
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Synthetic dataset % does not exist',
            p_set_code;
    END IF;


    -- --------------------------------------------------------
    -- 2. Estado OLTP / OLAP
    -- --------------------------------------------------------

    IF v_set.oltp_status <> 'VALIDATED' THEN
        RAISE EXCEPTION
            'Dataset % OLTP status must be VALIDATED. Current status: %',
            v_set.set_code,
            v_set.oltp_status;
    END IF;


    IF v_set.olap_status <> 'PENDING' THEN
        RAISE EXCEPTION
            'Dataset % OLAP status must be PENDING. Current status: %',
            v_set.set_code,
            v_set.olap_status;
    END IF;


    IF v_set.oltp_last_batch_id IS NULL THEN
        RAISE EXCEPTION
            'Dataset % has no OLTP batch associated',
            v_set.set_code;
    END IF;


    SELECT b.status
    INTO v_oltp_batch_status
    FROM ctl.etl_batch b
    WHERE b.batch_id = v_set.oltp_last_batch_id;


    IF v_oltp_batch_status <> 'SUCCESS' THEN
        RAISE EXCEPTION
            'Dataset % OLTP batch % must be SUCCESS. Current status: %',
            v_set.set_code,
            v_set.oltp_last_batch_id,
            v_oltp_batch_status;
    END IF;


    -- --------------------------------------------------------
    -- 3. Comprobar que el set aún no exista en OLAP
    -- --------------------------------------------------------

    SELECT COUNT(*)
    INTO v_dim_customers
    FROM olap.dim_customer dc
    WHERE dc.source_system_code = v_set.source_system_code
      AND dc.source_customer_key
          LIKE v_set.key_prefix || ':CUSTOMER:%';


    SELECT COUNT(*)
    INTO v_dim_cards
    FROM olap.dim_card dc
    WHERE dc.source_system_code = v_set.source_system_code
      AND dc.source_card_key
          LIKE v_set.key_prefix || ':CARD:%';


    SELECT COUNT(*)
    INTO v_dim_merchants
    FROM olap.dim_merchant dm
    WHERE dm.source_system_code = v_set.source_system_code
      AND dm.source_merchant_key
          LIKE v_set.key_prefix || ':MERCHANT:%';


    SELECT COUNT(*)
    INTO v_dim_locations
    FROM olap.dim_merchant_location dml
    WHERE dml.source_system_code = v_set.source_system_code
      AND dml.source_location_key
          LIKE v_set.key_prefix || ':LOCATION:%';


    SELECT COUNT(*)
    INTO v_facts
    FROM olap.fact_transaction f
    WHERE f.source_system_code = v_set.source_system_code
      AND f.source_transaction_key
          LIKE v_set.key_prefix || ':TX:%';


    IF
        v_dim_customers <> 0
        OR v_dim_cards <> 0
        OR v_dim_merchants <> 0
        OR v_dim_locations <> 0
        OR v_facts <> 0
    THEN
        RAISE EXCEPTION
            'Dataset % already has OLAP rows. customers=%, cards=%, merchants=%, locations=%, facts=%',
            v_set.set_code,
            v_dim_customers,
            v_dim_cards,
            v_dim_merchants,
            v_dim_locations,
            v_facts;
    END IF;


    -- --------------------------------------------------------
    -- 4. Cobertura dim_date
    -- --------------------------------------------------------

    SELECT COUNT(*)
    INTO v_missing_dates
    FROM generate_series(
        v_set.transaction_date_from,
        v_set.transaction_date_to,
        INTERVAL '1 day'
    ) g(full_date)
    LEFT JOIN olap.dim_date dd
      ON dd.full_date = g.full_date::date
    WHERE dd.date_key IS NULL;


    IF v_missing_dates <> 0 THEN
        RAISE EXCEPTION
            'Dataset % has % transaction dates missing from dim_date',
            v_set.set_code,
            v_missing_dates;
    END IF;


    -- --------------------------------------------------------
    -- 5. Cobertura de estados
    -- --------------------------------------------------------

    SELECT COUNT(*)
    INTO v_missing_statuses
    FROM (
        SELECT DISTINCT aus.status_code
        FROM oltp.card_transaction t
        JOIN oltp.authorization_status aus
          ON aus.authorization_status_id =
             t.authorization_status_id
        JOIN oltp.source_system ss
          ON ss.source_system_id = t.source_system_id
        WHERE ss.source_code = v_set.source_system_code
          AND t.source_transaction_key
              LIKE v_set.key_prefix || ':TX:%'
    ) src
    LEFT JOIN olap.dim_authorization_status d
      ON d.status_code = src.status_code
    WHERE d.authorization_status_key IS NULL;


    IF v_missing_statuses <> 0 THEN
        RAISE EXCEPTION
            'Dataset % has % authorization statuses missing in OLAP',
            v_set.set_code,
            v_missing_statuses;
    END IF;


    -- --------------------------------------------------------
    -- 6. Cobertura de decline reasons
    -- --------------------------------------------------------

    SELECT COUNT(*)
    INTO v_missing_decline_reasons
    FROM (
        SELECT DISTINCT dr.reason_code
        FROM oltp.card_transaction t
        JOIN oltp.decline_reason dr
          ON dr.decline_reason_id = t.decline_reason_id
        JOIN oltp.source_system ss
          ON ss.source_system_id = t.source_system_id
        WHERE ss.source_code = v_set.source_system_code
          AND t.source_transaction_key
              LIKE v_set.key_prefix || ':TX:%'
    ) src
    LEFT JOIN olap.dim_decline_reason d
      ON d.reason_code = src.reason_code
    WHERE d.decline_reason_key IS NULL;


    IF v_missing_decline_reasons <> 0 THEN
        RAISE EXCEPTION
            'Dataset % has % decline reasons missing in OLAP',
            v_set.set_code,
            v_missing_decline_reasons;
    END IF;


    -- --------------------------------------------------------
    -- 7. Cobertura entry mode
    -- --------------------------------------------------------

    SELECT COUNT(*)
    INTO v_missing_entry_modes
    FROM (
        SELECT DISTINCT
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
            END AS entry_mode_code

        FROM oltp.card_transaction t
        JOIN oltp.source_system ss
          ON ss.source_system_id = t.source_system_id

        WHERE ss.source_code = v_set.source_system_code
          AND t.source_transaction_key
              LIKE v_set.key_prefix || ':TX:%'
    ) src

    LEFT JOIN olap.dim_entry_mode d
      ON d.entry_mode_code = src.entry_mode_code

    WHERE d.entry_mode_key IS NULL;


    IF v_missing_entry_modes <> 0 THEN
        RAISE EXCEPTION
            'Dataset % has % entry modes missing in OLAP',
            v_set.set_code,
            v_missing_entry_modes;
    END IF;


    -- --------------------------------------------------------
    -- 8. Cobertura errores
    -- --------------------------------------------------------

    SELECT COUNT(*)
    INTO v_missing_errors
    FROM (
        SELECT DISTINCT ec.error_code

        FROM oltp.card_transaction t

        JOIN oltp.transaction_error te
          ON te.transaction_id = t.transaction_id

        JOIN oltp.error_catalog ec
          ON ec.error_id = te.error_id

        JOIN oltp.source_system ss
          ON ss.source_system_id = t.source_system_id

        WHERE ss.source_code = v_set.source_system_code
          AND t.source_transaction_key
              LIKE v_set.key_prefix || ':TX:%'
    ) src

    LEFT JOIN olap.dim_error d
      ON d.error_code = src.error_code

    WHERE d.error_key IS NULL;


    IF v_missing_errors <> 0 THEN
        RAISE EXCEPTION
            'Dataset % has % error codes missing in OLAP',
            v_set.set_code,
            v_missing_errors;
    END IF;


    -- --------------------------------------------------------
    -- 9. Cobertura MCC
    -- --------------------------------------------------------

    SELECT COUNT(*)
    INTO v_missing_mcc
    FROM (
        SELECT DISTINCT
            mc.category_scheme,
            mc.category_code

        FROM oltp.card_transaction t

        JOIN oltp.merchant_category mc
          ON mc.category_id = t.category_id

        JOIN oltp.source_system ss
          ON ss.source_system_id = t.source_system_id

        WHERE ss.source_code = v_set.source_system_code
          AND t.source_transaction_key
              LIKE v_set.key_prefix || ':TX:%'
    ) src

    LEFT JOIN olap.dim_merchant_category d
      ON d.category_scheme = src.category_scheme
     AND d.mcc_code = src.category_code

    WHERE d.merchant_category_key IS NULL;


    IF v_missing_mcc <> 0 THEN
        RAISE EXCEPTION
            'Dataset % has % MCC values missing in OLAP',
            v_set.set_code,
            v_missing_mcc;
    END IF;


    -- --------------------------------------------------------
    -- 10. Abrir batch OLAP
    -- --------------------------------------------------------

    INSERT INTO ctl.etl_batch (
        process_name,
        source_system,
        status
    )
    VALUES (
        'LOAD_SYNTHETIC_SET_TO_OLAP_INCREMENTAL',
        v_set.source_system_code,
        'RUNNING'
    )
    RETURNING batch_id
    INTO v_batch_id;


    -- --------------------------------------------------------
    -- 11. Marcar LOADING
    -- --------------------------------------------------------

    UPDATE ctl.synthetic_dataset d
    SET
        olap_status = 'LOADING',
        olap_last_batch_id = v_batch_id,
        updated_at = CURRENT_TIMESTAMP
    WHERE d.set_code = v_set.set_code;


    -- --------------------------------------------------------
    -- 12. Resultado
    -- --------------------------------------------------------

    RETURN QUERY
    SELECT
        v_set.set_code,
        v_set.source_system_code,
        v_set.key_prefix,
        v_set.target_customers,
        v_set.target_cards,
        v_set.target_merchants,
        v_set.target_locations,
        v_set.target_transactions,

        v_dim_customers,
        v_dim_cards,
        v_dim_merchants,
        v_dim_locations,
        v_facts,

        v_batch_id,
        'LOADING'::VARCHAR;

END;
$$;


COMMENT ON FUNCTION ctl.fn_prepare_synthetic_olap_load(VARCHAR) IS
'Prepara y abre el batch de carga incremental OLTP a OLAP para un dataset sintético validado.';


COMMIT;