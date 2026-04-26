# Neo4j — Master Setup & Integration Prompt

> **Copy this file into Claude Code. Replace `{{placeholders}}`. The model will set up Neo4j (containerized or Aura), wire it to your app, create initial constraints + indexes, and verify with sample data.**

---

## Context

You are setting up Neo4j for a project. Use this when relationships ARE the data — social networks, knowledge graphs, fraud detection, agent memory layer (Graphiti). For most apps, prefer Postgres.

If something is ambiguous, **ask once, then proceed**.

## Project parameters

```
project_slug:       {{project-slug}}
neo4j_version:      5.26                        # current LTS (or 2025.x for latest)
edition:            community                   # or enterprise (multi-db, RBAC, clustering)
hosting:            {{docker|aura|self-hosted-cluster}}
language:           {{python|node|go|java}}
include_apoc:       yes                         # APOC procedures (required for many tasks)
include_gds:        {{yes-or-no}}               # Graph Data Science library (algorithms)
include_graphiti:   {{yes-or-no}}               # for AI agent memory layer
```

---

## Locked stack

| Concern | Pick | Why |
|---------|------|-----|
| Version | **Neo4j 5.26 LTS** (or 2025.x for latest features) | LTS for stable; pick latest if you need new features |
| Edition | **Community** for most; **Enterprise** for clustering/RBAC | |
| Image | **`neo4j:5.26-community`** | Official |
| Procedures | **APOC** | Required for many real workflows; install as plugin |
| Algorithms | **GDS** if you need PageRank, community detection, etc. | Optional, big plugin |
| Driver | Official Neo4j drivers (Python, Node, Go, Java) | |
| Hosting | **Aura** for production (managed) — self-host for compliance | |

## Rejected

| Option | Why not |
|--------|---------|
| `:latest` tag | Pin major version |
| Default password (`neo4j/neo4j`) | Change immediately on first login |
| Single-node production (community) | No HA; use Aura or Enterprise cluster |
| Storing files as base64 properties | Use object storage |
| Querying without indexes | `MATCH (n {prop: $val})` scans all nodes without index |
| Treating as RDBMS — long property lists, sparse data | Re-think model |

---

## Directory layout

```
{{project-slug}}/infra/neo4j/
├── docker-compose.dev.yml
├── plugins/                              # APOC + GDS jars (or use NEO4J_PLUGINS env)
├── conf/
│   └── neo4j.conf                        # config overrides
├── import/                               # CSV staging for bulk import
├── backup.sh
└── README.md
```

---

## Key files

### `infra/neo4j/docker-compose.dev.yml`

```yaml
services:
  neo4j:
    image: neo4j:5.26-community
    container_name: {{project-slug}}-neo4j
    restart: unless-stopped
    ports:
      - '127.0.0.1:7474:7474'             # browser
      - '127.0.0.1:7687:7687'             # bolt
    volumes:
      - neo4j_data:/data
      - neo4j_logs:/logs
      - neo4j_import:/var/lib/neo4j/import
      - neo4j_plugins:/plugins
    environment:
      NEO4J_AUTH: neo4j/${NEO4J_PASSWORD:?NEO4J_PASSWORD required (min 8 chars)}
      NEO4J_PLUGINS: '["apoc"]'           # add "graph-data-science" if include_gds=yes
      NEO4J_dbms_security_procedures_unrestricted: 'apoc.*,gds.*'
      NEO4J_dbms_security_procedures_allowlist: 'apoc.*,gds.*'
      NEO4J_server_memory_heap_initial__size: 1G
      NEO4J_server_memory_heap_max__size: 2G
      NEO4J_server_memory_pagecache_size: 1G
      NEO4J_server_default__listen__address: 0.0.0.0
    healthcheck:
      test: ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:7474 || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s
    deploy:
      resources:
        limits: { cpus: '4', memory: 4G }
        reservations: { cpus: '1', memory: 1G }

volumes:
  neo4j_data:
  neo4j_logs:
  neo4j_import:
  neo4j_plugins:
```

### `infra/neo4j/conf/neo4j.conf`

```
# Network
server.default_listen_address=0.0.0.0
server.bolt.listen_address=0.0.0.0:7687
server.http.listen_address=0.0.0.0:7474

# Memory (tune per host)
server.memory.heap.initial_size=1g
server.memory.heap.max_size=2g
server.memory.pagecache.size=1g
db.tx_log.rotation.retention_policy=1G size

# Security — change default password immediately
dbms.security.auth_enabled=true

# APOC procedures whitelist
dbms.security.procedures.unrestricted=apoc.*,gds.*
dbms.security.procedures.allowlist=apoc.*,gds.*

# Logging
db.logs.query.enabled=INFO
db.logs.query.threshold=200ms
db.logs.query.parameter_logging_enabled=true

# Performance
db.transaction.timeout=60s
server.jvm.additional=-XX:+UseG1GC
server.jvm.additional=-XX:+ParallelRefProcEnabled

# Telemetry
dbms.usage_report.enabled=false
```

