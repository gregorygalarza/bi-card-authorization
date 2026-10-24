# Arquitectura

## Principio rector

La portabilidad del proyecto depende de:

- Docker Compose
- SQL
- Pentaho `.ktr` / `.kjb`
- configuración parametrizada
- Git

PowerShell 7 y Bash son **wrappers auxiliares**, no componentes centrales.

## Flujo

```text
CSV
 |
 v
STAGING
 |
 v
OLTP
 |
 | Pentaho
 v
OLAP / Data Mart
 |
 v
Power BI
```

## Base OLTP

La base `cards_oltp` contendrá:

```text
stg -> datos cercanos al origen
oltp -> modelo operacional normalizado
ctl -> auditoría, batches y calidad
```
