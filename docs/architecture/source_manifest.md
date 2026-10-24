# Manifiesto de fuentes — V2

## Núcleo IBM

| Archivo | Header | Rol | Tabla STAGING |
|---|---|---|---|
| `sd254_users.csv` | Users | Núcleo | `stg.ibm_users_raw` |
| `sd254_cards.csv` | Cards | Núcleo | `stg.ibm_cards_raw` |
| `User0_credit_card_transactions.csv` | IBM Transactions (15 columnas) | Núcleo | `stg.ibm_transactions_raw` |
| `credit_card_transactions-ibm_v2.csv` | IBM Transactions (15 columnas) | Núcleo | `stg.ibm_transactions_raw` |

## Verificación de los dos archivos IBM de transacciones

Ambos tienen exactamente este header:

```text
User,Card,Year,Month,Day,Time,Amount,Use Chip,Merchant Name,Merchant City,Merchant State,Zip,MCC,Errors?,Is Fraud?
```

Hashes SHA-256:

```text
User0_credit_card_transactions.csv
61C4ED49A98BF924C5DF0A740E1C415B91624C83821F8415BD8DB34C2D6A0D3C

credit_card_transactions-ibm_v2.csv
B01FA323C98522F8C710C7F7242581860C97C50183F1C5FA9E772E5C674A7F15
```

Tamaños:

```text
User0_credit_card_transactions.csv       1,899,258 bytes
credit_card_transactions-ibm_v2.csv  2,350,744,057 bytes
```

El archivo `User0` mostró 19,964 líneas incluyendo el encabezado.

Los hashes distintos prueban que no son archivos idénticos byte por byte.

## Política de carga

Ambos alimentan `stg.ibm_transactions_raw`.

Cada archivo se registra independientemente en `ctl.etl_file`. La procedencia de cada fila se preserva con:

- `etl_file_id`
- `source_file_name`
- `source_row_number`
- `batch_id`

No se deduplican automáticamente filas coincidentes entre archivos.
