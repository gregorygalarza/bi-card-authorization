# Reglas de negocio iniciales

1. Internacional: país emisor != país comercio.
2. Approved: authorization_status = APPROVED.
3. Declined: authorization_status = DECLINED.
4. DECLINED requiere decline_reason.
5. decline reason de fraude y fraud_flag son conceptos distintos.
6. Cada intento individual equivale a transaction_count = 1 en OLAP.
