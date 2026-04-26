# Redis — claudeforge guide

> Cache, ephemeral state, queues, pub/sub, rate limiting. Patterns and pitfalls.

## What Redis is for

| Use | Pattern |
|-----|---------|
| **Cache** | `SET key value EX 300` — short TTL |
| **Session store** | `HSET sess:abc user_id 123; EXPIRE sess:abc 3600` |
| **Rate limit** | `INCR + EXPIRE`, or `Redis.call('CL.THROTTLE', ...)` for token bucket |
| **Distributed lock** | `SET key uuid NX EX 30` + Lua release script (or Redlock) |
| **Job queue** | Use **BullMQ** (Node) or **Celery + Redis** (Python). Don't roll your own. |
| **Streams (pub/sub with replay)** | `XADD` / `XREADGROUP` — see `../async-and-queues/redis-streams.md` |
| **Real-time pub/sub** | `PUBLISH` / `SUBSCRIBE` — fire-and-forget |
| **Counters** | `INCR`, `INCRBY` — atomic |
| **Sorted sets (leaderboards)** | `ZADD`, `ZRANGE` |

What Redis is **not** for:

- Long-term storage — it's a cache; assume data can be lost
- Anything where you need joins or complex queries — Postgres
- Anything where you need exact-once semantics by default — use Streams + groups

## Versions + hosting

- **Redis 7.x** for new projects
- Hosted: **Upstash** (serverless), **Redis Cloud**, **AWS ElastiCache**
- Self-hosted: simple — a Docker container or `apt install redis-server`

## Memory configuration

```
maxmemory 1gb
maxmemory-policy allkeys-lru
```

Without these, Redis OOMs at full memory. `allkeys-lru` evicts least-recently-used keys when memory's full — sensible for cache use.

For data you can't lose (queue jobs, sessions): pin them with `noeviction` policy or use a dedicated Redis instance with persistence.

## Persistence

Two flavors:

| Mode | Behavior |
|------|----------|
| **RDB** (snapshots) | Periodic dumps. Fast restart. May lose minutes of data. |
| **AOF** (append-only file) | Every write logged. Slower, but recoverable to ~1s ago. |

For cache: **RDB only** is fine (data is regeneratable).
For queues / sessions: **RDB + AOF**.
For "I literally can't lose anything": don't use Redis — use Postgres.

## Drivers

| Lang | Driver |
|------|--------|
| Node | **ioredis** (most-used, robust) — or `redis` (official, modern) |
| Python | **redis-py** with `redis.asyncio` (async) |
| Both have type-safe wrappers; use the official tooling, not third-party clones |

## Connection pooling

```typescript
// ioredis
import IORedis from 'ioredis';
export const redis = new IORedis({
  host: env.REDIS_HOST,
  port: env.REDIS_PORT,
  maxRetriesPerRequest: 3,
  retryStrategy: (times) => Math.min(times * 50, 2000),
  enableReadyCheck: true,
});
```

```python
# redis-py async
from redis.asyncio import Redis, ConnectionPool

pool = ConnectionPool.from_url(settings.redis_url, max_connections=20)
redis = Redis(connection_pool=pool)
```

**Reuse the connection (or pool).** Don't open a new connection per request.

For BullMQ specifically: `maxRetriesPerRequest: null` (BullMQ handles retries itself).

## Patterns

### Cache-aside

```typescript
async function getUser(id: string): Promise<User> {
  const cached = await redis.get(`user:${id}`);
  if (cached) return JSON.parse(cached);

  const user = await db.user.findUnique({ where: { id } });
  if (!user) throw new NotFound();

  await redis.set(`user:${id}`, JSON.stringify(user), 'EX', 300);
  return user;
}

// invalidate on write
async function updateUser(id: string, data: any) {
  const user = await db.user.update({ where: { id }, data });
  await redis.del(`user:${id}`);
  return user;
}
```

Always `EX` (TTL) — never set a key without one in cache use. Otherwise you accumulate keys forever.

### Distributed lock (single instance)

```typescript
async function withLock<T>(key: string, ttlMs: number, fn: () => Promise<T>): Promise<T> {
  const token = crypto.randomUUID();
  const acquired = await redis.set(`lock:${key}`, token, 'NX', 'PX', ttlMs);
  if (!acquired) throw new Error('lock not acquired');

  try {
    return await fn();
  } finally {
    // safe release with Lua script — only delete if we still own it
    const releaseScript = `
      if redis.call("get", KEYS[1]) == ARGV[1] then
        return redis.call("del", KEYS[1])
      else
        return 0
      end
    `;
    await redis.eval(releaseScript, 1, `lock:${key}`, token);
  }
}
```

`SET NX` is atomic. The token + Lua release prevents a delayed task from releasing a lock taken by someone else.

