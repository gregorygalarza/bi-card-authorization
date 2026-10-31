BEGIN;

-- ============================================================
-- REGLAS DE NEGOCIO
-- ============================================================

CREATE OR REPLACE FUNCTION oltp.fn_validate_decline_reason()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_status_code VARCHAR(20);
BEGIN
    SELECT status_code
      INTO v_status_code
      FROM oltp.authorization_status
     WHERE authorization_status_id = NEW.authorization_status_id;

    IF v_status_code IS NULL THEN
        RAISE EXCEPTION
            'authorization_status_id % no existe',
            NEW.authorization_status_id;
    END IF;

    IF v_status_code = 'DECLINED' AND NEW.decline_reason_id IS NULL THEN
        RAISE EXCEPTION
            'Una transacción DECLINED debe tener decline_reason_id';
    END IF;

    IF v_status_code <> 'DECLINED' AND NEW.decline_reason_id IS NOT NULL THEN
        RAISE EXCEPTION
            'Solo una transacción DECLINED puede tener decline_reason_id';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_decline_reason
ON oltp.card_transaction;

CREATE TRIGGER trg_validate_decline_reason
BEFORE INSERT OR UPDATE OF authorization_status_id, decline_reason_id
ON oltp.card_transaction
FOR EACH ROW
EXECUTE FUNCTION oltp.fn_validate_decline_reason();

-- Mantener error_flag sincronizado con transaction_error.
CREATE OR REPLACE FUNCTION oltp.fn_transaction_error_after_insert_update()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE oltp.card_transaction
       SET error_flag = TRUE
     WHERE transaction_id = NEW.transaction_id;

    IF TG_OP = 'UPDATE'
       AND OLD.transaction_id IS DISTINCT FROM NEW.transaction_id THEN
        UPDATE oltp.card_transaction t
           SET error_flag = EXISTS (
               SELECT 1
                 FROM oltp.transaction_error te
                WHERE te.transaction_id = OLD.transaction_id
           )
         WHERE t.transaction_id = OLD.transaction_id;
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION oltp.fn_transaction_error_after_delete()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE oltp.card_transaction t
       SET error_flag = EXISTS (
           SELECT 1
             FROM oltp.transaction_error te
            WHERE te.transaction_id = OLD.transaction_id
       )
     WHERE t.transaction_id = OLD.transaction_id;

    RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS trg_transaction_error_after_insert_update
ON oltp.transaction_error;

CREATE TRIGGER trg_transaction_error_after_insert_update
AFTER INSERT OR UPDATE OF transaction_id, error_id
ON oltp.transaction_error
FOR EACH ROW
EXECUTE FUNCTION oltp.fn_transaction_error_after_insert_update();

DROP TRIGGER IF EXISTS trg_transaction_error_after_delete
ON oltp.transaction_error;

CREATE TRIGGER trg_transaction_error_after_delete
AFTER DELETE
ON oltp.transaction_error
FOR EACH ROW
EXECUTE FUNCTION oltp.fn_transaction_error_after_delete();

-- ------------------------------------------------------------
-- VISTA ENRIQUECIDA
-- Deriva internacional/aprobada/denegada sin duplicar dichos
-- atributos como columnas físicas de CARD_TRANSACTION.
-- ------------------------------------------------------------

CREATE OR REPLACE VIEW oltp.vw_transaction_enriched AS
SELECT
    t.transaction_id,
    t.source_system_id,
    ss.source_code,
    t.source_transaction_key,
    t.transaction_datetime,
    t.amount,
    t.entry_mode,
    t.authorization_response_code,
    t.error_flag,
    t.fraud_flag,

    t.card_id,
    c.customer_id,
    c.card_brand,
    c.card_type,
    c.has_chip,
    c.issuer_country_code,

    t.merchant_location_id,
    ml.merchant_id,
    ml.country_code AS merchant_country_code,
    ml.city AS merchant_city,
    ml.region_code AS merchant_region_code,
    ml.postal_code AS merchant_postal_code,

    t.category_id,
    mc.category_code AS mcc,
    mc.category_name AS merchant_category_name,

    t.authorization_status_id,
    aus.status_code AS authorization_status_code,
    aus.status_name AS authorization_status_name,

    t.decline_reason_id,
    dr.reason_code AS decline_reason_code,
    dr.reason_name AS decline_reason_name,
    dr.reason_category AS decline_reason_category,

    CASE
        WHEN c.issuer_country_code = 'ZZ'
          OR ml.country_code = 'ZZ'
            THEN NULL
        WHEN c.issuer_country_code <> ml.country_code
            THEN TRUE
        ELSE FALSE
    END AS international_flag,

    (aus.status_code = 'APPROVED') AS approved_flag,
    (aus.status_code = 'DECLINED') AS declined_flag

FROM oltp.card_transaction t
JOIN oltp.source_system ss
  ON ss.source_system_id = t.source_system_id
JOIN oltp.card c
  ON c.card_id = t.card_id
JOIN oltp.merchant_location ml
  ON ml.location_id = t.merchant_location_id
LEFT JOIN oltp.merchant_category mc
  ON mc.category_id = t.category_id
JOIN oltp.authorization_status aus
  ON aus.authorization_status_id = t.authorization_status_id
LEFT JOIN oltp.decline_reason dr
  ON dr.decline_reason_id = t.decline_reason_id;

COMMIT;
