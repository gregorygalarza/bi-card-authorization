/*
===============================================================================
14_validate_transaction_rules.sql

Objetivo:
    Validar la clasificación determinística de las transacciones IBM antes
    de cargarlas en oltp.card_transaction.

Valida:
    - Exclusión de transacciones con amount = 0.
    - Resolución de errores fuente según ctl.source_error_mapping.
    - Aplicación de reglas de autorización en orden de prioridad.
    - Distribución APPROVED / DECLINED / ERROR / REVERSED.
    - Coherencia entre DECLINED y decline_reason_code.
    - Total esperado de transacciones candidatas a OLTP.

Universo esperado:
    Fuente total                : 24,386,900
    Excluidas amount = 0        :     20,213
    Candidatas a OLTP           : 24,366,687

Nota:
    Esta validación evalúa el universo fuente completo con amount <> 0.
    No depende de si las transacciones ya fueron insertadas posteriormente
    en oltp.card_transaction.
===============================================================================
*/

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
                WHEN parameter_code = 'FRAUD_DECLINE_PERCENT'
                THEN parameter_value::int
            END
        ) AS fraud_decline_percent,

        MAX(
            CASE
                WHEN parameter_code = 'INTERNATIONAL_DECLINE_PERCENT'
                THEN parameter_value::int
            END
        ) AS international_decline_percent,

        MAX(
            CASE
                WHEN parameter_code = 'RULESET_VERSION'
                THEN parameter_value::int
            END
        ) AS ruleset_version

    FROM ctl.integration_parameter
),

/*
    En errors_raw pueden existir errores múltiples separados por coma.

    Ejemplo:
        Bad PIN,Insufficient Balance

    Primero obtenemos las combinaciones distintas para resolver cada patrón
    una sola vez, en vez de repetir el parsing sobre millones de filas.
*/
distinct_errors AS (
    SELECT DISTINCT
        BTRIM(errors_raw) AS errors_raw

    FROM stg.ibm_transactions_raw

    WHERE etl_file_id = 4
      AND NULLIF(BTRIM(errors_raw), '') IS NOT NULL
),

/*
    Si una transacción tiene múltiples errores, prevalece el mapping con
    menor valor de priority.
*/
resolved_errors AS (
    SELECT
        d.errors_raw,
        x.target_status_code,
        x.target_decline_reason_code,
        x.response_code

    FROM distinct_errors d

    LEFT JOIN LATERAL (
        SELECT
            m.target_status_code,
            m.target_decline_reason_code,
            m.response_code

        FROM unnest(
            string_to_array(d.errors_raw, ',')
        ) AS e(error_text)

        JOIN ctl.source_error_mapping m
          ON m.source_system_code = 'IBM_CORE'
         AND m.active_flag = TRUE
         AND m.source_error_pattern = BTRIM(e.error_text)

        ORDER BY m.priority
        LIMIT 1

    ) x ON TRUE
),

/*
    Normalización mínima de la transacción fuente.
*/
base AS (
    SELECT
        t.source_user_id,
        t.card_index,

        t.merchant_name_raw,
        t.merchant_city,
        t.merchant_state,
        t.merchant_zip_raw,

        t.errors_raw,
        t.is_fraud_raw,

        f.file_hash_sha256
            || ':'
            || t.source_row_number::text
            AS source_transaction_key,

        NULLIF(
            regexp_replace(
                BTRIM(t.amount_raw),
                '[$,]',
                '',
                'g'
            ),
            ''
        )::numeric AS amount_num,

        CASE UPPER(BTRIM(t.is_fraud_raw))
            WHEN 'YES' THEN TRUE
            ELSE FALSE
        END AS fraud_flag_num,

        concat_ws(
            '|',

            BTRIM(t.merchant_name_raw),

            UPPER(
                COALESCE(
                    NULLIF(BTRIM(t.merchant_city), ''),
                    'UNKNOWN'
                )
            ),

            UPPER(
                COALESCE(
                    NULLIF(BTRIM(t.merchant_state), ''),
                    ''
                )
            ),

            COALESCE(
                NULLIF(
                    regexp_replace(
                        BTRIM(t.merchant_zip_raw),
                        '\.0$',
                        ''
                    ),
                    ''
                ),
                ''
            )
        ) AS location_seed

    FROM stg.ibm_transactions_raw t

    JOIN ctl.etl_file f
      ON f.etl_file_id = t.etl_file_id

    WHERE t.etl_file_id = 4

      /*
          card_transaction tiene:
              CHECK (amount <> 0)

          Por tanto los montos cero quedan fuera de la carga OLTP
          y están auditados en ctl.data_quality_issue.
      */
      AND NULLIF(
          regexp_replace(
              BTRIM(t.amount_raw),
              '[$,]',
              '',
              'g'
          ),
          ''
      )::numeric <> 0
),

/*
    Incorporación de datos necesarios para aplicar las reglas:
        - límite de crédito
        - país emisor
        - país del comercio
        - mapping de errores
*/
enriched AS (
    SELECT
        b.*,

        c.credit_limit,
        c.issuer_country_code,

        ml.country_code AS merchant_country_code,

        r.target_status_code
            AS mapped_status_code,

        r.target_decline_reason_code
            AS mapped_decline_reason_code,

        r.response_code
            AS mapped_response_code,

        (
            NULLIF(BTRIM(b.errors_raw), '') IS NOT NULL
        ) AS error_flag_num

    FROM base b

    JOIN oltp.card c
      ON c.source_system_id = 1
     AND c.source_card_key =
         'IBM_CARD:'
         || BTRIM(b.source_user_id)
         || ':'
         || BTRIM(b.card_index)

    JOIN oltp.merchant m
      ON m.source_system_id = 1
     AND m.source_merchant_key =
         'IBM_MERCHANT:'
         || BTRIM(b.merchant_name_raw)

    JOIN oltp.merchant_location ml
      ON ml.merchant_id = m.merchant_id
     AND ml.source_location_key =
         'IBM_LOCATION:'
         || ctl.fn_sha256_hex(b.location_seed)

    LEFT JOIN resolved_errors r
      ON r.errors_raw = BTRIM(b.errors_raw)
),

