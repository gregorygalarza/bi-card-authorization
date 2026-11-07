BEGIN;

-- ============================================================
-- PREPARE SYNTHETIC DATASET
--
-- Funciones reutilizables por:
--   - consola / desarrollo
--   - Pentaho PDI
--   - Jobs
--   - futuro Windows Service
-- ============================================================


-- ------------------------------------------------------------
-- 1. VALIDACIÓN PRE-LOAD
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION ctl.fn_validate_synthetic_dataset_preload(
    p_set_code VARCHAR
)
RETURNS TABLE (
    set_code                VARCHAR,
    oltp_status             VARCHAR,
    olap_status             VARCHAR,
    source_system_id        SMALLINT,
    key_prefix              VARCHAR,
    target_transactions     BIGINT,
    existing_customers      BIGINT,
    existing_cards          BIGINT,
    existing_merchants      BIGINT,
    existing_locations      BIGINT,
    existing_transactions   BIGINT,
    is_clean                BOOLEAN
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_set                   ctl.synthetic_dataset%ROWTYPE;
    v_source_system_id      SMALLINT;

    v_customers             BIGINT;
    v_cards                 BIGINT;
    v_merchants             BIGINT;
    v_locations             BIGINT;
    v_transactions          BIGINT;
BEGIN

    SELECT *
    INTO v_set
    FROM ctl.synthetic_dataset d
    WHERE d.set_code = UPPER(BTRIM(p_set_code));

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Synthetic dataset % does not exist',
            p_set_code;
    END IF;


    SELECT ss.source_system_id
    INTO v_source_system_id
    FROM oltp.source_system ss
    WHERE ss.source_code = v_set.source_system_code
      AND ss.active_flag = TRUE;

    IF v_source_system_id IS NULL THEN
        RAISE EXCEPTION
            'Source system % does not exist or is inactive',
            v_set.source_system_code;
    END IF;


    SELECT COUNT(*)
    INTO v_customers
    FROM oltp.customer c
    WHERE c.source_system_id = v_source_system_id
      AND c.source_customer_key
          LIKE v_set.key_prefix || ':CUSTOMER:%';


    SELECT COUNT(*)
    INTO v_cards
    FROM oltp.card c
    WHERE c.source_system_id = v_source_system_id
      AND c.source_card_key
          LIKE v_set.key_prefix || ':CARD:%';


    SELECT COUNT(*)
    INTO v_merchants
    FROM oltp.merchant m
    WHERE m.source_system_id = v_source_system_id
      AND m.source_merchant_key
          LIKE v_set.key_prefix || ':MERCHANT:%';


    SELECT COUNT(*)
    INTO v_locations
    FROM oltp.merchant_location ml
    JOIN oltp.merchant m
      ON m.merchant_id = ml.merchant_id
    WHERE m.source_system_id = v_source_system_id
      AND ml.source_location_key
          LIKE v_set.key_prefix || ':LOCATION:%';


    SELECT COUNT(*)
    INTO v_transactions
    FROM oltp.card_transaction t
    WHERE t.source_system_id = v_source_system_id
      AND t.source_transaction_key
          LIKE v_set.key_prefix || ':TX:%';


    RETURN QUERY
    SELECT
        v_set.set_code,
        v_set.oltp_status,
        v_set.olap_status,
        v_source_system_id,
        v_set.key_prefix,
        v_set.target_transactions,
        v_customers,
        v_cards,
        v_merchants,
        v_locations,
        v_transactions,
        (
            v_customers = 0
            AND v_cards = 0
            AND v_merchants = 0
            AND v_locations = 0
            AND v_transactions = 0
        );

END;
$$;


-- ------------------------------------------------------------
-- 2. PREPARE DATASET
--
-- Solo cambia el estado a PREPARED cuando:
--   - el set existe;
--   - source system está activo;
--   - configuración es válida;
--   - no existen filas previas con su prefijo;
--   - el OLAP todavía está PENDING.
--
-- No abre aún un etl_batch.
-- El batch se abrirá cuando empiece la carga real.
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION ctl.fn_prepare_synthetic_dataset(
    p_set_code VARCHAR
)
RETURNS TABLE (
    set_code                VARCHAR,
    profile_code            VARCHAR,
    source_system_code      VARCHAR,
    source_system_id        SMALLINT,
    seed                    INTEGER,
    key_prefix              VARCHAR,
    target_customers        INTEGER,
    target_cards            INTEGER,
    target_merchants        INTEGER,
    target_locations        INTEGER,
    target_transactions     BIGINT,
    transaction_date_from   DATE,
    transaction_date_to     DATE,
    oltp_status             VARCHAR,
    olap_status             VARCHAR
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_set                   ctl.synthetic_dataset%ROWTYPE;
    v_source_system_id      SMALLINT;

    v_customers             BIGINT;
    v_cards                 BIGINT;
    v_merchants             BIGINT;
    v_locations             BIGINT;
    v_transactions          BIGINT;

    v_profile_metrics       INTEGER;
    v_dataset_targets       INTEGER;
BEGIN

    -- --------------------------------------------------------
    -- Dataset
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
    -- Estado permitido
    -- --------------------------------------------------------

    IF v_set.oltp_status IN (
        'LOADING',
        'LOADED',
        'VALIDATED'
    ) THEN
        RAISE EXCEPTION
            'Dataset % cannot be prepared because OLTP status is %',
            v_set.set_code,
            v_set.oltp_status;
    END IF;


    IF v_set.olap_status <> 'PENDING' THEN
        RAISE EXCEPTION
            'Dataset % cannot be prepared because OLAP status is %',
            v_set.set_code,
            v_set.olap_status;
    END IF;


    -- --------------------------------------------------------
    -- Source system
    -- --------------------------------------------------------

    SELECT ss.source_system_id
    INTO v_source_system_id
    FROM oltp.source_system ss
    WHERE ss.source_code = v_set.source_system_code
      AND ss.active_flag = TRUE;

    IF v_source_system_id IS NULL THEN
        RAISE EXCEPTION
            'Source system % does not exist or is inactive',
            v_set.source_system_code;
    END IF;


    -- --------------------------------------------------------
    -- Perfil y targets materializados
    -- --------------------------------------------------------

    SELECT COUNT(*)
    INTO v_profile_metrics
    FROM ctl.synthetic_profile_metric pm
    WHERE pm.profile_code = v_set.profile_code;


    SELECT COUNT(*)
    INTO v_dataset_targets
    FROM ctl.synthetic_dataset_target dt
    WHERE dt.set_code = v_set.set_code;


    IF v_profile_metrics = 0 THEN
        RAISE EXCEPTION
            'Profile % has no configured metrics',
            v_set.profile_code;
    END IF;


    IF v_dataset_targets <> v_profile_metrics THEN
        RAISE EXCEPTION
            'Dataset % target count (%) does not match profile metric count (%)',
            v_set.set_code,
            v_dataset_targets,
            v_profile_metrics;
    END IF;


    -- --------------------------------------------------------
    -- Colisiones OLTP
    -- --------------------------------------------------------

    SELECT COUNT(*)
    INTO v_customers
    FROM oltp.customer c
    WHERE c.source_system_id = v_source_system_id
      AND c.source_customer_key
          LIKE v_set.key_prefix || ':CUSTOMER:%';


    SELECT COUNT(*)
    INTO v_cards
    FROM oltp.card c
    WHERE c.source_system_id = v_source_system_id
      AND c.source_card_key
          LIKE v_set.key_prefix || ':CARD:%';


    SELECT COUNT(*)
    INTO v_merchants
    FROM oltp.merchant m
    WHERE m.source_system_id = v_source_system_id
      AND m.source_merchant_key
          LIKE v_set.key_prefix || ':MERCHANT:%';


    SELECT COUNT(*)
    INTO v_locations
    FROM oltp.merchant_location ml
    JOIN oltp.merchant m
      ON m.merchant_id = ml.merchant_id
    WHERE m.source_system_id = v_source_system_id
      AND ml.source_location_key
          LIKE v_set.key_prefix || ':LOCATION:%';


    SELECT COUNT(*)
    INTO v_transactions
    FROM oltp.card_transaction t
    WHERE t.source_system_id = v_source_system_id
      AND t.source_transaction_key
          LIKE v_set.key_prefix || ':TX:%';


    IF
        v_customers <> 0
        OR v_cards <> 0
        OR v_merchants <> 0
        OR v_locations <> 0
        OR v_transactions <> 0
    THEN
        RAISE EXCEPTION
            'Dataset % collides with existing OLTP data. customers=%, cards=%, merchants=%, locations=%, transactions=%',
            v_set.set_code,
            v_customers,
            v_cards,
            v_merchants,
            v_locations,
            v_transactions;
    END IF;


    -- --------------------------------------------------------
    -- Fecha cubierta por dim_date
    -- --------------------------------------------------------

    IF (
        SELECT COUNT(*)
        FROM olap.dim_date dd
        WHERE dd.full_date
              BETWEEN v_set.transaction_date_from
                  AND v_set.transaction_date_to
    )
    <>
    (
        v_set.transaction_date_to
        - v_set.transaction_date_from
        + 1
    )
    THEN
        RAISE EXCEPTION
            'Dataset % date range is not fully covered by dim_date',
            v_set.set_code;
    END IF;


    -- --------------------------------------------------------
    -- PREPARED
    -- --------------------------------------------------------

    UPDATE ctl.synthetic_dataset d
    SET
        oltp_status = 'PREPARED',
        updated_at = CURRENT_TIMESTAMP
    WHERE d.set_code = v_set.set_code;


    RETURN QUERY
    SELECT
        v_set.set_code,
        v_set.profile_code,
        v_set.source_system_code,
        v_source_system_id,
        v_set.seed,
        v_set.key_prefix,
        v_set.target_customers,
        v_set.target_cards,
        v_set.target_merchants,
        v_set.target_locations,
        v_set.target_transactions,
        v_set.transaction_date_from,
        v_set.transaction_date_to,
        'PREPARED'::VARCHAR,
        v_set.olap_status;

END;
$$;


COMMENT ON FUNCTION ctl.fn_validate_synthetic_dataset_preload(VARCHAR) IS
'Valida existencia y colisiones de un dataset sintético antes de cargarlo al OLTP.';

COMMENT ON FUNCTION ctl.fn_prepare_synthetic_dataset(VARCHAR) IS
'Prepara un dataset sintético para carga OLTP y cambia su estado a PREPARED solo cuando pasa todas las validaciones.';


COMMIT;