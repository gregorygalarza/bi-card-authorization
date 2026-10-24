BEGIN;

CREATE INDEX IF NOT EXISTS ix_customer_source_system
    ON oltp.customer(source_system_id);

CREATE INDEX IF NOT EXISTS ix_customer_address_customer
    ON oltp.customer_address(customer_id);

CREATE INDEX IF NOT EXISTS ix_customer_address_country
    ON oltp.customer_address(country_code);

CREATE INDEX IF NOT EXISTS ix_customer_financial_profile_customer
    ON oltp.customer_financial_profile(customer_id);

CREATE INDEX IF NOT EXISTS ix_card_customer
    ON oltp.card(customer_id);

CREATE INDEX IF NOT EXISTS ix_card_source_system
    ON oltp.card(source_system_id);

CREATE INDEX IF NOT EXISTS ix_card_issuer_country
    ON oltp.card(issuer_country_code);

CREATE INDEX IF NOT EXISTS ix_merchant_source_system
    ON oltp.merchant(source_system_id);

CREATE INDEX IF NOT EXISTS ix_merchant_location_merchant
    ON oltp.merchant_location(merchant_id);

CREATE INDEX IF NOT EXISTS ix_merchant_location_country
    ON oltp.merchant_location(country_code);

CREATE INDEX IF NOT EXISTS ix_decline_reason_source_system
    ON oltp.decline_reason(source_system_id);

CREATE INDEX IF NOT EXISTS ix_transaction_datetime
    ON oltp.card_transaction(transaction_datetime);

CREATE INDEX IF NOT EXISTS ix_transaction_card_datetime
    ON oltp.card_transaction(card_id, transaction_datetime);

CREATE INDEX IF NOT EXISTS ix_transaction_merchant_location
    ON oltp.card_transaction(merchant_location_id);

CREATE INDEX IF NOT EXISTS ix_transaction_category
    ON oltp.card_transaction(category_id);

CREATE INDEX IF NOT EXISTS ix_transaction_auth_status_datetime
    ON oltp.card_transaction(authorization_status_id, transaction_datetime);

CREATE INDEX IF NOT EXISTS ix_transaction_decline_reason
    ON oltp.card_transaction(decline_reason_id);

CREATE INDEX IF NOT EXISTS ix_transaction_source_system
    ON oltp.card_transaction(source_system_id);

CREATE INDEX IF NOT EXISTS ix_transaction_fraud_true
    ON oltp.card_transaction(transaction_datetime)
    WHERE fraud_flag = TRUE;

CREATE INDEX IF NOT EXISTS ix_transaction_error_transaction
    ON oltp.transaction_error(transaction_id);

CREATE INDEX IF NOT EXISTS ix_transaction_error_error
    ON oltp.transaction_error(error_id);

COMMIT;
