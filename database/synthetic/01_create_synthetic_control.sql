BEGIN;

-- ============================================================
-- SYNTHETIC DATA CONTROL MODEL
-- Proyecto BI - Denegación de Transacciones Internacionales
--
-- Objetivo:
--   Administrar perfiles estadísticos y datasets sintéticos
--   determinísticos utilizados para pruebas y demostraciones.
--
-- Importante:
--   Estas tablas NO contienen datos transaccionales sintéticos.
--   Solo contienen configuración, targets y estado de ejecución.
-- ============================================================


-- ------------------------------------------------------------
-- 1. PERFIL ESTADÍSTICO
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS ctl.synthetic_profile (
    profile_code            VARCHAR(50) PRIMARY KEY,
    profile_name            VARCHAR(150) NOT NULL,

    baseline_source_code    VARCHAR(30) NOT NULL,
    target_transactions     BIGINT NOT NULL,

    description             TEXT,

    active_flag             BOOLEAN NOT NULL DEFAULT TRUE,

    created_at              TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_synthetic_profile_baseline_source
        FOREIGN KEY (baseline_source_code)
        REFERENCES oltp.source_system(source_code),

    CONSTRAINT ck_synthetic_profile_target_transactions
        CHECK (target_transactions > 0)
);


-- ------------------------------------------------------------
-- 2. MÉTRICAS DEL PERFIL
--
-- target_count:
--   cantidad exacta deseada cuando corresponda.
--
-- target_pct:
--   porcentaje de referencia del baseline.
--
-- Algunos perfiles como COUNTRY_INTL o MCC se expresan
-- principalmente mediante porcentaje.
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS ctl.synthetic_profile_metric (
    profile_code            VARCHAR(50) NOT NULL,
    metric_group            VARCHAR(50) NOT NULL,
    metric_code             VARCHAR(100) NOT NULL,

    target_count            BIGINT,
    target_pct              NUMERIC(12,6),

    notes                   VARCHAR(500),

    created_at              TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_synthetic_profile_metric
        PRIMARY KEY (
            profile_code,
            metric_group,
            metric_code
        ),

    CONSTRAINT fk_synthetic_profile_metric_profile
        FOREIGN KEY (profile_code)
        REFERENCES ctl.synthetic_profile(profile_code)
        ON DELETE CASCADE,

    CONSTRAINT ck_synthetic_profile_metric_count
        CHECK (
            target_count IS NULL
            OR target_count >= 0
        ),

    CONSTRAINT ck_synthetic_profile_metric_pct
        CHECK (
            target_pct IS NULL
            OR target_pct BETWEEN 0 AND 100
        ),

    CONSTRAINT ck_synthetic_profile_metric_value
        CHECK (
            target_count IS NOT NULL
            OR target_pct IS NOT NULL
        )
);


-- ------------------------------------------------------------
-- 3. PERFIL DE MONTOS
--
-- Se almacena por estado de autorización.
-- Los percentiles provienen de una muestra determinística
-- del baseline IBM_CORE.
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS ctl.synthetic_amount_profile (
    profile_code            VARCHAR(50) NOT NULL,
    status_code             VARCHAR(20) NOT NULL,

    avg_abs_amount          NUMERIC(18,2) NOT NULL,

    p25                     NUMERIC(18,2) NOT NULL,
    p50                     NUMERIC(18,2) NOT NULL,
    p75                     NUMERIC(18,2) NOT NULL,
    p90                     NUMERIC(18,2) NOT NULL,
    p95                     NUMERIC(18,2) NOT NULL,
    p99                     NUMERIC(18,2) NOT NULL,

    created_at              TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_synthetic_amount_profile
        PRIMARY KEY (
            profile_code,
            status_code
        ),

    CONSTRAINT fk_synthetic_amount_profile_profile
        FOREIGN KEY (profile_code)
        REFERENCES ctl.synthetic_profile(profile_code)
        ON DELETE CASCADE,

    CONSTRAINT fk_synthetic_amount_profile_status
        FOREIGN KEY (status_code)
        REFERENCES oltp.authorization_status(status_code),

    CONSTRAINT ck_synthetic_amount_profile_values
        CHECK (
            avg_abs_amount > 0
            AND p25 > 0
            AND p25 <= p50
            AND p50 <= p75
            AND p75 <= p90
            AND p90 <= p95
            AND p95 <= p99
        )
);


