# Qdrant Collections & Schema

> Vector configs, payload indexes, multi-vector points, sparse vectors for hybrid search, multi-tenancy.

## Collection — the unit

A collection is a group of points (vectors + payload). All points in a collection share dimension and distance.

```python
from qdrant_client.models import VectorParams, Distance, OptimizersConfigDiff, HnswConfigDiff

await client.create_collection(
    collection_name="documents",
    vectors_config=VectorParams(
        size=1536,
        distance=Distance.COSINE,
        on_disk=True,                     # store vectors on disk (memory-mapped)
    ),
    optimizers_config=OptimizersConfigDiff(
        indexing_threshold=10_000,        # build HNSW after this many points
    ),
    hnsw_config=HnswConfigDiff(
        m=16,                             # graph connectivity
        ef_construct=100,                 # build quality
    ),
    on_disk_payload=True,                 # payload on disk
    shard_number=1,                       # 1 for single node; >1 for cluster
    replication_factor=1,                 # increase for HA
)
```

### Vector dimensions per embedding model

| Model | Dim |
|-------|-----|
| OpenAI `text-embedding-3-small` | 1536 (or any reduced via `dimensions` param) |
| OpenAI `text-embedding-3-large` | 3072 (or reduced) |
| Cohere `embed-v4.0` | up to 1536 |
| Voyage `voyage-3-large` | 1024 |
| `bge-large-en-v1.5` (open) | 1024 |
| `nomic-embed-text-v1.5` | 768 |

Pin model + version. Re-embedding millions of docs to switch models is expensive.

### Distance metrics

| Distance | When |
|----------|------|
| **Cosine** | Default for most embedding models (OpenAI, Cohere, Voyage) |
| **Dot product** | If your vectors are pre-normalized (faster than cosine on GPU) |
| **Euclid** (L2) | Some image embedding models |
| **Manhattan** (L1) | Rare |

## Multi-vector points

When a single document has multiple embeddings (e.g., title + body):

```python
await client.create_collection(
    collection_name="docs",
    vectors_config={
        "title": VectorParams(size=384, distance=Distance.COSINE),
        "body": VectorParams(size=1536, distance=Distance.COSINE),
    },
)

await client.upsert("docs", [
    PointStruct(
        id="doc-1",
        vector={
            "title": title_embedding,
            "body": body_embedding,
        },
        payload={...},
    ),
])

# query — choose which vector
hits = await client.query_points(
    collection_name="docs",
    query=query_embedding,
    using="body",                         # which named vector to search
    limit=10,
)
```

Use multi-vector when:
- Different fields warrant different models (small for title, large for body)
- You want to combine scores from multiple vectors at query time
- ColBERT-style late interaction retrieval

## Sparse vectors (for hybrid search)

Sparse vectors are dictionaries (token → weight), like BM25 or SPLADE outputs.

```python
from qdrant_client.models import SparseVectorParams, SparseIndexParams, Modifier

await client.create_collection(
    collection_name="docs",
    vectors_config={
        "dense": VectorParams(size=1536, distance=Distance.COSINE),
    },
    sparse_vectors_config={
        "sparse": SparseVectorParams(
            index=SparseIndexParams(on_disk=False),
            modifier=Modifier.IDF,         # IDF weighting if you provide raw counts
        ),
    },
)

await client.upsert("docs", [
    PointStruct(
        id="doc-1",
        vector={
            "dense": dense_vector,
            "sparse": SparseVector(indices=[1, 4, 7, 100], values=[0.5, 0.3, 0.2, 0.8]),
        },
        payload={...},
    ),
])
```

For hybrid query (dense + sparse + RRF):

```python
from qdrant_client.models import Prefetch, Query, FusionQuery, Fusion

results = await client.query_points(
    collection_name="docs",
    prefetch=[
        Prefetch(query=dense_vector, using="dense", limit=50),
        Prefetch(query=SparseVector(indices=[...], values=[...]), using="sparse", limit=50),
    ],
    query=FusionQuery(fusion=Fusion.RRF),
    limit=10,
)
```

Reciprocal Rank Fusion (RRF) combines the two rankings. Often outperforms either alone.

## Payload indexes

Without payload indexes, filter queries (`tenant_id == X`) scan all matching points. With indexes, they use index lookup. **Index every field you'll filter on.**

```python
from qdrant_client.models import PayloadSchemaType, KeywordIndexParams, IntegerIndexParams

await client.create_payload_index("docs", "tenant_id", PayloadSchemaType.KEYWORD)
await client.create_payload_index("docs", "user_id", PayloadSchemaType.KEYWORD)
await client.create_payload_index("docs", "created_at", PayloadSchemaType.INTEGER)
await client.create_payload_index("docs", "tags",
    field_schema=KeywordIndexParams(type=PayloadSchemaType.KEYWORD, is_tenant=False))

# full-text payload index for text search
await client.create_payload_index("docs", "title",
    field_schema=TextIndexParams(
        type=PayloadSchemaType.TEXT,
        tokenizer=TokenizerType.WORD,
        min_token_len=2,
        max_token_len=15,
        lowercase=True,
    ))
```

