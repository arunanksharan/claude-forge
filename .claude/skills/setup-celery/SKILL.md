---
name: setup-celery
description: Use when the user wants to add Celery (Python background jobs with Redis broker) to a FastAPI / Django / Flask app — tasks, retries, beat scheduling, queue routing, monitoring with Flower, systemd services. Triggers on "add celery", "set up background jobs python", "celery worker", "fastapi async tasks".
---

# Set Up Celery for Background Jobs (claudeforge)

Follow `async-and-queues/celery.md` (deeper) and `backend/fastapi/05-async-and-celery.md`. Steps:

1. **Confirm with user**:
   - Existing app (FastAPI / Django / Flask)?
   - Use cases: emails, scheduled jobs, heavy CPU work?
   - Already have Redis? If not, set up via Docker compose first.
2. **Install + configure**:
   - Add `celery[redis]>=5.4` and `redis>=5.2` to pyproject.toml
   - Create `workers/celery_app.py` with the locked config (acks_late, prefetch=1, max_tasks_per_child, queue routing, beat schedule)
   - Update env to include `REDIS_URL`
3. **Define tasks**:
   - Create `workers/{feature}_tasks.py` per feature
   - Each task: `@celery_app.task(bind=True, autoretry_for=..., retry_backoff=True, max_retries=5)`
   - **Idempotency**: every task either checks a DB flag, uses an idempotency key, or is naturally idempotent. **Do not skip this.**
   - For async DB operations: wrap in `asyncio.run(...)` inside the task
4. **Wire into the app**:
   - Add `task.delay(args)` calls from routes/services
   - Don't put heavy work directly in route handlers
5. **Run workers**:
   - Dev: `celery -A {{project-slug}}.workers.celery_app worker -Q emails -c 4 -n emails@%h`
   - Plus separate worker per queue, plus exactly one beat
6. **Production setup**:
   - systemd template (`{{project-slug}}-worker@.service`) so you can `systemctl enable {{project-slug}}-worker@emails`
   - Or Docker Compose with separate `worker` services per queue
   - Configure beat with persisted schedule file
7. **Monitoring**:
   - Install Flower: `flower --basic-auth=admin:CHANGEME --port=5555` (lock down with auth + IP filter)
   - Add OpenTelemetry: `CeleryInstrumentor().instrument()`
   - Add Sentry: `CeleryIntegration()` in sentry_sdk.init
8. **Verify**: enqueue a test task from a route, observe it process, confirm metric/trace appears.

Always make tasks idempotent. Always run exactly one beat. Always split queues by SLA.
