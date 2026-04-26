# PostgreSQL Language Clients

> Connection pools, prepared statements, LISTEN/NOTIFY, copy-from-stdin per language. Choose the right driver, configure it correctly.

## Driver picks per language

| Language | Driver | Notes |
|----------|--------|-------|
| **Python** | `asyncpg` (async) — `psycopg3` (sync + async) | asyncpg is fastest; psycopg3 supports both modes |
| **Node** | `postgres` (postgres.js) — or `pg` (node-postgres) | postgres.js newer + faster + simpler API |
| **Go** | `pgx/v5` | Pure-Go, fast, typed |
| **Java** | `pgjdbc` (sync) or `r2dbc-postgresql` (reactive) | |
| **Rust** | `tokio-postgres` + `sqlx` for query macros | |
| **Ruby** | `pg` gem | |
| **PHP** | `pdo_pgsql` | |

Rejected:
- **`psycopg2`** — sync-only, no longer recommended; use `psycopg3` or `asyncpg`
- **Sequelize** (Node) — slow, weak types
- **`go-pg`** — abandoned in favor of `pgx`

## Python — asyncpg

```python
import asyncpg

# pool — share across the app
pool = await asyncpg.create_pool(
    dsn=settings.database_url,
    min_size=5,
    max_size=20,
    max_queries=50_000,                  # recycle connections after N queries
    max_inactive_connection_lifetime=300, # recycle idle conns
    statement_cache_size=0 if settings.pgbouncer_transaction_mode else 100,
    server_settings={
        'application_name': '{{project-slug}}',
        'jit': 'off',                    # often slower on simple queries
    },
)

# query
async def get_user(user_id: str) -> dict | None:
    async with pool.acquire() as conn:
        return await conn.fetchrow("SELECT * FROM users WHERE id = $1", user_id)

# transaction
async def transfer(from_id, to_id, amount):
    async with pool.acquire() as conn:
        async with conn.transaction():
            await conn.execute("UPDATE accounts SET balance = balance - $1 WHERE id = $2", amount, from_id)
            await conn.execute("UPDATE accounts SET balance = balance + $1 WHERE id = $2", amount, to_id)
```

### COPY (bulk load)

```python
async with pool.acquire() as conn:
    await conn.copy_records_to_table(
        'orders',
        records=[(id, user_id, total) for id, user_id, total in batch],
        columns=['id', 'user_id', 'total_cents'],
    )
```

100× faster than INSERT for bulk loads.

### LISTEN / NOTIFY

```python
async def listen():
    async with pool.acquire() as conn:
        await conn.add_listener('orders_channel', on_notify)
        await asyncio.Event().wait()    # keep alive

async def on_notify(connection, pid, channel, payload):
    print(f"received: {payload}")

# from another session
await pool.execute("NOTIFY orders_channel, 'order:123'")
```

Useful for: cache invalidation, real-time UI updates without polling, simple pub/sub.

## Python — SQLAlchemy 2.0 async (over asyncpg)

For the full pattern, see [`backend/fastapi/02-sqlalchemy-and-alembic.md`](../../backend/fastapi/02-sqlalchemy-and-alembic.md). Key bits:

```python
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker

engine = create_async_engine(
    "postgresql+asyncpg://user:pass@host/db",
    pool_size=10,
    max_overflow=20,
    pool_pre_ping=True,           # detect dead connections
    pool_recycle=1800,
    echo=False,
    connect_args={
        "statement_cache_size": 0,    # PgBouncer transaction mode
        "server_settings": {"application_name": "{{project-slug}}"},
    },
)

SessionLocal = async_sessionmaker(engine, expire_on_commit=False, autoflush=False)
```

## Node — postgres.js (postgres)

