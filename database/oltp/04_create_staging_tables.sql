BEGIN;

-- PASO 4 - STAGING FÍSICO (V2)
-- Ambos archivos transaccionales IBM tienen el mismo layout y alimentan
-- stg.ibm_transactions_raw. Cada archivo mantiene trazabilidad independiente.

CREATE TABLE IF NOT EXISTS stg.ibm_users_raw (
    stg_row_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    batch_id BIGINT NOT NULL,
    etl_file_id BIGINT NOT NULL,
    source_row_number BIGINT NOT NULL,
    source_file_name VARCHAR(500) NOT NULL,
    record_hash_sha256 CHAR(64),
    loaded_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    person TEXT,
    current_age TEXT,
    retirement_age TEXT,
    birth_year TEXT,
    birth_month TEXT,
    gender TEXT,
    address TEXT,
    apartment TEXT,
    city TEXT,
    state TEXT,
    zipcode TEXT,
    latitude TEXT,
    longitude TEXT,
    per_capita_income_zipcode TEXT,
    yearly_income_person TEXT,
    total_debt TEXT,
    fico_score TEXT,
    num_credit_cards TEXT,
    CONSTRAINT fk_stg_ibm_users_batch FOREIGN KEY (batch_id) REFERENCES ctl.etl_batch(batch_id),
    CONSTRAINT fk_stg_ibm_users_file FOREIGN KEY (etl_file_id) REFERENCES ctl.etl_file(etl_file_id),
    CONSTRAINT uq_stg_ibm_users_file_row UNIQUE (etl_file_id, source_row_number)
);

CREATE TABLE IF NOT EXISTS stg.ibm_cards_raw (
    stg_row_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    batch_id BIGINT NOT NULL,
    etl_file_id BIGINT NOT NULL,
    source_row_number BIGINT NOT NULL,
    source_file_name VARCHAR(500) NOT NULL,
    record_hash_sha256 CHAR(64),
    loaded_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    source_user_id TEXT,
    card_index TEXT,
    card_brand TEXT,
    card_type TEXT,
    card_number_raw TEXT,
    expires_raw TEXT,
    cvv_raw TEXT,
    has_chip_raw TEXT,
    cards_issued TEXT,
    credit_limit_raw TEXT,
    account_open_date_raw TEXT,
    pin_last_changed_year TEXT,
    card_on_dark_web_raw TEXT,
    CONSTRAINT fk_stg_ibm_cards_batch FOREIGN KEY (batch_id) REFERENCES ctl.etl_batch(batch_id),
    CONSTRAINT fk_stg_ibm_cards_file FOREIGN KEY (etl_file_id) REFERENCES ctl.etl_file(etl_file_id),
    CONSTRAINT uq_stg_ibm_cards_file_row UNIQUE (etl_file_id, source_row_number)
);

CREATE TABLE IF NOT EXISTS stg.ibm_transactions_raw (
    stg_row_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    batch_id BIGINT NOT NULL,
    etl_file_id BIGINT NOT NULL,
    source_row_number BIGINT NOT NULL,
    source_file_name VARCHAR(500) NOT NULL,
    record_hash_sha256 CHAR(64),
    loaded_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    source_user_id TEXT,
    card_index TEXT,
    transaction_year TEXT,
    transaction_month TEXT,
    transaction_day TEXT,
    transaction_time_raw TEXT,
    amount_raw TEXT,
    use_chip_raw TEXT,
    merchant_name_raw TEXT,
    merchant_city TEXT,
    merchant_state TEXT,
    merchant_zip_raw TEXT,
    mcc_raw TEXT,
    errors_raw TEXT,
    is_fraud_raw TEXT,
    CONSTRAINT fk_stg_ibm_transactions_batch FOREIGN KEY (batch_id) REFERENCES ctl.etl_batch(batch_id),
    CONSTRAINT fk_stg_ibm_transactions_file FOREIGN KEY (etl_file_id) REFERENCES ctl.etl_file(etl_file_id),
    CONSTRAINT uq_stg_ibm_transactions_file_row UNIQUE (etl_file_id, source_row_number)
);

COMMENT ON TABLE stg.ibm_transactions_raw IS
'Staging raw compartido por User0_credit_card_transactions.csv y credit_card_transactions-ibm_v2.csv.';

