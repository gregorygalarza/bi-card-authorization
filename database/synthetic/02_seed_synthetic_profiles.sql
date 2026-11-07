BEGIN;

-- ============================================================
-- SEED SYNTHETIC PROFILES
-- ============================================================


-- ------------------------------------------------------------
-- 1. SOURCE SYSTEM SINTÉTICO
-- ------------------------------------------------------------

INSERT INTO oltp.source_system (
    source_code,
    source_name,
    description,
    active_flag
)
VALUES (
    'ACADEMIC_SYNTH',
    'Academic Synthetic Data',
    'Datos sintéticos determinísticos generados para pruebas académicas, validación ETL y demostraciones.',
    TRUE
)
ON CONFLICT (source_code)
DO UPDATE SET
    source_name = EXCLUDED.source_name,
    description = EXCLUDED.description,
    active_flag = TRUE;


-- ------------------------------------------------------------
-- 2. PERFIL BASE
-- ------------------------------------------------------------

INSERT INTO ctl.synthetic_profile (
    profile_code,
    profile_name,
    baseline_source_code,
    target_transactions,
    description,
    active_flag
)
VALUES (
    'IBM_CORE_1M_V1',
    'IBM Core Synthetic Profile - 1M',
    'IBM_CORE',
    1000000,
    'Perfil sintético determinístico basado en las distribuciones validadas de IBM_CORE.',
    TRUE
)
ON CONFLICT (profile_code)
DO UPDATE SET
    profile_name = EXCLUDED.profile_name,
    baseline_source_code = EXCLUDED.baseline_source_code,
    target_transactions = EXCLUDED.target_transactions,
    description = EXCLUDED.description,
    active_flag = TRUE,
    updated_at = CURRENT_TIMESTAMP;


-- ------------------------------------------------------------
-- 3. MÉTRICAS DEL PERFIL
-- ------------------------------------------------------------

INSERT INTO ctl.synthetic_profile_metric (
    profile_code,
    metric_group,
    metric_code,
    target_count,
    target_pct,
    notes
)
VALUES

-- ============================================================
-- AUTHORIZATION STATUS
-- ============================================================

('IBM_CORE_1M_V1','AUTH_STATUS','APPROVED',
 906918,90.6918,NULL),

('IBM_CORE_1M_V1','AUTH_STATUS','DECLINED',
 40088,4.0088,NULL),

('IBM_CORE_1M_V1','AUTH_STATUS','REVERSED',
 51081,5.1081,NULL),

('IBM_CORE_1M_V1','AUTH_STATUS','ERROR',
 1913,0.1913,NULL),


-- ============================================================
-- GEOGRAPHY
-- ============================================================

('IBM_CORE_1M_V1','GEOGRAPHY','DOMESTIC',
 881883,88.1883,NULL),

('IBM_CORE_1M_V1','GEOGRAPHY','UNKNOWN',
 111661,11.1661,NULL),

('IBM_CORE_1M_V1','GEOGRAPHY','INTERNATIONAL',
 6456,0.6456,NULL),


-- ============================================================
-- ENTRY MODE
-- ============================================================

('IBM_CORE_1M_V1','ENTRY_MODE','SWIPE',
 630849,63.0849,NULL),

('IBM_CORE_1M_V1','ENTRY_MODE','CHIP',
 257802,25.7802,NULL),

('IBM_CORE_1M_V1','ENTRY_MODE','ONLINE',
 111349,11.1349,NULL),


-- ============================================================
-- DECLINE REASON
-- Total = 40,088
-- ============================================================

('IBM_CORE_1M_V1','DECLINE_REASON','DO_NOT_HONOR',
 18538,46.2437,NULL),

('IBM_CORE_1M_V1','DECLINE_REASON','INSUFFICIENT_FUNDS',
 9493,23.6815,NULL),

('IBM_CORE_1M_V1','DECLINE_REASON','CREDIT_LIMIT_EXCEEDED',
 6891,17.1891,NULL),

('IBM_CORE_1M_V1','DECLINE_REASON','SECURITY_VIOLATION',
 2819,7.0319,NULL),

('IBM_CORE_1M_V1','DECLINE_REASON','SUSPECTED_FRAUD',
 680,1.6972,NULL),

