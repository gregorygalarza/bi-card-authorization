# Shared connection definition

Create one Pentaho database connection with these values:

```text
Connection name: cards_oltp
Connection type: PostgreSQL
Access: Native (JDBC)

Host Name:     ${BI_DB_HOST}
Database Name: ${BI_OLTP_DB}
Port Number:   ${BI_DB_PORT}
User Name:     ${BI_DB_USER}
Password:      ${BI_DB_PASSWORD}
```

Equivalent JDBC URL:

```text
jdbc:postgresql://${BI_DB_HOST}:${BI_DB_PORT}/${BI_OLTP_DB}
```

JDBC driver class:

```text
org.postgresql.Driver
```

Do not hardcode the local password in `.ktr`, `.kjb`, `shared.xml`, or Markdown.
