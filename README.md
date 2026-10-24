# BI Card Authorization

Proyecto académico de Inteligencia de Negocios orientado al análisis de
**transacciones internacionales denegadas**.

## Decisión arquitectónica oficial

La interfaz universal del proyecto es **Docker Compose**.

```text
Docker Compose -> infraestructura
SQL            -> definición de base de datos
Pentaho PDI    -> ETL
PostgreSQL     -> OLTP / OLAP
Power BI       -> explotación analítica
Git / GitHub   -> versionado
PowerShell 7   -> wrapper recomendado en Windows
Bash           -> wrapper alternativo
```

PowerShell **no contiene lógica ETL ni lógica de negocio**.

## Arquitectura objetivo

```text
CSV fuente
   |
   v
STAGING (cards_oltp.stg)
   |
   | limpieza / validación / enriquecimiento
   v
OLTP CORE (cards_oltp.oltp)
   |
   | Pentaho PDI
   v
DATA MART / OLAP (cards_dw)
   |
   v
Power BI
```

## Requisitos iniciales

Obligatorios:
- Git
- Docker Desktop + Docker Compose

Recomendado en Windows:
- PowerShell 7 (`pwsh`)

Fases posteriores:
- Pentaho Data Integration / Spoon
- Power BI Desktop

## Paso 1 - Clonar

```powershell
git clone <URL_DEL_REPOSITORIO>
cd bi-card-authorization
```

## Paso 2 - Crear configuración local

### Opción universal/manual

Copiar `.env.example` como `.env`.

### PowerShell 7

```powershell
Copy-Item .env.example .env
```

Editar `.env` y cambiar al menos:

```text
POSTGRES_PASSWORD=<password_local>
```

`.env` nunca debe subirse a Git.

## Paso 3 - Levantar PostgreSQL

### Comando oficial

```bash
docker compose up -d
```

### Wrapper PowerShell 7

```powershell
pwsh ./scripts/start.ps1
```

### Wrapper Bash

```bash
bash ./scripts/start.sh
```

## Paso 4 - Verificar

```bash
docker compose ps
```

El contenedor debe aparecer como `healthy`.

Probar PostgreSQL:

```bash
docker compose exec postgres psql -U bi_admin -d cards_oltp -c "SELECT version();"
```

## Comandos oficiales

```bash
docker compose up -d
docker compose ps
docker compose down
docker compose down -v
```

Los scripts `.ps1` y `.sh` solo simplifican estos comandos.

## Política de datos

Los CSV grandes se copian localmente a:

```text
data/raw/
```

y no se versionan.

Las muestras pequeñas de desarrollo pueden ir en:

```text
data/sample/
```

## Próximo hito

Crear en `cards_oltp`:

```text
ctl
stg
oltp
```

y las tablas iniciales de control ETL.
