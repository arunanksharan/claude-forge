# PostgreSQL — Master Setup & Integration Prompt

> **Copy this file into Claude Code. Replace `{{placeholders}}`. The model will set up Postgres (containerized or hosted), wire it to your app, create initial schema with conventions, and verify health end-to-end.**

---

## Context

You are setting up PostgreSQL for a project. This is the canonical setup matching the `claudeforge` discipline: latest stable Postgres, pgvector pre-installed, naming conventions enforced, sensible tuning, init scripts that create app users + DBs, language-specific drivers wired, and Alembic / Drizzle / Prisma migrations bootstrapped.

If something is ambiguous, **ask once, then proceed**.

## Project parameters

```
project_slug:       {{project-slug}}            # used in container names + db names
db_name:            {{db-name}}                 # primary application database
db_user:            {{db-user}}                 # app user (NOT postgres superuser)
postgres_version:   17                          # 18 is GA late 2026; 17 is current LTS
include_pgvector:   {{yes-or-no}}               # for embeddings / RAG
include_postgis:    {{yes-or-no}}               # for geo
include_timescale:  {{yes-or-no}}               # for time-series
hosting:            {{docker|managed|bare-metal}}
language:           {{python|node|go|java}}
orm:                {{sqlalchemy|drizzle|prisma|kysely|none}}
```

---

## Locked stack

| Concern | Pick | Why |
|---------|------|-----|
| Version | **Postgres 17** | Current major (18 lands late 2026; pin 17 unless you need 18 features) |
| Image | **`pgvector/pgvector:pg17`** if `include_pgvector=yes`, else **`postgres:17-alpine`** | pgvector image bundles the extension (no manual install) |
| Connection pooler | **PgBouncer** in transaction mode (production) | Max ~100 server conns; pooler handles 1000+ client conns |
| Backup | **`pg_dump`** for small DBs; **`pgBackRest`** or **WAL-G** for large + PITR | |
| Migrations | **Alembic** (Python), **Prisma Migrate**, **Drizzle Kit**, or **Atlas** | |
| Driver | **asyncpg** (Python), **postgres** / **pg** (Node), **pgx** (Go) | Async-first |
| TLS | **mTLS for cross-VPC**, plain TLS for client-to-server | |
| Monitoring | `pg_stat_statements` + `postgres_exporter` for Prometheus | |

## Rejected

| Option | Why not |
|--------|---------|
| `postgres:latest` tag | Unreliable across rebuilds — pin major version |
| `psycopg2` (sync) | Use `asyncpg` for async, or `psycopg3` with async support if you need both |
| Default `template1` without conventions | You'll regret unnamed indexes/constraints in migrations |
| Single shared `postgres` superuser for app | Use separate app user with least privilege |
| Sequential ID PK on hot tables | Use UUIDv7 — sortable, no enumeration, no race |
| MD5 `password_encryption` | Use `scram-sha-256` (default in 14+) |

---

## Directory layout (generate this)

```
{{project-slug}}/infra/postgres/
├── docker-compose.dev.yml               # standalone dev compose
├── postgresql.conf                       # custom config (optional, for prod tuning)
├── pg_hba.conf                           # auth rules (mostly default in dev)
├── init-scripts/
│   ├── 00-extensions.sh                  # pgvector, pg_stat_statements, etc.
│   ├── 01-create-app-user.sh             # creates {{db-user}} with limited perms
│   ├── 02-create-app-db.sh               # creates {{db-name}}
│   └── 99-verify.sh                      # verifies setup
├── backup.sh                             # nightly pg_dump
└── README.md                             # operator notes
```

---

## Key files

### `infra/postgres/docker-compose.dev.yml`

