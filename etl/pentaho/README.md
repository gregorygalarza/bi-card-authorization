# Pentaho PDI

Pentaho será responsable de:

```text
CSV -> STAGING
STAGING -> OLTP
OLTP -> OLAP
```

No se usará PowerShell para lógica ETL.

Se versionarán `.ktr` y `.kjb`.
Las rutas deberán parametrizarse; no se permitirán rutas absolutas personales.