For multi-instance Redis, use **Redlock** (`redlock` library). For single-instance, the above is fine.

### Rate limiting (sliding window)

```typescript
const KEY = `rate:${userId}`;
const WINDOW = 60;
const LIMIT = 10;

const count = await redis.incr(KEY);
if (count === 1) await redis.expire(KEY, WINDOW);
if (count > LIMIT) throw new Error('rate limited');
```

This is a **fixed window**, not sliding. Good enough for most cases. For sliding, use a sorted set:

```typescript
const now = Date.now();
const windowStart = now - 60_000;

await redis.zremrangebyscore(KEY, 0, windowStart);     // expire old
await redis.zadd(KEY, now, `${now}-${crypto.randomUUID()}`);
await redis.expire(KEY, 60);

const count = await redis.zcard(KEY);
if (count > LIMIT) throw new Error('rate limited');
```

For high-precision: use a Redis module like RedisCell.

### Distributed counter

```typescript
await redis.incr(`stats:active_users`);
const count = await redis.get(`stats:active_users`);
```

Atomic, fast. For analytics-grade counters, persist to Postgres periodically (every minute or on shutdown).

### Pub/Sub (fire-and-forget)

```typescript
// publisher
await redis.publish('channel:notifications', JSON.stringify(payload));

// subscriber
const sub = redis.duplicate();    // separate connection — pub/sub blocks the conn
await sub.subscribe('channel:notifications');
sub.on('message', (channel, msg) => { ... });
```

Pub/Sub is **at-most-once** — if no subscriber is connected when you publish, the message is gone. For durable messaging, use **Streams**.

### Sorted sets (leaderboard)

```typescript
await redis.zadd('leaderboard', score, userId);
const top10 = await redis.zrevrange('leaderboard', 0, 9, 'WITHSCORES');
const myRank = await redis.zrevrank('leaderboard', userId);
```

`ZADD` is O(log N). Excellent for leaderboards / top-K queries.

## Key naming conventions

```
{namespace}:{resource}:{id}[:{aspect}]

user:123:profile
session:abc-def-123
ratelimit:user:123:login
queue:emails
lock:invoice-process:42
```

- Use `:` as separator (Redis convention; `HSCAN`/`SCAN` glob matching works on it)
- Namespace prefix by service name in shared Redis instances
- Avoid spaces, weird chars
- Don't use very long keys — they're stored in memory

## TTL discipline

| Resource | TTL |
|----------|-----|
| Cache (db read-through) | 60–300s |
| Session | 30min–24h |
| Rate limit window | 60s |
| Lock | a few seconds beyond expected work duration |
| Idempotency key | 24h |
| Pub/Sub data | doesn't apply (no storage) |
| Stream entries | application-defined (XTRIM) |

**Always set TTL on cache keys.** Otherwise Redis fills up.

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| `KEYS *` in production | Blocks the server — use `SCAN` instead |
| Missing TTL → memory fills up | Always `EX` / `PX` / `EXPIRE` |
| Using Pub/Sub for durable messaging | Use Streams |
| Lock released by wrong owner | Use UUID token + Lua release script |
| Slow command blocks Redis | Redis is single-threaded — long Lua scripts and big SCANs hurt everyone |
| Hot key (single key with all the writes) | Shard via consistent hashing, or use a different design |
| Cache stampede on miss | Use `SETNX` lock around the cache-fill, or cache the negative result briefly |
| Multiple cache keys for one entity | Pick one canonical key shape; document it |
| Connection pool too small | Increase `maxClients` in your driver |
| Forgot to use `pipeline()` for batches | One round-trip vs N round-trips — big perf win |
| Redis CPU 100% | Find slow commands with `SLOWLOG GET 10`; review use of long Lua scripts and large SCANs |
| Blocking commands on shared connection | Use `redis.duplicate()` for `BLPOP`, subscribe, etc. |

## Tools

- **redis-cli** — command-line client
- **redis-commander** / **RedisInsight** — web UIs
- **MEMORY DOCTOR** — built-in diagnostics
- **SLOWLOG GET** — slow query inspection
- **CLIENT LIST** — see who's connected
- **MONITOR** — live command stream (impacts performance — debug only)

## Beyond Redis: alternatives

| Use case | Alternative |
|----------|-------------|
| Pub/Sub at scale | **NATS** (lighter, stateless) or **Kafka** (durable, replay) |
| Persistent queue | **BullMQ on Redis** is fine for most cases; **RabbitMQ** for cross-language |
| Cache at huge scale | **Memcached** if you only need plain GET/SET (simpler, faster for that) |
| Vector search | **Qdrant** (see `../qdrant/`) — Redis has vectors but it's a side feature |
| Time-series at scale | **InfluxDB**, **TimescaleDB** |
