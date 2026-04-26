# Redis Data Types & Patterns

> Strings, hashes, lists, sets, sorted sets, streams, bitmaps, hyperloglog. Plus the canonical cache / lock / rate-limit / counter patterns.

## Data types — when to use each

| Type | When |
|------|------|
| **String** | Most things — JSON blobs, counters, single values, cache entries |
| **Hash** | Object with multiple fields you read/update individually (sessions: `HGET sess:abc user_id`) |
| **List** | Insertion-order queue (LPUSH + BRPOP); not first choice — use Streams |
| **Set** | Unordered unique membership (`SADD active_users:today user_123`) |
| **Sorted Set** (ZSET) | Leaderboards, time-range indexes, priority queues |
| **Stream** | Durable log with consumer groups (replaces lists for queue use) |
| **Bitmap** | Compact boolean per-user (DAU tracking, A/B test buckets) |
| **HyperLogLog** | Approximate cardinality (e.g. unique visitors per day, ~0.8% error) |
| **Geo** | Lat/lng + radius queries (built on sorted set) |
| **Stream + Consumer Group** | At-least-once delivery; cross-service eventing — see `async-and-queues/redis-streams.md` |
| **JSON** (RedisJSON module) | When you need partial-update of structured data without ser/deser |

## Strings

```
SET user:123 '{"name":"alice","email":"alice@example.com"}' EX 300
GET user:123
DEL user:123
INCR pageviews:home          # atomic counter
INCRBY balance:abc -100
EXPIRE key 60                # seconds
TTL key                      # remaining
```