CREATE TABLE IF NOT EXISTS stg.fraud_transactions_raw (
    stg_row_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    batch_id BIGINT NOT NULL,
    etl_file_id BIGINT NOT NULL,
    source_row_number BIGINT NOT NULL,
    source_file_name VARCHAR(500) NOT NULL,
    record_hash_sha256 CHAR(64),
    loaded_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    source_index_raw TEXT,
    trans_date_trans_time_raw TEXT,
    cc_num_raw TEXT,
    merchant_raw TEXT,
    category_raw TEXT,
    amount_raw TEXT,
    first_name_raw TEXT,
    last_name_raw TEXT,
    gender_raw TEXT,
    street_raw TEXT,
    city_raw TEXT,
    state_raw TEXT,
    zip_raw TEXT,
    latitude_raw TEXT,
    longitude_raw TEXT,
    city_population_raw TEXT,
    job_raw TEXT,
    date_of_birth_raw TEXT,
    transaction_number_raw TEXT,
    unix_time_raw TEXT,
    merchant_latitude_raw TEXT,
    merchant_longitude_raw TEXT,
    is_fraud_raw TEXT,
    merchant_zipcode_raw TEXT,
    CONSTRAINT fk_stg_fraud_transactions_batch FOREIGN KEY (batch_id) REFERENCES ctl.etl_batch(batch_id),
    CONSTRAINT fk_stg_fraud_transactions_file FOREIGN KEY (etl_file_id) REFERENCES ctl.etl_file(etl_file_id),
    CONSTRAINT uq_stg_fraud_transactions_file_row UNIQUE (etl_file_id, source_row_number)
);

CREATE TABLE IF NOT EXISTS stg.ml_transactions_raw (
    stg_row_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    batch_id BIGINT NOT NULL,
    etl_file_id BIGINT NOT NULL,
    source_row_number BIGINT NOT NULL,
    source_file_name VARCHAR(500) NOT NULL,
    record_hash_sha256 CHAR(64),
    loaded_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    time_raw TEXT,
    v1_raw TEXT, v2_raw TEXT, v3_raw TEXT, v4_raw TEXT, v5_raw TEXT,
    v6_raw TEXT, v7_raw TEXT, v8_raw TEXT, v9_raw TEXT, v10_raw TEXT,
    v11_raw TEXT, v12_raw TEXT, v13_raw TEXT, v14_raw TEXT, v15_raw TEXT,
    v16_raw TEXT, v17_raw TEXT, v18_raw TEXT, v19_raw TEXT, v20_raw TEXT,
    v21_raw TEXT, v22_raw TEXT, v23_raw TEXT, v24_raw TEXT, v25_raw TEXT,
    v26_raw TEXT, v27_raw TEXT, v28_raw TEXT,
    amount_raw TEXT,
    class_raw TEXT,
    CONSTRAINT fk_stg_ml_transactions_batch FOREIGN KEY (batch_id) REFERENCES ctl.etl_batch(batch_id),
    CONSTRAINT fk_stg_ml_transactions_file FOREIGN KEY (etl_file_id) REFERENCES ctl.etl_file(etl_file_id),
    CONSTRAINT uq_stg_ml_transactions_file_row UNIQUE (etl_file_id, source_row_number)
);

CREATE INDEX IF NOT EXISTS ix_stg_ibm_users_batch ON stg.ibm_users_raw(batch_id);
CREATE INDEX IF NOT EXISTS ix_stg_ibm_cards_batch ON stg.ibm_cards_raw(batch_id);
CREATE INDEX IF NOT EXISTS ix_stg_ibm_cards_user_card ON stg.ibm_cards_raw(source_user_id, card_index);
CREATE INDEX IF NOT EXISTS ix_stg_ibm_transactions_batch ON stg.ibm_transactions_raw(batch_id);
CREATE INDEX IF NOT EXISTS ix_stg_ibm_transactions_file ON stg.ibm_transactions_raw(etl_file_id);
CREATE INDEX IF NOT EXISTS ix_stg_ibm_transactions_user_card ON stg.ibm_transactions_raw(source_user_id, card_index);
CREATE INDEX IF NOT EXISTS ix_stg_fraud_transactions_batch ON stg.fraud_transactions_raw(batch_id);
CREATE INDEX IF NOT EXISTS ix_stg_ml_transactions_batch ON stg.ml_transactions_raw(batch_id);

COMMIT;