```yaml
services:
  postgres:
    image: pgvector/pgvector:pg17           # or postgres:17-alpine
    container_name: {{project-slug}}-postgres
    restart: unless-stopped
    ports:
      - '127.0.0.1:5432:5432'                # bind to localhost only
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./init-scripts:/docker-entrypoint-initdb.d:ro
      - ./postgresql.conf:/etc/postgresql/postgresql.conf:ro
    environment:
      POSTGRES_USER: postgres                # superuser (dev only)
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:?POSTGRES_PASSWORD required}
      POSTGRES_DB: postgres
      PGDATA: /var/lib/postgresql/data/pgdata
      APP_DB_NAME: {{db-name}}
      APP_DB_USER: {{db-user}}
      APP_DB_PASSWORD: ${APP_DB_PASSWORD:?APP_DB_PASSWORD required}
    command:
      - "postgres"
      - "-c" 
      - "config_file=/etc/postgresql/postgresql.conf"
      - "-c"
      - "shared_preload_libraries=pg_stat_statements"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 10s
    deploy:
      resources:
        limits: { cpus: '2', memory: 2G }
        reservations: { cpus: '0.25', memory: 256M }

volumes:
  postgres_data:
```

### `infra/postgres/postgresql.conf`

Tuned for dev (8GB host RAM target). For production tuning see `03-operations.md`:

```
# Connections
max_connections = 100
listen_addresses = '*'

# Memory (assumes ~2GB available)
shared_buffers = 512MB                          # 25% of allocated RAM
effective_cache_size = 1500MB                   # 75% of allocated RAM
work_mem = 8MB                                  # per-sort, per-hash; tune carefully
maintenance_work_mem = 128MB                    # vacuum, create index

# WAL
wal_level = replica                             # required for replication / logical
max_wal_size = 2GB
min_wal_size = 256MB
checkpoint_timeout = 15min
checkpoint_completion_target = 0.9

# Query planner
random_page_cost = 1.1                          # SSD; for HDD use 4
effective_io_concurrency = 200                  # SSD; for HDD use 2
default_statistics_target = 100

# Logging
log_destination = 'stderr'
logging_collector = off
log_min_duration_statement = 1000               # log queries > 1s
log_line_prefix = '%t [%p]: user=%u,db=%d,app=%a,client=%h '
log_lock_waits = on
log_temp_files = 0
log_autovacuum_min_duration = 0

# Stats
track_io_timing = on
track_activities = on
track_counts = on

# Auto-vacuum (defaults are OK; tune per workload)
autovacuum = on

# Extensions
shared_preload_libraries = 'pg_stat_statements'
pg_stat_statements.max = 10000
pg_stat_statements.track = all

# Auth
password_encryption = scram-sha-256

# Locale
timezone = 'UTC'
datestyle = 'iso, mdy'
```

### `infra/postgres/init-scripts/00-extensions.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    -- always-on
    CREATE EXTENSION IF NOT EXISTS "pgcrypto";              -- gen_random_uuid()
    CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";    -- query telemetry
    CREATE EXTENSION IF NOT EXISTS "pg_trgm";               -- trigram fuzzy match

    -- if pgvector image
    CREATE EXTENSION IF NOT EXISTS "vector";

    -- propagate to template1 so new DBs get them automatically
    \c template1
    CREATE EXTENSION IF NOT EXISTS "pgcrypto";
    CREATE EXTENSION IF NOT EXISTS "pg_trgm";
    CREATE EXTENSION IF NOT EXISTS "vector";
EOSQL

echo "✓ extensions enabled"
```

### `infra/postgres/init-scripts/01-create-app-user.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

# create the app user with ONLY what it needs (no superuser, no createdb)
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres <<-EOSQL
    DO \$\$
    BEGIN
        IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${APP_DB_USER}') THEN
            CREATE USER ${APP_DB_USER} WITH PASSWORD '${APP_DB_PASSWORD}';
        END IF;
    END
    \$\$;
EOSQL

echo "✓ app user '${APP_DB_USER}' created"
```

### `infra/postgres/init-scripts/02-create-app-db.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres <<-EOSQL
    SELECT 'CREATE DATABASE ${APP_DB_NAME} OWNER ${APP_DB_USER}'
    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${APP_DB_NAME}')\gexec

    GRANT ALL PRIVILEGES ON DATABASE ${APP_DB_NAME} TO ${APP_DB_USER};

    -- enable extensions in the app DB explicitly
    \c ${APP_DB_NAME}
    CREATE EXTENSION IF NOT EXISTS "pgcrypto";
    CREATE EXTENSION IF NOT EXISTS "pg_trgm";
    CREATE EXTENSION IF NOT EXISTS "vector";

    -- give the app user create privileges in their DB
    GRANT CREATE ON SCHEMA public TO ${APP_DB_USER};
