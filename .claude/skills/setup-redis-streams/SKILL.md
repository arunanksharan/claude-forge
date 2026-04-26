---
name: setup-redis-streams
description: Use when the user wants to set up cross-service event publishing/consumption with Redis Streams + consumer groups (lighter alternative to Kafka). Covers producer, consumer, pending entry reclaiming, trimming, replay. Triggers on "redis streams", "cross-service events", "event bus without kafka", "publish events".
---

# Set Up Redis Streams (claudeforge)

Follow `async-and-queues/redis-streams.md`. Use this when you need cross-service eventing (multiple consumers each at different lag) but don't want to operate Kafka.

Steps:

1. **Confirm with user**:
   - Use case: which service produces events, which consume? (Sketch out one stream + 1-3 consumer groups.)
   - Stack: Python and/or Node?
   - Already have Redis? Need persistence (AOF) for the events.
2. **Producer side**:
   - Python: `await r.xadd("events:user", {"type": "signed_up", "user_id": str(uid)}, maxlen=100_000, approximate=True)`
   - Node: `await redis.xadd('events:user', '*', 'type', 'signed_up', 'user_id', uid)`
   - Schema discipline: include `type`, `v` (version), and `data` JSON for non-trivial events
3. **Consumer side**:
   - Create the group once (idempotent, catch BUSYGROUP):
     ```python
     try: await r.xgroup_create("events:user", "service-a", id="0", mkstream=True)
     except redis.exceptions.ResponseError as e:
         if "BUSYGROUP" not in str(e): raise
     ```
   - Loop reading new entries: `XREADGROUP GROUP service-a consumer-1 COUNT 10 BLOCK 5000 STREAMS events:user >`
   - Process each entry, then `XACK events:user service-a <msg_id>` on success
   - Don't ack on failure → entry stays pending → retried via XCLAIM
4. **Reclaim stuck pending entries** (separate periodic task):
   - List pending: `XPENDING events:user service-a - + 100`
   - For entries with `time_since_delivered > 60s`: `XCLAIM events:user service-a consumer-1 60000 <msg_ids>`
   - Then process + ack
5. **Trim periodically** (every hour or so): `XTRIM events:user MAXLEN ~ 100000` (the `~` is approximate, much faster)
6. **Idempotency**: handlers must be idempotent (XCLAIM may double-deliver)
7. **Replay**: for backfill, set start to `0` instead of `>` and read from the beginning
8. **Observability**:
   - Track `XLEN events:user` (stream depth)
   - Track pending count per group (`XPENDING ... | length`)
   - Add traces around producer + consumer for end-to-end latency
9. **Verify**: produce a test event in service A, consume in service B, ack it, confirm pending list is empty.

If you outgrow Streams: switch to Kafka (real ops cost) when you need multi-day retention, schema registry, or compaction.