/*
===============================================================================
Prioridad de reglas de autorización

1. amount < 0
       -> REVERSED

2. Error fuente mapeado como ERROR
       -> ERROR

3. Error fuente mapeado como DECLINED
       -> DECLINED + motivo del mapping

4. Error fuente presente pero no mapeado
       -> ERROR

5. amount > credit_limit
       -> DECLINED / CREDIT_LIMIT_EXCEEDED

6. fraud_flag = TRUE y bucket determinístico < FRAUD_DECLINE_PERCENT
       -> DECLINED / SUSPECTED_FRAUD

7. issuer_country <> merchant_country
   y bucket determinístico < INTERNATIONAL_DECLINE_PERCENT
       -> DECLINED / INTERNATIONAL_NOT_ALLOWED

8. Bucket residual < BASE_DECLINE_PERCENT
       -> DECLINED / DO_NOT_HONOR

9. Resto
       -> APPROVED
===============================================================================
*/
rules AS (
    SELECT
        e.*,

        CASE
            WHEN e.amount_num < 0
                THEN 'REVERSED'

            WHEN e.mapped_status_code = 'ERROR'
                THEN 'ERROR'

            WHEN e.mapped_status_code = 'DECLINED'
                THEN 'DECLINED'

            WHEN e.error_flag_num
                 AND e.mapped_status_code IS NULL
                THEN 'ERROR'

            WHEN e.credit_limit IS NOT NULL
                 AND e.amount_num > e.credit_limit
                THEN 'DECLINED'

            WHEN e.fraud_flag_num
                 AND ctl.fn_bucket_100(
                     e.source_transaction_key
                     || '|FRAUD|v'
                     || p.ruleset_version
                 ) < p.fraud_decline_percent
                THEN 'DECLINED'

            WHEN e.issuer_country_code <> e.merchant_country_code
                 AND ctl.fn_bucket_100(
                     e.source_transaction_key
                     || '|INTL|v'
                     || p.ruleset_version
                 ) < p.international_decline_percent
                THEN 'DECLINED'

            WHEN ctl.fn_bucket_100(
                     e.source_transaction_key
                     || '|BASE|v'
                     || p.ruleset_version
                 ) < p.base_decline_percent
                THEN 'DECLINED'

            ELSE 'APPROVED'
        END AS status_code,

        CASE
            /*
                REVERSED no puede llevar decline_reason_id.
            */
            WHEN e.amount_num < 0
                THEN NULL

            /*
                ERROR tampoco puede llevar decline_reason_id.
            */
            WHEN e.mapped_status_code = 'ERROR'
                THEN NULL

            /*
                Motivo proveniente directamente del mapping de errores.
            */
            WHEN e.mapped_status_code = 'DECLINED'
                THEN e.mapped_decline_reason_code

            /*
                Error no mapeado -> ERROR, por tanto sin decline reason.
            */
            WHEN e.error_flag_num
                 AND e.mapped_status_code IS NULL
                THEN NULL

            WHEN e.credit_limit IS NOT NULL
                 AND e.amount_num > e.credit_limit
                THEN 'CREDIT_LIMIT_EXCEEDED'

            WHEN e.fraud_flag_num
                 AND ctl.fn_bucket_100(
                     e.source_transaction_key
                     || '|FRAUD|v'
                     || p.ruleset_version
                 ) < p.fraud_decline_percent
                THEN 'SUSPECTED_FRAUD'

            WHEN e.issuer_country_code <> e.merchant_country_code
                 AND ctl.fn_bucket_100(
                     e.source_transaction_key
                     || '|INTL|v'
                     || p.ruleset_version
                 ) < p.international_decline_percent
                THEN 'INTERNATIONAL_NOT_ALLOWED'

            WHEN ctl.fn_bucket_100(
                     e.source_transaction_key
                     || '|BASE|v'
                     || p.ruleset_version
                 ) < p.base_decline_percent
                THEN 'DO_NOT_HONOR'

            ELSE NULL
        END AS decline_reason_code

    FROM enriched e
    CROSS JOIN params p
)

/*
===============================================================================
Resultado de validación
===============================================================================
*/
SELECT
    status_code,

    COALESCE(
        decline_reason_code,
        '<NULL>'
    ) AS decline_reason_code,

    COUNT(*) AS transactions,

    /*
        Debe ser 24,366,687 en todas las filas del resultado.
    */
    SUM(COUNT(*)) OVER ()
        AS total_transactions,

    /*
        Debe ser 0.

        Regla del trigger:
            DECLINED     -> decline_reason obligatorio
            No DECLINED  -> decline_reason debe ser NULL
    */
    SUM(
        COUNT(*) FILTER (
            WHERE
                (
                    status_code = 'DECLINED'
                    AND decline_reason_code IS NULL
                )
                OR
                (
                    status_code <> 'DECLINED'
                    AND decline_reason_code IS NOT NULL
                )
        )
    ) OVER () AS invalid_trigger_rows

FROM rules

GROUP BY
    status_code,
    decline_reason_code

ORDER BY
    CASE status_code
        WHEN 'APPROVED' THEN 1
        WHEN 'DECLINED' THEN 2
        WHEN 'ERROR' THEN 3
        WHEN 'REVERSED' THEN 4
        ELSE 5
    END,

    transactions DESC;