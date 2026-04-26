# Databases — claudeforge guides

Per-database guides — each at the same depth as the Next.js folder (PROMPT.md + 4-5 deep-dive sub-files).

| Database | When to use it |
|----------|----------------|
| [`postgres/`](./postgres) | Default OLTP. JSON columns, full-text search, materialized views, partitioning, pgvector for RAG. **PROMPT + 5 sub-files.** |
| [`mongodb/`](./mongodb) | Document-shaped data, embedded sub-documents, fast iteration on schema. **PROMPT + 4 sub-files.** |
| [`redis/`](./redis) | Cache, ephemeral state, queues (Streams), pub/sub, rate limiting, distributed locks. **PROMPT + 3 sub-files.** |
| [`qdrant/`](./qdrant) | Vector similarity search for RAG and memory-cache layers. **PROMPT + 4 sub-files.** |
| [`neo4j/`](./neo4j) | Graph database — when relationships ARE the data. Knowledge graphs (Graphiti), social, fraud, ReBAC. **PROMPT + 4 sub-files.** |

Each folder contains:

- `README.md` — overview, when to pick this DB, decision summary
- `PROMPT.md` — master scaffold prompt: docker-compose, init scripts, generation steps for Claude Code
- `01-*` — schema design / data modeling
- `02-*` — querying + indexing
- `03-operations.md` — backups, replication, monitoring, scaling
- `04-language-clients.md` — Python / Node / Go drivers, connection patterns

For ready-to-use docker-compose files + init scripts that wire these together with apps, see [`infra-recipes/`](../infra-recipes/).

## Quick decision tree

- **Default → Postgres.** Adding a database has a real ops cost. Justify each one.
- **Need vectors at small scale (< 1M)?** Use **pgvector** (Postgres extension) — see `postgres/05-pgvector-and-rag.md`.
- **Need vectors at scale (>1M)?** Add **Qdrant**.
- **Need cache / sessions / queues / rate limit?** Add **Redis**.
- **Need document model with deep nesting?** Consider **MongoDB** — but think twice. Postgres + jsonb covers more cases than people realize.
- **Relationships are the workload (multi-hop traversals, fraud rings, knowledge graphs, agent memory)?** Add **Neo4j** (often alongside Postgres).

## Versions tracked (2026)

- Postgres **17** (18 lands late 2026)
- MongoDB **8.0**
- Redis **8.0**
- Qdrant **latest stable** (~1.13+)
- Neo4j **5.26 LTS** (or 2025.x for latest features)

Pin specific versions in your `docker-compose.yml`. Don't rely on `:latest`.