EOSQL

echo "✓ app database '${APP_DB_NAME}' created"
```

### `infra/postgres/backup.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/var/backups/postgres}"
RETENTION_DAYS="${RETENTION_DAYS:-14}"
DB_NAME="${DB_NAME:?DB_NAME required}"

mkdir -p "$BACKUP_DIR"
TS=$(date -u +%Y%m%dT%H%M%SZ)
FILE="$BACKUP_DIR/${DB_NAME}-${TS}.dump"

# custom format (compressed, parallel-restorable)
docker exec {{project-slug}}-postgres pg_dump \
    -U postgres \
    -d "$DB_NAME" \
    -F c -Z 6 \
    > "$FILE"

# prune old
find "$BACKUP_DIR" -type f -name "${DB_NAME}-*.dump" -mtime +${RETENTION_DAYS} -delete

# optional: ship to S3 / B2
# aws s3 cp "$FILE" "s3://your-backups/${DB_NAME}/" || echo "warn: s3 upload failed"

echo "✓ backed up ${DB_NAME} → ${FILE} ($(du -h "$FILE" | cut -f1))"
```

---

## Generation steps

1. **Confirm parameters** with the user (project_slug, db_name, db_user, version, extensions).
2. **Create directory tree** as shown.
3. **Write `docker-compose.dev.yml`, `postgresql.conf`, `pg_hba.conf`, init scripts.**
4. **Generate `.env.example`** with `POSTGRES_PASSWORD` + `APP_DB_PASSWORD` placeholders.
5. **Bring up Postgres**: `docker compose -f infra/postgres/docker-compose.dev.yml up -d`.
6. **Verify**: `docker exec {{project-slug}}-postgres psql -U {{db-user}} -d {{db-name}} -c "SELECT version();"`.
7. **Set the application's connection string**:
   ```
   DATABASE_URL=postgresql+asyncpg://{{db-user}}:****@localhost:5432/{{db-name}}    # SQLAlchemy async
   DATABASE_URL=postgresql://{{db-user}}:****@localhost:5432/{{db-name}}            # Drizzle / Prisma / Kysely
   ```
8. **Initialize migrations** in the application based on chosen ORM:
   - Alembic: `uv run alembic init alembic` then customize per `02-sqlalchemy-and-alembic.md`
   - Prisma: `pnpm prisma init` + `pnpm prisma migrate dev --name init`
   - Drizzle: `pnpm drizzle-kit generate` + `pnpm drizzle-kit migrate`
9. **Schedule the backup script** via cron / systemd timer (production only).
10. **Hand off** with: connection strings, backup schedule, where to view slow queries (`pg_stat_statements`).

---

## Companion deep-dives

- [`README.md`](./README.md) — overview + decision summary
- [`01-schema-design.md`](./01-schema-design.md) — naming conventions, types, modeling patterns
- [`02-queries-and-indexes.md`](./02-queries-and-indexes.md) — query patterns, index strategies, EXPLAIN
- [`03-operations.md`](./03-operations.md) — backups, monitoring, scaling, PgBouncer, replication, WAL archiving
- [`04-language-clients.md`](./04-language-clients.md) — Python (asyncpg, psycopg3), Node (postgres, pg), Go (pgx) — connection pools, prepared statements, listen/notify
- [`05-pgvector-and-rag.md`](./05-pgvector-and-rag.md) — vector embeddings in Postgres for RAG without a separate vector DB

For end-to-end use with framework prompts: see [`backend/fastapi/02-sqlalchemy-and-alembic.md`](../../backend/fastapi/02-sqlalchemy-and-alembic.md), [`backend/nestjs/02-prisma-and-migrations.md`](../../backend/nestjs/02-prisma-and-migrations.md), [`backend/nodejs-express/02-drizzle-and-migrations.md`](../../backend/nodejs-express/02-drizzle-and-migrations.md).
