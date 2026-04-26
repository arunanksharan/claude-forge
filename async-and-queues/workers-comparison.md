# Background Workers — Decision Matrix

> Celery vs BullMQ vs Redis Streams vs RabbitMQ vs Kafka. Pick the right one and stop overthinking.

## The flowchart

```
Need to run code outside the request cycle?
│
├── In-process, fire-and-forget, < 5s, ok to lose? → BackgroundTasks (FastAPI) / setImmediate (Node)
│
├── Heavy / scheduled / retry-heavy work in Python? → Celery (Redis broker)
│       (or arq if you want async-native, lighter)
│
├── Same in Node? → BullMQ
│
├── Cross-language pub/sub with replay? → Redis Streams (consumer groups)
│
├── Cross-language pub/sub without replay? → NATS
│
├── Massive scale, replay, retention, multiple consumers each at different lag? → Kafka
│
└── Cross-language with strict messaging semantics, transactions, complex routing? → RabbitMQ
```

## Side-by-side comparison

| | **BackgroundTasks** | **Celery** | **arq** | **BullMQ** | **Redis Streams** | **RabbitMQ** | **Kafka** |
|---|---|---|---|---|---|---|---|
| Language | Py / Node | Python | Python (async) | Node | Any | Any | Any |
| Broker | none | Redis/RabbitMQ | Redis | Redis | Redis | RabbitMQ | Kafka |
| Persistence | no | yes | yes | yes | yes | yes | yes |
| Retries | no | yes | yes | yes | manual | yes | manual |
| Scheduling | no | beat | cron jobs | repeat opts | manual | (delayed plugin) | no |
| Multi-consumer fan-out | no | no | no | no | yes (groups) | yes (exchanges) | yes (consumer groups) |
| Replay | no | no | no | no | yes | no | yes (long retention) |
| Ops weight | none | low | low | low | low | medium | high |
| Use case | tiny | classic Python | greenfield Python | classic Node | cross-svc events | enterprise integration | log streams / big scale |

## Decision narratives

### Python service, want to send a welcome email after signup

`BackgroundTasks` for fire-and-forget:

```python
@router.post("/users")
async def create_user(payload, bg: BackgroundTasks, mailer):
    user = await service.register(payload)
    bg.add_task(mailer.send_welcome, user.email)
    return user
```

If the email failing is unacceptable, or you need retries, or it's >5s → **Celery**.

### Python service, billing job that runs nightly + retries on failure

**Celery + Redis broker + beat**:

```python
celery_app.conf.beat_schedule = {
    "nightly-billing": {
        "task": "...billing.charge_subscriptions",
        "schedule": crontab(hour=2, minute=0),
    },
}

@celery_app.task(bind=True, autoretry_for=(Exception,), max_retries=5, retry_backoff=True)
def charge_subscriptions(self):
    ...
```

See `celery.md`.

### Python service, modern async-first, lighter ops

**arq**:

```python
class WorkerSettings:
    functions = [send_welcome]
    cron_jobs = [cron(charge_subscriptions, hour={2})]
    redis_settings = RedisSettings.from_dsn(env.REDIS_URL)
```

Less mature than Celery but native async + simpler. Good for greenfield.

### Node/Nest service, any background work

**BullMQ** (`@nestjs/bullmq` for Nest, plain `bullmq` for Express):

```typescript
@Processor('emails')
export class EmailProcessor extends WorkerHost {
  async process(job: Job) {
    if (job.name === 'welcome') return this.sendWelcome(job.data);
  }
}

// add a job
await emailsQueue.add('welcome', { userId }, { jobId: `welcome:${userId}` });
```

See `bullmq.md`.

### Want to publish "user.signed_up" so 5 services can each react

**Redis Streams** with consumer groups (lighter) or **Kafka** (heavier, more durable):

```python
# producer
await redis.xadd("events:user", {"type": "signed_up", "user_id": user_id})

# consumer in service A
await redis.xgroup_create("events:user", "service-a", id="0", mkstream=True)
while True:
    msgs = await redis.xreadgroup("service-a", "consumer-1", {"events:user": ">"}, count=10, block=5000)
    for stream, entries in msgs:
        for msg_id, fields in entries:
            handle(fields)
            await redis.xack("events:user", "service-a", msg_id)
```

See `redis-streams.md`.

### Need to coordinate distributed transactions / saga pattern

