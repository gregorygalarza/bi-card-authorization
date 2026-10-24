# Flujo STG → OLTP

```text
CSV
 ↓
STAGING RAW
 ↓
validación + limpieza + tipificación
 ↓
resolución de claves fuente
 ↓
normalización y enriquecimiento determinístico
 ↓
OLTP NORMALIZADO
```

Orden lógico de carga:

```text
1. catálogos
2. customer
3. customer_address
4. customer_financial_profile
5. card
6. merchant
7. merchant_location
8. merchant_category
9. card_transaction
10. error_catalog / transaction_error
```

Las reglas que impactan indicadores se mantienen versionadas, reproducibles y auditables por `batch_id`.
