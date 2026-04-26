# Celery (Python) — Production Setup

> Celery + Redis broker. Patterns from `backend/fastapi/05-async-and-celery.md`, expanded.

## Install

```toml
# pyproject.toml
dependencies = [
    "celery[redis]>=5.4",
    "redis>=5.2",
]
[dependency-groups]
dev = [
    "flower>=2.0",
]
```

## Project layout

```
src/{{project-slug}}/workers/
├── __init__.py
├── celery_app.py        # Celery() instance + config
├── beat_schedule.py     # periodic schedule (separate file for clarity)
├── user_tasks.py
└── billing_tasks.py
```

## `celery_app.py`

```python
from celery import Celery
from celery.schedules import crontab
from {{project-slug}}.config import get_settings

settings = get_settings()

celery_app = Celery(
    "{{project-slug}}",
    broker=settings.redis_url,
    backend=settings.redis_url,    # set to None to skip result storage
    include=[
        "{{project-slug}}.workers.user_tasks",
        "{{project-slug}}.workers.billing_tasks",
    ],
)

celery_app.conf.update(
    # serialization
    task_serializer="json",
    accept_content=["json"],
    result_serializer="json",

    # timezone
    timezone="UTC",
    enable_utc=True,

    # worker behavior
    task_acks_late=True,                         # ack after task completes
    task_reject_on_worker_lost=True,
    task_time_limit=600,                          # hard kill at 10min
    task_soft_time_limit=540,
    worker_prefetch_multiplier=1,                 # critical for uneven jobs
    worker_max_tasks_per_child=1000,              # restart workers periodically
    worker_send_task_events=True,                 # for Flower
    task_send_sent_event=True,

    # broker
    broker_connection_retry_on_startup=True,
    broker_pool_limit=10,

    # results
    result_expires=3600,                          # 1h
    result_extended=True,                         # store more metadata

    # routing — split by SLA
    task_routes={
        "{{project-slug}}.workers.user_tasks.send_welcome_email":  {"queue": "emails"},
        "{{project-slug}}.workers.billing_tasks.*":                {"queue": "billing"},
        "{{project-slug}}.workers.billing_tasks.nightly_report":   {"queue": "long"},
    },

    # default queue if no route matches
    task_default_queue="default",
)

# beat schedule
celery_app.conf.beat_schedule = {
    "expire-stale-sessions": {
        "task": "{{project-slug}}.workers.user_tasks.expire_stale_sessions",
        "schedule": crontab(minute="*/15"),
    },
    "nightly-billing": {
        "task": "{{project-slug}}.workers.billing_tasks.charge_subscriptions",
        "schedule": crontab(hour=2, minute=0),
        "options": {"queue": "billing"},
    },
}
```

## Tasks

### Idempotent task with retries

```python
# user_tasks.py
import asyncio
from celery import shared_task
from celery.exceptions import SoftTimeLimitExceeded
import structlog
from uuid import UUID

from {{project-slug}}.workers.celery_app import celery_app
from {{project-slug}}.db.session import SessionLocal
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
    """Idempotent: checks `welcome_sent_at` before sending."""
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
        if user is None or user.welcome_sent_at is not None:
            return                                     # idempotent: nothing to do
        # ... send email via SES / Postmark / etc ...
        user.welcome_sent_at = datetime.now(UTC)
        await session.commit()
```

### Why each setting

| Setting | Why |
|---------|-----|
| `bind=True` | Gives `self` — access `self.request.retries`, `self.retry()` |
| `autoretry_for=(Exception,)` | Auto-retry on any exception (be specific in real apps) |
| `retry_backoff=True` | Exponential — 1s, 2s, 4s, 8s, ... |
| `retry_backoff_max=600` | Cap at 10min so retries don't drift forever |
| `retry_jitter=True` | Spreads retries — avoids stampede |
| `max_retries=5` | After 5 failures, don't retry (goes to failed state) |

### Calling from the API

```python
from {{project-slug}}.workers.user_tasks import send_welcome_email

@router.post("/users")
async def create_user(...):
    user = await service.register(...)
    send_welcome_email.delay(str(user.id))   # async, non-blocking
    return user
```

`.delay()` is shorthand for `.apply_async()`. For more control:

```python
send_welcome_email.apply_async(
    args=[str(user.id)],
    countdown=60,        # delay 60s before running
    queue="emails",
    priority=5,          # 0-9 (Redis broker only with priority routing)
)
```

## Running workers

```bash
# emails — 8 concurrent
uv run celery -A {{project-slug}}.workers.celery_app worker -Q emails -c 8 -n emails@%h

# billing — 4 concurrent
uv run celery -A {{project-slug}}.workers.celery_app worker -Q billing -c 4 -n billing@%h

# long — 1 at a time
uv run celery -A {{project-slug}}.workers.celery_app worker -Q long -c 1 -n long@%h

# beat — exactly one
uv run celery -A {{project-slug}}.workers.celery_app beat
```