For binary or large payload, use raw strings (Redis doesn't care about content). Always set `EX` if it's cacheable.

## Hashes

```
HSET sess:abc user_id 123 last_seen 1730000000
HGET sess:abc user_id
HGETALL sess:abc
HDEL sess:abc user_id
HINCRBY counters:total user_count 1
EXPIRE sess:abc 3600
```

Use hashes when the "object" has 5+ fields and you read/update some of them independently. Saves serialization overhead vs JSON-in-string.

## Lists

```
LPUSH queue:emails '{"to":"..."}'
RPOP queue:emails
BRPOP queue:emails 0          # blocking pop, wait forever
LRANGE queue:emails 0 -1
LLEN queue:emails
```

For queues, prefer **Streams** or **BullMQ/Celery** — Lists are too primitive (no retries, no acks, no visibility).

## Sets

```
SADD online:tenant-x user_123 user_456
SREM online:tenant-x user_123
SISMEMBER online:tenant-x user_123
SINTER online:tenant-x online:tenant-y    # intersection
SCARD online:tenant-x                       # count
```

Useful for membership, deduplication, set operations.

## Sorted sets

```
ZADD leaderboard 100 user_alice
ZADD leaderboard 200 user_bob
ZINCRBY leaderboard 50 user_alice         # alice now at 150

ZREVRANGE leaderboard 0 9 WITHSCORES      # top 10
ZREVRANK leaderboard user_alice           # alice's rank
ZSCORE leaderboard user_alice             # alice's score

# range query
ZRANGEBYSCORE leaderboard 100 500
ZREMRANGEBYRANK leaderboard 0 -101        # keep only top 100
```

Sorted sets are O(log N) — fast even with millions of elements. Excellent for leaderboards, time-range indexes (score = timestamp), priority queues (score = priority).

## Streams

```
XADD events:user '*' type signed_up user_id 123     # * = auto-generate ID
XLEN events:user
XRANGE events:user - +                               # all entries
XREAD COUNT 10 STREAMS events:user 0                # from start

# consumer groups (at-least-once)
XGROUP CREATE events:user service-a 0 MKSTREAM
XREADGROUP GROUP service-a consumer-1 COUNT 10 BLOCK 5000 STREAMS events:user '>'
XACK events:user service-a 1730000000-0

XTRIM events:user MAXLEN '~' 100000     # bound stream length
```

For cross-service eventing details, see [`async-and-queues/redis-streams.md`](../../async-and-queues/redis-streams.md).

## Bitmaps

```
SETBIT dau:2026-04-26 12345 1         # user 12345 active today
GETBIT dau:2026-04-26 12345
BITCOUNT dau:2026-04-26                # how many active
BITOP AND active_2days dau:today dau:yesterday    # intersection
```

Compact: 1M users = 125KB. Great for binary per-user-per-day analytics.

## HyperLogLog

```
PFADD visitors:2026-04-26 user_123 user_456 ...
PFCOUNT visitors:2026-04-26              # approximate count, ~0.8% error, 12KB constant memory
PFMERGE visitors:week visitors:day1 visitors:day2 ...
```

Constant memory regardless of cardinality. Approximate. Use when exact count isn't critical.

## Geo

```
GEOADD shops 12.4 41.9 rome 13.4 52.5 berlin
GEORADIUS shops 12.5 41.9 100 km
GEODIST shops rome berlin km
```

Built on sorted set; native lat/lng + radius queries.

---

## Patterns

### Cache-aside (the bread-and-butter)

```python
async def get_user(id: str) -> User:
    cached = await redis.get(f"user:{id}")
    if cached:
        return User.model_validate_json(cached)

    user = await db.user.find_one({"id": id})
    if not user:
        raise NotFound()

    await redis.set(f"user:{id}", user.model_dump_json(), ex=300)
    return user

async def update_user(id: str, data: dict):
    user = await db.user.update(id, data)
    await redis.delete(f"user:{id}")     # invalidate
    return user
```

Always `ex=N` (TTL). Never `SET` a cache key without expiry.

### Stampede protection (lock around cache fill)

When a cache miss happens for a popular key, multiple requests concurrently regenerate the value (the "stampede"). Add a lock:

```python
async def get_user_protected(id: str) -> User:
    cached = await redis.get(f"user:{id}")
    if cached:
        return User.model_validate_json(cached)

    # try acquire lock
    lock_key = f"lock:user:{id}"
    if await redis.set(lock_key, "1", nx=True, ex=10):
        try:
            user = await db.user.find_one({"id": id})
            await redis.set(f"user:{id}", user.model_dump_json(), ex=300)
            return user
        finally:
            await redis.delete(lock_key)
    else:
        # someone else is filling; wait + retry
        await asyncio.sleep(0.1)
        return await get_user_protected(id)
```

Or use a probabilistic early refresh — cache returns "almost-stale" entries to a small fraction of requests, who refresh while others see the cached value.

### Distributed lock (single-instance)

```python
import secrets

async def with_lock(key: str, ttl_ms: int, coro):
    token = secrets.token_hex(16)
    acquired = await redis.set(f"lock:{key}", token, nx=True, px=ttl_ms)
    if not acquired:
        raise LockNotAcquired()
    try:
        return await coro
    finally:
        # safe release with Lua — only delete if we still own it
        await redis.eval(
            """if redis.call("get", KEYS[1]) == ARGV[1] then
                  return redis.call("del", KEYS[1])
               else return 0 end""",
            1, f"lock:{key}", token,
        )
```

The token + Lua release prevents a stale lock from being released by someone else.

For multi-instance Redis, use **Redlock** (`redlock` library) — uses majority quorum across N instances.

### Rate limiting — fixed window

```python
async def rate_limit(key: str, limit: int, window: int) -> bool:
    """Returns True if allowed, False if over limit."""
    count = await redis.incr(f"rate:{key}")
    if count == 1:
        await redis.expire(f"rate:{key}", window)
    return count <= limit
```

Edge case: doesn't smoothly enforce — first request of a window starts the clock, so two windows of 60s × 10 reqs = 20 reqs in 1 second is possible at the boundary.

### Rate limiting — sliding window log

```python
async def sliding_rate_limit(key: str, limit: int, window_s: int) -> bool:
    now = time.time()
    pipe = redis.pipeline()
    pipe.zremrangebyscore(f"rate:{key}", 0, now - window_s)
    pipe.zadd(f"rate:{key}", {f"{now}:{secrets.token_hex(4)}": now})
    pipe.zcard(f"rate:{key}")
    pipe.expire(f"rate:{key}", window_s)
    _, _, count, _ = await pipe.execute()
    return count <= limit
```

Smooth + accurate. Slightly more memory + ops.

### Counters

```python
await redis.incr("stats:active_users")
count = int(await redis.get("stats:active_users"))
```

Atomic. For analytics-grade counters: persist to Postgres periodically, treat Redis as the hot accumulator.

### Pub/Sub

```python
# publisher
await redis.publish("notifications", json.dumps(payload))

# subscriber
sub = redis.pubsub()
await sub.subscribe("notifications")
async for msg in sub.listen():
    if msg["type"] == "message":
        handle(msg["data"])
```

**At-most-once** — if no subscriber connected when published, gone. For durable pub/sub, use **Streams**.

### Session storage

```python
await redis.hset(f"sess:{sess_id}", mapping={
    "user_id": user_id,
    "last_seen": int(time.time()),
})
await redis.expire(f"sess:{sess_id}", 3600)

# read on each request
sess = await redis.hgetall(f"sess:{sess_id}")
```

### Idempotency keys

```python
async def handle_payment(idempotency_key: str, ...):
    if not await redis.set(f"idem:{idempotency_key}", "1", nx=True, ex=86400):
        # already processed
        return await get_existing_result(idempotency_key)

    result = await process_payment(...)
    await redis.set(f"idem:{idempotency_key}:result", json.dumps(result), ex=86400)
    return result
```

24h TTL = client has 24h to retry safely. Stripe-style.

### Caching with negative results

If "lookup returns None" is expensive, cache that too:

```python
async def lookup_address(zip_code: str) -> Address | None:
    cached = await redis.get(f"addr:{zip_code}")
    if cached == "__none__":
        return None
    if cached:
        return Address.model_validate_json(cached)

    addr = await external_api.lookup(zip_code)
    if addr:
        await redis.set(f"addr:{zip_code}", addr.model_dump_json(), ex=86400)
    else:
        await redis.set(f"addr:{zip_code}", "__none__", ex=300)   # shorter TTL on neg cache
    return addr
```

## Key naming conventions

```
{namespace}:{resource}:{id}[:{aspect}]

user:123:profile
user:123:permissions
session:abc-def-123
ratelimit:user:123:login
queue:emails
lock:invoice-process:42
```

- `:` as separator (Redis convention)
- Namespace by service in shared Redis instances
- Avoid spaces, weird chars
- Keys live in memory — keep them short

## Pipelines + transactions

```python
# pipeline = batch ops in one round-trip (no atomicity)
async with redis.pipeline(transaction=False) as pipe:
    pipe.incr("counter:a")
    pipe.incr("counter:b")
    pipe.set("foo", "bar")
    results = await pipe.execute()

# transaction = MULTI/EXEC, atomic
async with redis.pipeline(transaction=True) as pipe:
    pipe.set("a", 1)
    pipe.set("b", 2)
    await pipe.execute()
```

Pipeline saves N round-trips → 1 round-trip. Big perf win for batch ops.

Transactions are atomic but Redis's transaction model is weaker than RDBMS. Use Lua for complex atomic logic.

## Lua scripts (server-side atomic logic)

```python
INC_AND_LIMIT = """
local count = redis.call('INCR', KEYS[1])
if count == 1 then
  redis.call('EXPIRE', KEYS[1], ARGV[1])
end
if count > tonumber(ARGV[2]) then
  return 0
end
return 1
"""

allowed = await redis.eval(INC_AND_LIMIT, 1, "rate:user:123", 60, 10)
```

Atomic execution server-side. No race window between commands. Faster than multiple round-trips.

## TTL discipline

| Resource | TTL |
|----------|-----|
| Cache (DB read-through) | 60–300s |
| Session | 30min–24h |
| Rate limit window | 60s |
| Distributed lock | a few seconds beyond expected work duration |
| Idempotency key | 24h |
| Negative cache | 30s–5min (shorter than positive) |
| Pub/Sub data | doesn't apply (no storage) |
| Stream entries | application-defined (XTRIM) |

**Always set TTL on cache keys.** Otherwise Redis fills up.

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| `KEYS *` in production | Blocks the server — use `SCAN` |
| Missing TTL → memory fills | Always `EX`/`PX` |
| Pub/Sub for durable messaging | Use Streams |
| Lock released by wrong owner | UUID token + Lua release |
| Slow command blocks server | Redis is single-threaded; long Lua/SCAN hurts everyone |
| Hot key (single key with all writes) | Shard via consistent hashing or rethink design |
| Cache stampede on miss | Stampede lock or probabilistic refresh |
| Pipeline forgotten → many round-trips | Use `pipeline()` for batches |
| Connection blocked (BLPOP, SUBSCRIBE on shared connection) | Use a separate connection (`redis.duplicate()`) |
| Redis CPU 100% | `SLOWLOG GET 10` to find slow commands |
| Wrong DB index used | Pin DB number in connection string `redis://...:6379/2` |
| Persistence enabled on cache | Wastes IO + memory; disable for pure cache |
| Memory policy `noeviction` on cache | Writes start failing when full; use `allkeys-lru` for cache |
