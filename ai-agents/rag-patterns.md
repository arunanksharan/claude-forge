# RAG Patterns — From Naive to Agentic

> Naive RAG works for ~30% of cases. The rest need one of: hybrid search, query expansion, reranking, contextual retrieval, agentic retrieval, or graph-based.

## The naive baseline (always start here)

```
query → embed → vector search top-K → stuff into prompt → LLM
```

```python
async def naive_rag(query: str) -> str:
    embedding = await embed(query)
    results = await qdrant.search(
        collection_name="docs",
        query_vector=embedding,
        limit=5,
    )
    context = "\n\n".join(r.payload["text"] for r in results)
    return await llm(f"Using only this context, answer: {query}\n\nContext:\n{context}")
```

**Build evals first** (`evals.md`). Without them you can't tell if subsequent improvements actually help.

Common naive RAG failures:
- **Synonym mismatch**: query "MacBook" misses docs that say "Apple laptop"
- **Multi-hop**: query needs 2 docs joined; vector search returns one
- **Acronyms / proper nouns**: "GDPR" pulls philosophy text, not legal text
- **Long-tail facts**: vector search prefers semantically central docs over rare ones
- **Multi-perspective queries**: "pros and cons of X" — vector finds either pros OR cons

If your evals show >70% accuracy on the naive baseline, you may not need anything fancier. If <50%, advance to one of the patterns below.

## Pattern 1 — Hybrid search (BM25 + vector)

Combine keyword (BM25) and semantic (vector) — fixes synonym + acronym failures:

```python
async def hybrid_rag(query: str) -> str:
    # parallel: keyword and vector
    bm25_hits, vector_hits = await asyncio.gather(
        bm25_search(query, k=20),
        vector_search(query, k=20),
    )

    # rank fusion (Reciprocal Rank Fusion is simple and works)
    fused = rrf([bm25_hits, vector_hits], k=60)
    top_k = fused[:5]
    context = "\n\n".join(d["text"] for d in top_k)
    return await llm(f"...\n\n{context}")


def rrf(rankings: list[list[dict]], k: int = 60) -> list[dict]:
    scores = {}
    for ranking in rankings:
        for rank, doc in enumerate(ranking):
            doc_id = doc["id"]
            scores[doc_id] = scores.get(doc_id, 0) + 1 / (k + rank)
    return sorted(scores.items(), key=lambda x: -x[1])

# get docs by id from your store, attach
```

Qdrant 1.10+ supports sparse vectors natively (BM25-shaped) — see `databases/qdrant/`.

For Postgres: `pg_trgm` or full-text search alongside `pgvector`.

## Pattern 2 — Query expansion (multi-query)

The original query may be ambiguous or under-specified. Generate variants:

```python
async def multi_query_rag(query: str) -> str:
    variants_prompt = f"""Given this user query, generate 3 alternative phrasings that
    might match relevant documents. Return as a JSON array of strings.

    Query: {query}"""
    variants = json.loads(await llm(variants_prompt))
    all_queries = [query] + variants

    # search for each, dedupe
    all_hits = await asyncio.gather(*[vector_search(q, k=10) for q in all_queries])
    seen = {}
    for hits in all_hits:
        for h in hits:
            seen[h["id"]] = h     # dedupe by id

    # rerank with the original query
    reranked = await rerank(query, list(seen.values()), top_k=5)
    return await llm(f"...\n\n{format_context(reranked)}")
```

Cost: 4× the vector searches + 1 LLM expansion call. Quality bump on ambiguous queries: large.

## Pattern 3 — HyDE (Hypothetical Document Embedding)

Embed a *hypothetical answer* instead of the query — sometimes finds better matches:

```python
async def hyde_rag(query: str) -> str:
    hypothetical = await llm(f"Write a hypothetical document that answers: {query}")
    embedding = await embed(hypothetical)
    hits = await qdrant.search("docs", query_vector=embedding, limit=5)
    context = "\n\n".join(h.payload["text"] for h in hits)
    return await llm(f"...\n\n{context}")
```

Counterintuitive but works because answer-shaped text matches answer-shaped chunks better than question-shaped text.

Cost: +1 LLM call. Gain: variable; test with your evals.

## Pattern 4 — Reranking

Vector search returns 20–50 candidates fast (recall). A reranker model scores them precisely (precision):

```python
from cohere import AsyncClient
co = AsyncClient(api_key="...")

async def reranked_rag(query: str) -> str:
    candidates = await vector_search(query, k=50)
    rerank_resp = await co.rerank(
        model="rerank-english-v3.0",
        query=query,
        documents=[c["text"] for c in candidates],
        top_n=5,
    )
    top_docs = [candidates[r.index] for r in rerank_resp.results]
    return await llm(f"...\n\n{format_context(top_docs)}")
```

| Reranker | When |
|---------|------|
| **Cohere Rerank** (API) | Default — high quality, simple |
| **Voyage rerank-2** | Comparable, pricing-driven choice |
| **bge-reranker-large** | Self-hosted, free, good quality |
| **ColBERT / ColPali** | High-end, dense token-level matching |

Reranking on top-50 → top-5 typically lifts naive RAG accuracy by 10–20 percentage points. **High-leverage; almost always worth adding.**

## Pattern 5 — Contextual retrieval (Anthropic's approach)