('IBM_CORE_1M_V1','DECLINE_REASON','INTERNATIONAL_NOT_ALLOWED',
 674,1.6809,NULL),

('IBM_CORE_1M_V1','DECLINE_REASON','INVALID_CARD',
 549,1.3690,NULL),

('IBM_CORE_1M_V1','DECLINE_REASON','EXPIRED_CARD',
 444,1.1067,NULL),


-- ============================================================
-- FRAUD
-- ============================================================

('IBM_CORE_1M_V1','FRAUD','TRUE',
 1221,0.1221,NULL),

('IBM_CORE_1M_V1','FRAUD','FALSE',
 998779,99.8779,NULL),


-- ============================================================
-- ERROR SUMMARY
-- ============================================================

('IBM_CORE_1M_V1','ERROR_SUMMARY','TRANSACTIONS_WITH_ERROR',
 15936,1.5936,
 'Cantidad de transacciones que tendrán al menos un error.'),

('IBM_CORE_1M_V1','ERROR_SUMMARY','ERROR_OCCURRENCES',
 16006,1.6006,
 'Cantidad total de ocurrencias de error; incluye errores múltiples.'),


-- ============================================================
-- ERROR OCCURRENCE DISTRIBUTION
-- Total = 16,006
-- ============================================================

('IBM_CORE_1M_V1','ERROR_OCCURRENCE','INSUFFICIENT_FUNDS',
 10018,62.5921,NULL),

('IBM_CORE_1M_V1','ERROR_OCCURRENCE','BAD_PIN',
 2443,15.2636,NULL),

('IBM_CORE_1M_V1','ERROR_OCCURRENCE','TECHNICAL_ERROR',
 2003,12.5112,NULL),

('IBM_CORE_1M_V1','ERROR_OCCURRENCE','INVALID_CARD',
 557,3.4831,NULL),

('IBM_CORE_1M_V1','ERROR_OCCURRENCE','BAD_CVV',
 450,2.8093,NULL),

('IBM_CORE_1M_V1','ERROR_OCCURRENCE','EXPIRED_CARD',
 449,2.8024,NULL),

('IBM_CORE_1M_V1','ERROR_OCCURRENCE','BAD_ZIPCODE',
 86,0.5382,NULL),


-- ============================================================
-- CARD PROFILE
-- ============================================================

('IBM_CORE_1M_V1','CARD_PROFILE','MASTERCARD|DEBIT',
 400103,40.0103,NULL),

('IBM_CORE_1M_V1','CARD_PROFILE','VISA|DEBIT',
 217388,21.7388,NULL),

('IBM_CORE_1M_V1','CARD_PROFILE','VISA|CREDIT',
 128179,12.8179,NULL),

('IBM_CORE_1M_V1','CARD_PROFILE','MASTERCARD|CREDIT',
 91424,9.1424,NULL),

('IBM_CORE_1M_V1','CARD_PROFILE','AMEX|CREDIT',
 65675,6.5675,NULL),

('IBM_CORE_1M_V1','CARD_PROFILE','MASTERCARD|DEBIT_PREPAID',
 45347,4.5347,NULL),

('IBM_CORE_1M_V1','CARD_PROFILE','DISCOVER|CREDIT',
 29389,2.9389,NULL),

('IBM_CORE_1M_V1','CARD_PROFILE','VISA|DEBIT_PREPAID',
 22495,2.2495,NULL),


-- ============================================================
-- INTERNATIONAL COUNTRY WEIGHTS
--
-- Top 25 = 86.6913 %
-- OTHER  = 13.3087 %
-- ============================================================

