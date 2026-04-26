# Async & Queues — claudeforge guides

> *Phase 2 — coming soon.* Per-runtime queueing guides plus a decision matrix.

## Quick decision summary

| Need | Pick |
|------|------|
| Python: heavy / scheduled / retry-heavy work | **Celery** with Redis or RabbitMQ broker |
| Python: lightweight async tasks in a single process | `asyncio.TaskGroup` + Redis Streams for handoff |
| Node/Nest: any background work | **BullMQ** — Redis-backed, great DX, well maintained |
| Cross-language fan-out, ordered consumption | **Redis Streams** with consumer groups |
| Massive scale, replay, long retention | **Kafka** (lift in ops cost — only if you need it) |

## Files

- `celery.md` — *Phase 4* — Celery setup with FastAPI, beat scheduling, retries, idempotency, result backend, dead letter queue
- `bullmq.md` — *Phase 4* — BullMQ with NestJS / Express, repeatable jobs, flow producers, worker patterns
- `redis-streams.md` — *Phase 4* — Streams + consumer groups for cross-service eventing without Kafka
- `workers-comparison.md` — *Phase 4* — Decision matrix with real-world failure modes
