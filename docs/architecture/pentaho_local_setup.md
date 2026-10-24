# Pentaho PDI local setup

## Purpose

Prepare Spoon/PDI so the ETL artifacts can be versioned while machine-specific values remain outside Git.

## 1. Confirm Java

From PowerShell:

```powershell
java -version
```

Record the output in your implementation notes if desired.

## 2. Start Spoon

On Windows, launch `Spoon.bat` from the Pentaho Data Integration installation directory.

The project does not require a Pentaho Repository. For this academic project, `.ktr` and `.kjb` files are stored directly in Git under:

```text
etl/pentaho/
```

## 3. Configure local Kettle variables

Pentaho's local properties file is normally under the current user's Kettle/PDI home directory.

Open Spoon and use the Kettle properties editor if available, or edit the local `kettle.properties`.

Copy the variables from:

```text
etl/pentaho/config/kettle.properties.example
```

Set:

```text
BI_PROJECT_DIR=C:/projects/bi-card-authorization
```

Use forward slashes in PDI paths for portability.

Set `BI_DB_PASSWORD` to the same PostgreSQL password used by the local `.env`.

Do not commit the local `kettle.properties`.

After editing the file, restart Spoon.

## 4. Create the PostgreSQL connection

Create a connection named:

```text
cards_oltp
```

Use:

```text
Type       PostgreSQL
Access     Native (JDBC)
Host       ${BI_DB_HOST}
Database   ${BI_OLTP_DB}
Port       ${BI_DB_PORT}
User       ${BI_DB_USER}
Password   ${BI_DB_PASSWORD}
```

Run **Test**.

Expected result:

```text
Connection to cards_oltp successful
```

## 5. JDBC troubleshooting

If Spoon reports that the PostgreSQL JDBC driver is missing, verify that a PostgreSQL JDBC `.jar` is present in the PDI `data-integration/lib` directory.

After adding or replacing a JDBC driver, restart Spoon.

## 6. Why no Pentaho Repository

This project already uses Git/GitHub for source control.

Keeping:

```text
.ktr
.kjb
.md
.sql
```

as ordinary files makes the project easier to reproduce on another machine and avoids adding Pentaho Server/Repository infrastructure that is unnecessary for the course project.

## Next transformation

After the connection test succeeds, create:

```text
etl/pentaho/transformations/stg/tr_load_ibm_users_to_stg.ktr
```

Its first version will implement:

```text
sd254_users.csv
    -> CSV Input
    -> source_row_number
    -> source_user_id = source_row_number - 1
    -> technical audit fields
    -> stg.ibm_users_raw
```

It will not yet load the OLTP. First we validate the CSV -> STG path end-to-end.