`-n name@%h` makes worker names unique (helpful in monitoring). `%h` is the hostname.

## systemd service (production)

```ini
# /etc/systemd/system/{{project-slug}}-worker@.service
[Unit]
Description={{project-slug}} celery worker (%i)
After=network.target redis.service

[Service]
Type=simple
User=deploy
WorkingDirectory=/var/www/{{project-slug}}
EnvironmentFile=/var/www/{{project-slug}}/.env
ExecStart=/var/www/{{project-slug}}/.venv/bin/celery -A {{project-slug}}.workers.celery_app worker -Q %i -c 4 -n %i@%H
KillMode=mixed
TimeoutStopSec=60
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl enable --now {{project-slug}}-worker@emails
sudo systemctl enable --now {{project-slug}}-worker@billing
sudo systemctl enable --now {{project-slug}}-worker@long
```

Beat as a separate service:

```ini
# /etc/systemd/system/{{project-slug}}-beat.service
[Unit]
Description={{project-slug}} celery beat
After=network.target redis.service

[Service]
Type=simple
User=deploy
WorkingDirectory=/var/www/{{project-slug}}
EnvironmentFile=/var/www/{{project-slug}}/.env
ExecStart=/var/www/{{project-slug}}/.venv/bin/celery -A {{project-slug}}.workers.celery_app beat -s /var/lib/{{project-slug}}/celerybeat-schedule
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
```

`-s /var/lib/.../celerybeat-schedule` persists the schedule across restarts. **Run exactly one beat** — multiple beats = duplicate fires.

## Monitoring

### Flower (web UI)

```bash
uv run celery -A {{project-slug}}.workers.celery_app flower --port=5555 --basic-auth=admin:CHANGEME
```

http://localhost:5555 — see queues, tasks, retries. Lock down with auth.

### OpenTelemetry

```python
from opentelemetry.instrumentation.celery import CeleryInstrumentor
CeleryInstrumentor().instrument()
```

Traces task spans automatically + correlates with HTTP request that originated them.

### Sentry

```python
import sentry_sdk
from sentry_sdk.integrations.celery import CeleryIntegration

sentry_sdk.init(
    dsn=settings.sentry_dsn,
    integrations=[CeleryIntegration()],
)
```

Failed tasks show up in Sentry with full context.

## Idempotency patterns

### 1. Database flag

```python
async def _process(order_id: str):
    order = await repo.get(order_id)
    if order.processed_at is not None:
        return
    # ... do work ...
    order.processed_at = datetime.now(UTC)
    await session.commit()
```

### 2. Idempotency key

```python
@celery_app.task
def process_event(event: dict):
    key = event["idempotency_key"]
    if redis.set(f"processed:{key}", "1", nx=True, ex=86400):
        # ... do work ...
        pass
    else:
        log.info("event already processed", key=key)
```

### 3. State machine

```python
async def _ship_order(order_id: str):
    order = await repo.get(order_id)
    if order.status != OrderStatus.PAID:
        return                          # only ship if currently paid
    order.status = OrderStatus.SHIPPED
    await session.commit()
    await shipping_provider.create_label(order)
```

If `_ship_order` runs twice, the second run sees `status=SHIPPED` and exits.

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| Tasks pile up because `worker_prefetch_multiplier=4` (default) | Set to 1 for uneven workloads |
| Memory leak in long-running worker | `worker_max_tasks_per_child=1000` |
| Multiple beat instances → duplicate jobs | Run exactly one beat process |
| Beat schedule lost on restart | Use `-s /path/to/celerybeat-schedule` (persisted) |
| Async task with `asyncio.run()` hangs | Don't share event loops; new `asyncio.run()` per task is fine |
| Tasks succeed but result lost | `result_expires=3600` — bump if you need longer |
| Slow shutdown drops in-flight jobs | `KillMode=mixed` + `TimeoutStopSec=60` in systemd |
| Connection pool exhaustion in worker | Don't share an SA session across tasks; new session per task |
| Tasks running in wrong queue | Verify `task_routes` matches the import path exactly |
| Worker silently swallows error | Add Sentry; check `task_reject_on_worker_lost=True` is set |
| Beat fires task but worker doesn't have it | Worker `--include` doesn't list that module |
| Retries hammer downstream | Use `retry_backoff=True` + `retry_jitter=True` |
| Task uses sync DB driver inside async code | Use `asyncio.run()` to enter async context, then await async work |

## When to outgrow Celery

- **Multi-step workflows with state passed between steps**: Temporal, Hatchet, Inngest
- **Cross-language consumers**: Redis Streams, NATS, Kafka
- **Real-time streaming with windowing**: Kafka + Flink/Spark
- **Need first-class subscribers / dead-letter exchanges / topic routing**: RabbitMQ
