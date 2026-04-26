# PostgreSQL — claudeforge guide

> Schema design, indexing, ops, common patterns. The default OLTP database for everything.

## Why Postgres

For new projects, **default to Postgres**. Reasons:

- Strong consistency, mature MVCC
- JSON columns when you need them, relational tables when you don't
- Full-text search built in (no Elasticsearch needed for most use cases)
- PostGIS for geo
- Logical replication, partitioning, row-level security
- Excellent ecosystem (pgvector for embeddings, TimescaleDB for time-series)
- Free and open-source

Skip Postgres only if:

- You specifically need a document model with embedded sub-docs that don't normalize cleanly → **MongoDB** (see `../mongodb/`)
- You need extreme write throughput on time-series → **TimescaleDB** (a Postgres extension) or ClickHouse
- You need vector search at huge scale (>100M vectors) → **Qdrant** as a sidecar (see `../qdrant/`)

## Versions

Use **Postgres 16** for new projects. 17 is fine if your hosting supports it. Avoid <14.

## Hosting

| Option | When |
|--------|------|
| **Self-hosted on a VPS** | Small projects, full control, lowest cost |
| **Neon** | Serverless, branching, scales to zero. Great for staging/preview. |
| **Supabase** | Postgres + auth + realtime + storage as a managed bundle |
| **AWS RDS / Aurora** | When already on AWS |
| **DigitalOcean Managed Postgres / Hetzner** | Boring, reliable, fairly priced |
| **Crunchy Bridge / Tembo** | Postgres-specialist managed hosts |

For dev/preview environments: **Neon** (branching is incredible — `git checkout` for your DB).
For production: managed if you can; self-hosted if you have the ops capacity.

## Schema design conventions

### Naming

| Convention | Example |
|-----------|---------|
| `snake_case` for table and column names | `created_at`, not `createdAt` |
| Plural table names | `users`, `orders` |
| Singular column names | `email`, not `emails` |
| `id` as primary key (UUID) | not `user_id` |
| Foreign keys: `<table>_id` | `user_id` references `users(id)` |
| Indexes: `<table>_<column>_idx` | `orders_user_id_idx` |

ORMs handle the case mapping automatically (Drizzle has `casing: 'snake_case'`, Prisma uses `@@map` and `@map`).

### IDs: UUID v7

For new tables: **UUID v7** as the primary key. Sortable like an int (so they index well), no enumeration, safe to expose in URLs.

```sql
CREATE EXTENSION IF NOT EXISTS pg_uuidv7;    -- if available

CREATE TABLE users (
  id uuid PRIMARY KEY DEFAULT uuidv7(),       -- or app-side generation
  email text NOT NULL UNIQUE,
  ...
);
```

If `pg_uuidv7` isn't available, generate in app code (most ORMs make this easy).

For legacy compatibility / external joins to int-keyed systems, `bigint` autoincrement is fine. Don't use `int` (max 2.1B is too small for hot tables).

### Timestamps

Always `timestamp with time zone` (Postgres stores in UTC, returns in client tz).

```sql
created_at timestamptz NOT NULL DEFAULT now(),
updated_at timestamptz NOT NULL DEFAULT now(),
deleted_at timestamptz
```

`updated_at` doesn't auto-update — set it in your ORM (Drizzle's `$onUpdate`, Prisma's `@updatedAt`) or via a trigger:

```sql
CREATE OR REPLACE FUNCTION set_updated_at() RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER users_updated_at BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
```

### NOT NULL by default

Every column should be `NOT NULL` unless there's a real reason. `NULL` is messy in queries (`WHERE x = NULL` doesn't work, `WHERE x != 'foo'` excludes nulls), and represents "we don't know" — usually you do know.

For unknown values, prefer empty string, 0, an explicit `'unknown'` enum value, or split into a separate table.

### ENUMs

Two patterns:

```sql
-- Postgres ENUM type
CREATE TYPE order_status AS ENUM ('pending', 'paid', 'shipped', 'cancelled');
CREATE TABLE orders (
  status order_status NOT NULL DEFAULT 'pending'
);
```

vs.

```sql
-- string + check constraint
status text NOT NULL CHECK (status IN ('pending', 'paid', 'shipped', 'cancelled'))
```

ENUM is more compact and faster to compare. But adding a value requires a migration (`ALTER TYPE ... ADD VALUE ...`). For values that change occasionally, ENUM. For values that change frequently, string + check (or a separate lookup table).

