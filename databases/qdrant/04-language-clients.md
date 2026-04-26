# Qdrant Language Clients

> Python (`qdrant-client`), Node (`@qdrant/js-client-rest`), Go, Rust, Java. Connection patterns, batching, error handling.

## Driver picks

| Language | Client | Notes |
|----------|--------|-------|
| **Python** | `qdrant-client` (sync + async) | Use `AsyncQdrantClient` |
| **Node** | `@qdrant/js-client-rest` (REST) or `@qdrant/js-client-grpc` | REST is simpler; gRPC for high throughput |
| **Go** | `github.com/qdrant/go-client` | Official |
| **Java** | `io.qdrant:client` | Official |
| **Rust** | `qdrant-client` crate | Official |
| **HTTP REST** | curl / any HTTP lib | Always works, well-documented |

## Python — qdrant-client

```python
from qdrant_client import AsyncQdrantClient
from qdrant_client.models import (
    VectorParams, Distance, PointStruct,
    Filter, FieldCondition, MatchValue, Range,
)

client = AsyncQdrantClient(
    url=settings.qdrant_url,            # http://localhost:6333 or https://your-cluster.qdrant.cloud
    api_key=settings.qdrant_api_key,
    prefer_grpc=True,                   # use gRPC for large operations
    grpc_port=6334,
    timeout=30,                         # seconds
)

# health
await client.get_collections()

# create
await client.create_collection(
    collection_name="docs",
    vectors_config=VectorParams(size=1536, distance=Distance.COSINE),
)

# upsert (batch!)
await client.upsert(
    collection_name="docs",
    points=[
        PointStruct(id=str(uuid7()), vector=embedding, payload={"text": text, "source": "..."}),
        # ...up to 1000 per batch...
    ],
    wait=True,                          # wait for ack; use False for fire-and-forget
)

# search
results = await client.search(
    collection_name="docs",
    query_vector=query_embedding,
    query_filter=Filter(must=[FieldCondition(key="tenant_id", match=MatchValue(value=tid))]),
    limit=10,
    with_payload=True,
)

for r in results:
    print(r.id, r.score, r.payload["text"][:80])

# scroll (iterate through all matching)
points, offset = await client.scroll("docs", scroll_filter=..., limit=500)
while offset is not None:
    points, offset = await client.scroll("docs", scroll_filter=..., offset=offset, limit=500)
```

### Sync vs async

```python
from qdrant_client import QdrantClient                # sync
from qdrant_client import AsyncQdrantClient           # async
```

Use async for FastAPI / async services. Use sync for one-off scripts (simpler).

### Batch helper

```python
import asyncio

async def bulk_upsert(client, collection, points, batch_size=500):
    for i in range(0, len(points), batch_size):
        batch = points[i:i+batch_size]
        await client.upsert(collection_name=collection, points=batch, wait=False)
        # optional: rate-limit
        await asyncio.sleep(0.05)
    # final wait
    await asyncio.sleep(2)
```

For >10K points, use batches of 1000 with `wait=False`. Verify count after.

### Pydantic integration

Vectors and payload work naturally with Pydantic:

```python
from pydantic import BaseModel

class DocumentChunk(BaseModel):
    id: str
    text: str
    source: str
    tenant_id: str
    created_at: int

# upsert from Pydantic models
points = [
    PointStruct(id=chunk.id, vector=embed(chunk.text), payload=chunk.model_dump(exclude={"id"}))
    for chunk in chunks
]
await client.upsert("docs", points=points)
```

## Node — `@qdrant/js-client-rest`

```bash
pnpm add @qdrant/js-client-rest
```

```typescript
import { QdrantClient } from '@qdrant/js-client-rest';

const client = new QdrantClient({
  url: process.env.QDRANT_URL,
  apiKey: process.env.QDRANT_API_KEY,
});

// health
await client.getCollections();

// create
await client.createCollection('docs', {
  vectors: { size: 1536, distance: 'Cosine' },
});

// upsert
await client.upsert('docs', {
  wait: true,
  points: [
    { id: crypto.randomUUID(), vector: embedding, payload: { text: '...', source: '...' } },
  ],
});

// search
const results = await client.search('docs', {
  vector: queryEmbedding,
  filter: {
    must: [{ key: 'tenant_id', match: { value: tenantId } }],
  },
  limit: 10,
  with_payload: true,
});

results.forEach((r) => console.log(r.id, r.score, r.payload?.text));
```

### Node — gRPC client (for high throughput)

```bash
pnpm add @qdrant/js-client-grpc
```

```typescript
import { QdrantClient } from '@qdrant/js-client-grpc';

const client = new QdrantClient({
  host: process.env.QDRANT_HOST,
  port: 6334,
  apiKey: process.env.QDRANT_API_KEY,
});
```

Same API surface; faster for large batches.

## Go — `go-client`

