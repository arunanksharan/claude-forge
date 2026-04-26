# Neo4j — claudeforge guide

> Graph database. When relationships ARE the data — social networks, knowledge graphs, fraud detection, dependency analysis, RAG memory layer (Graphiti).

## When Neo4j wins

| Pick Neo4j | Stay relational |
|------------|-----------------|
| Multi-hop traversals are the core query (`friends of friends of friends`) | Most queries are 1-2 joins |
| Schema is graph-shaped (people, places, things with rich relationships) | Schema is record-oriented |
| Need to find paths between entities | Aggregation / reporting is the workload |
| Knowledge graph for AI agents (see `memory-layer/`) | Standard CRUD app |
| Fraud / anomaly detection across networks | Single-entity queries |
| Recommendation via collaborative filtering | Pre-computed feature store |

For most apps: **Postgres**. Add Neo4j when you have a real graph problem (you'll know — your relational queries will be 5+ joins with horrible plans).

## When you'd add Neo4j to an existing stack

- AI agent memory layer (Graphiti uses Neo4j as the truth store — see [`memory-layer/`](../../memory-layer/))
- Identity resolution (matching person across data sources)
- Permissions graph (Google Zanzibar–style ReBAC)
- Recommendation engine
- Fraud detection (find rings of accounts)

## Files

| File | What it is |
|------|-----------|
| [`PROMPT.md`](./PROMPT.md) | Master setup prompt (Docker compose, init, drivers) |
| [`01-graph-data-modeling.md`](./01-graph-data-modeling.md) | Nodes, relationships, properties, labels, constraints |
| [`02-cypher-and-queries.md`](./02-cypher-and-queries.md) | Cypher syntax, traversals, aggregations, performance |
| [`03-operations.md`](./03-operations.md) | Backup, replication, monitoring, scaling |
| [`04-language-clients.md`](./04-language-clients.md) | Python (`neo4j`), Node (`neo4j-driver`), and Graphiti integration |

## Versions + hosting

- **Neo4j 5.26 LTS** (or **Neo4j 2025.x** if you want bleeding edge) — community or enterprise
- **Aura** (managed) — official; Aura Free for dev, Professional for prod
- **Neo4j Desktop** for local dev (GUI)
- **Self-hosted** Docker — `neo4j:5.26-community`

For production with relationships at scale: Aura or self-hosted enterprise (clustering / multi-DB).

## Quick decision summary

- **Greenfield app**: don't add Neo4j until you've felt the pain in Postgres
- **Already have a graph problem**: install Neo4j, model in nodes + relationships, query with Cypher
- **AI agent memory**: use Graphiti on top of Neo4j (`memory-layer/01-dual-memory-architecture.md`)
- **Permissions / RBAC**: Neo4j is one option; alternatives include OpenFGA, SpiceDB

## Anti-patterns rejected

- Modeling everything as nodes + relationships when most queries are single-entity (use Postgres)
- Storing large blobs as properties (use object storage)
- Running Cypher with no indexes on big graphs
- Treating Neo4j as a transactional system of record for non-graph data
- Forgetting `LIMIT` on traversal queries (paths can explode combinatorially)
- Single-node prod (no HA) — use cluster or Aura