('IBM_CORE_1M_V1','COUNTRY_INTL','MX',NULL,29.9743,NULL),
('IBM_CORE_1M_V1','COUNTRY_INTL','CA',NULL,12.8080,NULL),
('IBM_CORE_1M_V1','COUNTRY_INTL','IT',NULL,5.5458,NULL),
('IBM_CORE_1M_V1','COUNTRY_INTL','GB',NULL,5.1205,NULL),
('IBM_CORE_1M_V1','COUNTRY_INTL','FR',NULL,3.3762,NULL),
('IBM_CORE_1M_V1','COUNTRY_INTL','DE',NULL,3.3457,NULL),
('IBM_CORE_1M_V1','COUNTRY_INTL','CN',NULL,3.1759,NULL),
('IBM_CORE_1M_V1','COUNTRY_INTL','JP',NULL,2.5142,NULL),
('IBM_CORE_1M_V1','COUNTRY_INTL','IN',NULL,2.2135,NULL),
('IBM_CORE_1M_V1','COUNTRY_INTL','ES',NULL,2.0361,NULL),
('IBM_CORE_1M_V1','COUNTRY_INTL','DO',NULL,1.7507,NULL),
('IBM_CORE_1M_V1','COUNTRY_INTL','NL',NULL,1.6630,NULL),
('IBM_CORE_1M_V1','COUNTRY_INTL','JM',NULL,1.3884,NULL),
('IBM_CORE_1M_V1','COUNTRY_INTL','KR',NULL,1.3845,NULL),
('IBM_CORE_1M_V1','COUNTRY_INTL','CH',NULL,1.2377,NULL),
('IBM_CORE_1M_V1','COUNTRY_INTL','IL',NULL,1.1125,NULL),
('IBM_CORE_1M_V1','COUNTRY_INTL','IE',NULL,1.0769,NULL),
('IBM_CORE_1M_V1','COUNTRY_INTL','BS',NULL,1.0642,NULL),
('IBM_CORE_1M_V1','COUNTRY_INTL','TW',NULL,0.9739,NULL),
('IBM_CORE_1M_V1','COUNTRY_INTL','CO',NULL,0.9167,NULL),
('IBM_CORE_1M_V1','COUNTRY_INTL','AT',NULL,0.9129,NULL),
('IBM_CORE_1M_V1','COUNTRY_INTL','CR',NULL,0.8131,NULL),
('IBM_CORE_1M_V1','COUNTRY_INTL','TH',NULL,0.7940,NULL),
('IBM_CORE_1M_V1','COUNTRY_INTL','PH',NULL,0.7666,NULL),
('IBM_CORE_1M_V1','COUNTRY_INTL','BR',NULL,0.7260,NULL),

('IBM_CORE_1M_V1','COUNTRY_INTL','OTHER',
 NULL,13.3087,
 'Distribuir determinísticamente entre otros países activos diferentes de US y ZZ.'),


-- ============================================================
-- MCC WEIGHTS
--
-- Top 25 = 91.4426 %
-- OTHER  = 8.5574 %
-- ============================================================

('IBM_CORE_1M_V1','MCC','5411',NULL,11.7403,NULL),
('IBM_CORE_1M_V1','MCC','5499',NULL,11.0011,NULL),
('IBM_CORE_1M_V1','MCC','5541',NULL,10.8303,NULL),
('IBM_CORE_1M_V1','MCC','5812',NULL,7.3786,NULL),
('IBM_CORE_1M_V1','MCC','5912',NULL,5.7769,NULL),
('IBM_CORE_1M_V1','MCC','4784',NULL,4.6140,NULL),
('IBM_CORE_1M_V1','MCC','5300',NULL,4.6089,NULL),
('IBM_CORE_1M_V1','MCC','4829',NULL,4.5508,NULL),
('IBM_CORE_1M_V1','MCC','4121',NULL,4.0281,NULL),
('IBM_CORE_1M_V1','MCC','7538',NULL,3.7536,NULL),
('IBM_CORE_1M_V1','MCC','5814',NULL,3.6946,NULL),
('IBM_CORE_1M_V1','MCC','5311',NULL,3.6349,NULL),
('IBM_CORE_1M_V1','MCC','4900',NULL,1.8780,NULL),
('IBM_CORE_1M_V1','MCC','5310',NULL,1.8636,NULL),
('IBM_CORE_1M_V1','MCC','5813',NULL,1.8017,NULL),
('IBM_CORE_1M_V1','MCC','5942',NULL,1.7109,NULL),
('IBM_CORE_1M_V1','MCC','4814',NULL,1.6722,NULL),
('IBM_CORE_1M_V1','MCC','5211',NULL,1.3275,NULL),
('IBM_CORE_1M_V1','MCC','7832',NULL,1.0217,NULL),
('IBM_CORE_1M_V1','MCC','5921',NULL,0.9261,NULL),
('IBM_CORE_1M_V1','MCC','7230',NULL,0.8153,NULL),
('IBM_CORE_1M_V1','MCC','9402',NULL,0.7216,NULL),
('IBM_CORE_1M_V1','MCC','4214',NULL,0.7208,NULL),
('IBM_CORE_1M_V1','MCC','4111',NULL,0.7133,NULL),
('IBM_CORE_1M_V1','MCC','5719',NULL,0.6578,NULL),

