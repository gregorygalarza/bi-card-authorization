BEGIN;

-- ------------------------------------------------------------
-- Validación defensiva:
-- todo valor textual internacional debe poder resolverse.
-- ------------------------------------------------------------
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM oltp.merchant_location ml

        LEFT JOIN oltp.country c
          ON UPPER(c.country_name) = UPPER(BTRIM(ml.state))

        LEFT JOIN ctl.country_name_alias a
          ON a.source_system = 'IBM_CORE'
         AND UPPER(a.source_country_name) = UPPER(BTRIM(ml.state))

        WHERE NULLIF(BTRIM(ml.state), '') IS NOT NULL

          AND NOT EXISTS (
              SELECT 1
              FROM ctl.us_state_code u
              WHERE u.state_code = UPPER(BTRIM(ml.state))
          )

          AND COALESCE(c.country_code, a.country_code) IS NULL
    ) THEN
        RAISE EXCEPTION
            'Existen valores de merchant_location.state sin mapeo de país';
    END IF;
END
$$;

-- ------------------------------------------------------------
-- Normalizar país:
-- 1) vacío/ONLINE -> ZZ
-- 2) código territorial USA -> US
-- 3) nombre internacional -> ISO-2 / alias explícito
-- ------------------------------------------------------------
WITH resolved AS (
    SELECT
        ml.location_id,
        CASE
            WHEN NULLIF(BTRIM(ml.state), '') IS NULL
                THEN 'ZZ'::char(2)

            WHEN EXISTS (
                SELECT 1
                FROM ctl.us_state_code u
                WHERE u.state_code = UPPER(BTRIM(ml.state))
            )
                THEN 'US'::char(2)

            ELSE COALESCE(
                c.country_code,
                a.country_code
            )
        END AS normalized_country_code
    FROM oltp.merchant_location ml
    LEFT JOIN oltp.country c
      ON UPPER(c.country_name) = UPPER(BTRIM(ml.state))
    LEFT JOIN ctl.country_name_alias a
      ON a.source_system = 'IBM_CORE'
     AND UPPER(a.source_country_name) = UPPER(BTRIM(ml.state))
)
UPDATE oltp.merchant_location ml
SET country_code = r.normalized_country_code
FROM resolved r
WHERE r.location_id = ml.location_id
  AND ml.country_code IS DISTINCT FROM r.normalized_country_code;

-- ------------------------------------------------------------
-- El antiguo "state" deja de contener nombres de países.
-- Solo se conserva código regional cuando corresponde.
-- ------------------------------------------------------------
ALTER TABLE oltp.merchant_location
    RENAME COLUMN state TO region_code;

UPDATE oltp.merchant_location ml
SET region_code =
    CASE
        WHEN EXISTS (
            SELECT 1
            FROM ctl.us_state_code u
            WHERE u.state_code = UPPER(BTRIM(ml.region_code))
        )
            THEN UPPER(BTRIM(ml.region_code))
        ELSE NULL
    END;

ALTER TABLE oltp.merchant_location
    DROP CONSTRAINT IF EXISTS ck_merchant_location_region_code;

ALTER TABLE oltp.merchant_location
    ADD CONSTRAINT ck_merchant_location_region_code
    CHECK (
        region_code IS NULL
        OR region_code ~ '^[A-Z]{2}$'
    );

ALTER VIEW oltp.vw_transaction_enriched
    RENAME COLUMN merchant_state TO merchant_region_code;

COMMENT ON COLUMN oltp.merchant_location.country_code IS
'Código de país normalizado. US para ubicaciones con código territorial estadounidense, ISO-2 para ubicaciones internacionales y ZZ cuando el país no está informado.';

COMMENT ON COLUMN oltp.merchant_location.region_code IS
'Código territorial/regional informado por la fuente cuando aplica. Para IBM corresponde principalmente a códigos de dos letras de EE.UU.; NULL para ubicaciones internacionales y ONLINE sin región conocida.';

COMMIT;