### Initial setup script (one-time after first start)

`infra/neo4j/init.cypher`:

```cypher
// constraints (uniqueness + auto-indexed)
CREATE CONSTRAINT user_id_unique IF NOT EXISTS
  FOR (u:User) REQUIRE u.id IS UNIQUE;

CREATE CONSTRAINT user_email_unique IF NOT EXISTS
  FOR (u:User) REQUIRE u.email IS UNIQUE;

CREATE CONSTRAINT product_sku_unique IF NOT EXISTS
  FOR (p:Product) REQUIRE p.sku IS UNIQUE;

// indexes (range + lookup)
CREATE INDEX user_tenant_idx IF NOT EXISTS
  FOR (u:User) ON (u.tenant_id);

CREATE INDEX user_created_at_idx IF NOT EXISTS
  FOR (u:User) ON (u.created_at);

// composite index
CREATE INDEX user_tenant_created_idx IF NOT EXISTS
  FOR (u:User) ON (u.tenant_id, u.created_at);

// full-text index (for search)
CREATE FULLTEXT INDEX user_name_fts IF NOT EXISTS
  FOR (u:User) ON EACH [u.name, u.bio];

// vector index (for embedding-based similarity, Neo4j 5.13+)
CREATE VECTOR INDEX user_embedding_idx IF NOT EXISTS
  FOR (u:User) ON (u.embedding)
  OPTIONS { indexConfig: {
    `vector.dimensions`: 1536,
    `vector.similarity_function`: 'cosine'
  }};

// relationship indexes
CREATE INDEX follow_created_idx IF NOT EXISTS
  FOR ()-[r:FOLLOWS]-() ON (r.created_at);

// verify
SHOW CONSTRAINTS;
SHOW INDEXES;
```

Apply with:

```bash
docker exec -i {{project-slug}}-neo4j cypher-shell -u neo4j -p $NEO4J_PASSWORD < infra/neo4j/init.cypher
```

### `infra/neo4j/backup.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/var/backups/neo4j}"
RETENTION_DAYS="${RETENTION_DAYS:-14}"
mkdir -p "$BACKUP_DIR"

TS=$(date -u +%Y%m%dT%H%M%SZ)
DEST="$BACKUP_DIR/neo4j-${TS}"

# Community: stop the DB and snapshot the data dir
# Enterprise: use neo4j-admin backup (online)

# COMMUNITY (offline)
docker stop {{project-slug}}-neo4j
docker run --rm -v {{project-slug}}_neo4j_data:/data -v "${BACKUP_DIR}:/backup" \
    neo4j:5.26-community \
    tar czf /backup/neo4j-${TS}.tar.gz /data
docker start {{project-slug}}-neo4j

# ENTERPRISE (online):
# docker exec {{project-slug}}-neo4j neo4j-admin database backup --to-path=/backups neo4j

find "$BACKUP_DIR" -name 'neo4j-*.tar.gz' -mtime +${RETENTION_DAYS} -delete
echo "✓ backup written to neo4j-${TS}.tar.gz"
```

For production: use **Enterprise + online backup**. Or **Aura** (managed, included).

---

## Generation steps

1. **Confirm parameters** with the user.
2. **Create directory tree**.
3. **Write `docker-compose.dev.yml`**, conf, init.cypher.
4. **Bring up**: `docker compose -f infra/neo4j/docker-compose.dev.yml up -d`.
5. **Wait for healthy** (Neo4j first start takes ~30-60s).
6. **Apply init.cypher**: constraints + indexes.
7. **Verify**: open `http://localhost:7474` → connect with `neo4j/$NEO4J_PASSWORD` → run `MATCH (n) RETURN count(n)`.
8. **Set the connection URI**:
   ```
   NEO4J_URI=bolt://localhost:7687
   NEO4J_USER=neo4j
   NEO4J_PASSWORD=...
   ```
9. **Wire the language client** (`04-language-clients.md`).
10. **For Graphiti** (agent memory): see `memory-layer/01-dual-memory-architecture.md` and `04-language-clients.md`.
11. **Schedule backups**.

---

## Companion deep-dives

- [`README.md`](./README.md) — when to use Neo4j
- [`01-graph-data-modeling.md`](./01-graph-data-modeling.md) — modeling, constraints, indexes, when to embed properties vs split nodes
- [`02-cypher-and-queries.md`](./02-cypher-and-queries.md) — Cypher patterns, traversals, aggregations, EXPLAIN/PROFILE
- [`03-operations.md`](./03-operations.md) — backup, clustering, monitoring, scaling
- [`04-language-clients.md`](./04-language-clients.md) — Python `neo4j` driver, Node `neo4j-driver`, Graphiti integration

For agent memory built on Neo4j, see [`memory-layer/`](../../memory-layer/).
