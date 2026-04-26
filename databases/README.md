# Databases — claudeforge guides

> *Phase 2 — coming soon.* Per-database guides for the four datastores I reach for most often. Each will cover: when to pick it, schema/index design, ops basics, common pitfalls, library picks per language.

| Database | When to use it |
|----------|----------------|
| [`postgres/`](./postgres) | Default OLTP. JSON columns, full-text search, materialized views, partitioning. |
| [`mongodb/`](./mongodb) | Document-shaped data, embedded sub-documents, fast iteration on schema. |
| [`redis/`](./redis) | Cache, ephemeral state, queues (Streams), pub/sub, rate limiting. |
| [`qdrant/`](./qdrant) | Vector similarity search for RAG and memory-cache layers. |
