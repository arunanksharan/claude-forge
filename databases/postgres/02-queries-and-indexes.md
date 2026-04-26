# PostgreSQL Queries & Indexes

> Reading EXPLAIN, choosing index types, common query patterns, performance tuning. The skill that separates "Postgres works" from "Postgres flies."

## EXPLAIN — read it, always

```sql
EXPLAIN (ANALYZE, BUFFERS) SELECT ... ;
```

| Output piece | Meaning |
|--------------|---------|
| `Seq Scan` | Sequential scan — fine on small tables, bad on large |
| `Index Scan` | Used an index — usually good |
| `Bitmap Heap Scan` + `Bitmap Index Scan` | Index used to find a set, then heap fetched — fine |
| `Index Only Scan` | All needed columns in the index — fastest |
| `Nested Loop` / `Hash Join` / `Merge Join` | Join algorithm chosen |
| `cost=A..B` | Planner's estimate |
| `actual time=X..Y rows=N loops=L` | Real execution stats |
| `Buffers: shared hit=X read=Y` | Cache hit/miss — high read = disk I/O |
| `Rows Removed by Filter: N` | Filter applied after scan — sometimes a missed index opportunity |

Look for:
- **Seq Scan on a big table** → add an index
- **Big estimate vs actual mismatch** → run `ANALYZE` (stats stale)
- **Sort spilling to disk** → increase `work_mem`
- **High `Buffers: read`** → cold cache; consider warming or more RAM

## Index types

| Type | When |
|------|------|
| **B-tree** (default) | Equality + range on most data types — 90% of indexes |
| **Hash** | Equality only; rarely better than B-tree, mostly avoid |
| **GIN** | Contains queries on arrays / JSONB / full-text — `@>`, `?`, `@@` |
| **GiST** | Geometric, range types, ltree, fuzzy text |
| **BRIN** | Massive append-only tables (events) where data is naturally sorted |
| **HNSW / IVFFlat** (pgvector) | Vector similarity |

```sql
-- B-tree (implicit)
CREATE INDEX orders_user_id_idx ON orders (user_id);
CREATE INDEX orders_created_at_idx ON orders (created_at DESC);

-- Composite (column order matters)
CREATE INDEX orders_user_status_created_idx ON orders (user_id, status, created_at DESC);

-- Partial (only matching rows; smaller, faster)
CREATE INDEX orders_pending_idx ON orders (created_at DESC) WHERE status = 'pending';
CREATE INDEX users_active_email_uq ON users (email) WHERE deleted_at IS NULL;

-- Expression
CREATE INDEX users_email_lower_idx ON users (lower(email));    -- for case-insensitive search

-- GIN on JSONB
CREATE INDEX events_payload_gin_idx ON events USING gin (payload jsonb_path_ops);

-- GIN for trigram fuzzy
CREATE EXTENSION pg_trgm;
CREATE INDEX users_name_trgm_idx ON users USING gin (name gin_trgm_ops);
```

## Composite index — column order rules

Order columns by:
1. **Equality first** (filtered with `=`)
2. **Range last** (`<`, `>`, `BETWEEN`)
3. **Sort matches the trailing columns** (so `ORDER BY` uses the index)

```sql
-- query: WHERE user_id = ? AND status = 'paid' ORDER BY created_at DESC
CREATE INDEX orders_user_status_created_idx ON orders (user_id, status, created_at DESC);
```

A query like `WHERE status = 'paid'` (without user_id) does NOT use this index — leading column missing.

## Common query patterns

### Cursor pagination (preferred)

```sql
-- first page
SELECT id, ... FROM orders
WHERE user_id = $1
ORDER BY id ASC
LIMIT 50;

-- next page (cursor = last id of previous page)
SELECT id, ... FROM orders
WHERE user_id = $1 AND id > $2
ORDER BY id ASC
LIMIT 50;
```

Stable across inserts/deletes. Fast (uses the index seek). No `OFFSET` slowness.

For descending order:

```sql
SELECT ... FROM orders
WHERE user_id = $1 AND id < $2
ORDER BY id DESC
LIMIT 50;
```

