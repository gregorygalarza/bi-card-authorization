BEGIN;

-- ============================================================
-- PRELOAD VALIDATION - SYNTHETIC TRANSACTIONS
-- ============================================================

DO $$
DECLARE
    v_set_code           VARCHAR := 'SYNTH_SET_01';
    v_source_system_id   SMALLINT;

    v_customers          BIGINT;
    v_cards              BIGINT;
    v_merchants          BIGINT;
    v_locations          BIGINT;
    v_transactions       BIGINT;
BEGIN

    SELECT ss.source_system_id
    INTO v_source_system_id
    FROM ctl.synthetic_dataset d
    JOIN oltp.source_system ss
      ON ss.source_code = d.source_system_code
    WHERE d.set_code = v_set_code
      AND d.oltp_status = 'LOADING'
      AND d.olap_status = 'PENDING';

    IF v_source_system_id IS NULL THEN
        RAISE EXCEPTION
            'Dataset % is not ready for transaction generation',
            v_set_code;
    END IF;


    SELECT COUNT(*)
    INTO v_customers
    FROM oltp.customer
    WHERE source_system_id = v_source_system_id
      AND source_customer_key
          LIKE 'SYNTH:S01:CUSTOMER:%';


    SELECT COUNT(*)
    INTO v_cards
    FROM oltp.card
    WHERE source_system_id = v_source_system_id
      AND source_card_key
          LIKE 'SYNTH:S01:CARD:%';


    SELECT COUNT(*)
    INTO v_merchants
    FROM oltp.merchant
    WHERE source_system_id = v_source_system_id
      AND source_merchant_key
          LIKE 'SYNTH:S01:MERCHANT:%';


    SELECT COUNT(*)
    INTO v_locations
    FROM oltp.merchant_location ml
    JOIN oltp.merchant m
      ON m.merchant_id = ml.merchant_id
    WHERE m.source_system_id = v_source_system_id
      AND ml.source_location_key
          LIKE 'SYNTH:S01:LOCATION:%';


    SELECT COUNT(*)
    INTO v_transactions
    FROM oltp.card_transaction
    WHERE source_system_id = v_source_system_id
      AND source_transaction_key
          LIKE 'SYNTH:S01:TX:%';


    IF v_customers <> 100 THEN
        RAISE EXCEPTION
            'Expected 100 customers, found %',
            v_customers;
    END IF;

    IF v_cards <> 300 THEN
        RAISE EXCEPTION
            'Expected 300 cards, found %',
            v_cards;
    END IF;

    IF v_merchants <> 4000 THEN
        RAISE EXCEPTION
            'Expected 4000 merchants, found %',
            v_merchants;
    END IF;

    IF v_locations <> 12000 THEN
        RAISE EXCEPTION
            'Expected 12000 locations, found %',
            v_locations;
    END IF;

    IF v_transactions <> 0 THEN
        RAISE EXCEPTION
            'Transaction target is not empty. Existing transactions: %',
            v_transactions;
    END IF;


    IF NOT EXISTS (
        SELECT 1
        FROM oltp.authorization_status
        WHERE status_code = 'APPROVED'
    )
    OR NOT EXISTS (
        SELECT 1
        FROM oltp.authorization_status
        WHERE status_code = 'DECLINED'
    )
    OR NOT EXISTS (
        SELECT 1
        FROM oltp.authorization_status
        WHERE status_code = 'REVERSED'
    )
    OR NOT EXISTS (
        SELECT 1
        FROM oltp.authorization_status
        WHERE status_code = 'ERROR'
    )
    THEN
        RAISE EXCEPTION
            'Required authorization status catalog is incomplete';
    END IF;


    IF (
        SELECT COUNT(*)
        FROM oltp.merchant_category
        WHERE active_flag = TRUE
    ) < 100
    THEN
        RAISE EXCEPTION
            'Merchant category catalog is incomplete';
    END IF;

END;
$$;


SELECT
    d.set_code,
    d.oltp_status,
    d.olap_status,
    d.target_transactions,

    (
        SELECT COUNT(*)
        FROM oltp.customer c
        JOIN oltp.source_system ss
          ON ss.source_system_id = c.source_system_id
        WHERE ss.source_code = d.source_system_code
          AND c.source_customer_key
              LIKE d.key_prefix || ':CUSTOMER:%'
    ) AS customers,

    (
        SELECT COUNT(*)
        FROM oltp.card c
        JOIN oltp.source_system ss
          ON ss.source_system_id = c.source_system_id
        WHERE ss.source_code = d.source_system_code
          AND c.source_card_key
              LIKE d.key_prefix || ':CARD:%'
    ) AS cards,

    (
        SELECT COUNT(*)
        FROM oltp.merchant m
        JOIN oltp.source_system ss
          ON ss.source_system_id = m.source_system_id
        WHERE ss.source_code = d.source_system_code
          AND m.source_merchant_key
              LIKE d.key_prefix || ':MERCHANT:%'
    ) AS merchants,

    (
        SELECT COUNT(*)
        FROM oltp.merchant_location ml
        JOIN oltp.merchant m
          ON m.merchant_id = ml.merchant_id
        JOIN oltp.source_system ss
          ON ss.source_system_id = m.source_system_id
        WHERE ss.source_code = d.source_system_code
          AND ml.source_location_key
              LIKE d.key_prefix || ':LOCATION:%'
    ) AS locations,

    (
        SELECT COUNT(*)
        FROM oltp.card_transaction t
        JOIN oltp.source_system ss
          ON ss.source_system_id = t.source_system_id
        WHERE ss.source_code = d.source_system_code
          AND t.source_transaction_key
              LIKE d.key_prefix || ':TX:%'
    ) AS transactions

FROM ctl.synthetic_dataset d
WHERE d.set_code = 'SYNTH_SET_01';

COMMIT;