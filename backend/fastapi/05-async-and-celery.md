# Async, Background Tasks, Celery

> When to use FastAPI's built-in background tasks vs Celery vs arq vs Redis Streams. With code for each.

## Decision: which background runner

| Workload | Pick |
|----------|------|
| "Send a welcome email after signup" — fire-and-forget, ok to lose on restart | **`BackgroundTasks`** (built into FastAPI) |
| Heavy work, retries, scheduling, multiple workers, observability | **Celery** with Redis or RabbitMQ broker |
| Same as Celery but you want async-native, smaller deps | **arq** (Redis-only, async) |
| Cross-service eventing, ordered processing per stream key | **Redis Streams** with consumer groups (covered in `async-and-queues/redis-streams.md`) |
| Massive scale, replay, long retention, multiple consumers | **Kafka** (significant ops cost — only if you really need it) |

For 90% of apps, the answer is **Celery**. arq is great if you're greenfield and want async-native and lighter ops. Skip RQ — Celery is the more battle-tested superset.

## FastAPI BackgroundTasks (the simple case)

```python
from fastapi import BackgroundTasks


@router.post("/users", response_model=UserResponse)
async def create_user(
    payload: UserCreate,
    bg: BackgroundTasks,
    service: UserService = Depends(get_user_service),
    mailer: Mailer = Depends(get_mailer),
):
    user = await service.register(email=payload.email, password=payload.password)
    bg.add_task(mailer.send_welcome, to=user.email, name=user.email)
    return UserResponse.model_validate(user)
```

`BackgroundTasks` runs **after the response is sent**, in the same process. Best for:

- Sending an email
- Logging an audit event
- Cache invalidation
- Anything that takes <2s and is ok to lose if the server restarts

**Don't use BackgroundTasks for:**

- Tasks longer than ~5 seconds — they delay graceful shutdown
- Anything you need retry semantics on
- Anything that should run on a different machine from the API
- Anything you need a result for

## Celery setup

### Install + structure

```toml
# pyproject.toml
dependencies = [
    "celery[redis]>=5.4",
    "redis>=5.2",
]
```

```
src/{{project-slug}}/workers/
├── __init__.py
├── celery_app.py          # Celery() instance + config
├── beat_schedule.py       # periodic tasks
├── user_tasks.py
└── billing_tasks.py
```

### `celery_app.py`

```python
from celery import Celery
from {{project-slug}}.config import get_settings

settings = get_settings()

celery_app = Celery(
    "{{project-slug}}",
    broker=settings.redis_url,
    backend=settings.redis_url,
    include=[
        "{{project-slug}}.workers.user_tasks",
        "{{project-slug}}.workers.billing_tasks",
    ],
)

celery_app.conf.update(
    task_serializer="json",
    accept_content=["json"],
    result_serializer="json",
    timezone="UTC",
    enable_utc=True,

    task_acks_late=True,                         # ack only after task completes
    task_reject_on_worker_lost=True,
    task_time_limit=600,                         # hard kill at 10min
    task_soft_time_limit=540,                    # SoftTimeLimitExceeded at 9min

    worker_prefetch_multiplier=1,                # don't hoard tasks
    worker_max_tasks_per_child=1000,             # restart worker periodically (memory)
    worker_send_task_events=True,                # for monitoring (Flower)

    broker_connection_retry_on_startup=True,
    result_expires=3600,
)

# beat schedule
from celery.schedules import crontab
celery_app.conf.beat_schedule = {
    "expire-stale-sessions": {
        "task": "{{project-slug}}.workers.user_tasks.expire_stale_sessions",
        "schedule": crontab(minute="*/15"),
    },
}
```

### Why these specific settings

