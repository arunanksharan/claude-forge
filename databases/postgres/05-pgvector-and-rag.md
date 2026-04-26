# pgvector — Vector Search in Postgres

> Skip the separate vector DB if your scale is < ~1M vectors. pgvector + your existing Postgres is enough for most RAG.

## When pgvector beats Qdrant

| pgvector wins | Qdrant wins |
|---------------|-------------|
| <1M vectors | >1M vectors |
| Vectors join with relational data heavily | Vector search is mostly standalone |
| You want one less service | You can run Qdrant alongside |
| You're already on Postgres | Greenfield, vector-first |
| You want SQL semantics | You want a dedicated vector API + filtering DSL |
| You want ACID transactions over vectors + metadata | |

For the broader vector-DB tradeoff including Qdrant, Weaviate, Chroma, Pinecone, see [`databases/qdrant/README.md`](../qdrant/README.md).

## Setup

### Image (easiest)

Use `pgvector/pgvector:pg17` (already in `PROMPT.md`). It bundles the extension binary.

### Manual install on existing Postgres

```bash
# Ubuntu / Debian
sudo apt install postgresql-17-pgvector
```

```sql
CREATE EXTENSION IF NOT EXISTS vector;
```

Verify:

```sql
SELECT '[1,2,3]'::vector;
```

## Schema

```sql
CREATE TABLE document_chunks (
  id uuid PRIMARY KEY DEFAULT uuidv7(),
  document_id uuid NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
  tenant_id uuid NOT NULL,                          -- for multi-tenant filter
  chunk_index int NOT NULL,
  text text NOT NULL,
  embedding vector(1536),                            -- OpenAI text-embedding-3-small
  metadata jsonb NOT NULL DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now()
);

-- index for similarity search (HNSW, fast)
CREATE INDEX document_chunks_embedding_hnsw_idx
  ON document_chunks USING hnsw (embedding vector_cosine_ops)
  WITH (m = 16, ef_construction = 64);

-- standard indexes for filters
CREATE INDEX document_chunks_tenant_idx ON document_chunks (tenant_id);
CREATE INDEX document_chunks_document_idx ON document_chunks (document_id);

-- optional: tsvector for hybrid search
ALTER TABLE document_chunks ADD COLUMN search_tsv tsvector
  GENERATED ALWAYS AS (to_tsvector('english', coalesce(text, ''))) STORED;
CREATE INDEX document_chunks_search_idx ON document_chunks USING gin (search_tsv);
```

### Vector dimensions

| Embedding model | Dim |
|-----------------|-----|
| OpenAI `text-embedding-3-small` | 1536 (or any reduced via `dimensions:` param) |
| OpenAI `text-embedding-3-large` | 3072 (or reduced) |
| Cohere `embed-v4.0` | up to 1536 |
| Voyage `voyage-3-large` | 1024 |
| `bge-large-en-v1.5` (open) | 1024 |
| `nomic-embed-text-v1.5` | 768 |

Pick a model. Pin its version. Re-embedding everything to upgrade is costly.

### Distance operators

| Op | Distance | Index op class |
|----|----------|----------------|
| `<->` | L2 (Euclidean) | `vector_l2_ops` |
| `<#>` | Negative inner product | `vector_ip_ops` |
| `<=>` | Cosine | `vector_cosine_ops` |
| `<+>` | L1 (Manhattan) | `vector_l1_ops` (newer) |

For most embeddings (OpenAI, Cohere): **cosine**. Match the index op class.

### Index types

| Index | When |
|-------|------|
| **HNSW** (default choice) | Best recall + speed for most workloads |
| **IVFFlat** | Older, requires `LISTS` parameter, faster index build, worse recall |
| no index | <10K vectors — sequential scan is fine |

HNSW parameters:
- `m` — graph connectivity (default 16; 32 for very large datasets)
- `ef_construction` — index build quality (default 64; up to 200 for better recall)
- `ef` (search-time) — `SET hnsw.ef_search = 100` (default 40); higher = better recall, slower

Tune by measuring recall + p95 latency on your actual queries.

## Querying

### Basic similarity

```sql
SELECT id, text, 1 - (embedding <=> $1) AS similarity
FROM document_chunks
WHERE tenant_id = $2
ORDER BY embedding <=> $1
LIMIT 10;
```

`1 - (... <=> ...)` converts cosine distance to similarity (0..1).

### With multiple filters

```sql
SELECT id, text, 1 - (embedding <=> $1) AS similarity
FROM document_chunks
WHERE tenant_id = $2
  AND document_id = ANY($3)
  AND created_at > $4
ORDER BY embedding <=> $1
LIMIT 10;
```

For filters with high selectivity (filter eliminates >90%), Postgres may skip the HNSW index — that's fine, it falls back to seq scan + post-filter. For low-selectivity filters, HNSW is used directly.

### Hybrid search (vector + BM25-like)

```sql
WITH vector_hits AS (
  SELECT id, embedding <=> $1 AS distance,
         row_number() OVER (ORDER BY embedding <=> $1) AS rank
  FROM document_chunks
  WHERE tenant_id = $2
  ORDER BY embedding <=> $1 LIMIT 50
),
keyword_hits AS (
  SELECT id, ts_rank(search_tsv, query) AS score,
         row_number() OVER (ORDER BY ts_rank(search_tsv, query) DESC) AS rank
  FROM document_chunks, to_tsquery('english', $3) query
  WHERE tenant_id = $2 AND search_tsv @@ query
  ORDER BY ts_rank(search_tsv, query) DESC LIMIT 50
)
SELECT id, COALESCE(1.0 / (60 + v.rank), 0) + COALESCE(1.0 / (60 + k.rank), 0) AS rrf_score
FROM vector_hits v FULL OUTER JOIN keyword_hits k USING (id)
ORDER BY rrf_score DESC LIMIT 10;
```

