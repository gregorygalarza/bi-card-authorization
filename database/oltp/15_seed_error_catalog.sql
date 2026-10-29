/*
===============================================================================
15_seed_error_catalog.sql

Objetivo:
    Poblar oltp.error_catalog a partir de los errores IBM configurados
    en ctl.source_error_mapping.

Criterio:
    - response_code se utiliza como código normalizado del error.
    - source_error_pattern conserva la descripción original de la fuente.
    - UNKNOWN permanece como fallback.
    - La carga es idempotente.
===============================================================================
*/

INSERT INTO oltp.error_catalog (
    error_code,
    error_description,
    active_flag
)
SELECT DISTINCT
    m.response_code AS error_code,
    m.source_error_pattern AS error_description,
    TRUE AS active_flag
FROM ctl.source_error_mapping m
WHERE m.source_system_code = 'IBM_CORE'
  AND m.active_flag = TRUE
  AND m.response_code IS NOT NULL

ON CONFLICT (error_code)
DO UPDATE SET
    error_description = EXCLUDED.error_description,
    active_flag = EXCLUDED.active_flag;


/*
===============================================================================
Validación
===============================================================================
*/

SELECT
    error_id,
    error_code,
    error_description,
    active_flag
FROM oltp.error_catalog
ORDER BY error_id;