| Setting | Why |
|---------|-----|
| `task_acks_late=True` | If worker crashes mid-task, broker re-delivers. Pairs with idempotency. |
| `task_reject_on_worker_lost=True` | Worker death → broker re-queues, doesn't ack the lost task |
| `task_time_limit=600` | Hard upper bound — protects you from runaway tasks |
| `task_soft_time_limit=540` | Inside the task, you can catch `SoftTimeLimitExceeded` and exit cleanly |
| `worker_prefetch_multiplier=1` | Critical for unevenly-sized tasks. Default of 4 means a worker may grab 4 long tasks while another sits idle. |
| `worker_max_tasks_per_child=1000` | Periodic restart fights memory leaks (especially with C extensions) |

### Writing a task

```python
# workers/user_tasks.py
import asyncio
from celery import shared_task
from celery.exceptions import SoftTimeLimitExceeded
import structlog

from {{project-slug}}.workers.celery_app import celery_app
from {{project-slug}}.db.session import SessionLocal
from {{project-slug}}.services.user import UserService
from {{project-slug}}.repositories.user import UserRepository

log = structlog.get_logger()


@celery_app.task(
    bind=True,
    autoretry_for=(Exception,),
    retry_backoff=True,
    retry_backoff_max=600,
    retry_jitter=True,
    max_retries=5,
)
def send_welcome_email(self, user_id: str) -> None:
    """Idempotent: safe to retry."""
    log.info("send_welcome_email.start", user_id=user_id, attempt=self.request.retries)
    try:
        asyncio.run(_send_welcome_async(user_id))
    except SoftTimeLimitExceeded:
        log.warning("send_welcome_email.soft_timeout", user_id=user_id)
        raise


async def _send_welcome_async(user_id: str) -> None:
    async with SessionLocal() as session:
        repo = UserRepository(session)
        user = await repo.get(UUID(user_id))
        if user is None:
            return  # idempotent: nothing to do
        # ... actually send email
```

### Idempotency

**Tasks must be idempotent.** With `task_acks_late=True` + `retry_on_worker_lost`, a task may run more than once. Common patterns:

1. **Natural idempotency**: "send if not already sent" — gate on a `sent_at` column.
2. **Idempotency key**: caller passes a UUID; task records "I handled this key" before doing work.
3. **State machine**: only act if state is the expected `from` state.

### Calling tasks

```python
# from a route
from {{project-slug}}.workers.user_tasks import send_welcome_email

@router.post("/users")
async def create_user(...):
    user = await service.register(...)
    send_welcome_email.delay(str(user.id))  # async, non-blocking
    return ...
```

`.delay()` is shorthand for `.apply_async()`. Use `.apply_async(countdown=60, queue="emails")` for delay/queue routing.

### Running workers

```bash
# in dev
uv run celery -A {{project-slug}}.workers.celery_app worker --loglevel=info --concurrency=4

# beat (scheduler) in a separate process
uv run celery -A {{project-slug}}.workers.celery_app beat --loglevel=info

# combined (DEV ONLY — never in prod)
uv run celery -A {{project-slug}}.workers.celery_app worker --beat --loglevel=info
```

In production: separate worker pods/processes from beat (you want exactly one beat).

### Queues

Don't dump everything in `celery`. Split by SLA:

```python
celery_app.conf.task_routes = {
    "{{project-slug}}.workers.user_tasks.send_welcome_email": {"queue": "emails"},
    "{{project-slug}}.workers.billing_tasks.charge_card": {"queue": "billing"},
    "{{project-slug}}.workers.billing_tasks.nightly_report": {"queue": "long"},
}
```

Run separate worker processes per queue:

```bash
celery -A app worker -Q emails -c 8
celery -A app worker -Q billing -c 4
celery -A app worker -Q long -c 1
```

Now a clogged-up "long" queue doesn't starve emails.

### Monitoring

- **Flower** (`pip install flower`): web UI for queue inspection, easy.
- **OpenTelemetry**: instrument with `opentelemetry-instrumentation-celery`. Traces show task spans linked to the originating HTTP request.
- **Sentry** has Celery integration that captures task errors with context.

## arq (the async-native lighter alternative)

