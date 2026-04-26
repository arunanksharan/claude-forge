# PostgreSQL Schema Design

> Naming, types, modeling patterns, multi-tenancy, partitioning. The decisions you make in week 1 you live with forever — start opinionated.

## Naming conventions

| Object | Convention | Example |
|--------|-----------|---------|
| Tables | `snake_case`, plural | `users`, `order_items` |
| Columns | `snake_case`, singular | `email`, `created_at` |
| Primary key | `id` (uuid v7) | `id uuid PRIMARY KEY DEFAULT uuidv7()` |
| Foreign keys | `<referenced_singular>_id` | `user_id` references `users(id)` |
| Indexes | `<table>_<columns>_idx` | `orders_user_id_status_idx` |
| Unique indexes | `<table>_<columns>_uq` | `users_email_uq` |
| Constraints | `<table>_<purpose>_ck` | `users_email_format_ck` |
| Sequences | `<table>_<column>_seq` | `legacy_orders_id_seq` |
| Functions | `<verb>_<noun>` | `compute_user_score()` |
| Schemas | reserved by domain | `public`, `analytics`, `audit` |

ORMs handle case mapping automatically (Drizzle `casing: 'snake_case'`, Prisma `@@map`, SQLAlchemy explicit `__tablename__`).

## Primary keys — UUID v7 (default)

```sql
-- requires pg_uuidv7 extension OR app-side generation
CREATE TABLE users (
  id uuid PRIMARY KEY DEFAULT uuidv7(),  -- or app-generated
  ...
);
```

Why v7 over v4: monotonic-ish (sortable by creation), index-friendly, no leak of cardinality, safe in URLs, no auto-increment race.

When NOT to use UUID:
- Tables that join to a legacy system using bigint
- Append-only event tables where bigint sequence is fine + size matters

When to use bigint instead:
```sql
id bigserial PRIMARY KEY  -- or bigint generated always as identity
```

`int` (max 2.1B) is too small for hot tables. Always `bigint` if not UUID.

## Standard timestamp columns

Every table that's not pure metadata gets:

```sql
created_at timestamptz NOT NULL DEFAULT now(),
updated_at timestamptz NOT NULL DEFAULT now()
```

For `updated_at` auto-bump:

```sql
CREATE OR REPLACE FUNCTION set_updated_at() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$;

CREATE TRIGGER users_updated_at BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
```

ORM alternative (preferred — testable in Python):
- Drizzle: `.$onUpdate(() => new Date())`
- Prisma: `@updatedAt`
- SQLAlchemy: `default=lambda: datetime.now(UTC), onupdate=lambda: datetime.now(UTC)`

**Always `timestamptz`, never `timestamp`** — Postgres stores in UTC, returns in client zone.

## NOT NULL by default

Every column `NOT NULL` unless you have a real reason. `NULL` semantics are messy:

- `WHERE x = NULL` doesn't work (need `IS NULL`)
- `WHERE x != 'foo'` excludes nulls
- Aggregates skip nulls (sometimes desired, often surprising)

Use sentinel values when "unknown" is a real state:
- Empty string `''` for text
- `0` for counts
- An explicit `'unknown'` enum value
- Or split into a separate child table

## Type choices

| Need | Pick |
|------|------|
| Variable text < 1KB | `text` (no length limit; cheaper than `varchar(N)`) |
| Long text | `text` (Postgres TOASTs over ~2KB) |
| Email | `text` + check constraint or domain type |
| URL | `text` |
| Money | `bigint` for cents, `numeric(18,2)` for fractional |
| Boolean | `boolean` |
| Enum | `pg_enum` type or `text` + check constraint |
| JSON | `jsonb` (always — never `json`) |
| Array | `text[]`, `int[]`, etc. — use sparingly |
| UUID | `uuid` |
| Date (no time) | `date` |
| Timestamp | `timestamptz` |
| Duration | `interval` |
| IP address | `inet` |
| MAC address | `macaddr` |
| Binary | `bytea` (small) or external storage (large) |

### Money

Never `float`/`double`. Cents in `bigint` is the simplest:

```sql
total_cents bigint NOT NULL CHECK (total_cents >= 0)
```

For fractional cents (financial calc):

```sql
amount numeric(18,2) NOT NULL CHECK (amount >= 0)
```

In code, convert to/from `Decimal` (Python) or `BigInt` (JS) — never to `float`.

### ENUMs

