# Databases — claudeforge guides

Per-database guides for the four datastores I reach for most often. Each covers: when to pick it, schema/index design, ops basics, common pitfalls.

| Database | When to use it |
|----------|----------------|
| [`postgres/`](./postgres) | Default OLTP. JSON columns, full-text search, materialized views, partitioning. |
| [`mongodb/`](./mongodb) | Document-shaped data, embedded sub-documents, fast iteration on schema. |
| [`redis/`](./redis) | Cache, ephemeral state, queues (Streams), pub/sub, rate limiting. |
| [`qdrant/`](./qdrant) | Vector similarity search for RAG and memory-cache layers. |

## Quick decision tree

- **Default → Postgres.** Adding a database has a real ops cost. Justify each one.
- **Need vectors at small scale?** Use **pgvector** (Postgres extension) — saves a service.
- **Need vectors at scale (>1M)?** Add **Qdrant**.
- **Need cache / sessions / queues / rate limit?** Add **Redis**.
- **Need document model with deep nesting?** Consider **MongoDB** — but think twice. Postgres + jsonb covers more cases than people realize.
