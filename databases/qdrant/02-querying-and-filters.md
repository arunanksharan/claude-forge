# Qdrant Querying & Filters

> Search, filter DSL, hybrid search, scroll, recommend, with payload + score thresholds.

## Basic search

```python
from qdrant_client.models import Filter, FieldCondition, MatchValue

results = await client.search(
    collection_name="docs",
    query_vector=embedding,
    limit=10,
    with_payload=True,
    with_vectors=False,                 # don't return vectors (big)
    score_threshold=0.7,                 # filter by min similarity
)
for r in results:
    print(r.id, r.score, r.payload)
```

`r.score` is the similarity (Cosine returns 0..1, higher = more similar).

## Filtering — the DSL

```python
from qdrant_client.models import Filter, FieldCondition, MatchValue, Range, MatchAny, MatchExcept

# AND of all conditions
must_filter = Filter(must=[
    FieldCondition(key="tenant_id", match=MatchValue(value=tenant_id)),
    FieldCondition(key="status", match=MatchValue(value="published")),
    FieldCondition(key="created_at", range=Range(gte=1730000000)),
])

# OR (any of these matches)
any_filter = Filter(should=[
    FieldCondition(key="category", match=MatchValue(value="blog")),
    FieldCondition(key="category", match=MatchValue(value="news")),
])

# NOT
not_filter = Filter(must_not=[
    FieldCondition(key="status", match=MatchValue(value="draft")),
])

# combined
combined = Filter(
    must=[FieldCondition(key="tenant_id", match=MatchValue(value=tenant_id))],
    should=[
        FieldCondition(key="category", match=MatchAny(any=["blog", "news"])),
    ],
    must_not=[
        FieldCondition(key="archived", match=MatchValue(value=True)),
    ],
)

results = await client.search(
    collection_name="docs",
    query_vector=embedding,
    query_filter=combined,
    limit=10,
)
```

### Filter operators

| Operator | Use |
|----------|-----|
| `MatchValue(value=X)` | Exact equality |
| `MatchAny(any=[...])` | IN array |
| `MatchExcept(except=[...])` | NOT IN |
| `MatchText(text="...")` | Full-text on TEXT-indexed field |
| `Range(gte, lte, gt, lt)` | Numeric range |
| `GeoBoundingBox(...)`, `GeoRadius(...)` | Geo queries on GEO-indexed field |
| `IsEmptyCondition`, `IsNullCondition` | Field absence |
| `HasIdCondition(has_id=[...])` | Filter by point IDs |

### Nested fields

```python
FieldCondition(key="metadata.author.id", match=MatchValue(value=author_id))
```

Dot notation for nested objects.

## Hybrid search (dense + sparse with RRF)

```python
from qdrant_client.models import Prefetch, FusionQuery, Fusion

results = await client.query_points(
    collection_name="docs",
    prefetch=[
        Prefetch(query=dense_vector, using="dense", limit=50),
        Prefetch(query=sparse_vector, using="sparse", limit=50),
    ],
    query=FusionQuery(fusion=Fusion.RRF),
    query_filter=Filter(must=[FieldCondition(key="tenant_id", match=MatchValue(value=tid))]),
    limit=10,
    with_payload=True,
)
```

Each prefetch returns top-50; RRF merges by reciprocal rank. The final query uses the merged ranking.

## Multi-stage search (rerank with full-precision after binary)

For binary-quantized collections:

```python
from qdrant_client.models import SearchParams, QuantizationSearchParams

results = await client.search(
    collection_name="docs",
    query_vector=embedding,
    search_params=SearchParams(
        quantization=QuantizationSearchParams(
            ignore=False,
            rescore=True,                  # re-rank with original vectors
            oversampling=2.0,              # search top 2× then re-rank
        ),
        hnsw_ef=128,                       # search-time depth
    ),
    limit=10,
)
```

## Recommend (find similar to a point you already have)

```python
results = await client.recommend(
    collection_name="docs",
    positive=[point_id_1, point_id_2],     # find similar to these
    negative=[point_id_3],                  # avoid these
    limit=10,
    query_filter=Filter(...),
)
```

Useful for "more like this" without re-embedding.

## Scroll (iterate through all matching points)

For batch operations / re-indexing:

