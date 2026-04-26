# Qdrant — claudeforge guide

> Vector similarity search for RAG, semantic search, and memory caches. Why Qdrant over the alternatives, and patterns.

## When to use a vector DB

You have:
- **Embeddings** (vectors from OpenAI, sentence-transformers, etc.)
- A need to find "things semantically close to this"

You don't have these → you don't need a vector DB. Don't add one speculatively.

## Why Qdrant (over the alternatives)

| Option | Verdict |
|--------|---------|
| **Qdrant** | Pick this. Rust-fast, gRPC + REST, hybrid search (BM25 + vector), payload filtering, self-hostable, managed cloud. |
| **pgvector** (Postgres extension) | Pick this if you have Postgres and your scale is < ~1M vectors. Saves a service. |
| **Weaviate** | Bigger feature surface, more opinions. Heavier. |
| **Chroma** | Excellent for prototyping; not production-grade at scale. |
| **Pinecone** | Managed-only. Pricey at scale. Locked in. |
| **Milvus** | Powerful but operationally heavy. |
| **OpenSearch / Elasticsearch with k-NN** | If you already have OpenSearch, fine. Otherwise overkill. |

The decision shrinks to: **pgvector at low scale, Qdrant at high scale or when you need rich filters.**

## Concepts

| Term | Meaning |
|------|---------|
| **Collection** | Like a table — a group of vectors with the same dimension and config |
| **Point** | A row — has `id`, `vector`, and `payload` (metadata as JSON) |
| **Vector** | Float array, fixed dimension per collection |
| **Payload** | Arbitrary JSON metadata per point — filterable |
| **Distance** | How similarity is measured: `Cosine`, `Dot`, `Euclid` |
| **HNSW** | The graph index used for fast approximate nearest neighbor (ANN) |

## Hosting

| Option | When |
|--------|------|
| **Docker (self-hosted)** | Default for dev + small prod |
| **Qdrant Cloud (managed)** | Production at scale |
| **Embedded** | Single-binary, no network — for edge / desktop apps |

```bash
# self-hosted via Docker
docker run -d --name qdrant -p 6333:6333 -p 6334:6334 \
  -v $(pwd)/qdrant_storage:/qdrant/storage \
  qdrant/qdrant:latest
```

## Drivers

| Lang | Client |
|------|--------|
| Python | `qdrant-client` (sync + async) |
| Node/TS | `@qdrant/js-client-rest` (REST) or `@qdrant/js-client-grpc` |
| Rust, Go | Official clients |

```python
# Python async
from qdrant_client import AsyncQdrantClient

client = AsyncQdrantClient(url="http://localhost:6333")
```

```typescript
// Node REST
import { QdrantClient } from '@qdrant/js-client-rest';
const client = new QdrantClient({ url: 'http://localhost:6333' });
```

## Schema design

### Create a collection

```python
from qdrant_client.models import VectorParams, Distance

await client.create_collection(
    collection_name="documents",
    vectors_config=VectorParams(
        size=1536,                  # OpenAI text-embedding-3-small dim
        distance=Distance.COSINE,
    ),
)
```

For **multi-vector** points (separate text + title vectors):

```python
vectors_config={
    "text": VectorParams(size=1536, distance=Distance.COSINE),
    "title": VectorParams(size=384, distance=Distance.COSINE),
}
```

Then per-vector queries.

### Insert points

```python
from qdrant_client.models import PointStruct

await client.upsert(
    collection_name="documents",
    points=[
        PointStruct(
            id="doc-1",            # uuid or int — your choice
            vector=embedding,       # list[float]
            payload={
                "text": "...",
                "user_id": "u-123",
                "category": "blog",
                "created_at": 1730000000,
            },
        ),
        # ... batch
    ],
    wait=True,                     # wait for ack
)
```

**Always batch upserts** (100–1000 per request). Single-point upserts are slow.

### Indexes for filterable payload fields

```python
from qdrant_client.models import PayloadSchemaType

await client.create_payload_index(
    collection_name="documents",
    field_name="user_id",
    field_schema=PayloadSchemaType.KEYWORD,
)
await client.create_payload_index(
    collection_name="documents",
    field_name="created_at",
    field_schema=PayloadSchemaType.INTEGER,
)
```

Without payload indexes, filters scan all matching points → slow at scale. **Index every field you filter on.**

## Searching

### Basic similarity

```python
from qdrant_client.models import Filter, FieldCondition, MatchValue

results = await client.search(
    collection_name="documents",
    query_vector=query_embedding,
    limit=10,
    with_payload=True,
)
for r in results:
    print(r.id, r.score, r.payload)
```

### With filter

```python
results = await client.search(
    collection_name="documents",
    query_vector=query_embedding,
    query_filter=Filter(
        must=[
            FieldCondition(key="user_id", match=MatchValue(value="u-123")),
            FieldCondition(key="category", match=MatchValue(value="blog")),
        ],
    ),
    limit=10,
)
```

`must` = AND. There's also `should` (OR) and `must_not`.

### Range filters

```python
from qdrant_client.models import Range

query_filter=Filter(must=[
    FieldCondition(key="created_at", range=Range(gte=1730000000)),
])
```

### Hybrid search (vector + BM25 keyword)

Qdrant 1.10+ supports sparse vectors (BM25-like) alongside dense.

