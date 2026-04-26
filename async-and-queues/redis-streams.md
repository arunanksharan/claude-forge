# Redis Streams (cross-service eventing)

> Streams + consumer groups give you most of what you'd use Kafka for, with Redis-level ops cost.

## When Streams beat alternatives

| Need | Pick |
|------|------|
| Cross-service events, multiple consumers each at different lag | **Streams** |
| Same, plus replay from arbitrary point in history | **Streams** (or Kafka) |
| Same, plus you already have Kafka | **Kafka** |
| Single consumer, fire-and-forget | **Pub/Sub** |
| Background jobs within one service | **BullMQ** / **Celery** |

Streams are durable, ordered, support consumer groups (work distribution), and are dead simple to operate (just Redis).

## Concepts

| Term | Meaning |
|------|---------|
| **Stream** | Append-only log identified by a key (e.g. `events:user`) |
| **Entry** | A message in the stream — has an auto-generated `id` (timestamp-based) and fields |
| **Consumer group** | Named group of consumers; each entry is delivered to exactly one consumer per group |
| **Pending entries list (PEL)** | Entries delivered but not acked — for at-least-once |
| **`>`** | "give me new entries I haven't seen" (special id) |

```
Producer → XADD events:user * type signed_up user_id 123
                                   ↓
Stream "events:user":
  1730000000000-0  type=signed_up user_id=123
  1730000000123-0  type=updated user_id=123
                                   ↓
Group "service-a":  consumer-1, consumer-2 ← each gets a subset
Group "service-b":  consumer-1             ← independent of group A
```

## Producer

```python
# Python
import redis.asyncio as redis

r = redis.Redis.from_url(settings.redis_url)

# add an event
msg_id = await r.xadd("events:user", {
    "type": "signed_up",
    "user_id": str(user_id),
    "ts": str(int(time.time())),
})

# bounded-length stream — keeps last ~10000 entries
await r.xadd("events:user", {...}, maxlen=10000, approximate=True)
```

```typescript
// Node ioredis
const msgId = await redis.xadd(
  'events:user', '*',
  'type', 'signed_up',
  'user_id', userId,
  'ts', String(Date.now()),
);
```

`*` means "auto-generate ID" (millisecond timestamp + sequence). Or pass an explicit ID for replays.

## Consumer (with group)

```python
# Python
GROUP = "service-a"
CONSUMER = "consumer-1"

# create the group (idempotent — `mkstream=True` creates the stream too)
try:
    await r.xgroup_create("events:user", GROUP, id="0", mkstream=True)
except redis.exceptions.ResponseError as e:
    if "BUSYGROUP" not in str(e):
        raise

while True:
    # block waiting for new messages
    msgs = await r.xreadgroup(
        GROUP, CONSUMER,
        {"events:user": ">"},
        count=10,
        block=5000,            # 5s — then loop
    )
    if not msgs:
        continue

    for stream_name, entries in msgs:
        for msg_id, fields in entries:
            try:
                await handle_event(fields)
                await r.xack("events:user", GROUP, msg_id)
            except Exception as e:
                log.exception("handler failed", msg_id=msg_id)
                # don't ack — will retry via XCLAIM
```

```typescript
// Node ioredis
const GROUP = 'service-a';
const CONSUMER = 'consumer-1';

try {
  await redis.xgroup('CREATE', 'events:user', GROUP, '0', 'MKSTREAM');
} catch (e) {
  if (!(e as Error).message.includes('BUSYGROUP')) throw e;
}

while (true) {
  const result = await redis.xreadgroup(
    'GROUP', GROUP, CONSUMER,
    'COUNT', 10,
    'BLOCK', 5000,
    'STREAMS', 'events:user', '>',
  ) as [string, [string, string[]][]][] | null;

  if (!result) continue;

  for (const [stream, entries] of result) {
    for (const [msgId, fields] of entries) {
      try {
        await handleEvent(parseFields(fields));
        await redis.xack('events:user', GROUP, msgId);
      } catch (e) {
        logger.error({ err: e, msgId }, 'handler failed');
      }
    }
  }
}
```

## At-least-once delivery — handling failures

