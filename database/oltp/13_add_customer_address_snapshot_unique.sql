ALTER TABLE oltp.customer_address
ADD CONSTRAINT uq_customer_address_effective
UNIQUE (customer_id, valid_from);