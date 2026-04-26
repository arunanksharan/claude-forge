# Redis — Master Setup & Integration Prompt

> **Copy this file into Claude Code. Replace `{{placeholders}}`. The model will set up Redis (containerized or managed), wire it to your app, and verify health.**

---

## Context

You are setting up Redis for a project. Redis serves multiple roles: cache, session store, rate limiter, distributed lock, queue broker (BullMQ/Celery), pub/sub, and Streams. This prompt focuses on the standalone setup; for queues see [`async-and-queues/`](../../async-and-queues/), for streams see [`async-and-queues/redis-streams.md`](../../async-and-queues/redis-streams.md).

If something is ambiguous, **ask once, then proceed**.

## Project parameters

```
project_slug:       {{project-slug}}
redis_version:      8.0                         # current GA in 2026
hosting:            {{docker|managed|self-hosted-cluster}}
language:           {{python|node|go|java}}
include_persistence:{{rdb|aof|both|none}}       # cache=none; queue/sessions=both
include_modules:    {{stack|bare}}              # 'stack' = RedisJSON, RediSearch, RedisTimeSeries (use redis/redis-stack)
intended_use:       {{cache|queue|sessions|streams|all}}
```

---

## Locked stack

| Concern | Pick | Why |
|---------|------|-----|
| Version | **Redis 8.0** | Current GA; significant performance improvements over 7.x |
| Image | **`redis:8.0-alpine`** (lean) — or **`redis/redis-stack:latest`** (with modules) | Stack adds JSON, search, time-series |
| Persistence (cache only) | **none** | Cache is regenerable |
| Persistence (queue, sessions) | **AOF + RDB** | Survive restarts |
| Memory policy | **`noeviction`** for queues — **`allkeys-lru`** for cache | |
| Driver (Python) | **`redis` (asyncio)** for general; **`coredis`** for high-perf | |
| Driver (Node) | **`ioredis`** | More features than `node-redis` |
| Hosting | **Upstash** (serverless), **Redis Cloud**, **AWS ElastiCache** for managed | |
| TLS | Required for internet-exposed; optional VPC-internal | |

## Rejected

| Option | Why not |
|--------|---------|
| `redis:latest` tag | Pin major version |
| Default config (no `maxmemory`, no `requirepass`) | OOMs + open to anyone — set both |
| Sync redis-py | Use `redis.asyncio` for async apps |
| Long-form `KEYS *` in prod | Blocks the server; use `SCAN` |
| Redis as your durable store | It's a cache; use Postgres for durability |
| `bull` (deprecated) | Use BullMQ |

---

## Directory layout

```
{{project-slug}}/infra/redis/
├── docker-compose.dev.yml
├── redis.conf                            # custom config
└── README.md
```

---

## Key files

### `infra/redis/docker-compose.dev.yml`

```yaml
services:
  redis:
    image: redis:8.0-alpine               # or redis/redis-stack:latest for modules
    container_name: {{project-slug}}-redis
    restart: unless-stopped
    ports:
      - '127.0.0.1:6379:6379'             # bind localhost only
    volumes:
      - redis_data:/data
      - ./redis.conf:/usr/local/etc/redis/redis.conf:ro
    command:
      - redis-server
      - /usr/local/etc/redis/redis.conf
      - --requirepass
      - ${REDIS_PASSWORD:?REDIS_PASSWORD required}
    healthcheck:
      test: ["CMD", "sh", "-c", "redis-cli -a $$REDIS_PASSWORD ping | grep -q PONG"]
      interval: 10s
      timeout: 3s
      retries: 5
      start_period: 10s
    deploy:
      resources:
        limits: { cpus: '1', memory: 512M }
        reservations: { cpus: '0.25', memory: 128M }

volumes:
  redis_data:
```

### `infra/redis/redis.conf`

```
# Network
bind 0.0.0.0
protected-mode yes
port 6379
tcp-backlog 511
timeout 0
tcp-keepalive 300

# General
daemonize no
loglevel notice
databases 16

# Snapshotting (RDB)
# Format: save <seconds> <changes>
# Disable for pure cache: replace with `save ""`
save 900 1
save 300 10
save 60 10000
stop-writes-on-bgsave-error yes
rdbcompression yes
rdbchecksum yes
dbfilename dump.rdb
dir /data

# AOF (append-only file) — for queue/sessions
appendonly yes
appendfilename "appendonly.aof"
appendfsync everysec                      # 1s window for data loss; perf compromise
no-appendfsync-on-rewrite no
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 64mb

# Memory
maxmemory 2gb
# Cache: allkeys-lru
# Queue / sessions / locks: noeviction (let writes fail rather than evict)
maxmemory-policy allkeys-lru
maxmemory-samples 5

# Lazy free (non-blocking deletes)
lazyfree-lazy-eviction yes
lazyfree-lazy-expire yes
lazyfree-lazy-server-del yes
replica-lazy-flush yes
lazyfree-lazy-user-del yes

# Slow log
slowlog-log-slower-than 10000             # 10ms
slowlog-max-len 128

# Client output buffer
client-output-buffer-limit normal 0 0 0
client-output-buffer-limit replica 256mb 64mb 60
client-output-buffer-limit pubsub 32mb 8mb 60

# Latency monitoring (manual via LATENCY DOCTOR)
latency-monitor-threshold 100
```

---

## Generation steps

1. **Confirm parameters** (use case dictates persistence + memory policy).
2. **Create directory tree**.
3. **Write `docker-compose.dev.yml` and `redis.conf`** tuned per `intended_use`.
4. **Bring up**: `docker compose -f infra/redis/docker-compose.dev.yml up -d`.
5. **Verify**: `docker exec {{project-slug}}-redis redis-cli -a $REDIS_PASSWORD ping` → `PONG`.
6. **Set the connection string** in app:
   ```
   REDIS_URL=redis://:****@localhost:6379/0
   ```
7. **Wire the language client** (see `04-language-clients.md`).
8. **For BullMQ / Celery**: see [`async-and-queues/bullmq.md`](../../async-and-queues/bullmq.md) / [`async-and-queues/celery.md`](../../async-and-queues/celery.md).
9. **Schedule monitoring** (`redis-cli INFO`, slowlog, latency).
10. **Hand off** with: connection string, persistence mode, intended use case.

---

## Companion deep-dives

- [`README.md`](./README.md) — overview + use cases
- [`01-data-types-and-patterns.md`](./01-data-types-and-patterns.md) — strings, hashes, lists, sets, sorted sets, streams, hyperloglog, bitmaps; cache-aside, distributed lock, rate limit
- [`02-operations.md`](./02-operations.md) — persistence, replication, sentinel, cluster, monitoring
- [`03-language-clients.md`](./03-language-clients.md) — `redis.asyncio`, `ioredis`, common patterns + pitfalls

For specialized uses:
- Queues: [`async-and-queues/bullmq.md`](../../async-and-queues/bullmq.md), [`async-and-queues/celery.md`](../../async-and-queues/celery.md)
- Cross-service eventing: [`async-and-queues/redis-streams.md`](../../async-and-queues/redis-streams.md)