If a consumer crashes mid-processing, the entry stays in the **pending entries list (PEL)**. Re-deliver it via `XCLAIM` after a timeout:

```python
async def reclaim_stale_entries():
    """Move entries that have been pending for >60s to this consumer."""
    pending = await r.xpending_range(
        "events:user", GROUP,
        min="-", max="+", count=100,
        consumername=None,                # all consumers
    )
    for entry in pending:
        if entry["time_since_delivered"] > 60_000:
            await r.xclaim(
                "events:user", GROUP, CONSUMER,
                min_idle_time=60_000,
                message_ids=[entry["message_id"]],
            )
            # then process + ack
```

Run a periodic reclaimer every 30s. Pairs with **idempotent handlers** (since the same message may now be delivered twice).

## Trimming

Streams grow without bound. Trim periodically:

```python
# keep last 100k entries
await r.xtrim("events:user", maxlen=100_000, approximate=True)

# trim by time (entries older than X)
await r.xtrim("events:user", minid=f"{timestamp}-0", approximate=True)
```

`approximate=True` is much faster (uses radix tree pruning, may keep slightly more).

## Replay from a specific point

```python
# read all entries from the beginning
async for msg_id, fields in stream_iter("events:user", start="0"):
    ...

# read from a specific timestamp
async for msg_id, fields in stream_iter("events:user", start=f"{ts}-0"):
    ...
```

This is the killer feature over plain Pub/Sub. Service spins up new, replays from beginning to backfill its state.

## Schema discipline

Treat events as a public contract. Versioned shapes:

```json
{
  "type": "user.signed_up",
  "v": "1",
  "user_id": "u-123",
  "ts": "1730000000",
  "data": { "email": "...", "plan": "free" }
}
```

For non-trivial events: serialize the body as JSON in a single `data` field. Field-per-attribute works for tiny events but doesn't scale.

Bump `v` for breaking changes. Consumers handle multiple versions or fail loudly on unknown.

## Multi-stream consumer

```python
msgs = await r.xreadgroup(
    GROUP, CONSUMER,
    {"events:user": ">", "events:order": ">"},
    count=10, block=5000,
)
```

One consumer reads from multiple streams. The stream name in the response tells you which it came from.

## Operations

### Inspect

```bash
redis-cli xinfo stream events:user
redis-cli xinfo groups events:user
redis-cli xinfo consumers events:user service-a
redis-cli xpending events:user service-a
```

### Manual cleanup of pending

```bash
# delete an entry from pending after a poison message
redis-cli xack events:user service-a 1730000000-0
```

### Backups

`xrange` to dump:

```bash
redis-cli xrange events:user - + > events.dump
```

For real backup: enable Redis AOF persistence (see `databases/redis/`).

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| Stream growing unbounded → OOM | `XTRIM` periodically |
| Consumer dies, entries stuck in PEL | `XCLAIM` reclaimer process |
| Duplicate processing on crash | Make handlers idempotent |
| Forgot `mkstream=True` on `XGROUP CREATE` | Stream doesn't exist yet — `MKSTREAM` flag creates it |
| `BUSYGROUP` error on startup | Group already exists — catch and ignore |
| Slow consumer blocks the group | Add more consumers (same group, different name) |
| Lost events on Redis restart | Enable AOF + `everysec` fsync |
| `XADD` with explicit ID smaller than last | Errors — let auto-id do its job |
| Consumer reading from `0` instead of `>` | Reads everything from beginning every time — use `>` for "new only" |
| Multi-key with mixed `>` and explicit ids | Behaves oddly — use one or the other |

## When to migrate to Kafka

- **Multi-day retention** at high volume
- **Compacted topics** (latest value per key forever)
- **Strict ordering across partitions**
- **Multi-DC replication**
- **Schema registry enforcement**

For most internal eventing, Redis Streams is enough. Kafka adds real ops cost — only if you need its specific guarantees.

## Combining with BullMQ / Celery

A common pattern:

- **BullMQ / Celery** for "do this work async" within a service
- **Redis Streams** for "publish this happened, anyone interested can react"

Don't conflate them. Different shapes, different uses.