```python
# create collection with both
await client.create_collection(
    collection_name="docs",
    vectors_config={
        "dense": VectorParams(size=1536, distance=Distance.COSINE),
    },
    sparse_vectors_config={
        "sparse": SparseVectorParams(),
    },
)

# upsert with both
await client.upsert(
    collection_name="docs",
    points=[PointStruct(
        id="doc-1",
        vector={
            "dense": dense_embedding,
            "sparse": SparseVector(indices=[1,4,7], values=[0.5,0.3,0.2]),
        },
        payload={...},
    )],
)
```

Hybrid query with reciprocal rank fusion via Qdrant's `query_points` API.

## Common patterns

### RAG retrieval (typical flow)

```python
async def retrieve_context(query: str, user_id: str, k: int = 5) -> list[dict]:
    embedding = await embed(query)
    results = await client.search(
        collection_name="documents",
        query_vector=embedding,
        query_filter=Filter(must=[
            FieldCondition(key="user_id", match=MatchValue(value=user_id)),
        ]),
        limit=k,
        with_payload=True,
    )
    return [{"text": r.payload["text"], "score": r.score} for r in results]
```

### Memory cache (Mem0-style)

```python
# upsert each user statement as a memory
await client.upsert("memories", [PointStruct(
    id=str(uuid7()),
    vector=await embed(content),
    payload={
        "user_id": user_id,
        "content": content,
        "memory_type": "mention",
        "created_at": int(time.time()),
        "ttl_at": int(time.time()) + 86400,    # for TTL pruning
    },
)])

# retrieve relevant memories for context
hits = await client.search("memories",
    query_vector=await embed(query),
    query_filter=Filter(must=[
        FieldCondition(key="user_id", match=MatchValue(value=user_id)),
    ]),
    limit=10,
)
```

See `memory-layer/` for the full dual-memory architecture (Graphiti + Mem0).

### Multi-tenancy (one collection, payload filter)

```python
# every search has a tenant filter
query_filter=Filter(must=[
    FieldCondition(key="tenant_id", match=MatchValue(value=tenant_id)),
])
```

Only safe if you guarantee the filter is always applied. Use a thin client wrapper that injects it.

### Multi-tenancy (one collection per tenant)

For strict isolation, separate collections. Pros: stronger boundaries, can drop a tenant easily. Cons: doesn't scale to many tenants (Qdrant has a limit per node).

For many tenants: stick with payload filter + indexed `tenant_id`.

## Operations

### Snapshots

```python
await client.create_snapshot(collection_name="documents")
```

Stores in Qdrant's snapshot dir. For backups, copy to S3 / B2 / wherever.

### Cluster mode

For >100M vectors or HA: run a cluster. Qdrant supports sharding + replication. Configure in `config.yaml`.

For most apps, single-node + snapshots is fine.

### Performance tuning

```python
# at collection creation:
hnsw_config=HnswConfigDiff(
    m=16,                # connections per node — higher = better recall, more memory
    ef_construct=100,    # build-time search depth — higher = slower indexing, better quality
),
optimizers_config=OptimizersConfigDiff(
    indexing_threshold=10000,    # below this, no HNSW (faster updates)
)

# at search time:
search_params=SearchParams(hnsw_ef=128)   # search-time depth — higher = better recall, slower
```

For 80% of cases, defaults are fine. Tune only when you measure problems.

### On-disk vectors

For very large collections, store vectors on disk (mmap) instead of in RAM:

```python
vectors_config=VectorParams(
    size=1536,
    distance=Distance.COSINE,
    on_disk=True,
)
```

Significantly slower than RAM but lets you fit huge collections.

### Quantization

For memory savings, scalar or product quantization:

```python
quantization_config=ScalarQuantization(
    scalar=ScalarQuantizationConfig(
        type=ScalarType.INT8,
        always_ram=True,
    ),
)
```

INT8 = ~4× memory savings, slight recall loss (often <1%).

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| Slow filter without payload index | Create indexes on filterable fields |
| Slow upserts | Batch (1000 at a time) + `wait=False` for fire-and-forget |
| Memory blowing up | Use `on_disk=True` + scalar quantization |
| Cosine distance with not-normalized vectors | Some embedding models output non-normalized — Qdrant normalizes for cosine, but verify |
| Different embedding models for index vs query | Embeddings must come from the same model |
| Mismatched dim | Collection's `size` must match your embedding dim |
| `wait=True` on hot path | Slows the request — use `wait=False` if eventual consistency is ok |
| No TTL — old data accumulates | Run a periodic delete job filtering on `ttl_at` |
| Tenant filter forgotten | Wrap client in a per-tenant context that auto-injects |
| `search` returns < limit results | Either fewer points match the filter, or `hnsw_ef` too low |
| Cold-start latency | First search after restart is slow as HNSW loads — pre-warm |
| Crashes on OOM | Set memory limits in deployment, monitor |

## When to use pgvector instead

| Pick pgvector | Pick Qdrant |
|---------------|-------------|
| < 1M vectors | > 1M vectors |
| You want one less service | You can run Qdrant alongside |
| You join vector results with relational data heavily | Vector search is mostly standalone |
| You're already on Postgres | Greenfield |
| You want SQL semantics over your vectors | You want a dedicated vector API |

pgvector setup:

```sql
CREATE EXTENSION vector;
CREATE TABLE items (
  id uuid PRIMARY KEY,
  embedding vector(1536),
  user_id uuid,
  text text
);
CREATE INDEX ON items USING hnsw (embedding vector_cosine_ops);

-- search
SELECT id, text, embedding <=> $1 as distance
FROM items
WHERE user_id = $2
ORDER BY embedding <=> $1
LIMIT 10;
```

Often the right starting point. Migrate to Qdrant when you hit scale or feature limits.