### Money

Never `float` or `double`. Always:

```sql
total_cents bigint NOT NULL    -- store as integer cents
-- or
amount numeric(18,2) NOT NULL  -- exact decimal
```

Cents are simpler in code and avoid currency-conversion bugs. Use `numeric` only if your business does fractional cents (e.g. financial calculations).

### JSON columns

```sql
metadata jsonb NOT NULL DEFAULT '{}'
```

`jsonb` (binary) is faster than `json` (text) for queries. Always index the specific paths you query:

```sql
CREATE INDEX users_metadata_plan_idx ON users ((metadata->>'plan'));
-- or GIN for full document search
CREATE INDEX users_metadata_idx ON users USING gin (metadata jsonb_path_ops);
```

Use jsonb for: settings, flexible attributes, third-party API responses you cache. **Don't** use it for things you'll join on or aggregate over heavily — those should be real columns.

## Indexes

### When to add an index

- Foreign keys → almost always (FK lookups + cascades)
- Columns in `WHERE`, `ORDER BY`, `JOIN ON` → add when the query's slow
- Composite `(a, b)` for `WHERE a = ? AND b = ?` (column order matters)
- Unique constraints → automatically indexed
- Partial: `CREATE INDEX ... WHERE deleted_at IS NULL` for soft-delete-aware indexes

### When NOT to add an index

- Tables under ~1000 rows — sequential scan is faster
- Columns that are written constantly but rarely queried (every index slows writes)
- Low-cardinality columns (e.g. `is_active`) — unless combined with another in a partial index

### Inspect

```sql
EXPLAIN ANALYZE SELECT * FROM orders WHERE user_id = '...' AND status = 'paid';
```

Look for `Index Scan` (good) vs `Seq Scan` (bad on big tables). `Bitmap Index Scan` is fine.

### Concurrent index creation (production)

Adding an index locks the table by default — bad in production:

```sql
CREATE INDEX CONCURRENTLY orders_user_id_status_idx ON orders (user_id, status);
```

`CONCURRENTLY` doesn't lock writers but takes longer + can fail. Always use it on big tables in prod.

If creation fails, the index is left in an `INVALID` state — drop and retry:

```sql
SELECT indexname FROM pg_indexes WHERE indisvalid = false;
DROP INDEX CONCURRENTLY orders_user_id_status_idx;
```

## Common queries

### Pagination — cursor (preferred)

```sql
-- first page
SELECT * FROM orders WHERE user_id = ? ORDER BY id LIMIT 50;

-- next page (cursor = last id of previous page)
SELECT * FROM orders WHERE user_id = ? AND id > ? ORDER BY id LIMIT 50;
```

Stable across inserts/deletes, fast.

### Pagination — offset (small finite lists only)

```sql
SELECT * FROM orders ORDER BY created_at DESC LIMIT 50 OFFSET 100;
SELECT count(*) FROM orders;     -- total
```

OFFSET gets slow at high values (the DB has to scan and discard).

### Upsert

```sql
INSERT INTO sessions (id, user_id, last_seen_at)
VALUES ($1, $2, now())
ON CONFLICT (id) DO UPDATE SET last_seen_at = EXCLUDED.last_seen_at;
```

### Soft delete (skeptical opinion)

```sql
deleted_at timestamptz       -- NULL = active

-- queries always filter
SELECT * FROM users WHERE deleted_at IS NULL;
```

Add a partial index for the live-set queries:

```sql
CREATE INDEX users_active_email_idx ON users (email) WHERE deleted_at IS NULL;
```

I lean against soft delete (FK constraints, "user shows up twice", reporting headaches). Use only when the business genuinely needs to recover deleted rows.

### Full-text search

```sql
-- column for search
ALTER TABLE articles ADD COLUMN search_tsv tsvector
  GENERATED ALWAYS AS (
    setweight(to_tsvector('english', coalesce(title, '')), 'A') ||
    setweight(to_tsvector('english', coalesce(body, '')), 'B')
  ) STORED;

CREATE INDEX articles_search_idx ON articles USING gin (search_tsv);

-- query
SELECT id, title, ts_rank(search_tsv, query) AS rank
FROM articles, to_tsquery('english', $1) query
WHERE search_tsv @@ query
ORDER BY rank DESC
LIMIT 20;
```

For most cases, this beats setting up Elasticsearch. For ranked search across millions of docs with faceting, consider a real search service.

