BEGIN;

-- ============================================================
-- MIGRACIÓN CORRECTIVA V0.1.2
-- Reclasificación de autorizaciones con geografía desconocida
--
-- Contexto:
-- ciertas ubicaciones ONLINE sin país informado fueron tratadas
-- previamente como internacionales debido al enriquecimiento
-- geográfico anterior.
--
-- Después de V0.1.1 estas ubicaciones tienen country_code = 'ZZ'.
-- Por tanto, INTERNATIONAL_NOT_ALLOWED ya no es aplicable.
--
-- Regla corregida:
--   - si ambos países son conocidos y diferentes -> internacional
--   - si alguno es ZZ -> internacionalidad desconocida
--
-- Para las filas afectadas, al eliminar la regla internacional,
-- la siguiente regla aplicable es BASE_DECLINE_PERCENT:
--
--   bucket BASE < porcentaje -> DECLINED / DO_NOT_HONOR
--   resto                    -> APPROVED
-- ============================================================


-- ------------------------------------------------------------
-- Validaciones defensivas de catálogos requeridos
-- ------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM oltp.authorization_status
        WHERE status_code = 'APPROVED'
    ) THEN
        RAISE EXCEPTION
            'No existe authorization_status APPROVED';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM oltp.authorization_status
        WHERE status_code = 'DECLINED'
    ) THEN
        RAISE EXCEPTION
            'No existe authorization_status DECLINED';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM oltp.decline_reason
        WHERE reason_code = 'INTERNATIONAL_NOT_ALLOWED'
    ) THEN
        RAISE EXCEPTION
            'No existe decline_reason INTERNATIONAL_NOT_ALLOWED';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM oltp.decline_reason
        WHERE reason_code = 'DO_NOT_HONOR'
    ) THEN
        RAISE EXCEPTION
            'No existe decline_reason DO_NOT_HONOR';
    END IF;
END
$$;


-- ------------------------------------------------------------
-- Reclasificar únicamente transacciones que:
--
-- 1) actualmente están DECLINED por INTERNATIONAL_NOT_ALLOWED
-- 2) tienen geografía desconocida (issuer o merchant = ZZ)
--
-- Estas filas ya superaron las reglas anteriores del ruleset,
-- por lo que al retirar la regla internacional corresponde
-- evaluar la siguiente regla: BASE_DECLINE_PERCENT.
-- ------------------------------------------------------------
WITH params AS (
    SELECT
        MAX(
            CASE
                WHEN parameter_code = 'BASE_DECLINE_PERCENT'
                THEN parameter_value::int
            END
        ) AS base_decline_percent,

        MAX(
            CASE
                WHEN parameter_code = 'RULESET_VERSION'
                THEN parameter_value::int
            END
        ) AS ruleset_version

    FROM ctl.integration_parameter
),

catalog AS (
    SELECT
        (
            SELECT authorization_status_id
            FROM oltp.authorization_status
            WHERE status_code = 'APPROVED'
        ) AS approved_status_id,

        (
            SELECT authorization_status_id
            FROM oltp.authorization_status
            WHERE status_code = 'DECLINED'
        ) AS declined_status_id,

        (
            SELECT decline_reason_id
            FROM oltp.decline_reason
            WHERE reason_code = 'DO_NOT_HONOR'
        ) AS do_not_honor_reason_id,

        (
            SELECT decline_reason_id
            FROM oltp.decline_reason
            WHERE reason_code = 'INTERNATIONAL_NOT_ALLOWED'
        ) AS international_not_allowed_reason_id
),

target AS (
    SELECT
        t.transaction_id,

        (
            ctl.fn_bucket_100(
                t.source_transaction_key
                || '|BASE|v'
                || p.ruleset_version
            ) < p.base_decline_percent
        ) AS base_declined

    FROM oltp.card_transaction t

    JOIN oltp.card c
      ON c.card_id = t.card_id

    JOIN oltp.merchant_location ml
      ON ml.location_id = t.merchant_location_id

    CROSS JOIN params p
    CROSS JOIN catalog cat

    WHERE t.decline_reason_id =
          cat.international_not_allowed_reason_id

      AND (
          c.issuer_country_code = 'ZZ'
          OR ml.country_code = 'ZZ'
      )
)

UPDATE oltp.card_transaction t
SET
    authorization_status_id =
        CASE
            WHEN x.base_declined
                THEN cat.declined_status_id
            ELSE cat.approved_status_id
        END,

    decline_reason_id =
        CASE
            WHEN x.base_declined
                THEN cat.do_not_honor_reason_id
            ELSE NULL
        END,

    authorization_response_code =
        CASE
            WHEN x.base_declined
                THEN 'DO_NOT_HONOR'
            ELSE 'APPROVED'
        END

FROM target x
CROSS JOIN catalog cat

WHERE t.transaction_id = x.transaction_id;


COMMIT;