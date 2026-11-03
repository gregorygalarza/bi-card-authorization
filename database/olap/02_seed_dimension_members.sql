/*
===============================================================================
02_seed_dimension_members.sql

Proyecto:
    Denegación de Transacciones Internacionales

Objetivo:
    Poblar las dimensiones pequeñas y los miembros especiales requeridos
    por fact_transaction.

Dimensiones:
    - dim_authorization_status
    - dim_decline_reason
    - dim_entry_mode
    - dim_error

Criterios:
    - Los catálogos existentes se copian desde OLTP.
    - NOT_APPLICABLE se utiliza cuando una dimensión no aplica al evento.
    - UNKNOWN se utiliza como fallback cuando el valor no puede determinarse.
    - El script es idempotente mediante ON CONFLICT.
===============================================================================
*/

BEGIN;


/*
===============================================================================
1. DIM_AUTHORIZATION_STATUS

El catálogo OLTP ya contiene UNKNOWN.
===============================================================================
*/

INSERT INTO olap.dim_authorization_status (
    status_code,
    status_name,
    status_description,
    active_flag
)
SELECT
    s.status_code,
    s.status_name,
    s.description,
    s.active_flag
FROM oltp.authorization_status s

ON CONFLICT (status_code)
DO UPDATE SET
    status_name        = EXCLUDED.status_name,
    status_description = EXCLUDED.status_description,
    active_flag        = EXCLUDED.active_flag;


/*
===============================================================================
2. DIM_DECLINE_REASON

Los motivos reales se copian desde OLTP.

NOT_APPLICABLE:
    Se utilizará para transacciones cuyo estado no sea DECLINED.

UNKNOWN:
    Ya existe en el catálogo OLTP y se mantiene como fallback para
    transacciones denegadas cuyo motivo no pueda determinarse.
===============================================================================
*/

INSERT INTO olap.dim_decline_reason (
    reason_code,
    reason_name,
    reason_description,
    reason_category,
    active_flag
)
VALUES (
    'NOT_APPLICABLE',
    'Not applicable',
    'No corresponde un motivo de denegación para el estado de la transacción.',
    'NOT_APPLICABLE',
    TRUE
)

ON CONFLICT (reason_code)
DO UPDATE SET
    reason_name        = EXCLUDED.reason_name,
    reason_description = EXCLUDED.reason_description,
    reason_category    = EXCLUDED.reason_category,
    active_flag        = EXCLUDED.active_flag;


INSERT INTO olap.dim_decline_reason (
    reason_code,
    reason_name,
    reason_description,
    reason_category,
    active_flag
)
SELECT
    d.reason_code,
    d.reason_name,
    d.reason_description,
    d.reason_category,
    d.active_flag
FROM oltp.decline_reason d

ON CONFLICT (reason_code)
DO UPDATE SET
    reason_name        = EXCLUDED.reason_name,
    reason_description = EXCLUDED.reason_description,
    reason_category    = EXCLUDED.reason_category,
    active_flag        = EXCLUDED.active_flag;


/*
===============================================================================
3. DIM_ENTRY_MODE

Valores normalizados utilizados actualmente por el proceso ETL.

UNKNOWN:
    Fallback para modos de entrada no identificados.
===============================================================================
*/

INSERT INTO olap.dim_entry_mode (
    entry_mode_code,
    entry_mode_description,
    active_flag
)
VALUES
    (
        'SWIPE',
        'Transacción procesada mediante lectura de banda magnética.',
        TRUE
    ),
    (
        'CHIP',
        'Transacción procesada mediante chip de la tarjeta.',
        TRUE
    ),
    (
        'ONLINE',
        'Transacción realizada mediante canal online.',
        TRUE
    ),
    (
        'UNKNOWN',
        'Modo de entrada no informado o no determinado.',
        TRUE
    )

ON CONFLICT (entry_mode_code)
DO UPDATE SET
    entry_mode_description = EXCLUDED.entry_mode_description,
    active_flag            = EXCLUDED.active_flag;


/*
===============================================================================
4. DIM_ERROR

NOT_APPLICABLE:
    Se utilizará cuando la transacción no presente ningún error fuente.

UNKNOWN:
    Ya existe en oltp.error_catalog y se mantiene como fallback.

Los demás errores se copian directamente desde el catálogo operacional.
===============================================================================
*/

INSERT INTO olap.dim_error (
    error_code,
    error_description,
    active_flag
)
VALUES (
    'NOT_APPLICABLE',
    'La transacción no presenta un error fuente asociado.',
    TRUE
)

ON CONFLICT (error_code)
DO UPDATE SET
    error_description = EXCLUDED.error_description,
    active_flag       = EXCLUDED.active_flag;


INSERT INTO olap.dim_error (
    error_code,
    error_description,
    active_flag
)
SELECT
    e.error_code,
    e.error_description,
    e.active_flag
FROM oltp.error_catalog e

ON CONFLICT (error_code)
DO UPDATE SET
    error_description = EXCLUDED.error_description,
    active_flag       = EXCLUDED.active_flag;


COMMIT;


/*
===============================================================================
5. VALIDACIÓN
===============================================================================
*/

SELECT
    'dim_authorization_status' AS dimension_name,
    COUNT(*) AS rows
FROM olap.dim_authorization_status

UNION ALL

SELECT
    'dim_decline_reason',
    COUNT(*)
FROM olap.dim_decline_reason

UNION ALL

SELECT
    'dim_entry_mode',
    COUNT(*)
FROM olap.dim_entry_mode

UNION ALL

SELECT
    'dim_error',
    COUNT(*)
FROM olap.dim_error

ORDER BY dimension_name;


/*
===============================================================================
6. DETALLE DE MIEMBROS ESPECIALES
===============================================================================
*/

SELECT
    'DECLINE_REASON' AS dimension_name,
    reason_code AS member_code,
    reason_name AS member_name
FROM olap.dim_decline_reason
WHERE reason_code IN (
    'NOT_APPLICABLE',
    'UNKNOWN'
)

UNION ALL

SELECT
    'ENTRY_MODE',
    entry_mode_code,
    entry_mode_description
FROM olap.dim_entry_mode
WHERE entry_mode_code = 'UNKNOWN'

UNION ALL

SELECT
    'ERROR',
    error_code,
    error_description
FROM olap.dim_error
WHERE error_code IN (
    'NOT_APPLICABLE',
    'UNKNOWN'
)

ORDER BY
    dimension_name,
    member_code;