```python
# arq_worker.py
from arq import create_pool
from arq.connections import RedisSettings


async def send_welcome(ctx, user_id: str):
    async with SessionLocal() as session:
        repo = UserRepository(session)
        user = await repo.get(UUID(user_id))
        # ...


class WorkerSettings:
    functions = [send_welcome]
    redis_settings = RedisSettings.from_dsn(get_settings().redis_url)
    max_jobs = 10
    job_timeout = 600
```

```bash
arq path.to.WorkerSettings
```

```python
# from a route
redis = await create_pool(RedisSettings.from_dsn(...))
await redis.enqueue_job("send_welcome", str(user.id))
```

Pros: native async, simpler than Celery, no `asyncio.run()` shenanigans.
Cons: smaller community, fewer features (no beat scheduling out of box, no result backend richness).

## Periodic tasks

**Celery beat:** define schedule in `celery_app.conf.beat_schedule` (see above). Beat issues tasks on schedule; workers pick them up.

**arq:** use `cron` jobs in `WorkerSettings`:

```python
from arq import cron

class WorkerSettings:
    functions = [send_welcome]
    cron_jobs = [cron(expire_stale_sessions, minute={0, 15, 30, 45})]
```

**Alternative:** use the OS scheduler (`cron` / `systemd timers`) to call a CLI command. Simpler, no extra moving piece. Fine for low-frequency things.

## Async best practices inside FastAPI

### Don't block the event loop

If your route handler is `async def`, **never** call sync IO in it. Common offenders:

| Sync | Async replacement |
|------|-------------------|
| `requests.get(...)` | `httpx.AsyncClient().get(...)` |
| `boto3` | `aiobotocore` or run in threadpool |
| `redis-py` (sync) | `redis-py` async (`redis.asyncio`) |
| `psycopg2` | `asyncpg` |
| `pymongo` | `motor` |
| File reads (>small) | `aiofiles` or threadpool |
| CPU-bound work | `loop.run_in_executor(None, ...)` or — better — Celery |

If a sync library is unavoidable, wrap it:

```python
import asyncio

result = await asyncio.to_thread(blocking_call, arg1, arg2)
```

### Concurrent fan-out

```python
import asyncio

async def fanout(user_id: str):
    profile, orders, prefs = await asyncio.gather(
        get_profile(user_id),
        get_orders(user_id),
        get_preferences(user_id),
    )
    return assemble(profile, orders, prefs)
```

For partial-tolerance fan-out (some calls allowed to fail), use `return_exceptions=True`:

```python
results = await asyncio.gather(*tasks, return_exceptions=True)
```

For Python 3.11+ structured concurrency:

```python
async with asyncio.TaskGroup() as tg:
    profile_t = tg.create_task(get_profile(user_id))
    orders_t = tg.create_task(get_orders(user_id))
    prefs_t = tg.create_task(get_preferences(user_id))
# all tasks complete here; if any raised, all are cancelled and an ExceptionGroup is raised
```

### Timeouts

Always wrap external calls in timeouts:

```python
async with asyncio.timeout(2.0):
    result = await external_api.call(...)
```

If you don't, a slow upstream can pile up requests until you exhaust the connection pool.

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| `RuntimeError: Event loop is closed` in tests | Use `pytest-asyncio` properly with `asyncio_mode = "auto"` |
| Worker silently swallows task errors | Set up Sentry or structured logging in the task |
| Memory leak in long-running worker | `worker_max_tasks_per_child=1000` to recycle |
| Tasks "stuck" in pending forever | Check broker connection; check that worker has the task imported (matches `include=[...]`) |
| Beat firing duplicate tasks | Run exactly one beat process. Use `celery beat -s /var/run/celerybeat-schedule` for persistence. |
| `asyncio.run()` inside a Celery task hangs | Don't share an event loop across tasks; new `asyncio.run()` per task is fine |
| Connection pool exhaustion under load | Don't share an SA session across tasks; open a new one per task |
| Slow shutdown (workers won't exit) | Send SIGTERM, wait 30s, then SIGKILL. Don't `kill -9` immediately or you'll lose in-flight tasks. |