```typescript
import postgres from 'postgres';

export const sql = postgres(process.env.DATABASE_URL!, {
  max: 20,                          // pool size
  idle_timeout: 30,
  max_lifetime: 60 * 30,            // recycle conn every 30 min
  prepare: false,                   // for PgBouncer transaction mode
  connection: {
    application_name: '{{project-slug}}',
  },
  transform: { undefined: null },   // map undefined → NULL
});

// tagged template — auto-parameterized
const users = await sql`SELECT * FROM users WHERE id = ${userId}`;

// dynamic columns / values (still safe)
const cols = sql(['email', 'name']);
const filter = sql`WHERE ${sql(filterField)} = ${filterValue}`;
const rows = await sql`SELECT ${cols} FROM users ${filter}`;

// transaction
const result = await sql.begin(async (txn) => {
  await txn`UPDATE accounts SET balance = balance - ${amount} WHERE id = ${fromId}`;
  await txn`UPDATE accounts SET balance = balance + ${amount} WHERE id = ${toId}`;
});

// LISTEN
sql.listen('orders_channel', (payload) => {
  console.log('received:', payload);
});

// NOTIFY
await sql.notify('orders_channel', 'order:123');
```

postgres.js auto-parameterizes everything in tagged templates — SQL injection is structurally hard.

## Node — pg (node-postgres)

The classic. Used by most ORMs internally.

```typescript
import { Pool } from 'pg';

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  max: 20,
  idleTimeoutMillis: 30_000,
  connectionTimeoutMillis: 5_000,
});

const result = await pool.query('SELECT * FROM users WHERE id = $1', [userId]);
```

Use postgres.js for new projects. pg if you need ecosystem compat.

## Drizzle / Prisma / Kysely

These are query builders / ORMs sitting on top of `postgres` or `pg`. See their respective guides:

- [`backend/nodejs-express/02-drizzle-and-migrations.md`](../../backend/nodejs-express/02-drizzle-and-migrations.md) — Drizzle
- [`backend/nestjs/02-prisma-and-migrations.md`](../../backend/nestjs/02-prisma-and-migrations.md) — Prisma
- Kysely is a type-safe SQL builder with no codegen step

## Go — pgx

```go
import (
    "context"
    "github.com/jackc/pgx/v5/pgxpool"
)

pool, err := pgxpool.New(ctx, os.Getenv("DATABASE_URL"))
if err != nil { log.Fatal(err) }
defer pool.Close()

// query one
var user User
err = pool.QueryRow(ctx, "SELECT id, email FROM users WHERE id = $1", userID).
    Scan(&user.ID, &user.Email)

// query many
rows, err := pool.Query(ctx, "SELECT id, email FROM users WHERE created_at > $1", since)
defer rows.Close()
for rows.Next() {
    var u User
    rows.Scan(&u.ID, &u.Email)
    users = append(users, u)
}

// transaction
tx, err := pool.Begin(ctx)
defer tx.Rollback(ctx)
tx.Exec(ctx, "UPDATE ...")
tx.Exec(ctx, "INSERT ...")
tx.Commit(ctx)

// COPY (bulk load)
_, err = pool.CopyFrom(ctx,
    pgx.Identifier{"orders"},
    []string{"id", "user_id", "total_cents"},
    pgx.CopyFromRows(rowsData),
)
```

### sqlc (codegen for Go)

For type-safe query results:

```sql
-- query.sql
-- name: GetUser :one
SELECT * FROM users WHERE id = $1;
```

```bash
sqlc generate
```

Generates Go functions returning typed structs. Combines pgx's speed with type safety.

## Java — JDBC

```java
HikariConfig config = new HikariConfig();
config.setJdbcUrl("jdbc:postgresql://localhost:5432/" + dbName);
config.setUsername(user);
config.setPassword(pass);
config.setMaximumPoolSize(20);
config.setConnectionTimeout(5_000);
config.setIdleTimeout(30_000);

HikariDataSource ds = new HikariDataSource(config);

try (Connection conn = ds.getConnection();
     PreparedStatement stmt = conn.prepareStatement("SELECT * FROM users WHERE id = ?")) {
    stmt.setObject(1, userId);
    try (ResultSet rs = stmt.executeQuery()) {
        if (rs.next()) { ... }
    }
}
```

