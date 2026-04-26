# PostgreSQL Operations

> Backups, monitoring, scaling, replication, PgBouncer, WAL archiving. The "now we're in production" cuts.

## Backup strategy

Decide on RPO (how much data can you lose) and RTO (how fast must you recover).

| Strategy | RPO | RTO | Setup cost |
|----------|-----|-----|-----------|
| Nightly `pg_dump` | 24h | 1-4h | trivial |
| `pg_dump` every 4h + WAL archiving | 5min | 30min | medium |
| Streaming replication + standby promotion | <1min | <5min | medium |
| Continuous backup with PITR (pgBackRest / WAL-G) | seconds | <30min | medium-high |
| Managed (Aurora, Supabase, Neon) | seconds | minutes | $$ |

For most projects: **nightly `pg_dump` + WAL archiving** is the sweet spot.

### `pg_dump` (logical, simple)

```bash
# custom format (compressed, parallel-restorable, selective restore)
pg_dump -U postgres -d {{db-name}} -F c -Z 6 -f /var/backups/{{db-name}}-$(date -u +%FT%H%M%SZ).dump

# restore
createdb -U postgres {{db-name}}_restore
pg_restore -U postgres -d {{db-name}}_restore -j 4 /var/backups/{{db-name}}-...dump
```

Pros: portable across versions, selective restore, simple.
Cons: not for huge DBs (locks read momentarily, can be slow on TB scale), no PITR.

### Continuous backup with pgBackRest

```ini
# /etc/pgbackrest.conf
[global]
repo1-path=/var/lib/pgbackrest
repo1-retention-full=2
repo1-retention-diff=7
process-max=4
log-level-console=info

[main]
pg1-path=/var/lib/postgresql/17/main
```

Initial setup, full backup, archive WAL continuously:

```bash
sudo -u postgres pgbackrest --stanza=main stanza-create
sudo -u postgres pgbackrest --stanza=main backup --type=full
# WAL archiving via postgres.conf:
# archive_mode = on
# archive_command = 'pgbackrest --stanza=main archive-push %p'
```

Restore to any point in time:

```bash
sudo -u postgres pgbackrest --stanza=main --type=time --target="2026-04-26 12:00:00" restore
```

Use pgBackRest if you have >50GB DB or need PITR.

### Test restoring

A backup that's never been restored is hope, not a backup. **Test restoring monthly.** Pick an arbitrary date, restore to a sandbox DB, verify counts and a sample query.

## Monitoring

### Built-in views to watch

```sql
-- live activity
SELECT pid, usename, application_name, state, query_start, query
FROM pg_stat_activity
WHERE state = 'active' AND pid != pg_backend_pid();

-- connection count
SELECT count(*) FROM pg_stat_activity;

-- per-table stats
SELECT relname, n_live_tup, n_dead_tup, last_autovacuum, last_autoanalyze
FROM pg_stat_user_tables
ORDER BY n_dead_tup DESC LIMIT 20;

-- index usage
SELECT relname, indexrelname, idx_scan, idx_tup_read, idx_tup_fetch
FROM pg_stat_user_indexes ORDER BY idx_scan;

-- slow queries (requires pg_stat_statements)
SELECT query, calls, mean_exec_time, total_exec_time
FROM pg_stat_statements ORDER BY total_exec_time DESC LIMIT 20;

-- replication lag (on primary)
SELECT client_addr, state, sync_state, replay_lag
FROM pg_stat_replication;

-- bloat (rough)
SELECT schemaname, relname,
       pg_size_pretty(pg_total_relation_size(relid)) AS total_size,
       n_live_tup, n_dead_tup,
       round(100.0 * n_dead_tup / nullif(n_live_tup + n_dead_tup, 0), 1) AS dead_pct
FROM pg_stat_user_tables ORDER BY pg_total_relation_size(relid) DESC LIMIT 20;
```

### Prometheus + postgres_exporter

