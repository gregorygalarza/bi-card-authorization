# Mapeo Fuente → STAGING → OLTP — V2

## IBM Transactions

Fuentes:

```text
User0_credit_card_transactions.csv
credit_card_transactions-ibm_v2.csv
```

Ambas alimentan `stg.ibm_transactions_raw`.

| Campo CSV | STAGING | Tratamiento | Destino OLTP |
|---|---|---|---|
| User | `source_user_id` | Resolver cliente/tarjeta | indirecto vía `card_id` |
| Card | `card_index` | Resolver `(User, Card)` | `card_transaction.card_id` |
| Year | `transaction_year` | Validar entero | timestamp |
| Month | `transaction_month` | Validar 1–12 | timestamp |
| Day | `transaction_day` | Validar fecha | timestamp |
| Time | `transaction_time_raw` | Parsear HH:mm | `card_transaction.transaction_datetime` |
| Amount | `amount_raw` | Quitar `$`, convertir NUMERIC | `card_transaction.amount` |
| Use Chip | `use_chip_raw` | Normalizar | `card_transaction.entry_mode` |
| Merchant Name | `merchant_name_raw` | Tratar como identificador fuente del comercio | `merchant.source_merchant_key` |
| Merchant City | `merchant_city` | Normalizar | `merchant_location.city` |
| Merchant State | `merchant_state` | Normalizar | `merchant_location.state` |
| Zip | `merchant_zip_raw` | Limpiar formato | `merchant_location.postal_code` |
| MCC | `mcc_raw` | Normalizar | `merchant_category.category_code` |
| Errors? | `errors_raw` | Parsear errores | `error_catalog`, `transaction_error` |
| Is Fraud? | `is_fraud_raw` | Yes/No → BOOLEAN | `card_transaction.fraud_flag` |

Identidad de fila fuente:

```text
etl_file_id + source_row_number
```

No se usa `SELECT DISTINCT` entre los dos archivos.

El `source_transaction_key` del OLTP se generará de forma determinística conservando procedencia.

## IBM Users y Cards

Se mantiene el mapeo del Paso 4 original. La corrección V2 afecta principalmente la política de los dos archivos IBM de transacciones.
