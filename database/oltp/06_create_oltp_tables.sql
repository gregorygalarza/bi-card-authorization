BEGIN;

-- ============================================================
-- PASO 5 - MODELO FÍSICO OLTP
-- PostgreSQL 18+
-- ============================================================

-- ------------------------------------------------------------
-- 1. CATÁLOGOS / MAESTROS
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS oltp.source_system (
    source_system_id      SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    source_code           VARCHAR(30)  NOT NULL,
    source_name           VARCHAR(100) NOT NULL,
    description           VARCHAR(500),
    active_flag           BOOLEAN      NOT NULL DEFAULT TRUE,
    CONSTRAINT uq_source_system_code UNIQUE (source_code)
);

CREATE TABLE IF NOT EXISTS oltp.country (
    country_code          CHAR(2)      PRIMARY KEY,
    country_code_3        CHAR(3),
    country_name          VARCHAR(100) NOT NULL,
    active_flag           BOOLEAN      NOT NULL DEFAULT TRUE,
    CONSTRAINT uq_country_code_3 UNIQUE (country_code_3),
    CONSTRAINT ck_country_code_upper
        CHECK (country_code = UPPER(country_code)),
    CONSTRAINT ck_country_code_3_upper
        CHECK (country_code_3 IS NULL OR country_code_3 = UPPER(country_code_3))
);

CREATE TABLE IF NOT EXISTS oltp.authorization_status (
    authorization_status_id SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    status_code             VARCHAR(20)  NOT NULL,
    status_name             VARCHAR(50)  NOT NULL,
    description             VARCHAR(250),
    active_flag             BOOLEAN      NOT NULL DEFAULT TRUE,
    CONSTRAINT uq_authorization_status_code UNIQUE (status_code)
);

CREATE TABLE IF NOT EXISTS oltp.merchant_category (
    category_id             INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    category_scheme         VARCHAR(30)  NOT NULL DEFAULT 'MCC',
    category_code           VARCHAR(30)  NOT NULL,
    category_name           VARCHAR(150),
    description             VARCHAR(250),
    active_flag             BOOLEAN      NOT NULL DEFAULT TRUE,
    CONSTRAINT uq_merchant_category UNIQUE (category_scheme, category_code)
);

CREATE TABLE IF NOT EXISTS oltp.error_catalog (
    error_id                INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    error_code              VARCHAR(80)  NOT NULL,
    error_description       VARCHAR(250) NOT NULL,
    active_flag             BOOLEAN      NOT NULL DEFAULT TRUE,
    CONSTRAINT uq_error_catalog_code UNIQUE (error_code)
);

CREATE TABLE IF NOT EXISTS oltp.decline_reason (
    decline_reason_id       INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    reason_code             VARCHAR(40)  NOT NULL,
    reason_name             VARCHAR(120) NOT NULL,
    reason_description      VARCHAR(300),
    reason_category         VARCHAR(50)  NOT NULL,
    source_system_id        SMALLINT,
    active_flag             BOOLEAN      NOT NULL DEFAULT TRUE,

    CONSTRAINT fk_decline_reason_source_system
        FOREIGN KEY (source_system_id)
        REFERENCES oltp.source_system(source_system_id),

    CONSTRAINT uq_decline_reason
        UNIQUE NULLS NOT DISTINCT (source_system_id, reason_code)
);

-- ------------------------------------------------------------
-- 2. CLIENTE
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS oltp.customer (
    customer_id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    source_system_id        SMALLINT      NOT NULL,
    source_customer_key     VARCHAR(100)  NOT NULL,
    first_name              VARCHAR(100),
    last_name               VARCHAR(100),
    full_name               VARCHAR(200),
    gender                  VARCHAR(20),
    birth_year              SMALLINT,
    birth_month             SMALLINT,
    retirement_age          SMALLINT,
    created_at              TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at              TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_customer_source_system
        FOREIGN KEY (source_system_id)
        REFERENCES oltp.source_system(source_system_id),

    CONSTRAINT uq_customer_source
        UNIQUE (source_system_id, source_customer_key),

    CONSTRAINT ck_customer_birth_month
        CHECK (birth_month IS NULL OR birth_month BETWEEN 1 AND 12),

    CONSTRAINT ck_customer_retirement_age
        CHECK (retirement_age IS NULL OR retirement_age BETWEEN 0 AND 120)
);