```yaml
# docker-compose.yml addition
postgres-exporter:
  image: prometheuscommunity/postgres-exporter:latest
  environment:
    DATA_SOURCE_NAME: "postgresql://postgres:${POSTGRES_PASSWORD}@postgres:5432/postgres?sslmode=disable"
  ports:
    - "9187:9187"
```

Scrape from Prometheus, dashboard with Grafana ID #9628 (PostgreSQL Database).

Key metrics to alert on:
- Connection count > 80% of `max_connections`
- Replication lag > 10s
- Cache hit ratio < 99%
- Long-running query > 5min (`pg_stat_activity` query duration)
- Table bloat > 30%
- Disk free < 20%

## Connection pooling — PgBouncer

Postgres maxes out around 300-500 connections per server (each is a process, not a thread). With many app instances each with 10-20 conns, you blow it fast.

**Always front Postgres with PgBouncer in production.**

```ini
# /etc/pgbouncer/pgbouncer.ini
[databases]
{{db-name}} = host=postgres port=5432 dbname={{db-name}}

[pgbouncer]
listen_addr = 0.0.0.0
listen_port = 6432
auth_type = scram-sha-256
auth_file = /etc/pgbouncer/userlist.txt
pool_mode = transaction
max_client_conn = 1000
default_pool_size = 25
reserve_pool_size = 5
reserve_pool_timeout = 3
server_idle_timeout = 600
server_lifetime = 3600
```

```
# /etc/pgbouncer/userlist.txt
"{{db-user}}" "SCRAM-SHA-256$..."  # use `pg_dump --schema-only auth_users` or scram-tool
```

App connects to `pgbouncer:6432` instead of `postgres:5432`. Same connection string (just different host/port).

### Pool modes

| Mode | When |
|------|------|
| **session** | Default; safest. Connection reserved for the lifetime of a client session. |
| **transaction** | Connection only reserved per transaction. **Highest throughput, but breaks prepared statements.** |
| **statement** | Per-statement; not generally useful. |

For modern apps: **transaction mode** + disable prepared statement cache:

- asyncpg: `prepared_statement_cache_size=0` in URL or driver options
- postgres-js: `{ prepare: false }` in client options
- Prisma: `?pgbouncer=true` in URL
- pgx: `default_query_exec_mode=simple_protocol`

Without disabling prepared statements, you'll see weird `prepared statement "X" already exists` errors.

## Replication

### Streaming replication (built-in)

Primary streams WAL to one or more replicas:

```ini
# primary postgresql.conf
wal_level = replica
max_wal_senders = 10
max_replication_slots = 10
hot_standby = on

# pg_hba.conf
host  replication  replicator  10.0.0.0/8  scram-sha-256
```

```ini
# replica postgresql.conf
hot_standby = on
primary_conninfo = 'host=primary port=5432 user=replicator password=...'
```

```bash
# on replica, initial base backup
pg_basebackup -h primary -U replicator -D /var/lib/postgresql/17/main -P -R -X stream
```

`-R` writes the standby signal file. Start the replica; it streams from primary.

### Logical replication (selective)

Replicate specific tables to a different DB (e.g., for analytics):

```sql
-- on primary
CREATE PUBLICATION analytics FOR TABLE orders, users;

-- on subscriber
CREATE SUBSCRIPTION analytics_sub
  CONNECTION 'host=primary user=replicator password=...'
  PUBLICATION analytics;
```

Useful for: cross-version replication, partial replication, blue-green migrations.

### Read replicas in code

```python
# read pool vs write pool
from sqlalchemy.ext.asyncio import create_async_engine

write_engine = create_async_engine(WRITE_DB_URL)
read_engine = create_async_engine(READ_DB_URL)

# in repos:
async def get_user(id):
    async with read_engine.connect() as conn:
        ...

async def create_user(data):
    async with write_engine.begin() as conn:
        ...
```

Be aware of replication lag — a write to primary may not yet be on replica when you read. Stale reads are usually fine; for "read your writes" use the primary.

