BEGIN;

CREATE SCHEMA IF NOT EXISTS ctl;
CREATE SCHEMA IF NOT EXISTS stg;
CREATE SCHEMA IF NOT EXISTS oltp;

COMMENT ON SCHEMA ctl IS 'Control, auditoría y calidad de procesos ETL.';
COMMENT ON SCHEMA stg IS 'Área de staging para datos cercanos a las fuentes CSV.';
COMMENT ON SCHEMA oltp IS 'Modelo operacional normalizado del proceso de autorización de transacciones.';

COMMIT;