CREATE TABLE IF NOT EXISTS oltp.customer_address (
    address_id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id             BIGINT       NOT NULL,
    country_code            CHAR(2)      NOT NULL,
    street                  VARCHAR(250),
    apartment               VARCHAR(50),
    city                    VARCHAR(100),
    state                   VARCHAR(100),
    postal_code             VARCHAR(30),
    latitude                NUMERIC(9,6),
    longitude               NUMERIC(9,6),
    valid_from              DATE,
    valid_to                DATE,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_customer_address_customer
        FOREIGN KEY (customer_id)
        REFERENCES oltp.customer(customer_id)
        ON DELETE CASCADE,

    CONSTRAINT fk_customer_address_country
        FOREIGN KEY (country_code)
        REFERENCES oltp.country(country_code),

    CONSTRAINT ck_customer_address_latitude
        CHECK (latitude IS NULL OR latitude BETWEEN -90 AND 90),

    CONSTRAINT ck_customer_address_longitude
        CHECK (longitude IS NULL OR longitude BETWEEN -180 AND 180),

    CONSTRAINT ck_customer_address_dates
        CHECK (valid_to IS NULL OR valid_from IS NULL OR valid_to >= valid_from)
);

CREATE TABLE IF NOT EXISTS oltp.customer_financial_profile (
    profile_id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id             BIGINT         NOT NULL,
    yearly_income           NUMERIC(18,2),
    total_debt              NUMERIC(18,2),
    fico_score              SMALLINT,
    reported_num_cards      SMALLINT,
    effective_date          DATE           NOT NULL,
    end_date                DATE,
    created_at              TIMESTAMPTZ    NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_customer_financial_profile_customer
        FOREIGN KEY (customer_id)
        REFERENCES oltp.customer(customer_id)
        ON DELETE CASCADE,

    CONSTRAINT ck_financial_profile_income
        CHECK (yearly_income IS NULL OR yearly_income >= 0),

    CONSTRAINT ck_financial_profile_debt
        CHECK (total_debt IS NULL OR total_debt >= 0),

    CONSTRAINT ck_financial_profile_fico
        CHECK (fico_score IS NULL OR fico_score BETWEEN 300 AND 850),

    CONSTRAINT ck_financial_profile_num_cards
        CHECK (reported_num_cards IS NULL OR reported_num_cards >= 0),

    CONSTRAINT ck_financial_profile_dates
        CHECK (end_date IS NULL OR end_date >= effective_date),

    CONSTRAINT uq_financial_profile_effective
        UNIQUE (customer_id, effective_date)
);

-- ------------------------------------------------------------
-- 3. TARJETA
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS oltp.card (
    card_id                  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id              BIGINT         NOT NULL,
    source_system_id         SMALLINT       NOT NULL,
    issuer_country_code      CHAR(2)        NOT NULL,
    source_card_key          VARCHAR(150)   NOT NULL,
    card_number_token        VARCHAR(128),
    card_brand               VARCHAR(30),
    card_type                VARCHAR(30),
    expiration_month         SMALLINT,
    expiration_year          SMALLINT,
    has_chip                 BOOLEAN,
    cards_issued             SMALLINT,
    credit_limit             NUMERIC(18,2),
    account_open_date        DATE,
    pin_last_changed_year    SMALLINT,
    dark_web_flag            BOOLEAN        NOT NULL DEFAULT FALSE,
    created_at               TIMESTAMPTZ    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at               TIMESTAMPTZ    NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_card_customer
        FOREIGN KEY (customer_id)
        REFERENCES oltp.customer(customer_id),

    CONSTRAINT fk_card_source_system
        FOREIGN KEY (source_system_id)
        REFERENCES oltp.source_system(source_system_id),

    CONSTRAINT fk_card_issuer_country
        FOREIGN KEY (issuer_country_code)
        REFERENCES oltp.country(country_code),

    CONSTRAINT uq_card_source
        UNIQUE (source_system_id, source_card_key),

    CONSTRAINT uq_card_number_token
        UNIQUE (card_number_token),

    CONSTRAINT ck_card_expiration_month
        CHECK (expiration_month IS NULL OR expiration_month BETWEEN 1 AND 12),

    CONSTRAINT ck_card_cards_issued
        CHECK (cards_issued IS NULL OR cards_issued > 0),

    CONSTRAINT ck_card_credit_limit
        CHECK (credit_limit IS NULL OR credit_limit >= 0)
);