```python
points, next_offset = await client.scroll(
    collection_name="docs",
    scroll_filter=Filter(must=[FieldCondition(key="needs_reembedding", match=MatchValue(value=True))]),
    limit=500,
    with_payload=True,
    with_vectors=False,
)

while next_offset is not None:
    # process batch
    points, next_offset = await client.scroll(
        collection_name="docs",
        offset=next_offset,
        scroll_filter=...,
        limit=500,
    )
```

## Group results

For "give me top-K per group":

```python
results = await client.query_points_groups(
    collection_name="docs",
    query=embedding,
    group_by="document_id",                # group by source doc
    limit=10,                              # 10 groups
    group_size=3,                          # 3 chunks per group
)
```

Useful for diversity — don't return 5 chunks all from the same document.

## Search params (tune at query time)

```python
SearchParams(
    hnsw_ef=128,                          # depth of HNSW search; higher = better recall, slower
    exact=False,                           # True = brute-force (no HNSW); slow but perfect recall
    indexed_only=True,                     # skip points that haven't been indexed yet
    quantization=QuantizationSearchParams(rescore=True, oversampling=2.0),
)
```

`hnsw_ef` defaults to 40 (set when creating collection). Bump to 100-200 if recall isn't enough.

## Score threshold + filtering tradeoffs

| Approach | When |
|----------|------|
| `score_threshold=X` | Drop results below similarity threshold |
| `limit=K` | Return top K regardless of score |
| Both | Top K but only if above threshold (may return fewer than K) |

For RAG: `limit=5` + `score_threshold=0.5` ensures you don't pass irrelevant junk to the LLM.

## Filter + HNSW interaction

When filter is **highly selective** (eliminates most points), Qdrant may bypass HNSW and do post-filter. This is fine:

- Low cardinality filter (matches > 10% of points): HNSW used, filter applied during traversal
- High selectivity (< 1% of points match): may do filter-first then exact search on candidates

Qdrant decides automatically. Force one mode via:

```python
from qdrant_client.models import SearchParams, FilterStrategy

SearchParams(quantization=..., hnsw_ef=128, filter_strategy=FilterStrategy.PAYLOAD_INDEX_FIRST)
```

## Payload retrieval

```python
# only return specific payload fields
results = await client.search(
    collection_name="docs",
    query_vector=embedding,
    with_payload=PayloadSelectorInclude(include=["text", "source"]),
    limit=10,
)

# exclude specific
with_payload=PayloadSelectorExclude(exclude=["large_field"])
```

Saves bandwidth; large payloads add up.

## Update / delete operations

```python
# update payload
await client.set_payload(
    collection_name="docs",
    payload={"reviewed": True},
    points=[point_id_1, point_id_2],
)

# overwrite payload
await client.overwrite_payload(
    collection_name="docs",
    payload={"text": "...", "source": "..."},
    points=[point_id_1],
)

# delete payload field
await client.delete_payload(
    collection_name="docs",
    keys=["old_field"],
    points=[point_id_1],
)

# delete points
await client.delete(
    collection_name="docs",
    points_selector=PointIdsList(points=[point_id_1, point_id_2]),
)

# delete by filter
await client.delete(
    collection_name="docs",
    points_selector=FilterSelector(filter=Filter(must=[
        FieldCondition(key="archived", match=MatchValue(value=True)),
    ])),
)
```

## Count

```python
count = await client.count(
    collection_name="docs",
    count_filter=Filter(must=[FieldCondition(key="tenant_id", match=MatchValue(value=tid))]),
    exact=True,                            # False = approximate, faster
)
print(count.count)
```

`exact=False` for big collections (estimate is fine).

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| Filter without payload index | Slow scan — add index |
| Cosine search returns negative scores | Vectors not normalized; Qdrant normalizes for cosine, but verify |
| HNSW returns < limit results | Either fewer points match the filter, or `hnsw_ef` too low |
| Slow query at huge scale | Tune `hnsw_ef`; use quantization; check filter selectivity |
| Search doesn't see recent upserts | Indexing async; use `indexed_only=False` (default) or wait |
| Different results between runs | HNSW is approximate — use `exact=True` for reproducibility (slow) |
| Bulk delete with filter slow | Use point_selector with IDs when possible |
| Payload too large in results | Use payload selector to narrow |
| Score `>1.0` for cosine | Some normalization causes this — clamp at app layer |
| Multi-tenant filter forgotten | Wrap client with auto-tenant injection |
