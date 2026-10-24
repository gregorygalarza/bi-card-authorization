BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

ALTER TABLE stg.ibm_users_raw
    ADD COLUMN IF NOT EXISTS source_user_id TEXT;

COMMENT ON COLUMN stg.ibm_users_raw.source_user_id IS
'Identificador técnico IBM derivado del orden 0-based del registro de usuario.';

CREATE TABLE IF NOT EXISTS ctl.integration_parameter (
    parameter_code VARCHAR(80) PRIMARY KEY,
    parameter_value VARCHAR(250) NOT NULL,
    data_type VARCHAR(20) NOT NULL,
    description VARCHAR(500) NOT NULL,
    active_flag BOOLEAN NOT NULL DEFAULT TRUE,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ck_integration_parameter_type
        CHECK (data_type IN ('TEXT','INTEGER','NUMERIC','BOOLEAN'))
);

INSERT INTO ctl.integration_parameter
(parameter_code, parameter_value, data_type, description)
VALUES
('RULESET_VERSION','1','INTEGER','Versión de las reglas determinísticas STG -> OLTP.'),
('SOURCE_ROW_NUMBER_BASE','1','INTEGER','source_row_number inicia en 1 para la primera fila de datos, excluyendo el header.'),
('IBM_USER_ID_BASE','0','INTEGER','Los identificadores User del dataset IBM se interpretan como índices 0-based.'),
('IBM_DEFAULT_CUSTOMER_COUNTRY','US','TEXT','País por defecto para direcciones de clientes IBM cuando la fuente no contiene país explícito.'),
('IBM_DEFAULT_ISSUER_COUNTRY','US','TEXT','País emisor por defecto de tarjetas IBM para este caso de integración.'),
('FRAUD_DECLINE_PERCENT','65','INTEGER','Porcentaje determinístico de transacciones fraude que se deniegan por sospecha de fraude si no aplica una regla de mayor prioridad.'),
('INTERNATIONAL_DECLINE_PERCENT','12','INTEGER','Porcentaje determinístico de transacciones internacionales que se deniegan por restricción internacional si no aplica una regla de mayor prioridad.'),
('BASE_DECLINE_PERCENT','2','INTEGER','Porcentaje determinístico residual de denegaciones DO_NOT_HONOR.')
ON CONFLICT (parameter_code) DO UPDATE
SET parameter_value = EXCLUDED.parameter_value,
    data_type = EXCLUDED.data_type,
    description = EXCLUDED.description,
    active_flag = TRUE,
    updated_at = CURRENT_TIMESTAMP;

CREATE TABLE IF NOT EXISTS ctl.us_state_code (
    state_code VARCHAR(2) PRIMARY KEY,
    state_name VARCHAR(100) NOT NULL
);

INSERT INTO ctl.us_state_code (state_code, state_name) VALUES
('AL','Alabama'),('AK','Alaska'),('AZ','Arizona'),('AR','Arkansas'),('CA','California'),('CO','Colorado'),
('CT','Connecticut'),('DE','Delaware'),('FL','Florida'),('GA','Georgia'),('HI','Hawaii'),('ID','Idaho'),
('IL','Illinois'),('IN','Indiana'),('IA','Iowa'),('KS','Kansas'),('KY','Kentucky'),('LA','Louisiana'),
('ME','Maine'),('MD','Maryland'),('MA','Massachusetts'),('MI','Michigan'),('MN','Minnesota'),('MS','Mississippi'),
('MO','Missouri'),('MT','Montana'),('NE','Nebraska'),('NV','Nevada'),('NH','New Hampshire'),('NJ','New Jersey'),
('NM','New Mexico'),('NY','New York'),('NC','North Carolina'),('ND','North Dakota'),('OH','Ohio'),('OK','Oklahoma'),
('OR','Oregon'),('PA','Pennsylvania'),('RI','Rhode Island'),('SC','South Carolina'),('SD','South Dakota'),
('TN','Tennessee'),('TX','Texas'),('UT','Utah'),('VT','Vermont'),('VA','Virginia'),('WA','Washington'),
('WV','West Virginia'),('WI','Wisconsin'),('WY','Wyoming'),('DC','District of Columbia'),('PR','Puerto Rico'),
('VI','U.S. Virgin Islands'),('GU','Guam'),('AS','American Samoa'),('MP','Northern Mariana Islands'),
('AA','Armed Forces Americas'),('AE','Armed Forces Europe'),('AP','Armed Forces Pacific')
ON CONFLICT (state_code) DO UPDATE SET state_name = EXCLUDED.state_name;