-- ------------------------------------------------------------
-- 4. COMERCIO Y UBICACIÓN
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS oltp.merchant (
    merchant_id                 BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    source_system_id            SMALLINT      NOT NULL,
    source_merchant_key         VARCHAR(150)  NOT NULL,
    merchant_source_identifier  VARCHAR(250),
    active_flag                 BOOLEAN       NOT NULL DEFAULT TRUE,
    created_at                  TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                  TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_merchant_source_system
        FOREIGN KEY (source_system_id)
        REFERENCES oltp.source_system(source_system_id),

    CONSTRAINT uq_merchant_source
        UNIQUE (source_system_id, source_merchant_key)
);

CREATE TABLE IF NOT EXISTS oltp.merchant_location (
    location_id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    merchant_id              BIGINT        NOT NULL,
    source_location_key      VARCHAR(250)  NOT NULL,
    country_code             CHAR(2)       NOT NULL,
    city                     VARCHAR(100),
    region_code              VARCHAR(100),
    postal_code              VARCHAR(30),
    latitude                 NUMERIC(9,6),
    longitude                NUMERIC(9,6),
    active_flag              BOOLEAN       NOT NULL DEFAULT TRUE,
    created_at               TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_merchant_location_merchant
        FOREIGN KEY (merchant_id)
        REFERENCES oltp.merchant(merchant_id)
        ON DELETE CASCADE,

    CONSTRAINT fk_merchant_location_country
        FOREIGN KEY (country_code)
        REFERENCES oltp.country(country_code),

    CONSTRAINT uq_merchant_location_source
        UNIQUE (merchant_id, source_location_key),

    CONSTRAINT ck_merchant_location_region_code
    CHECK (
        region_code IS NULL
        OR region_code ~ '^[A-Z]{2}$'
    ),

    CONSTRAINT ck_merchant_location_latitude
        CHECK (latitude IS NULL OR latitude BETWEEN -90 AND 90),

    CONSTRAINT ck_merchant_location_longitude
        CHECK (longitude IS NULL OR longitude BETWEEN -180 AND 180)
);

-- ------------------------------------------------------------
-- 5. TRANSACCIÓN
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS oltp.card_transaction (
    transaction_id                  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    source_system_id                SMALLINT       NOT NULL,
    source_transaction_key          VARCHAR(150)   NOT NULL,
    card_id                         BIGINT         NOT NULL,
    merchant_location_id            BIGINT         NOT NULL,
    category_id                     INTEGER,
    authorization_status_id         SMALLINT       NOT NULL,
    decline_reason_id               INTEGER,
    transaction_datetime            TIMESTAMPTZ    NOT NULL,
    amount                          NUMERIC(18,2)   NOT NULL,
    entry_mode                      VARCHAR(50),
    authorization_response_code     VARCHAR(30),
    error_flag                      BOOLEAN        NOT NULL DEFAULT FALSE,
    fraud_flag                      BOOLEAN        NOT NULL DEFAULT FALSE,
    created_at                      TIMESTAMPTZ    NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_transaction_source_system
        FOREIGN KEY (source_system_id)
        REFERENCES oltp.source_system(source_system_id),

    CONSTRAINT fk_transaction_card
        FOREIGN KEY (card_id)
        REFERENCES oltp.card(card_id),

    CONSTRAINT fk_transaction_merchant_location
        FOREIGN KEY (merchant_location_id)
        REFERENCES oltp.merchant_location(location_id),

    CONSTRAINT fk_transaction_category
        FOREIGN KEY (category_id)
        REFERENCES oltp.merchant_category(category_id),

    CONSTRAINT fk_transaction_authorization_status
        FOREIGN KEY (authorization_status_id)
        REFERENCES oltp.authorization_status(authorization_status_id),

    CONSTRAINT fk_transaction_decline_reason
        FOREIGN KEY (decline_reason_id)
        REFERENCES oltp.decline_reason(decline_reason_id),

    CONSTRAINT uq_transaction_source
        UNIQUE (source_system_id, source_transaction_key),

    CONSTRAINT ck_transaction_amount_nonzero
        CHECK (amount <> 0)
);

CREATE TABLE IF NOT EXISTS oltp.transaction_error (
    transaction_id          BIGINT       NOT NULL,
    error_id                INTEGER      NOT NULL,
    error_detail            VARCHAR(500),

    CONSTRAINT pk_transaction_error
        PRIMARY KEY (transaction_id, error_id),

    CONSTRAINT fk_transaction_error_transaction
        FOREIGN KEY (transaction_id)
        REFERENCES oltp.card_transaction(transaction_id)
        ON DELETE CASCADE,

    CONSTRAINT fk_transaction_error_error
        FOREIGN KEY (error_id)
        REFERENCES oltp.error_catalog(error_id)
);

COMMIT;