For reactive: `r2dbc-postgresql`.

For higher-level: jOOQ (type-safe SQL DSL), Spring Data JDBC.

## Rust — sqlx

```rust
use sqlx::postgres::{PgPool, PgPoolOptions};

let pool = PgPoolOptions::new()
    .max_connections(20)
    .connect(&database_url)
    .await?;

// query — checked at compile time against schema
let user = sqlx::query_as!(
    User,
    "SELECT id, email FROM users WHERE id = $1",
    user_id
).fetch_optional(&pool).await?;

// transaction
let mut tx = pool.begin().await?;
sqlx::query!("UPDATE accounts SET balance = balance - $1 WHERE id = $2", amount, from_id)
    .execute(&mut *tx).await?;
sqlx::query!("UPDATE accounts SET balance = balance + $1 WHERE id = $2", amount, to_id)
    .execute(&mut *tx).await?;
tx.commit().await?;
```

`query!` and `query_as!` macros validate SQL against your DB at compile time. Run `cargo sqlx prepare` in CI.

## Connection string forms

```
# standard
postgresql://user:pass@host:5432/dbname

# with options
postgresql://user:pass@host:5432/dbname?sslmode=require&application_name=app

# SQLAlchemy + asyncpg
postgresql+asyncpg://user:pass@host:5432/dbname

# psycopg3
postgresql+psycopg://user:pass@host:5432/dbname

# Prisma + PgBouncer
postgresql://user:pass@host:6432/dbname?pgbouncer=true&connection_limit=1

# Unix socket
postgresql:///dbname?host=/var/run/postgresql

# multiple hosts (failover)
postgresql://user:pass@host1,host2,host3:5432/dbname?target_session_attrs=read-write
```

## TLS

In production, always use TLS:

```
postgresql://user:pass@host:5432/dbname?sslmode=require
```

`sslmode` levels:

| Mode | Meaning |
|------|---------|
| `disable` | No TLS |
| `prefer` | Try TLS, fall back to plain (default) |
| `require` | TLS required, but cert not verified |
| `verify-ca` | Cert verified against CA |
| `verify-full` | Cert verified, hostname must match |

For internet-exposed Postgres: `verify-full`. For VPC-internal: `require` is usually enough.

## Common patterns

### Health check

```python
async def health() -> dict:
    try:
        async with pool.acquire() as conn:
            v = await conn.fetchval("SELECT 1")
        return {"status": "ok", "result": v}
    except Exception as e:
        return {"status": "degraded", "error": str(e)}
```

### Graceful shutdown

```python
@asynccontextmanager
async def lifespan(app):
    yield
    await pool.close()
```

```typescript
process.on('SIGTERM', async () => {
  await sql.end();
  process.exit(0);
});
```

Without graceful close, in-flight queries are aborted.

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| Single connection shared across async tasks | Use a pool; one connection per concurrent op |
| `prepared statement already exists` (PgBouncer) | Set `prepare: false` / `statement_cache_size=0` |
| `Could not connect: server closed the connection unexpectedly` | Connection idle too long; `pool_pre_ping=True` (SQLAlchemy) or recycle interval |
| `password authentication failed` | URL-encode special chars in password (`%21` for `!`) |
| `database "X" does not exist` | Connection succeeded; DB name typo |
| Connection pool exhaustion under load | Increase `max_size`; or check for held connections (long-running queries) |
| `MissingGreenlet` (SA async) | Sync code called inside async context — `await session.run_sync(...)` |
| `DetachedInstanceError` after commit | `expire_on_commit=False` in SA session factory |
| Slow first query in a connection | Connection startup overhead; pre-warm with `pool_pre_ping` |
| TLS cert verification failed | Match certificate hostname to connection host; or use `sslmode=require` if cert is self-signed |