CREATE TABLE IF NOT EXISTS ctl.merchant_country_bucket (
    bucket_from SMALLINT PRIMARY KEY,
    bucket_to SMALLINT NOT NULL,
    country_code CHAR(2) NOT NULL,
    description VARCHAR(250),
    CONSTRAINT fk_merchant_country_bucket_country
        FOREIGN KEY (country_code) REFERENCES oltp.country(country_code),
    CONSTRAINT ck_merchant_country_bucket_range
        CHECK (bucket_from BETWEEN 0 AND 99 AND bucket_to BETWEEN 0 AND 99 AND bucket_to >= bucket_from)
);

INSERT INTO ctl.merchant_country_bucket
(bucket_from, bucket_to, country_code, description) VALUES
(0,24,'CA','Canada'),
(25,44,'MX','Mexico'),
(45,59,'GB','United Kingdom'),
(60,69,'ES','Spain'),
(70,79,'FR','France'),
(80,87,'DE','Germany'),
(88,93,'JP','Japan'),
(94,99,'BR','Brazil')
ON CONFLICT (bucket_from) DO UPDATE
SET bucket_to = EXCLUDED.bucket_to,
    country_code = EXCLUDED.country_code,
    description = EXCLUDED.description;

CREATE TABLE IF NOT EXISTS ctl.source_error_mapping (
    error_mapping_id SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    source_system_code VARCHAR(30) NOT NULL,
    source_error_pattern VARCHAR(100) NOT NULL,
    priority SMALLINT NOT NULL,
    target_status_code VARCHAR(20) NOT NULL,
    target_decline_reason_code VARCHAR(40),
    response_code VARCHAR(30),
    active_flag BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT uq_source_error_mapping UNIQUE (source_system_code, source_error_pattern),
    CONSTRAINT fk_source_error_mapping_status
        FOREIGN KEY (target_status_code) REFERENCES oltp.authorization_status(status_code),
    CONSTRAINT ck_source_error_mapping_priority CHECK (priority > 0)
);

INSERT INTO ctl.source_error_mapping
(source_system_code, source_error_pattern, priority, target_status_code, target_decline_reason_code, response_code)
VALUES
('IBM_CORE','Technical Glitch',10,'ERROR',NULL,'TECHNICAL_ERROR'),
('IBM_CORE','Insufficient Balance',20,'DECLINED','INSUFFICIENT_FUNDS','INSUFFICIENT_FUNDS'),
('IBM_CORE','Bad Expiration',30,'DECLINED','EXPIRED_CARD','EXPIRED_CARD'),
('IBM_CORE','Bad Card Number',40,'DECLINED','INVALID_CARD','INVALID_CARD'),
('IBM_CORE','Bad PIN',50,'DECLINED','SECURITY_VIOLATION','BAD_PIN'),
('IBM_CORE','Bad CVV',60,'DECLINED','SECURITY_VIOLATION','BAD_CVV'),
('IBM_CORE','Bad Zipcode',70,'DECLINED','SECURITY_VIOLATION','BAD_ZIPCODE')
ON CONFLICT (source_system_code, source_error_pattern) DO UPDATE
SET priority = EXCLUDED.priority,
    target_status_code = EXCLUDED.target_status_code,
    target_decline_reason_code = EXCLUDED.target_decline_reason_code,
    response_code = EXCLUDED.response_code,
    active_flag = TRUE;

CREATE OR REPLACE FUNCTION ctl.fn_sha256_hex(p_value TEXT)
RETURNS TEXT
LANGUAGE SQL
IMMUTABLE
STRICT
AS $$
    SELECT encode(digest(p_value, 'sha256'), 'hex');
$$;

CREATE OR REPLACE FUNCTION ctl.fn_bucket_100(p_value TEXT)
RETURNS SMALLINT
LANGUAGE SQL
IMMUTABLE
STRICT
AS $$
    SELECT (((get_byte(digest(p_value, 'sha256'),0)::INTEGER * 256)
           + get_byte(digest(p_value, 'sha256'),1)::INTEGER) % 100)::SMALLINT;
$$;

COMMIT;