('IBM_CORE_1M_V1','MCC','OTHER',
 NULL,8.5574,
 'Distribuir determinísticamente entre otros MCC activos.'),


-- ============================================================
-- KPI INTERSECTION
--
-- El target_count se ajustará por SET.
-- ============================================================

('IBM_CORE_1M_V1','KPI','INTERNATIONAL_DECLINED',
 1035,16.0240,
 'El porcentaje corresponde al baseline. El conteo exacto varía entre los cuatro sets.')

ON CONFLICT (
    profile_code,
    metric_group,
    metric_code
)
DO UPDATE SET
    target_count = EXCLUDED.target_count,
    target_pct = EXCLUDED.target_pct,
    notes = EXCLUDED.notes;


-- ------------------------------------------------------------
-- 4. AMOUNT PROFILE
-- ------------------------------------------------------------

INSERT INTO ctl.synthetic_amount_profile (
    profile_code,
    status_code,
    avg_abs_amount,
    p25,
    p50,
    p75,
    p90,
    p95,
    p99
)
VALUES
(
    'IBM_CORE_1M_V1',
    'APPROVED',
    50.98,
    11.38,
    32.63,
    66.97,
    108.81,
    150.01,
    322.68
),
(
    'IBM_CORE_1M_V1',
    'REVERSED',
    102.19,
    64.00,
    79.00,
    93.00,
    168.00,
    333.00,
    467.00
),
(
    'IBM_CORE_1M_V1',
    'DECLINED',
    60.60,
    15.64,
    46.55,
    81.11,
    118.60,
    156.01,
    346.40
),
(
    'IBM_CORE_1M_V1',
    'ERROR',
    53.54,
    11.06,
    35.72,
    74.00,
    120.00,
    150.96,
    298.43
)
ON CONFLICT (
    profile_code,
    status_code
)
DO UPDATE SET
    avg_abs_amount = EXCLUDED.avg_abs_amount,
    p25 = EXCLUDED.p25,
    p50 = EXCLUDED.p50,
    p75 = EXCLUDED.p75,
    p90 = EXCLUDED.p90,
    p95 = EXCLUDED.p95,
    p99 = EXCLUDED.p99;


-- ------------------------------------------------------------
-- 5. DATASETS
--
-- Se utilizan ventanas históricas distintas y ya cubiertas
-- por dim_date. Los registros serán NUEVOS por su source key,
-- aunque las fechas pertenezcan a 2019.
--
-- Cardinalidad aproximada IBM:
--   100 customers
--   300 cards
--   4,000 merchants
--   12,000 locations
--   1,000,000 transactions
-- ------------------------------------------------------------

INSERT INTO ctl.synthetic_dataset (
    set_code,
    profile_code,
    source_system_code,
    seed,
    key_prefix,
    purpose,

    target_customers,
    target_cards,
    target_merchants,
    target_locations,
    target_transactions,

    transaction_date_from,
    transaction_date_to,

    oltp_status,
    olap_status,

    notes
)
VALUES

(
    'SYNTH_SET_01',
    'IBM_CORE_1M_V1',
    'ACADEMIC_SYNTH',
    1101,
    'SYNTH:S01',
    'Desarrollo y prueba inicial',

    100,
    300,
    4000,
    12000,
    1000000,

    DATE '2019-09-01',
    DATE '2019-09-30',

    'REGISTERED',
    'PENDING',

    'Primer set para desarrollo del generador e incremental OLTP a OLAP.'
),

