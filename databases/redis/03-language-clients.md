# Redis Language Clients

> Connection pooling, async patterns, pipelines, pub/sub, cluster-awareness per language.

## Driver picks

| Language | Driver | Notes |
|----------|--------|-------|
| **Python (async)** | `redis` (with `redis.asyncio`) | Official, well-maintained |
| **Python (high-perf)** | `coredis` | Faster, fully async, fewer features |
| **Node** | `ioredis` | More features than `node-redis` |
| **Node (alt)** | `node-redis` (v5+ has good API) | OK if you prefer official |
| **Go** | `redis/go-redis/v9` | Standard |
| **Java** | `lettuce` (async) or `jedis` (sync) | Lettuce is the modern pick |
| **Rust** | `redis-rs` + `bb8-redis` for pool | |

## Python — `redis.asyncio`

```python
import redis.asyncio as redis

# pool — share across the app
pool = redis.ConnectionPool.from_url(
    settings.redis_url,
    max_connections=20,
    socket_keepalive=True,
    socket_connect_timeout=5,
    socket_timeout=10,
    health_check_interval=30,
    decode_responses=True,           # auto-decode bytes to str
)
r = redis.Redis(connection_pool=pool)

# basic
await r.set("user:1", "alice", ex=300)
val = await r.get("user:1")        # 'alice' (str if decode_responses=True)

# hash
await r.hset("sess:abc", mapping={"user_id": "123", "last_seen": str(int(time.time()))})
sess = await r.hgetall("sess:abc")   # {'user_id': '123', 'last_seen': '...'}

# pipeline (batch — one round-trip)
async with r.pipeline(transaction=False) as pipe:
    pipe.incr("c:a")
    pipe.incr("c:b")
    pipe.set("foo", "bar")
    results = await pipe.execute()

# transaction
async with r.pipeline(transaction=True) as pipe:
    pipe.set("a", 1)
    pipe.set("b", 2)
    await pipe.execute()

# pub/sub (separate connection)
sub = r.pubsub()
await sub.subscribe("notifications")
async for msg in sub.listen():
    if msg["type"] == "message":
        handle(msg["data"])

# cleanup
await pool.disconnect()
```

For BullMQ-compat (BullMQ requires `null` for `maxRetriesPerRequest`), use the Node `ioredis` instead — Python uses Celery, not BullMQ.

For Celery integration, see [`async-and-queues/celery.md`](../../async-and-queues/celery.md).

## Python — Sentinel + Cluster

```python
# Sentinel
from redis.asyncio.sentinel import Sentinel

sentinel = Sentinel([("sent-1", 26379), ("sent-2", 26379), ("sent-3", 26379)],
                    socket_timeout=0.1, password=PASSWORD)
master = sentinel.master_for("mymaster", socket_timeout=0.1, password=PASSWORD)

# Cluster
from redis.asyncio.cluster import RedisCluster

cluster = RedisCluster(host="cluster-node-1", port=6379, password=PASSWORD,
                       decode_responses=True)
await cluster.set("user:123", "alice")
```

## Node — `ioredis`

```typescript
import IORedis from 'ioredis';

export const redis = new IORedis(process.env.REDIS_URL!, {
  maxRetriesPerRequest: 3,           // null for BullMQ
  enableReadyCheck: true,
  lazyConnect: false,
  connectTimeout: 5_000,
  retryStrategy: (times) => Math.min(times * 50, 2000),
});

// basic
await redis.set('user:1', 'alice', 'EX', 300);
const val = await redis.get('user:1');

// hash
await redis.hset('sess:abc', { user_id: '123', last_seen: String(Date.now()) });
const sess = await redis.hgetall('sess:abc');

// pipeline
const results = await redis.pipeline()
  .incr('c:a')
  .incr('c:b')
  .set('foo', 'bar')
  .exec();

// transaction (MULTI/EXEC)
const txResults = await redis.multi()
  .set('a', 1)
  .set('b', 2)
  .exec();

// pub/sub — separate connection
const sub = redis.duplicate();
await sub.subscribe('notifications');
sub.on('message', (channel, message) => {
  console.log(channel, message);
});

// graceful shutdown
process.on('SIGTERM', async () => {
  await redis.quit();
  process.exit(0);
});
```

For BullMQ:

```typescript
const connection = new IORedis(REDIS_URL, {
  maxRetriesPerRequest: null,        // BullMQ requirement
  enableReadyCheck: false,
});
```

See [`async-and-queues/bullmq.md`](../../async-and-queues/bullmq.md).

### `ioredis` Sentinel + Cluster

```typescript
// Sentinel
const sentinelRedis = new IORedis({
  sentinels: [
    { host: 'sent-1', port: 26379 },
    { host: 'sent-2', port: 26379 },
    { host: 'sent-3', port: 26379 },
  ],
  name: 'mymaster',
  password: REDIS_PASSWORD,
});

// Cluster
import { Cluster } from 'ioredis';
const cluster = new Cluster(
  [
    { host: 'node-1', port: 6379 },
    { host: 'node-2', port: 6379 },
  ],
  { redisOptions: { password: REDIS_PASSWORD } },
);
```

## Go — `go-redis`

```go
import (
    "context"
    "github.com/redis/go-redis/v9"
)

rdb := redis.NewClient(&redis.Options{
    Addr:     "localhost:6379",
    Password: os.Getenv("REDIS_PASSWORD"),
    DB:       0,
    PoolSize: 20,
})
defer rdb.Close()

// basic
err := rdb.Set(ctx, "user:1", "alice", 5*time.Minute).Err()
val, err := rdb.Get(ctx, "user:1").Result()

// pipeline
pipe := rdb.Pipeline()
incrA := pipe.Incr(ctx, "c:a")
incrB := pipe.Incr(ctx, "c:b")
_, err = pipe.Exec(ctx)
fmt.Println(incrA.Val(), incrB.Val())

// transaction with optimistic lock (WATCH)
err = rdb.Watch(ctx, func(tx *redis.Tx) error {
    n, err := tx.Get(ctx, "counter").Int()
    if err != nil && err != redis.Nil { return err }

    _, err = tx.TxPipelined(ctx, func(pipe redis.Pipeliner) error {
        pipe.Set(ctx, "counter", n+1, 0)
        return nil
    })
    return err
}, "counter")
```

## Connection string forms

```
# basic
redis://:password@host:6379/0

# TLS
rediss://:password@host:6380/0

# Sentinel (driver-specific syntax — see above)
# Cluster (driver-specific)
```

The path component (`/0`) is the database index (0-15 by default). For shared Redis with multiple apps, use different DB numbers OR namespaced keys (preferred — gives flexibility for migration to Cluster which only has DB 0).

## Reconnection + retry

Each driver handles disconnects differently. General principles:

- **Auto-reconnect** is the default in modern drivers
- **Exponential backoff** with jitter for retry strategy
- **Don't retry forever** — circuit-break after N failures
- **Idempotent commands** (SET, GET) safe to retry; **non-idempotent** (LPUSH, INCR) need care

For BullMQ / Celery, the queue libraries handle their own retry logic — you don't need to.

## Health check

```python
async def health() -> dict:
    try:
        ok = await r.ping()
        return {"status": "ok", "ping": ok}
    except Exception as e:
        return {"status": "degraded", "error": str(e)}
```

```typescript
async function health() {
  try {
    const ok = await redis.ping();
    return { status: 'ok', ping: ok };
  } catch (e) {
    return { status: 'degraded', error: (e as Error).message };
  }
}
```

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| New connection per request | Use a pool / shared client |
| Missing `decode_responses=True` (Python) | Get bytes back, expected str |
| Pipeline forgotten → many round-trips | Use `pipeline()` for batches |
| Pub/Sub on same connection as commands | Separate connection (`duplicate()`) |
| Long blocking BLPOP on shared connection | Separate connection |
| `EXPIRE` after `SET` (race) | Use `SET ... EX N` or pipeline together |
| Different DB numbers across services not isolated enough | Use ACLs or separate Redis instances |
| TLS errors with self-signed | `tls: { rejectUnauthorized: false }` (dev only) |
| Memory creeping up despite TTLs | TTL doesn't apply to keys without explicit expire; audit |
| Stuck waiting on subscribe (no signal) | Set `socket_keepalive=True`; check network |
| `ConnectionResetError` under load | Connection pool too small or server-side limit hit |
| Slow Lua script blocks server | Keep scripts short; profile with SLOWLOG |