Reciprocal Rank Fusion (RRF) — simple, effective, beats raw vector for many queries.

## App integration

### Python (SQLAlchemy)

```python
from pgvector.sqlalchemy import Vector
from sqlalchemy.orm import Mapped, mapped_column

class DocumentChunk(Base):
    __tablename__ = "document_chunks"
    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid7)
    text: Mapped[str]
    embedding: Mapped[list[float]] = mapped_column(Vector(1536))
    # ...

# query
from sqlalchemy import select
stmt = (
    select(DocumentChunk, DocumentChunk.embedding.cosine_distance(query_embedding).label("d"))
    .where(DocumentChunk.tenant_id == tenant_id)
    .order_by("d")
    .limit(10)
)
results = (await session.execute(stmt)).all()
```

### Node (Drizzle)

```typescript
import { vector, pgTable, uuid, text } from 'drizzle-orm/pg-core';
import { sql } from 'drizzle-orm';

export const documentChunks = pgTable('document_chunks', {
  id: uuid().primaryKey(),
  text: text().notNull(),
  embedding: vector({ dimensions: 1536 }).notNull(),
});

// query
const distance = sql<number>`${documentChunks.embedding} <=> ${queryEmbedding}`;
const results = await db
  .select({ id: documentChunks.id, text: documentChunks.text, distance })
  .from(documentChunks)
  .where(eq(documentChunks.tenantId, tenantId))
  .orderBy(distance)
  .limit(10);
```

## Indexing strategy

### Build the index AFTER bulk-loading

```sql
-- bulk-load first (no index = faster inserts)
COPY document_chunks FROM 'chunks.csv' WITH CSV HEADER;

-- then create the index
CREATE INDEX document_chunks_embedding_hnsw_idx
  ON document_chunks USING hnsw (embedding vector_cosine_ops);
```

Building HNSW on existing data is faster than maintaining it during inserts.

### Adjust `maintenance_work_mem` for index build

```sql
SET maintenance_work_mem = '4GB';
CREATE INDEX ... USING hnsw ...;
```

Default is too small for big indexes — build will be slow.

### Concurrent in production

```sql
CREATE INDEX CONCURRENTLY ... USING hnsw ...;
```

Doesn't lock writes. Required for production tables.

## Operations

### Disk usage

A 1536-dim float vector is 6KB per row. 1M rows = 6GB just for vectors, plus the HNSW graph (~20-30% overhead).

Use **half-precision** (newer pgvector) to cut disk by 50% with minimal recall loss:

```sql
embedding halfvec(1536)        -- pgvector >= 0.7
```

Or **quantization** via expression index:

```sql
-- bit quantization for fast pre-filter
CREATE INDEX document_chunks_embedding_bin_idx
  ON document_chunks USING hnsw ((binary_quantize(embedding)::bit(1536)) bit_hamming_ops);

-- two-stage search: bin filter → re-rank with float
WITH candidates AS (
  SELECT id, embedding
  FROM document_chunks
  ORDER BY binary_quantize(embedding)::bit(1536) <~> binary_quantize($1)::bit(1536)
  LIMIT 100
)
SELECT id, embedding <=> $1 AS distance
FROM candidates
ORDER BY distance LIMIT 10;
```

### Re-embedding

When you upgrade the embedding model:

1. Add a new column `embedding_v2 vector(N)`
2. Backfill in batches (Celery task that re-embeds 100 rows at a time)
3. Build the HNSW index
4. Switch queries to use `embedding_v2`
5. Drop the old column + index

Don't try to do this in one transaction — too much memory pressure.

### Backup considerations

Vectors are large. Standard `pg_dump` works but is slow. Consider:
- pgBackRest with parallel processes
- Logical replication to a vector-only replica for analytics

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| HNSW index not used | Check `EXPLAIN`; verify dimension matches `vector(N)`; ensure `ORDER BY ... LIMIT N` pattern |
| Slow recall | Increase `hnsw.ef_search` (search-time depth) |
| Slow build | Increase `maintenance_work_mem`; use parallel workers |
| Index size huge | Use `halfvec` or quantization |
| Wrong distance op | Match index op class to query op (`<=>` with `vector_cosine_ops`) |
| Different embedding model for index vs query | Embeddings must come from the same model |
| Filter eliminates most rows but HNSW still used | Postgres may misjudge selectivity; force seq scan with `SET enable_indexscan = off` for that query, or restructure |
| Embedding column nullable + indexed | NULL vectors fail HNSW; either NOT NULL or use partial index |
| App OOMs ingesting big batches | Embed + insert in batches of 100-500 |
| `vector_norm` not used | For raw cosine you need normalized vectors; OpenAI normalizes by default; verify per model |

## When to migrate to a dedicated vector DB

You've outgrown pgvector when:

- > 10M vectors with HNSW build > 30 min
- Need sub-100ms p99 at high QPS (Qdrant is ~3-5× faster at scale)
- Need vector-specific features (multi-vector, sparse vectors, dense+sparse hybrid, payload-only collections)
- Want vector workload isolated from OLTP

Migration: dual-write for a few weeks, switch reads, drop the pgvector column. See [`databases/qdrant/README.md`](../qdrant/README.md).

For the conceptual context (RAG variants, when each pattern wins), see [`ai-agents/rag-patterns.md`](../../ai-agents/rag-patterns.md).