(
    'SYNTH_SET_02',
    'IBM_CORE_1M_V1',
    'ACADEMIC_SYNTH',
    1102,
    'SYNTH:S02',
    'Revalidación de no colisión e idempotencia',

    100,
    300,
    4000,
    12000,
    1000000,

    DATE '2019-10-01',
    DATE '2019-10-31',

    'REGISTERED',
    'PENDING',

    'Segundo set para validar independencia, no colisión e incremental.'
),

(
    'SYNTH_SET_03',
    'IBM_CORE_1M_V1',
    'ACADEMIC_SYNTH',
    1103,
    'SYNTH:S03',
    'Demostración docente',

    100,
    300,
    4000,
    12000,
    1000000,

    DATE '2019-11-01',
    DATE '2019-11-30',

    'REGISTERED',
    'PENDING',

    'Set reservado para demostración en clase.'
),

(
    'SYNTH_SET_04',
    'IBM_CORE_1M_V1',
    'ACADEMIC_SYNTH',
    1104,
    'SYNTH:S04',
    'Backup de demostración',

    100,
    300,
    4000,
    12000,
    1000000,

    DATE '2019-12-01',
    DATE '2019-12-31',

    'REGISTERED',
    'PENDING',

    'Set de respaldo reservado para contingencia durante la demostración.'
)

ON CONFLICT (set_code)
DO UPDATE SET
    profile_code = EXCLUDED.profile_code,
    source_system_code = EXCLUDED.source_system_code,
    seed = EXCLUDED.seed,
    key_prefix = EXCLUDED.key_prefix,
    purpose = EXCLUDED.purpose,

    target_customers = EXCLUDED.target_customers,
    target_cards = EXCLUDED.target_cards,
    target_merchants = EXCLUDED.target_merchants,
    target_locations = EXCLUDED.target_locations,
    target_transactions = EXCLUDED.target_transactions,

    transaction_date_from = EXCLUDED.transaction_date_from,
    transaction_date_to = EXCLUDED.transaction_date_to,

    notes = EXCLUDED.notes,
    updated_at = CURRENT_TIMESTAMP;


-- ------------------------------------------------------------
-- 6. MATERIALIZAR TARGETS POR DATASET
-- ------------------------------------------------------------

INSERT INTO ctl.synthetic_dataset_target (
    set_code,
    metric_group,
    metric_code,
    target_count,
    target_pct,
    notes
)
SELECT
    d.set_code,
    m.metric_group,
    m.metric_code,
    m.target_count,
    m.target_pct,
    m.notes
FROM ctl.synthetic_dataset d
JOIN ctl.synthetic_profile_metric m
  ON m.profile_code = d.profile_code
WHERE d.profile_code = 'IBM_CORE_1M_V1'

ON CONFLICT (
    set_code,
    metric_group,
    metric_code
)
DO UPDATE SET
    target_count = EXCLUDED.target_count,
    target_pct = EXCLUDED.target_pct,
    notes = EXCLUDED.notes;


-- ------------------------------------------------------------
-- 7. OVERRIDE KPI INTERNACIONAL POR SET
--
-- SET 01: 1,035 / 6,456 = 16.0316 %
-- SET 02: 1,035 / 6,456 = 16.0316 %
-- SET 03: 1,034 / 6,456 = 16.0161 %
-- SET 04: 1,034 / 6,456 = 16.0161 %
--
-- Total:
-- 4,138 / 25,824 = 16.0239 %
-- ------------------------------------------------------------

UPDATE ctl.synthetic_dataset_target
SET
    target_count = 1035,
    target_pct = 16.0316,
    notes = 'Set-specific international denial target.'
WHERE set_code IN (
    'SYNTH_SET_01',
    'SYNTH_SET_02'
)
AND metric_group = 'KPI'
AND metric_code = 'INTERNATIONAL_DECLINED';


UPDATE ctl.synthetic_dataset_target
SET
    target_count = 1034,
    target_pct = 16.0161,
    notes = 'Set-specific international denial target.'
WHERE set_code IN (
    'SYNTH_SET_03',
    'SYNTH_SET_04'
)
AND metric_group = 'KPI'
AND metric_code = 'INTERNATIONAL_DECLINED';


COMMIT;