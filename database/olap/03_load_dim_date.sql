/*
===============================================================================
03_load_dim_date.sql

Proyecto:
    Denegación de Transacciones Internacionales

Objetivo:
    Poblar olap.dim_date utilizando únicamente el rango temporal realmente
    presente en oltp.card_transaction.

Convención temporal:
    transaction_datetime fue normalizado utilizando UTC debido a que la fuente
    original no proporciona zona horaria.

    Por reproducibilidad, la fecha analítica se obtiene mediante:

        transaction_datetime AT TIME ZONE 'UTC'

Clave:
    date_key = YYYYMMDD

Ejemplo:
    2026-10-29 -> 20261029

El script es idempotente.
===============================================================================
*/

WITH date_bounds AS (
    SELECT
        MIN(
            (transaction_datetime AT TIME ZONE 'UTC')::date
        ) AS min_date,

        MAX(
            (transaction_datetime AT TIME ZONE 'UTC')::date
        ) AS max_date

    FROM oltp.card_transaction
),

calendar AS (
    SELECT
        b.min_date + g.day_offset AS full_date
    FROM date_bounds b
    CROSS JOIN LATERAL generate_series(
        0,
        b.max_date - b.min_date
    ) AS g(day_offset)
),

prepared AS (
    SELECT
        full_date,

        TO_CHAR(
            full_date,
            'YYYYMMDD'
        )::integer AS date_key,

        EXTRACT(YEAR FROM full_date)::smallint
            AS year_number,

        EXTRACT(QUARTER FROM full_date)::smallint
            AS quarter_number,

        EXTRACT(MONTH FROM full_date)::smallint
            AS month_number,

        CASE EXTRACT(MONTH FROM full_date)::integer
            WHEN 1  THEN 'Enero'
            WHEN 2  THEN 'Febrero'
            WHEN 3  THEN 'Marzo'
            WHEN 4  THEN 'Abril'
            WHEN 5  THEN 'Mayo'
            WHEN 6  THEN 'Junio'
            WHEN 7  THEN 'Julio'
            WHEN 8  THEN 'Agosto'
            WHEN 9  THEN 'Septiembre'
            WHEN 10 THEN 'Octubre'
            WHEN 11 THEN 'Noviembre'
            WHEN 12 THEN 'Diciembre'
        END AS month_name,

        EXTRACT(DAY FROM full_date)::smallint
            AS day_of_month,

        EXTRACT(ISODOW FROM full_date)::smallint
            AS day_of_week,

        CASE EXTRACT(ISODOW FROM full_date)::integer
            WHEN 1 THEN 'Lunes'
            WHEN 2 THEN 'Martes'
            WHEN 3 THEN 'Miércoles'
            WHEN 4 THEN 'Jueves'
            WHEN 5 THEN 'Viernes'
            WHEN 6 THEN 'Sábado'
            WHEN 7 THEN 'Domingo'
        END AS day_name,

        (
            EXTRACT(ISODOW FROM full_date)::integer
            IN (6, 7)
        ) AS is_weekend

    FROM calendar
)

INSERT INTO olap.dim_date (
    date_key,
    full_date,
    year_number,
    quarter_number,
    month_number,
    month_name,
    day_of_month,
    day_of_week,
    day_name,
    is_weekend
)

SELECT
    date_key,
    full_date,
    year_number,
    quarter_number,
    month_number,
    month_name,
    day_of_month,
    day_of_week,
    day_name,
    is_weekend

FROM prepared

ON CONFLICT (date_key)
DO UPDATE SET
    full_date      = EXCLUDED.full_date,
    year_number    = EXCLUDED.year_number,
    quarter_number = EXCLUDED.quarter_number,
    month_number   = EXCLUDED.month_number,
    month_name     = EXCLUDED.month_name,
    day_of_month   = EXCLUDED.day_of_month,
    day_of_week    = EXCLUDED.day_of_week,
    day_name       = EXCLUDED.day_name,
    is_weekend     = EXCLUDED.is_weekend;


/*
===============================================================================
VALIDACIÓN
===============================================================================
*/

SELECT
    COUNT(*) AS date_rows,
    MIN(full_date) AS min_date,
    MAX(full_date) AS max_date,
    MIN(date_key) AS min_date_key,
    MAX(date_key) AS max_date_key
FROM olap.dim_date;


/*
Verificar que cada fecha presente en las transacciones tenga correspondencia
en la dimensión.
*/

SELECT
    COUNT(*) AS missing_transaction_dates
FROM (
    SELECT DISTINCT
        (t.transaction_datetime AT TIME ZONE 'UTC')::date AS transaction_date
    FROM oltp.card_transaction t
) x

LEFT JOIN olap.dim_date d
  ON d.full_date = x.transaction_date

WHERE d.date_key IS NULL;