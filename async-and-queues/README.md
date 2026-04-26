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

- [`celery.md`](./celery.md) — Celery + Redis broker, retries, beat schedule, idempotency, observability
- [`bullmq.md`](./bullmq.md) — BullMQ standalone, queues, processors, repeatable, flow producers
- [`redis-streams.md`](./redis-streams.md) — Streams + consumer groups for cross-service eventing
- [`workers-comparison.md`](./workers-comparison.md) — Decision matrix: Celery vs BullMQ vs Streams vs Kafka vs RabbitMQ vs Temporal