## Scaling

### Vertical (add CPU/RAM)

Easiest: bigger box. Postgres scales well vertically up to ~32 cores. Tune `shared_buffers`, `work_mem`, `effective_cache_size` accordingly.

### Read replicas

Easy with streaming replication. Doesn't help write throughput.

### Connection pooling (PgBouncer)

Reduces overhead, lets you serve more clients per Postgres backend.

### Partitioning

Per `01-schema-design.md` — table-level horizontal split.

### Sharding

Postgres doesn't shard natively. Options:
- **Citus** extension (formerly an extension; now part of Microsoft) — multi-node sharded Postgres
- **Application-level sharding** (route requests to one of N independent DBs by tenant_id)
- **Move to a sharded DB** (CockroachDB, YugabyteDB) — Postgres-wire-compatible

Don't shard until you've exhausted vertical scaling + replication. The complexity is real.

## Tuning checklist

Realistic defaults for a 4 CPU / 16 GB RAM server dedicated to Postgres:

```
shared_buffers = 4GB              # 25% RAM
effective_cache_size = 12GB       # 75% RAM (filesystem cache estimate)
work_mem = 32MB                   # per-operation; multiply by concurrency
maintenance_work_mem = 1GB        # vacuum, create index
wal_buffers = 16MB
max_connections = 200             # behind PgBouncer
random_page_cost = 1.1            # SSD
effective_io_concurrency = 200    # SSD (1 for HDD)
checkpoint_completion_target = 0.9
default_statistics_target = 100
```

For deeper tuning, use https://pgtune.leopard.in.ua/ as a starting point.

## Maintenance

### VACUUM

Auto-vacuum runs by default. Tune for hot tables:

```sql
ALTER TABLE orders SET (
  autovacuum_vacuum_scale_factor = 0.05,    -- vacuum at 5% dead rows
  autovacuum_analyze_scale_factor = 0.02,
  autovacuum_vacuum_cost_limit = 2000
);
```

For severe bloat, `VACUUM FULL` rewrites the table (locks it!). For online: `pg_repack` extension.

### REINDEX

After major data churn:

```sql
REINDEX INDEX CONCURRENTLY orders_user_id_idx;
```

`CONCURRENTLY` doesn't lock writes (Postgres 12+).

### Stats

```sql
ANALYZE orders;          -- after big bulk loads
SELECT * FROM pg_stats WHERE tablename = 'orders';   -- inspect
```

## Disaster recovery

Have a runbook. Periodically (annually) drill:

1. Simulate primary failure (stop the container)
2. Promote replica (`pg_ctl promote`)
3. Update app to point at the new primary (DNS or env config)
4. Verify writes succeed
5. Restore the original as a new replica

Without rehearsals, your "DR plan" is fiction.

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| Backups never tested | Restore monthly to a sandbox |
| `max_connections=100` too low under load | PgBouncer (don't just raise it — process count cost) |
| `prepared statement already exists` with PgBouncer | Disable prepared statement cache in driver |
| Bloat sneaking up | Monitor `pg_stat_user_tables`; tune autovacuum thresholds |
| Slow shutdown holding connections | `pg_terminate_backend(pid)` for stuck sessions; investigate why |
| Disk fills (WAL not archived) | Verify `archive_command` succeeds; alert on `pg_stat_archiver` failures |
| Failover lost data | Replicate synchronously (`synchronous_commit=on`, `synchronous_standby_names`) for critical writes — slower but durable |
| Replica lag growing | Network bottleneck; or replica overloaded — check stats |
| Long-running transactions blocking VACUUM | Find via `pg_stat_activity`; cancel or address |
| Postgres won't start after disk full | Free space, may need `pg_resetwal` (DESTRUCTIVE — use only as last resort) |
| Default-tuned Postgres on a 64GB box | Tune! `shared_buffers=8MB` is the install default — utterly wrong for prod |
