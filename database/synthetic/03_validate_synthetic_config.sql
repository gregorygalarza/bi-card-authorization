BEGIN;

-- ============================================================
-- VALIDATE SYNTHETIC CONFIGURATION
-- ============================================================


-- ------------------------------------------------------------
-- 1. SOURCE SYSTEM
-- ------------------------------------------------------------

DO $$
BEGIN

    IF NOT EXISTS (
        SELECT 1
        FROM oltp.source_system
        WHERE source_code = 'ACADEMIC_SYNTH'
          AND active_flag = TRUE
    ) THEN
        RAISE EXCEPTION
            'ACADEMIC_SYNTH source system does not exist or is inactive';
    END IF;

END;
$$;


-- ------------------------------------------------------------
-- 2. PERFIL
-- ------------------------------------------------------------

DO $$
BEGIN

    IF NOT EXISTS (
        SELECT 1
        FROM ctl.synthetic_profile
        WHERE profile_code = 'IBM_CORE_1M_V1'
          AND active_flag = TRUE
          AND target_transactions = 1000000
    ) THEN
        RAISE EXCEPTION
            'IBM_CORE_1M_V1 profile is missing or invalid';
    END IF;

END;
$$;


-- ------------------------------------------------------------
-- 3. EXACTAMENTE CUATRO SETS
-- ------------------------------------------------------------

DO $$
DECLARE
    v_count INTEGER;
BEGIN

    SELECT COUNT(*)
    INTO v_count
    FROM ctl.synthetic_dataset
    WHERE profile_code = 'IBM_CORE_1M_V1'
      AND set_code IN (
          'SYNTH_SET_01',
          'SYNTH_SET_02',
          'SYNTH_SET_03',
          'SYNTH_SET_04'
      );

    IF v_count <> 4 THEN
        RAISE EXCEPTION
            'Expected 4 synthetic datasets, found %',
            v_count;
    END IF;

END;
$$;


-- ------------------------------------------------------------
-- 4. TARGET 1M POR SET
-- ------------------------------------------------------------

DO $$
BEGIN

    IF EXISTS (
        SELECT 1
        FROM ctl.synthetic_dataset
        WHERE profile_code = 'IBM_CORE_1M_V1'
          AND target_transactions <> 1000000
    ) THEN
        RAISE EXCEPTION
            'Every dataset must target exactly 1,000,000 transactions';
    END IF;

END;
$$;


-- ------------------------------------------------------------
-- 5. VENTANAS DE FECHA NO SUPERPUESTAS
-- ------------------------------------------------------------

DO $$
BEGIN

    IF EXISTS (
        SELECT 1
        FROM ctl.synthetic_dataset a
        JOIN ctl.synthetic_dataset b
          ON a.set_code < b.set_code
         AND a.profile_code = b.profile_code
         AND daterange(
                a.transaction_date_from,
                a.transaction_date_to,
                '[]'
             )
             &&
             daterange(
                b.transaction_date_from,
                b.transaction_date_to,
                '[]'
             )
        WHERE a.profile_code = 'IBM_CORE_1M_V1'
    ) THEN
        RAISE EXCEPTION
            'Synthetic dataset transaction date ranges overlap';
    END IF;

END;
$$;


-- ------------------------------------------------------------
-- 6. COBERTURA EN DIM_DATE
-- ------------------------------------------------------------

DO $$
BEGIN

    IF EXISTS (
        SELECT 1
        FROM ctl.synthetic_dataset d
        WHERE d.profile_code = 'IBM_CORE_1M_V1'
          AND (
              SELECT COUNT(*)
              FROM olap.dim_date dd
              WHERE dd.full_date
                    BETWEEN d.transaction_date_from
                        AND d.transaction_date_to
          )
          <>
          (
              d.transaction_date_to
              - d.transaction_date_from
              + 1
          )
    ) THEN
        RAISE EXCEPTION
            'At least one synthetic date range is not fully covered by olap.dim_date';
    END IF;

END;
$$;


-- ------------------------------------------------------------
-- 7. VALIDAR DISTRIBUCIONES QUE DEBEN SUMAR 1M
-- ------------------------------------------------------------

DO $$
DECLARE
    r RECORD;
BEGIN

    FOR r IN
        SELECT
            set_code,
            metric_group,
            SUM(target_count) AS total_count
        FROM ctl.synthetic_dataset_target
        WHERE metric_group IN (
            'AUTH_STATUS',
            'GEOGRAPHY',
            'ENTRY_MODE',
            'CARD_PROFILE',
            'FRAUD'
        )
        GROUP BY
            set_code,
            metric_group
    LOOP

        IF r.total_count <> 1000000 THEN
            RAISE EXCEPTION
                'Invalid target sum for set %, group %: %',
                r.set_code,
                r.metric_group,
                r.total_count;
        END IF;

    END LOOP;

END;
$$;


-- ------------------------------------------------------------
-- 8. DECLINE REASON = DECLINED
-- ------------------------------------------------------------

DO $$
DECLARE
    r RECORD;
BEGIN

    FOR r IN
        SELECT
            d.set_code,

            SUM(t.target_count)
                FILTER (
                    WHERE t.metric_group = 'DECLINE_REASON'
                ) AS decline_reason_total,

            MAX(t.target_count)
                FILTER (
                    WHERE t.metric_group = 'AUTH_STATUS'
                      AND t.metric_code = 'DECLINED'
                ) AS declined_total

        FROM ctl.synthetic_dataset d

        JOIN ctl.synthetic_dataset_target t
          ON t.set_code = d.set_code

        WHERE d.profile_code = 'IBM_CORE_1M_V1'

        GROUP BY d.set_code
    LOOP

        IF r.decline_reason_total <> r.declined_total THEN
            RAISE EXCEPTION
                'Decline reason total does not match DECLINED for set %: % vs %',
                r.set_code,
                r.decline_reason_total,
                r.declined_total;
        END IF;

    END LOOP;