```go
import (
    "context"
    "github.com/qdrant/go-client/qdrant"
)

client, err := qdrant.NewClient(&qdrant.Config{
    Host:   "localhost",
    Port:   6334,
    APIKey: os.Getenv("QDRANT_API_KEY"),
})

// upsert
_, err = client.Upsert(ctx, &qdrant.UpsertPoints{
    CollectionName: "docs",
    Points: []*qdrant.PointStruct{
        {
            Id:      qdrant.NewIDUUID(uuid.New().String()),
            Vectors: qdrant.NewVectors(embedding...),
            Payload: qdrant.NewValueMap(map[string]any{
                "text": text, "source": source,
            }),
        },
    },
})

// search
result, err := client.Query(ctx, &qdrant.QueryPoints{
    CollectionName: "docs",
    Query:          qdrant.NewQuery(queryEmbedding...),
    Filter: &qdrant.Filter{
        Must: []*qdrant.Condition{
            qdrant.NewMatch("tenant_id", tid),
        },
    },
    Limit: qdrant.PtrOf(uint64(10)),
})
```

## Java — official

```java
QdrantClient client = new QdrantClient(
    QdrantGrpcClient.newBuilder("localhost", 6334, false)
        .withApiKey(System.getenv("QDRANT_API_KEY"))
        .build()
);

client.upsertAsync("docs", List.of(
    PointStruct.newBuilder()
        .setId(id(UUID.randomUUID().toString()))
        .setVectors(vectors(embedding))
        .putAllPayload(Map.of("text", value(text)))
        .build()
)).get();
```

## REST API direct (any language)

```bash
# upsert
curl -X PUT "http://localhost:6333/collections/docs/points" \
  -H "api-key: $QDRANT_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "points": [
      {
        "id": "doc-1",
        "vector": [0.1, 0.2, ...],
        "payload": {"text": "...", "source": "..."}
      }
    ]
  }'

# search
curl -X POST "http://localhost:6333/collections/docs/points/search" \
  -H "api-key: $QDRANT_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "vector": [0.1, 0.2, ...],
    "limit": 10,
    "with_payload": true,
    "filter": {"must": [{"key": "tenant_id", "match": {"value": "..."}}]}
  }'
```

## Connection lifecycle

```python
# in FastAPI lifespan
@asynccontextmanager
async def lifespan(app):
    await client.get_collections()    # warm-up / health check
    yield
    await client.close()
```

```typescript
process.on('SIGTERM', () => {
  // qdrant-client doesn't have explicit close for REST; gRPC does
  process.exit(0);
});
```

## Health check

```python
async def health() -> dict:
    try:
        await client.get_collections()
        return {"status": "ok"}
    except Exception as e:
        return {"status": "degraded", "error": str(e)}
```

## Common patterns

### Tenant-scoped client wrapper

```python
class TenantQdrantClient:
    def __init__(self, client: AsyncQdrantClient, tenant_id: str):
        self.client = client
        self.tenant_id = tenant_id

    async def search(self, collection: str, query_vector, **kwargs):
        existing_filter = kwargs.pop("query_filter", None)
        tenant_condition = FieldCondition(key="tenant_id", match=MatchValue(value=self.tenant_id))

        if existing_filter is None:
            new_filter = Filter(must=[tenant_condition])
        else:
            existing_filter.must = (existing_filter.must or []) + [tenant_condition]
            new_filter = existing_filter

        return await self.client.search(
            collection_name=collection,
            query_vector=query_vector,
            query_filter=new_filter,
            **kwargs,
        )

    async def upsert(self, collection, points):
        # auto-inject tenant_id into payload
        for p in points:
            p.payload = (p.payload or {}) | {"tenant_id": self.tenant_id}
        return await self.client.upsert(collection_name=collection, points=points)
```

Now app code can't accidentally bypass tenant scoping.

### Embedding + upsert pipeline

```python
async def index_documents(docs: list[Document]):
    # 1. embed in batches (parallel API calls)
    embeddings = await asyncio.gather(*[
        embed_batch(docs[i:i+100]) for i in range(0, len(docs), 100)
    ])
    flat_embeddings = [e for batch in embeddings for e in batch]

    # 2. build points
    points = [
        PointStruct(id=str(uuid7()), vector=emb, payload={"text": doc.text, "source": doc.source})
        for doc, emb in zip(docs, flat_embeddings)
    ]

    # 3. upsert in batches
    for i in range(0, len(points), 500):
        await client.upsert("docs", points=points[i:i+500], wait=False)
```

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| Single point per upsert | Batch — 100-1000 at once |
| `wait=True` on hot path | Slows the request; use `wait=False` if eventual consistency ok |
| Wrong dim mismatch error | Embedding model dim ≠ collection size; verify both |
| Slow first query after restart | HNSW lazy load; pre-warm |
| Memory blowing up | Use `on_disk=True` + scalar quantization |
| Cosine score > 1.0 | Vectors not normalized; some libraries don't normalize — Qdrant does for cosine but verify |
| Different embedding model for index vs query | Must match exactly |
| Stale client version | Pin client + server; check release notes for breaking changes |
| API key not passed | `api_key=...` in client init; check `Authorization` header |
| TLS cert verification fails | Set `verify=True` with proper CA; or `verify=False` for self-signed (dev only) |
| Tenant filter forgotten | Use a wrapper client that auto-injects |
| Bulk upsert times out | Reduce batch size; check Qdrant memory pressure |