-- ------------------------------------------------------------
-- 4. DATASETS SINTÉTICOS
--
-- Cada dataset representa un set reproducible e independiente.
--
-- Estados OLTP:
--   REGISTERED
--   PREPARED
--   LOADING
--   LOADED
--   VALIDATED
--   FAILED
--
-- Estados OLAP:
--   PENDING
--   LOADING
--   LOADED
--   VALIDATED
--   FAILED
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS ctl.synthetic_dataset (
    set_code                VARCHAR(30) PRIMARY KEY,

    profile_code            VARCHAR(50) NOT NULL,
    source_system_code      VARCHAR(30) NOT NULL,

    seed                    INTEGER NOT NULL,
    key_prefix              VARCHAR(40) NOT NULL,

    purpose                 VARCHAR(150) NOT NULL,

    target_customers        INTEGER NOT NULL,
    target_cards            INTEGER NOT NULL,
    target_merchants        INTEGER NOT NULL,
    target_locations        INTEGER NOT NULL,
    target_transactions     BIGINT NOT NULL,

    transaction_date_from   DATE NOT NULL,
    transaction_date_to     DATE NOT NULL,

    oltp_status             VARCHAR(20) NOT NULL DEFAULT 'REGISTERED',
    olap_status             VARCHAR(20) NOT NULL DEFAULT 'PENDING',

    oltp_last_batch_id      BIGINT,
    olap_last_batch_id      BIGINT,

    oltp_loaded_at          TIMESTAMPTZ,
    oltp_validated_at       TIMESTAMPTZ,

    olap_loaded_at          TIMESTAMPTZ,
    olap_validated_at       TIMESTAMPTZ,

    notes                   TEXT,

    created_at              TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_synthetic_dataset_profile
        FOREIGN KEY (profile_code)
        REFERENCES ctl.synthetic_profile(profile_code),

    CONSTRAINT fk_synthetic_dataset_source
        FOREIGN KEY (source_system_code)
        REFERENCES oltp.source_system(source_code),

    CONSTRAINT fk_synthetic_dataset_oltp_batch
        FOREIGN KEY (oltp_last_batch_id)
        REFERENCES ctl.etl_batch(batch_id),

    CONSTRAINT fk_synthetic_dataset_olap_batch
        FOREIGN KEY (olap_last_batch_id)
        REFERENCES ctl.etl_batch(batch_id),

    CONSTRAINT uq_synthetic_dataset_seed
        UNIQUE (seed),

    CONSTRAINT uq_synthetic_dataset_prefix
        UNIQUE (key_prefix),

    CONSTRAINT ck_synthetic_dataset_targets
        CHECK (
            target_customers > 0
            AND target_cards > 0
            AND target_merchants > 0
            AND target_locations > 0
            AND target_transactions > 0
        ),

    CONSTRAINT ck_synthetic_dataset_dates
        CHECK (
            transaction_date_to >= transaction_date_from
        ),

    CONSTRAINT ck_synthetic_dataset_oltp_status
        CHECK (
            oltp_status IN (
                'REGISTERED',
                'PREPARED',
                'LOADING',
                'LOADED',
                'VALIDATED',
                'FAILED'
            )
        ),

    CONSTRAINT ck_synthetic_dataset_olap_status
        CHECK (
            olap_status IN (
                'PENDING',
                'LOADING',
                'LOADED',
                'VALIDATED',
                'FAILED'
            )
        )
);


-- ------------------------------------------------------------
-- 5. TARGETS EXACTOS POR DATASET
--
-- Copia materializada del perfil para cada set.
--
-- Esto permite:
--   - auditar cada set de manera independiente;
--   - realizar pequeños overrides;
--   - mantener SET_03 y SET_04 congelados para la demo.
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS ctl.synthetic_dataset_target (
    set_code                VARCHAR(30) NOT NULL,
    metric_group            VARCHAR(50) NOT NULL,
    metric_code             VARCHAR(100) NOT NULL,

    target_count            BIGINT,
    target_pct              NUMERIC(12,6),

    notes                   VARCHAR(500),

    created_at              TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_synthetic_dataset_target
        PRIMARY KEY (
            set_code,
            metric_group,
            metric_code
        ),

    CONSTRAINT fk_synthetic_dataset_target_dataset
        FOREIGN KEY (set_code)
        REFERENCES ctl.synthetic_dataset(set_code)
        ON DELETE CASCADE,

    CONSTRAINT ck_synthetic_dataset_target_count
        CHECK (
            target_count IS NULL
            OR target_count >= 0
        ),

    CONSTRAINT ck_synthetic_dataset_target_pct
        CHECK (
            target_pct IS NULL
            OR target_pct BETWEEN 0 AND 100
        ),

    CONSTRAINT ck_synthetic_dataset_target_value
        CHECK (
            target_count IS NOT NULL
            OR target_pct IS NOT NULL
        )
);


-- ------------------------------------------------------------
-- 6. ÍNDICES DE APOYO
-- ------------------------------------------------------------

CREATE INDEX IF NOT EXISTS ix_synthetic_dataset_profile
    ON ctl.synthetic_dataset(profile_code);

CREATE INDEX IF NOT EXISTS ix_synthetic_dataset_oltp_status
    ON ctl.synthetic_dataset(oltp_status);

CREATE INDEX IF NOT EXISTS ix_synthetic_dataset_olap_status
    ON ctl.synthetic_dataset(olap_status);

CREATE INDEX IF NOT EXISTS ix_synthetic_dataset_target_group
    ON ctl.synthetic_dataset_target(
        set_code,
        metric_group
    );


COMMENT ON TABLE ctl.synthetic_profile IS
'Perfil estadístico congelado utilizado para generar datasets sintéticos determinísticos.';

COMMENT ON TABLE ctl.synthetic_dataset IS
'Registro y estado de cada dataset sintético utilizado en pruebas y demostraciones académicas.';

COMMENT ON TABLE ctl.synthetic_dataset_target IS
'Targets estadísticos exactos o porcentuales correspondientes a cada dataset sintético.';

COMMIT;