### Offset pagination (only when total + page-jump matters)

```sql
SELECT ... FROM orders
ORDER BY created_at DESC
LIMIT 50 OFFSET 100;

-- separate count
SELECT count(*) FROM orders;     -- slow on big tables
```

OFFSET gets quadratically slow as you go deeper. Use only for admin tables ≤ 10K rows.

### Upsert

```sql
INSERT INTO sessions (id, user_id, last_seen_at)
VALUES ($1, $2, now())
ON CONFLICT (id) DO UPDATE
SET last_seen_at = EXCLUDED.last_seen_at,
    last_seen_count = sessions.last_seen_count + 1
RETURNING *;
```

`ON CONFLICT DO NOTHING` for idempotent inserts.
`EXCLUDED.col` refers to the proposed value.

### Distinct + latest per group

```sql
-- "for each user, give me their latest order"
SELECT DISTINCT ON (user_id) user_id, id, created_at, status
FROM orders
ORDER BY user_id, created_at DESC;
```

`DISTINCT ON` is Postgres-specific — much faster than the equivalent self-join.

Index for this: `(user_id, created_at DESC)`.

### Window functions

```sql
-- rank orders per user by amount
SELECT id, user_id, total_cents,
       row_number() OVER (PARTITION BY user_id ORDER BY total_cents DESC) AS rank
FROM orders;

-- running total
SELECT id, occurred_at, amount_cents,
       sum(amount_cents) OVER (ORDER BY occurred_at ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
       AS running_total
FROM transactions;
```

Window functions are powerful + readable but can be expensive. Profile.

### Recursive CTE (tree traversal)

```sql
WITH RECURSIVE descendants AS (
  SELECT id, parent_id, name FROM categories WHERE id = $1
  UNION ALL
  SELECT c.id, c.parent_id, c.name FROM categories c
  JOIN descendants d ON c.parent_id = d.id
)
SELECT * FROM descendants;
```

For deep trees, consider `ltree` (faster).

### Bulk insert

```sql
INSERT INTO orders (id, user_id, total_cents)
SELECT * FROM unnest($1::uuid[], $2::uuid[], $3::bigint[])
RETURNING id;
```

Faster than N single inserts. Or `COPY` for true bulk:

```bash
psql -c "\COPY orders FROM 'orders.csv' WITH CSV HEADER"
```

`COPY` is 10-100× faster than INSERT for big datasets.

### Bulk update from another table

```sql
UPDATE products p
SET price_cents = u.new_price
FROM (VALUES
  ('prod_a', 1000),
  ('prod_b', 2000),
  ('prod_c', 1500)
) AS u(sku, new_price)
WHERE p.sku = u.sku;
```

### Full-text search (built-in, often better than reaching for Elastic)

```sql
-- generated column with weighted tsvector
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

Beats Elasticsearch for ~95% of "search docs by text" use cases. Reach for ES only at very large scale or with rich faceting needs.

### Trigram fuzzy match

```sql
CREATE EXTENSION pg_trgm;
CREATE INDEX users_email_trgm_idx ON users USING gin (email gin_trgm_ops);

SELECT id, email, similarity(email, $1) AS sim
FROM users
WHERE email % $1                     -- threshold default 0.3
ORDER BY sim DESC LIMIT 10;
```

Great for "search-as-you-type" with typos.

## Transactions

```sql
BEGIN;
  UPDATE accounts SET balance = balance - 100 WHERE id = $1;
  UPDATE accounts SET balance = balance + 100 WHERE id = $2;
COMMIT;
```

Inside a transaction:
- Reads see a consistent snapshot (Read Committed, default)
- Other sessions don't see your writes until commit
- Failure rolls back everything

### Isolation levels

| Level | Use case |
|-------|----------|
| `READ UNCOMMITTED` | Postgres treats as READ COMMITTED |
| `READ COMMITTED` (default) | Most queries — see committed snapshot at each statement |
| `REPEATABLE READ` | Long reports needing consistency across statements |
| `SERIALIZABLE` | Highest isolation; will retry on conflict |

```sql
BEGIN ISOLATION LEVEL SERIALIZABLE;
  ...