## Operations

### Connection pooling

Postgres maxes out around **300-500 connections per server**. With many app instances (each opening 10-20 conns), you blow that.

Use **PgBouncer** in transaction mode in front:

```
[app1, app2, app3] → PgBouncer (1000 client conns → 50 server conns) → Postgres
```

PgBouncer transaction mode breaks prepared statements. If using async drivers (asyncpg, postgres-js), set:

- asyncpg: `prepared_statement_cache_size=0` in connection URL
- postgres-js: `prepare: false` in the client options
- Prisma: `?pgbouncer=true` in URL

### Backups

```bash
# nightly logical backup
pg_dump -U postgres -d {{db-name}} -F c -f /var/backups/{{db-name}}-$(date +%F).dump

# restore
pg_restore -U postgres -d {{db-name}}_restored /var/backups/{{db-name}}-2026-04-26.dump
```

For larger DBs, switch to **physical backups + WAL archiving** (PgBackRest, Barman). Or use a managed host that does this for you.

**Test restoring from backup at least monthly.** A backup that's never been restored is hope, not a backup.

### Vacuum

Postgres MVCC keeps old row versions until VACUUM cleans them up. Default autovacuum is fine for most workloads — but tune for big tables:

```sql
ALTER TABLE orders SET (
  autovacuum_vacuum_scale_factor = 0.05,         -- vacuum after 5% dead rows
  autovacuum_analyze_scale_factor = 0.02,
  autovacuum_vacuum_cost_limit = 1000
);
```

If autovacuum can't keep up, you'll see bloat in `pg_stat_all_tables`. Run a manual `VACUUM (VERBOSE, ANALYZE) tablename;` and tune autovacuum thresholds.

### Monitoring

Track these:

- Connection count (`pg_stat_activity`)
- Long-running queries (`pg_stat_activity` where state = 'active' and `query_start` < now() - interval)
- Cache hit ratio (`pg_stat_database` — should be >99%)
- Replication lag (if using replicas)
- Disk usage per table (`pg_total_relation_size`)
- Slow queries (enable `pg_stat_statements` extension)

Use **Postgres exporter** for Prometheus (`postgres-exporter` or `pgbouncer-exporter`).

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| `SELECT *` everywhere | Specify columns; saves bandwidth + lets the planner use covering indexes |
| N+1 queries | Use `JOIN` or `selectinload` (SA) / `with` (Drizzle) / `include` (Prisma) |
| `WHERE column = $1 OR $1 IS NULL` | Forces seq scan. Build the query dynamically. |
| `ORDER BY random()` | Slow on big tables. Use `TABLESAMPLE` or random seek. |
| `LIMIT 1` without `ORDER BY` | Non-deterministic — could return any row |
| Implicit type cast | `WHERE id = '1'` on integer column triggers seq scan in some cases — use `WHERE id = 1` |
| Missing FK indexes | Adding a FK doesn't auto-create an index — add one yourself |
| Timestamps without timezone | Use `timestamptz` always. `timestamp` is a footgun. |
| Storing booleans as int 0/1 | Use `boolean` |
| `text` with no length limit + huge values | Application-side validation; or use `varchar(N)` if there's a hard limit |
| `array_agg` returning `{NULL}` | Use `array_agg(x) FILTER (WHERE x IS NOT NULL)` |
| `count(*)` slow on big tables | Use `pg_class.reltuples` for an estimate; or maintain a counter table |
| Long transactions blocking VACUUM | Keep transactions short; investigate `pg_stat_activity` for long ones |
| `SELECT FOR UPDATE` deadlocks | Lock rows in a consistent order; use `SKIP LOCKED` for queue-style consumers |

## Useful extensions

| Extension | Use |
|-----------|-----|
| `pg_stat_statements` | Slow query inspection |
| `pgcrypto` | UUIDs, hashing, GenRandomBytes |
| `uuid-ossp` (legacy) | UUIDs (use pgcrypto/`gen_random_uuid()` in newer versions) |
| `pg_trgm` | Trigram matching for `LIKE '%foo%'` queries |
| `unaccent` | Diacritic-insensitive search |
| `pgvector` | Embedding/vector similarity (HNSW, IVFFlat) |
| `postgis` | Geo |
| `hypopg` | Hypothetical indexes (test if an index would be used before creating) |
| `timescaledb` | Time-series compression and continuous aggregates |