**Temporal**, not a queue. See `backend/fastapi/05-async-and-celery.md` for the case where you outgrow queues.

## Anti-patterns

### Rolling your own queue with Redis lists

Don't. `LPUSH` + `BRPOP` looks easy until you need:

- Retries on failure
- Visibility into the queue (admin UI)
- Delayed jobs
- Concurrency limits
- Dead-letter queue

BullMQ / Celery already solved all of these. Use them.

### Putting CPU-heavy work on the request thread

If a request triggers something CPU-bound (>500ms), push it to a worker. Otherwise:

- Other requests queue up behind it
- The web server's worker pool gets exhausted
- Latency p99 explodes

### Background tasks for things you can't lose

`BackgroundTasks` runs in-process. Crash → lost. For "must complete" work, use a queue with retries.

### Ignoring idempotency

With at-least-once delivery (which most queues offer), tasks may run more than once. **Make tasks idempotent.** Otherwise you'll send duplicate emails / charge twice.

Patterns:

1. **Natural idempotency**: "send welcome if not already sent" — check before doing
2. **Idempotency key**: caller passes a UUID; task stores "I handled this key"
3. **State machine**: only act if state is the expected `from` state

### One queue for everything

Mix slow (`generate-pdf`) and fast (`send-email`) jobs and the slow ones starve the fast ones. Always **split queues by SLA** and run dedicated workers per queue.

## What about Temporal / Inngest / Hatchet / Trigger.dev?

These are "durable execution" / workflow engines, not just queues:

| Pick | When |
|------|------|
| **Temporal** | Multi-step workflows where each step has retries + state, complex business processes |
| **Inngest** / **Trigger.dev** | Same idea, hosted, event-triggered, easier setup |
| **Hatchet** | Self-hostable Temporal-lite alternative |

If you find yourself building a saga in Celery/BullMQ — passing state between tasks via Redis, hand-rolling resumption logic — switch to a durable execution engine. The complexity payoff is huge.

For most apps, you don't need them. Celery/BullMQ + good idempotency is enough.

## What about message buses (Kafka / NATS / RabbitMQ)?

Different category — these are about **decoupling services**, not about offloading async work from a request:

| | Job queue (Celery/BullMQ) | Message bus (Kafka/NATS) |
|---|---|---|
| Producer | Knows the consumer (queue) | Doesn't know consumers |
| Consumer | Owned by app | Anyone can subscribe |
| Replay | No | Often yes (Kafka) |
| Ordering | Per-queue | Per-partition (Kafka) |
| Use | Background work | Inter-service eventing |

A real system often uses both:

- **Job queue** to handle "send this email" within a service
- **Message bus** to publish "user.signed_up" event that other services react to

Don't conflate them.

## Specifics by ecosystem

### Python ecosystem picks

- **Default for anything Python**: Celery + Redis broker. Mature, ecosystem-rich.
- **Lighter, async-native**: arq.
- **Don't use**: RQ (subset of Celery, less maintained), Huey (good but smaller).

### Node ecosystem picks

- **Default**: BullMQ.
- **Don't use**: Bull v3 (deprecated), Bee-Queue (smaller community), Agenda (MongoDB-backed; only if you're not on Redis).

### Cross-language

- **Light**: Redis Streams + consumer groups. Operationally trivial, gets you 80% of Kafka.
- **Heavy**: Kafka. Real ops investment. Pick when scale or replay demands it.
- **Routing-rich**: RabbitMQ. Topic exchanges, headers, dead-letter exchanges.

## Common pitfalls (across all)

| Pitfall | Fix |
|---------|-----|
| At-most-once vs at-least-once confusion | Default = at-least-once → make tasks idempotent |
| Tasks "stuck" with no logs | Check broker connection, queue name, worker has the task imported |
| Workers OOM | Lower concurrency, restart periodically (`max_tasks_per_child`) |
| Slow shutdown loses jobs | Set `kill_timeout` long enough for graceful shutdown |
| Worker can't connect to broker after a deploy | Networking issue — verify Redis URL reachable from worker container |
| Duplicate beat / scheduler | Run exactly one beat / scheduler instance |
| Long jobs block fast queues | Split by SLA |
| Retries hammer the downstream | Use exponential backoff with jitter |
| No observability | Set up Flower (Celery), Bull Board (BullMQ), or just integrate OTel |
| Failed jobs disappear | Configure dead-letter queue / `removeOnFail: false` for inspection |
