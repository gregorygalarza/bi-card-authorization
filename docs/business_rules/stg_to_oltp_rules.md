# Reglas STG → OLTP y enriquecimiento

La integración es determinística e idempotente: una misma entrada, con la misma versión de reglas, produce el mismo resultado. No se usa `RANDOM()` para atributos que afecten KPI.

## Identidades

- `source_user_id = source_row_number - 1` para `sd254_users.csv`.
- `source_customer_key = 'IBM_USER:' + source_user_id`.
- `source_card_key = 'IBM_CARD:' + source_user_id + ':' + card_index`.
- `source_transaction_key = file_hash_sha256 + ':' + source_row_number`.
- `card_number_token = SHA256(PAN normalizado)`; el CVV no pasa al OLTP.

## Países

Para IBM, cuando la fuente no contiene país explícito:

- cliente: `US`;
- emisor de tarjeta: `US`.

Si `Merchant State` coincide con un código estadounidense reconocido, `merchant_location.country_code = US`. En otro caso, el país se obtiene de forma determinística con `ctl.fn_bucket_100(...)` y `ctl.merchant_country_bucket`.

La internacionalidad se deriva como:

```text
issuer_country_code <> merchant_country_code
```

## Resultado de autorización — prioridad

1. Importe negativo → `REVERSED`.
2. Error técnico explícito → `ERROR`.
3. Error de negocio explícito → `DECLINED` + motivo mapeado.
4. Importe positivo superior a `credit_limit` → `DECLINED / CREDIT_LIMIT_EXCEEDED`.
5. `fraud_flag=TRUE` y bucket dentro de `FRAUD_DECLINE_PERCENT` → `DECLINED / SUSPECTED_FRAUD`.
6. Transacción internacional y bucket dentro de `INTERNATIONAL_DECLINE_PERCENT` → `DECLINED / INTERNATIONAL_NOT_ALLOWED`.
7. Bucket residual dentro de `BASE_DECLINE_PERCENT` → `DECLINED / DO_NOT_HONOR`.
8. En cualquier otro caso → `APPROVED`.

`fraud_flag` y motivo de denegación por fraude se mantienen como conceptos distintos.

## Errores

`Errors?` puede contener cero, uno o varios valores. Se separan en `error_catalog` y `transaction_error`. Los patrones reconocidos se mapean mediante `ctl.source_error_mapping`; los no reconocidos se conservan y se registran como incidencia de calidad para revisión.