| Field type | Index type |
|------------|-----------|
| String enum / id | `KEYWORD` |
| Integer | `INTEGER` |
| Float | `FLOAT` |
| Boolean | `BOOL` |
| Geo (lat/lng) | `GEO` |
| Datetime (epoch) | `DATETIME` |
| UUID | `UUID` |
| Free-form text | `TEXT` |

### Tenant index (Qdrant 1.10+)

```python
await client.create_payload_index("docs", "tenant_id",
    field_schema=KeywordIndexParams(type=PayloadSchemaType.KEYWORD, is_tenant=True))
```

`is_tenant=True` tells Qdrant to optimize storage layout per-tenant (groups vectors of the same tenant together). Big perf win for multi-tenant deployments.

## Multi-tenancy patterns

### Shared collection + payload filter (recommended)

```python
# always filter
hits = await client.search(
    collection_name="docs",
    query_vector=embedding,
    query_filter=Filter(must=[
        FieldCondition(key="tenant_id", match=MatchValue(value=tenant_id)),
    ]),
    limit=10,
)
```

Wrap in a thin client that auto-injects the tenant filter — never trust callers to remember.

Pros: simple ops, scales to millions of tenants.
Cons: blast radius (a bug forgetting filter leaks data) — mitigate via wrapper.

### Collection per tenant

For strict isolation:

```python
# one collection per tenant
collection_name = f"docs_{tenant_id}"
```

Pros: hard isolation; can drop a tenant easily.
Cons: doesn't scale beyond ~hundreds of collections.

For SaaS scale: stick with shared collection + tenant filter.

## Quantization (memory savings)

Vector data is large: 1536 dims × 4 bytes = 6KB per vector. 10M vectors = 60GB just for vectors.

### Scalar quantization (INT8)

~4× memory savings, <1% recall loss for most workloads:

```python
from qdrant_client.models import ScalarQuantization, ScalarQuantizationConfig, ScalarType

await client.create_collection(
    collection_name="docs",
    vectors_config=VectorParams(size=1536, distance=Distance.COSINE),
    quantization_config=ScalarQuantization(
        scalar=ScalarQuantizationConfig(
            type=ScalarType.INT8,
            quantile=0.99,
            always_ram=True,                # keep quantized in RAM, original on disk
        ),
    ),
)
```

### Binary quantization (1 bit per dim)

~32× memory savings, ~2-5% recall loss; best with re-ranking:

```python
from qdrant_client.models import BinaryQuantization, BinaryQuantizationConfig

quantization_config=BinaryQuantization(
    binary=BinaryQuantizationConfig(always_ram=True),
)
```

Two-stage search: binary HNSW for candidates → re-rank with original vectors:

```python
results = await client.query_points(
    collection_name="docs",
    query=query_vector,
    search_params=SearchParams(quantization=QuantizationSearchParams(rescore=True, oversampling=2.0)),
    limit=10,
)
```

For very large collections (>50M): binary quantization is often the right answer.

## Collection lifecycle

```python
# update HNSW params (rebuilds index)
await client.update_collection(
    collection_name="docs",
    optimizers_config=OptimizersConfigDiff(indexing_threshold=20_000),
    hnsw_config=HnswConfigDiff(ef_construct=200),
)

# add a new vector (e.g., upgraded embedding model)
# Qdrant doesn't support adding a vector to existing collection;
# create new collection with both vectors, copy data, switch reads, delete old.

# delete collection
await client.delete_collection("docs")
```

## Snapshots (collection-level backup)

```python
await client.create_snapshot("docs")
# stored in qdrant_snapshots/ — copy to S3 / B2 for backup
```

Snapshots include vectors + payload + indexes. Use for migration between environments.

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| Mixed embedding models | All vectors in a collection must come from the same model |
| Wrong distance for normalized vectors | Cosine and Dot give same ranking on normalized; pick one and stick |
| Missing payload index | Slow filtered queries — add indexes for every filtered field |
| `is_tenant=False` on tenant_id | Add `is_tenant=True` for big perf win in multi-tenant collections |
| Building HNSW during bulk insert | Disable indexing first (`indexing_threshold` very high), bulk-load, then enable |
| Wrong `ef_construct` (too low) | Bad recall — bump to 200 for high-quality |
| Wrong `m` (too high) | Index size grows; default 16 is fine |
| `on_disk: false` for huge collection | OOM — switch to `on_disk: true` + scalar quantization |
| Sparse + dense without RRF | You're not benefiting from hybrid; use FusionQuery |
| Multiple collections per tenant at SaaS scale | Switch to shared collection + tenant index |
| Stale collection schema after migration | Use snapshots to migrate cleanly |