Standard chunking loses context. "Section 3.2 says X" — chunk says "X" but context was "in the legacy v1 API, …".

Add a small per-chunk context prefix at index time:

```python
async def index_with_context(doc: str):
    # split doc into chunks (e.g. 500 tokens each)
    chunks = split(doc, max_tokens=500)

    # for each chunk, generate a 50-100 token context
    for chunk in chunks:
        context = await llm(
            f"<document>{doc}</document>\n"
            f"<chunk>{chunk}</chunk>\n"
            f"Generate a short (50-100 token) context that situates this chunk within the document."
        )
        contextualized = f"{context}\n\n{chunk}"
        embedding = await embed(contextualized)
        await qdrant.upsert("docs", [PointStruct(id=..., vector=embedding, payload={"text": chunk, "context": context})])
```

Index-time cost is significant (1 LLM call per chunk). Retrieval is unchanged. Anthropic's blog reports 35-49% reduction in retrieval failures.

Combine with reranking for best results.

## Pattern 6 — Parent-child / sentence-window

Index small chunks (sentences) but return larger chunks (paragraphs) at retrieval time:

```
Document: D
  ├── Paragraph P1
  │     ├── Sentence S1 (indexed)
  │     ├── Sentence S2 (indexed)
  │     └── Sentence S3 (indexed)
  └── Paragraph P2
        └── ...

Query → matches S2 → return P1 (the parent)
```

```python
# at index time, store both
await qdrant.upsert("sentences", [PointStruct(
    id=str(uuid7()),
    vector=embed(sentence),
    payload={"text": sentence, "paragraph_id": para_id},
)])
await postgres.execute("INSERT INTO paragraphs (id, text) VALUES (...)")

# at query time
hits = await qdrant.search("sentences", query_vector=embed(query), limit=10)
para_ids = list({h.payload["paragraph_id"] for h in hits})
paragraphs = await postgres.fetch("SELECT text FROM paragraphs WHERE id = ANY($1)", para_ids)
context = "\n\n".join(p["text"] for p in paragraphs)
```

Better recall on specific facts, better context for the LLM.

## Pattern 7 — Agentic retrieval

Let the model decide what to search for, iteratively:

```python
search_tool = {
    "name": "search_docs",
    "description": "Search the documentation for relevant info",
    "input_schema": {"type": "object", "properties": {"query": {"type": "string"}}, "required": ["query"]},
}

# the agent loop calls search_docs as many times as needed
result = await run_agent(
    user_query=query,
    tools=[search_tool],
    max_steps=5,
)
```

The model issues 1-3 search queries based on what it learns. Best for multi-hop questions ("compare X and Y") and exploration.

Cost: 3-5× a single retrieval. Quality on complex queries: significantly better. Use with caution — easy to spiral.

## Pattern 8 — GraphRAG

For knowledge requiring relational traversal ("what did Person A do at Company B that affected Project C?"):

1. Extract entities + relationships during indexing → knowledge graph
2. At query time, retrieve subgraph → linearize → feed to LLM

This is what `memory-layer/01-dual-memory-architecture.md` does for agent memory. Graphiti and Microsoft's GraphRAG are reference implementations.

When to consider: structured-knowledge-heavy domains (legal, finance, healthcare records). Overkill for general docs.

## Chunking strategy

| Approach | When |
|----------|------|
| **Fixed-size (500 tokens)** | Default; works well with reranker |
| **Semantic (sentence boundaries)** | Better for prose; needs a tokenizer-aware splitter |
| **Recursive splitter** (e.g. LangChain's) | For mixed-format docs (markdown, code) |
| **Semantic chunking** (embed-based boundary detection) | High-quality but slow at index time |

Overlap (50–100 tokens) helps continuity. Don't go below 200 tokens or above 1500.

## Evaluation

Build a held-out set of `(query, expected_passages, expected_answer)`:

```python
eval_set = [
    {"query": "What is GDPR consent?", "expected_passages": ["...gdpr-consent.md..."], "expected_answer": "..."},
    # 20-100 examples
]

for variant_name, variant_fn in {"naive": naive_rag, "hybrid": hybrid_rag, "rerank": reranked_rag}.items():
    metrics = await evaluate(variant_fn, eval_set)
    print(variant_name, metrics)
    # metrics: passage_recall@5, answer_correctness (LLM-judge), latency, cost
```

Without evals you'll add complexity without knowing if it helps. See `evals.md`.

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| Same embedding model used for index and query | Required — must match |
| Embedding model upgraded → existing index incompatible | Re-index with the new model |
| Reranking 1000 docs (slow) | Rerank top-50 from vector search, not all |
| Context too large for the model | Cap at 30K tokens for Claude / 100K for GPT-5 long context — quality often degrades past midpoint |
| Stuffing irrelevant chunks "just in case" | Hurts more than helps — model gets distracted |
| Forgetting metadata filters | Always scope by user/tenant/permission |
| HyDE on a domain the model knows nothing about | Hypothetical answer is also wrong — use vanilla query |
| Agentic retrieval loops | Cap iterations + give the model a "synthesize now" tool |
| Index size exploding (50× source size) | Vector + sparse + parent-child takes space; quantize or shard |
| Stale index after source updates | Track source `updated_at`; re-embed changed docs nightly |