Two patterns:

```sql
-- Postgres ENUM type (compact, fast)
CREATE TYPE order_status AS ENUM ('pending', 'paid', 'shipped', 'cancelled');
ALTER TABLE orders ADD COLUMN status order_status NOT NULL DEFAULT 'pending';

-- adding a value:
ALTER TYPE order_status ADD VALUE 'refunded';
```

vs.

```sql
-- text + check (flexible, easier in migrations)
status text NOT NULL DEFAULT 'pending'
  CHECK (status IN ('pending', 'paid', 'shipped', 'cancelled'))
```

Pick ENUM if values are stable. Pick text+check if values change frequently. Reordering ENUM values is painful (Postgres doesn't allow it directly).

### JSON / JSONB

```sql
metadata jsonb NOT NULL DEFAULT '{}'::jsonb
```

Always `jsonb` (binary, indexable). Index specific paths you query:

```sql
-- exact path equality
CREATE INDEX users_metadata_plan_idx ON users ((metadata->>'plan'));

-- generic containment / existence (slower but covers more queries)
CREATE INDEX users_metadata_gin_idx ON users USING gin (metadata jsonb_path_ops);
```

Use jsonb for: settings, flexible attributes, third-party API responses you cache.

**Don't** use jsonb for: data you'll join on, aggregate over, or filter by frequently. Those go in real columns.

## Foreign keys

Always declared with explicit ON DELETE behavior:

```sql
user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
parent_id uuid REFERENCES categories(id) ON DELETE SET NULL,
created_by uuid REFERENCES users(id) ON DELETE RESTRICT
```

| ON DELETE | When |
|-----------|------|
| `CASCADE` | Children have no meaning without parent (order_items without order) |
| `SET NULL` | Reference is informational; child survives (parent_id in tree, optional) |
| `RESTRICT` | Block delete; force explicit cleanup |
| `NO ACTION` (default) | Same as RESTRICT but checked at end of statement |
| `SET DEFAULT` | Rarely useful |

**Always index the FK column** — Postgres doesn't auto-index FKs (unlike some other DBs):

```sql
CREATE INDEX orders_user_id_idx ON orders (user_id);
```

Without this, every parent delete scans the child table.

## Modeling patterns

### Soft delete (skeptical view)

```sql
deleted_at timestamptz       -- NULL = active
```

Then every query filters `WHERE deleted_at IS NULL`. Add a partial index:

```sql
CREATE INDEX users_active_email_uq ON users (email) WHERE deleted_at IS NULL;
```

**I lean against soft delete.** It causes:
- "User shows up twice" bugs (forgot the filter)
- FK constraint complications
- Reporting confusion

Use real DELETE + a separate `audit_log` or `deleted_users` archive table if you need history.

### Multi-tenancy

Three patterns:

| Pattern | When |
|---------|------|
| **Shared schema, `tenant_id` column** | Default — simple, scales well, requires query discipline |
| **Schema-per-tenant** | Strong isolation, manageable for ~100 tenants |
| **Database-per-tenant** | Compliance / VIP customers; doesn't scale to many |

Shared schema with RLS for enforcement:

```sql
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON orders
  USING (tenant_id = current_setting('app.tenant_id')::uuid);

-- in your app, before each query:
SET LOCAL app.tenant_id = '...';
```

Now even if you forget the WHERE clause, Postgres adds it. Bulletproof.

For multi-tenancy without RLS: **discipline + code review**. Have your repo class take `tenant_id` in its constructor and add it to every query.

### Polymorphic associations (don't)

"`comment.commentable_type` and `comment.commentable_id`" is tempting and almost always wrong:
- No FK constraint enforcement
- Can't JOIN naturally
- Every commentable type breaks discovery

Instead:

```sql
-- one table per relationship
CREATE TABLE post_comments (id, post_id REFERENCES posts(id), body, ...);
CREATE TABLE photo_comments (id, photo_id REFERENCES photos(id), body, ...);
```

If they truly share behavior, abstract via a view or generic comment service that knows the schema.

### Tree / hierarchy

For arbitrary-depth trees:

```sql
-- adjacency list (simple, recursive CTE for traversal)
parent_id uuid REFERENCES categories(id) ON DELETE CASCADE

-- query
WITH RECURSIVE tree AS (
  SELECT id, name, parent_id FROM categories WHERE id = $1
  UNION ALL
  SELECT c.id, c.name, c.parent_id FROM categories c
  JOIN tree ON c.parent_id = tree.id
)
SELECT * FROM tree;
```

For frequent ancestor / descendant queries, install `ltree` extension:

```sql
CREATE EXTENSION IF NOT EXISTS ltree;

ALTER TABLE categories ADD COLUMN path ltree NOT NULL;
CREATE INDEX categories_path_gist_idx ON categories USING gist (path);
```

Querying becomes `WHERE path <@ 'electronics.computers'` (descendants) or `WHERE path @> 'electronics.computers.laptops.thinkpad'` (ancestors).

### Audit log

```sql
CREATE TABLE audit_log (
  id uuid PRIMARY KEY DEFAULT uuidv7(),
  actor_id uuid,                            -- user who did it (or null = system)
  tenant_id uuid,                           -- multi-tenant scope
  action text NOT NULL,                     -- e.g. 'order.created', 'user.deleted'
  entity_type text NOT NULL,                -- 'order', 'user'
  entity_id uuid NOT NULL,
  before_state jsonb,                       -- prior state (for updates)
  after_state jsonb,                        -- new state
  metadata jsonb,                           -- request_id, ip, user_agent
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX audit_log_entity_idx ON audit_log (entity_type, entity_id, created_at DESC);
CREATE INDEX audit_log_actor_idx ON audit_log (actor_id, created_at DESC) WHERE actor_id IS NOT NULL;
CREATE INDEX audit_log_tenant_idx ON audit_log (tenant_id, created_at DESC);
```

Append-only. Never UPDATE / DELETE. Partition by month for big systems (see below).

## Partitioning

For tables over ~50M rows or with predictable time-based access:

```sql
-- declarative partitioning by range (Postgres 10+)
CREATE TABLE events (
  id uuid NOT NULL,
  occurred_at timestamptz NOT NULL,
  ...
) PARTITION BY RANGE (occurred_at);

CREATE TABLE events_2026_01 PARTITION OF events
  FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');

-- automate creation with pg_partman extension
```

Benefits:
- Fast time-based deletes (drop a partition vs DELETE millions of rows)
- Smaller indexes per partition → faster queries
- Maintenance per-partition

Don't over-partition. Under 10M rows, partitioning adds operational complexity without payoff.

## Constraints — use them

```sql
CREATE TABLE orders (
  ...
  total_cents bigint NOT NULL CHECK (total_cents >= 0),
  status order_status NOT NULL CHECK (status IN ('pending', 'paid', ...)),
  email text CHECK (email ~* '^[^@]+@[^@]+\.[^@]+$'),
  shipped_at timestamptz,
  CONSTRAINT shipped_implies_paid CHECK (shipped_at IS NULL OR status IN ('shipped', 'delivered'))
);
```

Constraints catch bugs the application would let slip. Cheap to add at design time, painful to add later (must validate all existing rows).

## Schema migration discipline

Same as the language-specific guides (`backend/*/02-*-and-migrations.md`):

| Rule | Why |
|------|-----|
| **Expand → migrate → contract** for any schema change in a live system | Old code keeps working |
| **CONCURRENT** index creation in production | `CREATE INDEX CONCURRENTLY ...` — don't lock writes |
| **Backfill before NOT NULL** | Add nullable → backfill → set NOT NULL (3 migrations) |
| **One migration per merged PR** | Easier review/rebase/revert |
| **Test on prod-sized snapshot** | A 30s migration on dev = 6h on prod |
| **Always read auto-generated SQL** | ORMs miss things (CONCURRENT, ENUM additions, server defaults) |

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| Auto-incrementing PK on hot table | UUID v7 |
| `varchar(N)` with arbitrary N | Use `text`; constrain via CHECK if needed |
| Using `timestamp without time zone` | Use `timestamptz` |
| Missing FK index | Index every FK |
| `ORDER BY random()` slow | Use `TABLESAMPLE` or random seek |
| `COUNT(*)` slow on big table | Approximation via `pg_class.reltuples`; or maintain a counter |
| Big composite index used for only first column query | Drop and replace; or add separate single-column index |
| Indexes on columns with low cardinality | Use partial index instead: `WHERE deleted_at IS NULL` |
| ENUM value reorder needed | You can't directly — drop, recreate, migrate |
| JSONB with deeply nested structure | Flatten what you query; query patterns drive schema |
| Tables that grow forever (events, logs) | Partition + retention policy |
