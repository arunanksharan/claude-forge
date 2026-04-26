# Qdrant — Master Setup & Integration Prompt

> **Copy this file into Claude Code. Replace `{{placeholders}}`. The model will set up Qdrant (containerized or managed), wire it to your app, create initial collection with payload indexes, and verify with a sample upsert/search.**

---

## Context

You are setting up Qdrant for vector similarity search — RAG, semantic search, recommendation, agent memory. **Default to pgvector first** (per [`databases/postgres/05-pgvector-and-rag.md`](../postgres/05-pgvector-and-rag.md)) — only proceed with Qdrant when you genuinely need >1M vectors, sub-100ms p99 at high QPS, or rich payload filtering.

If something is ambiguous, **ask once, then proceed**.

## Project parameters

```
project_slug:       {{project-slug}}
qdrant_version:     latest                      # Qdrant releases monthly; pin in prod
hosting:            {{docker|managed|self-hosted-cluster}}
language:           {{python|node|go|rust}}
collection_name:    {{collection-name}}
vector_dimension:   {{1536}}                    # match your embedding model
distance:           {{Cosine|Dot|Euclid}}       # Cosine for OpenAI/Cohere; Dot for normalized
include_sparse:     {{yes-or-no}}               # for hybrid search (BM25-like)
quantization:       {{none|scalar|binary}}      # binary for very large collections
```

---

## Locked stack

| Concern | Pick | Why |
|---------|------|-----|
| Version | **Latest stable** (~1.13+ in 2026) | Pin in prod; Qdrant releases monthly |
| Image | **`qdrant/qdrant:latest`** (or pinned tag) | Official |
| Index | **HNSW** | Best recall + speed |
| Distance | **Cosine** for most embeddings | Match your model's training |
| Hosting | **Qdrant Cloud** for production | Self-host for compliance / cost |
| API | **gRPC** for high throughput, **REST** for simplicity | Drivers wrap both |
| Storage | **on-disk vectors** for >5M vectors | Saves RAM, slight latency penalty |
| Quantization | **binary** for >100M vectors with re-rank | 32× memory savings |

## Rejected

| Option | Why not |
|--------|---------|
| `:latest` in production | Pin to specific version |
| Default config without payload indexes | Filter queries scan entire collection |
| 1 vector per upsert | Batch (100-1000 per request) |
| Forgetting tenant_id filter | Multi-tenancy data leak |
| Building HNSW during ingestion of millions | Bulk-load first, build index after |

---

## Directory layout

```
{{project-slug}}/infra/qdrant/
├── docker-compose.dev.yml
├── config.yaml                            # qdrant tuning
├── snapshots/                             # for backups
└── README.md
```

---

## Key files

### `infra/qdrant/docker-compose.dev.yml`

```yaml
services:
  qdrant:
    image: qdrant/qdrant:latest
    container_name: {{project-slug}}-qdrant
    restart: unless-stopped
    ports:
      - '127.0.0.1:6333:6333'              # REST
      - '127.0.0.1:6334:6334'              # gRPC
    volumes:
      - qdrant_storage:/qdrant/storage
      - qdrant_snapshots:/qdrant/snapshots
      - ./config.yaml:/qdrant/config/production.yaml:ro
    environment:
      QDRANT__SERVICE__API_KEY: ${QDRANT_API_KEY:?QDRANT_API_KEY required}
      QDRANT__SERVICE__ENABLE_TLS: "false"  # set true + provide certs in prod
      QDRANT__LOG_LEVEL: INFO
    healthcheck:
      test: ["CMD-SHELL", "wget --quiet --spider --tries=1 http://localhost:6333/healthz || exit 1"]
      interval: 10s
      timeout: 3s
      retries: 5
      start_period: 30s
    deploy:
      resources:
        limits: { cpus: '4', memory: 4G }
        reservations: { cpus: '1', memory: 1G }

volumes:
  qdrant_storage:
  qdrant_snapshots:
```

### `infra/qdrant/config.yaml`

```yaml
log_level: INFO

service:
  http_port: 6333
  grpc_port: 6334
  enable_cors: true
  max_request_size_mb: 32

storage:
  performance:
    optimizers:
      default_segment_number: 4
      max_segment_size_kb: 200000
      memmap_threshold_kb: 50000
      indexing_threshold_kb: 20000
      flush_interval_sec: 5
      max_optimization_threads: 2

  on_disk_payload: true                     # store payload on disk (saves RAM)

  hnsw_index:
    m: 16
    ef_construct: 100
    full_scan_threshold: 10000              # don't use HNSW for tiny collections

# Cluster mode (production HA)
# cluster:
#   enabled: true
#   p2p:
#     port: 6335
#   consensus:
#     tick_period_ms: 100

telemetry_disabled: true                    # don't phone home
```

---

## Generation steps

1. **Confirm parameters** (vector dim must match embedding model — pin both).
2. **Create directory tree**.
3. **Write `docker-compose.dev.yml` and `config.yaml`**.
4. **Bring up Qdrant**: `docker compose -f infra/qdrant/docker-compose.dev.yml up -d`.
5. **Verify**: `curl -H "api-key: $QDRANT_API_KEY" http://localhost:6333/collections`.
6. **Create the collection** (one-time, programmatic):
   ```python
   await client.create_collection(
       collection_name="{{collection-name}}",
       vectors_config=VectorParams(size={{1536}}, distance=Distance.COSINE),
       on_disk_payload=True,
       hnsw_config=HnswConfigDiff(m=16, ef_construct=100),
       quantization_config=ScalarQuantization(
           scalar=ScalarQuantizationConfig(type=ScalarType.INT8, always_ram=True),
       ) if quantization == "scalar" else None,
   )
   ```
7. **Create payload indexes** for every field you'll filter on:
   ```python
   await client.create_payload_index("{{collection-name}}", "tenant_id", PayloadSchemaType.KEYWORD)
   await client.create_payload_index("{{collection-name}}", "created_at", PayloadSchemaType.INTEGER)
   ```
8. **Wire the app** with the language client (see `04-language-clients.md`).
9. **Smoke test**: upsert a few vectors, run a search, verify results.
10. **Schedule snapshots** (production).

---

## Companion deep-dives

- [`README.md`](./README.md) — overview + when to choose Qdrant vs pgvector
- [`01-collections-and-schema.md`](./01-collections-and-schema.md) — vector configs, payload indexes, multi-vector points, hybrid setup
- [`02-querying-and-filters.md`](./02-querying-and-filters.md) — search, filter DSL, hybrid search, scroll, recommend
- [`03-operations.md`](./03-operations.md) — snapshots, cluster mode, monitoring, on-disk + quantization
- [`04-language-clients.md`](./04-language-clients.md) — `qdrant-client` (Python), `@qdrant/js-client-rest`, gRPC clients

For RAG end-to-end including Qdrant alternatives, see [`ai-agents/rag-patterns.md`](../../ai-agents/rag-patterns.md).