END;
$$;


-- ------------------------------------------------------------
-- 9. ERROR OCCURRENCES
-- ------------------------------------------------------------

DO $$
DECLARE
    r RECORD;
BEGIN

    FOR r IN
        SELECT
            d.set_code,

            SUM(t.target_count)
                FILTER (
                    WHERE t.metric_group = 'ERROR_OCCURRENCE'
                ) AS error_distribution_total,

            MAX(t.target_count)
                FILTER (
                    WHERE t.metric_group = 'ERROR_SUMMARY'
                      AND t.metric_code = 'ERROR_OCCURRENCES'
                ) AS error_occurrence_target

        FROM ctl.synthetic_dataset d

        JOIN ctl.synthetic_dataset_target t
          ON t.set_code = d.set_code

        WHERE d.profile_code = 'IBM_CORE_1M_V1'

        GROUP BY d.set_code
    LOOP

        IF r.error_distribution_total
           <> r.error_occurrence_target
        THEN
            RAISE EXCEPTION
                'Error occurrence distribution mismatch for set %: % vs %',
                r.set_code,
                r.error_distribution_total,
                r.error_occurrence_target;
        END IF;

    END LOOP;

END;
$$;


-- ------------------------------------------------------------
-- 10. KPI INTERNACIONAL
-- ------------------------------------------------------------

DO $$
DECLARE
    r RECORD;
BEGIN

    FOR r IN
        SELECT
            d.set_code,

            MAX(t.target_count)
                FILTER (
                    WHERE t.metric_group = 'GEOGRAPHY'
                      AND t.metric_code = 'INTERNATIONAL'
                ) AS international_total,

            MAX(t.target_count)
                FILTER (
                    WHERE t.metric_group = 'KPI'
                      AND t.metric_code = 'INTERNATIONAL_DECLINED'
                ) AS international_declined

        FROM ctl.synthetic_dataset d

        JOIN ctl.synthetic_dataset_target t
          ON t.set_code = d.set_code

        WHERE d.profile_code = 'IBM_CORE_1M_V1'

        GROUP BY d.set_code
    LOOP

        IF r.international_total IS NULL
           OR r.international_declined IS NULL
        THEN
            RAISE EXCEPTION
                'Missing international KPI target for set %',
                r.set_code;
        END IF;

        IF r.international_declined
           > r.international_total
        THEN
            RAISE EXCEPTION
                'International declined exceeds international total for set %',
                r.set_code;
        END IF;

    END LOOP;

END;
$$;


-- ------------------------------------------------------------
-- 11. KPI AGREGADO DE LOS CUATRO SETS
-- ------------------------------------------------------------

DO $$
DECLARE
    v_international          BIGINT;
    v_international_declined BIGINT;
    v_rate                   NUMERIC(12,6);
BEGIN

    SELECT
        SUM(
            CASE
                WHEN metric_group = 'GEOGRAPHY'
                 AND metric_code = 'INTERNATIONAL'
                THEN target_count
                ELSE 0
            END
        ),

        SUM(
            CASE
                WHEN metric_group = 'KPI'
                 AND metric_code = 'INTERNATIONAL_DECLINED'
                THEN target_count
                ELSE 0
            END
        )

    INTO
        v_international,
        v_international_declined

    FROM ctl.synthetic_dataset_target
    WHERE set_code IN (
        'SYNTH_SET_01',
        'SYNTH_SET_02',
        'SYNTH_SET_03',
        'SYNTH_SET_04'
    );


    v_rate :=
        ROUND(
            100.0
            * v_international_declined
            / NULLIF(v_international, 0),
            4
        );


    IF ABS(v_rate - 16.0240) > 0.01 THEN
        RAISE EXCEPTION
            'Aggregate international denial rate outside tolerance: %',
            v_rate;
    END IF;

END;
$$;


-- ------------------------------------------------------------
-- 12. RESULTADO DE VALIDACIÓN
-- ------------------------------------------------------------

SELECT
    d.set_code,
    d.seed,
    d.key_prefix,
    d.purpose,
    d.target_customers,
    d.target_cards,
    d.target_merchants,
    d.target_locations,
    d.target_transactions,
    d.transaction_date_from,
    d.transaction_date_to,
    d.oltp_status,
    d.olap_status
FROM ctl.synthetic_dataset d
WHERE d.profile_code = 'IBM_CORE_1M_V1'
ORDER BY d.set_code;


SELECT
    set_code,

    MAX(target_count)
        FILTER (
            WHERE metric_group = 'GEOGRAPHY'
              AND metric_code = 'INTERNATIONAL'
        ) AS international_transactions,

    MAX(target_count)
        FILTER (
            WHERE metric_group = 'KPI'
              AND metric_code = 'INTERNATIONAL_DECLINED'
        ) AS international_declined,

    ROUND(
        100.0
        * MAX(target_count)
            FILTER (
                WHERE metric_group = 'KPI'
                  AND metric_code = 'INTERNATIONAL_DECLINED'
            )
        /
        NULLIF(
            MAX(target_count)
                FILTER (
                    WHERE metric_group = 'GEOGRAPHY'
                      AND metric_code = 'INTERNATIONAL'
                ),
            0
        ),
        4
    ) AS international_denial_rate_pct

FROM ctl.synthetic_dataset_target

WHERE set_code IN (
    'SYNTH_SET_01',
    'SYNTH_SET_02',
    'SYNTH_SET_03',
    'SYNTH_SET_04'
)

GROUP BY set_code
ORDER BY set_code;


COMMIT;