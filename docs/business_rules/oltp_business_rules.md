# Reglas de negocio OLTP implementadas

## RN01 — Internacional

```text
issuer_country_code != merchant_country_code
```

La regla se deriva en `oltp.vw_transaction_enriched`.

## RN02 — Approved

```text
authorization_status.status_code = 'APPROVED'
```

## RN03 — Declined

```text
authorization_status.status_code = 'DECLINED'
```

## RN04 — Motivo de denegación

Una transacción `DECLINED` requiere `decline_reason_id`.

Una transacción no `DECLINED` no debe tener `decline_reason_id`.

Se implementa mediante `trg_validate_decline_reason`.

## RN05 — Fraude

`decline_reason.reason_category = 'FRAUD'` no significa necesariamente lo mismo que:

```text
card_transaction.fraud_flag = TRUE
```

Ambos se conservan como conceptos distintos.

## RN06 — Errores

Una transacción puede tener cero, uno o múltiples errores.

Detalle:

```text
transaction_error
```

Indicador rápido:

```text
card_transaction.error_flag
```

El trigger de errores mantiene dicho flag sincronizado.