COMMIT;
```

Use SERIALIZABLE when you need true ACID semantics for multi-row operations (e.g. inventory + order create). Be ready to handle `40001 serialization_failure` — retry the transaction.

### Locking

```sql
SELECT * FROM orders WHERE id = $1 FOR UPDATE;       -- exclusive lock until commit
SELECT * FROM orders WHERE id = $1 FOR SHARE;        -- shared lock
SELECT * FROM orders WHERE id = $1 FOR UPDATE NOWAIT; -- error if locked
SELECT * FROM orders WHERE id = $1 FOR UPDATE SKIP LOCKED; -- skip locked rows (queue pattern)
```

`SKIP LOCKED` is the right pattern for queue-style consumers — multiple workers each grabbing different rows without blocking.

### Advisory locks (cross-session coordination without rows)

```sql
-- exclusive lock on a "key" — auto-released at session end
SELECT pg_advisory_lock(hashtext('migration:run'));
-- ... do work ...
SELECT pg_advisory_unlock(hashtext('migration:run'));

-- non-blocking
SELECT pg_try_advisory_lock(hashtext('migration:run'));
-- returns true if acquired
```

Useful for: "only one app instance should run migrations on boot."

## ANALYZE — keep stats fresh

The query planner uses table stats. After a big change:

```sql
ANALYZE orders;          -- one table
ANALYZE;                 -- all tables
```

Auto-vacuum runs ANALYZE for you on changing tables. After a big bulk load: run manually.

## Slow query inspection

```sql
-- requires pg_stat_statements extension
SELECT
  query,
  calls,
  mean_exec_time,
  total_exec_time,
  rows
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 20;
```

`pg_stat_statements` is the highest-leverage observability tool for Postgres. Always enable.

For a specific suspicious query:

```sql
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, FORMAT JSON) SELECT ... ;
```

Paste into https://explain.dalibo.com/ for visual analysis.

## When indexes hurt

Every index slows writes (must update on each INSERT/UPDATE/DELETE) and takes disk space. Don't add indexes "just in case."

Drop unused ones:

```sql
SELECT schemaname, relname, indexrelname, idx_scan
FROM pg_stat_user_indexes
WHERE idx_scan = 0
  AND indexrelname NOT LIKE '%_pkey'
  AND indexrelname NOT LIKE '%_uq';
```

These haven't been used since the last stats reset — candidates for `DROP INDEX`.

## Concurrent index creation (production)

```sql
CREATE INDEX CONCURRENTLY orders_user_status_idx ON orders (user_id, status);
```

Doesn't block writes. Takes 2-3× longer. Can fail (creates an INVALID index) — drop and retry:

```sql
SELECT indexname FROM pg_indexes WHERE indisvalid = false;
DROP INDEX CONCURRENTLY orders_user_status_idx;
```

**Always use CONCURRENTLY in production** for new indexes on tables > ~100K rows.

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| Implicit type cast in WHERE | `WHERE id = '123'` on integer triggers seq scan; use `WHERE id = 123` |
| Functional condition not matching index | `WHERE lower(email) = ?` needs an expression index `(lower(email))` |
| `WHERE x LIKE '%foo%'` slow | Use `pg_trgm` GIN index |
| `OR` between unindexed and indexed | Postgres often falls back to seq scan; restructure with UNION |
| `IN (subquery)` slow | Try `EXISTS` or `JOIN` instead |
| `NOT IN` with NULLs | NULL semantics break it; use `NOT EXISTS` |
| `count(*)` slow | Approximation via `pg_class.reltuples`, or maintain a counter table |
| Sort spilling to disk | Increase `work_mem` for that session |
| Index not used for `ORDER BY` | Order matches the trailing index columns? Ascending vs descending mismatch? |
| Connection pool exhausted under load | Use PgBouncer; or raise pool size cautiously |
| Statements suddenly slow after data growth | Run `ANALYZE`; stats stale |
| Deadlock errors | Lock rows in a consistent order across transactions |
