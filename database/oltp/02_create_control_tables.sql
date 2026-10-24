BEGIN;

CREATE TABLE IF NOT EXISTS ctl.etl_batch (
    batch_id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    process_name       VARCHAR(150) NOT NULL,
    source_system      VARCHAR(100),
    start_ts           TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    end_ts             TIMESTAMPTZ,
    status             VARCHAR(20) NOT NULL DEFAULT 'RUNNING',
    rows_read          BIGINT NOT NULL DEFAULT 0,
    rows_loaded        BIGINT NOT NULL DEFAULT 0,
    rows_rejected      BIGINT NOT NULL DEFAULT 0,
    error_message      TEXT,
    created_by         VARCHAR(100) NOT NULL DEFAULT CURRENT_USER,
    CONSTRAINT ck_etl_batch_status
        CHECK (status IN ('RUNNING','SUCCESS','FAILED','WARNING'))
);

COMMENT ON TABLE ctl.etl_batch IS
'Una fila por ejecución lógica de un proceso ETL.';

CREATE TABLE IF NOT EXISTS ctl.etl_file (
    etl_file_id        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    batch_id           BIGINT NOT NULL,
    file_name          VARCHAR(500) NOT NULL,
    source_system      VARCHAR(100),
    file_path          VARCHAR(1000),
    file_size_bytes    BIGINT,
    file_hash_sha256   CHAR(64),
    rows_read          BIGINT NOT NULL DEFAULT 0,
    rows_loaded        BIGINT NOT NULL DEFAULT 0,
    rows_rejected      BIGINT NOT NULL DEFAULT 0,
    load_status        VARCHAR(20) NOT NULL DEFAULT 'PENDING',
    started_at         TIMESTAMPTZ,
    finished_at        TIMESTAMPTZ,
    error_message      TEXT,
    CONSTRAINT fk_etl_file_batch
        FOREIGN KEY (batch_id)
        REFERENCES ctl.etl_batch(batch_id),
    CONSTRAINT ck_etl_file_status
        CHECK (load_status IN ('PENDING','RUNNING','SUCCESS','FAILED','WARNING'))
);

COMMENT ON TABLE ctl.etl_file IS
'Control de archivos procesados dentro de un batch ETL.';

CREATE TABLE IF NOT EXISTS ctl.data_quality_issue (
    issue_id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    batch_id           BIGINT,
    etl_file_id        BIGINT,
    source_system      VARCHAR(100),
    entity_name        VARCHAR(150),
    source_record_key  VARCHAR(250),
    rule_code          VARCHAR(100) NOT NULL,
    severity           VARCHAR(20) NOT NULL,
    field_name         VARCHAR(150),
    field_value        TEXT,
    issue_description  TEXT NOT NULL,
    detected_at        TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    resolved_flag      BOOLEAN NOT NULL DEFAULT FALSE,
    resolved_at        TIMESTAMPTZ,
    resolution_note    TEXT,
    CONSTRAINT fk_dq_issue_batch
        FOREIGN KEY (batch_id)
        REFERENCES ctl.etl_batch(batch_id),
    CONSTRAINT fk_dq_issue_file
        FOREIGN KEY (etl_file_id)
        REFERENCES ctl.etl_file(etl_file_id),
    CONSTRAINT ck_dq_issue_severity
        CHECK (severity IN ('INFO','WARNING','ERROR','CRITICAL')),
    CONSTRAINT ck_dq_issue_resolution
        CHECK (
            (resolved_flag = FALSE AND resolved_at IS NULL)
            OR
            (resolved_flag = TRUE)
        )
);

COMMENT ON TABLE ctl.data_quality_issue IS
'Incidencias de calidad detectadas durante la carga o validación de datos.';

CREATE INDEX IF NOT EXISTS ix_etl_batch_status
    ON ctl.etl_batch(status);

CREATE INDEX IF NOT EXISTS ix_etl_batch_start_ts
    ON ctl.etl_batch(start_ts);

CREATE INDEX IF NOT EXISTS ix_etl_file_batch_id
    ON ctl.etl_file(batch_id);

CREATE INDEX IF NOT EXISTS ix_etl_file_status
    ON ctl.etl_file(load_status);

CREATE INDEX IF NOT EXISTS ix_dq_issue_batch_id
    ON ctl.data_quality_issue(batch_id);

CREATE INDEX IF NOT EXISTS ix_dq_issue_rule_code
    ON ctl.data_quality_issue(rule_code);

CREATE INDEX IF NOT EXISTS ix_dq_issue_severity
    ON ctl.data_quality_issue(severity);

COMMIT;
