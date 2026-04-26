# End-to-End: Building "SupportBot", a Customer-Support AI Agent

> Hypothetical RAG-powered support chatbot. Demonstrates chaining the AI-agent prompts: architecture, RAG, tool use, evals, memory, observability, deployment.

## The hypothetical product

**SupportBot** — a customer support assistant for a SaaS company:
- Customer asks a question via web chat
- Agent retrieves from product docs (RAG)
- Agent has tools: `lookup_user`, `create_support_ticket`, `escalate_to_human`
- Agent has cross-session memory (what the user previously discussed)
- Hosted: FastAPI backend + Next.js chat widget, Postgres + Redis + Qdrant + Neo4j (Graphiti)

Realistic-but-simplified. Adapt to your domain.

---

## Phase 0 — Decide before building (1 day)

| Decision | Reference |
|----------|-----------|
| Architecture: single-shot RAG vs agent | [`ai-agents/agent-architectures.md`](../ai-agents/agent-architectures.md) — agent because we need tool calls. |
| RAG variant | [`ai-agents/rag-patterns.md`](../ai-agents/rag-patterns.md) — start naive, plan to add reranking after baseline evals |
| Vector store | [`databases/qdrant/README.md`](../databases/qdrant/README.md) — Qdrant (>1M chunks expected) |
| Memory | [`memory-layer/01-dual-memory-architecture.md`](../memory-layer/01-dual-memory-architecture.md) — Graphiti + Mem0 for cross-session |
| LLM provider | Claude Sonnet primary, Haiku for tool selection (cost) |
| Observability | [`observability/04-langfuse.md`](../observability/04-langfuse.md) — Langfuse for prompt/completion tracing |
| Backend | [`backend/fastapi/README.md`](../backend/fastapi/README.md) — FastAPI |
| Frontend | [`frontend/nextjs/README.md`](../frontend/nextjs/README.md) — Next.js for the chat widget |
| Hosting | [`deployment/README.md`](../deployment/README.md) — Docker Compose on a Hetzner VPS |

**Output**: 1-page decision doc + a 20-example baseline eval set (we build evals BEFORE the system).

---

## Phase 1 — Build the eval baseline (half day, mandatory)

Read [`ai-agents/evals.md`](../ai-agents/evals.md). **Don't skip this.** Without evals you'll iterate prompts blind.

Curate 20 representative customer queries by category:
- 5 easy ("how do I reset my password?")
- 5 hard (multi-doc retrieval: "compare plan A and plan B")
- 5 edge (negatives, ambiguous, out-of-scope)
- 5 adversarial (prompt injection attempts, off-topic)

For each: query, expected behavior, key facts to mention, key facts NOT to invent.

```jsonl
{"id": "easy-1", "query": "How do I reset my password?", "expected_facts": ["click 'Forgot password'", "check email"], "category": "easy"}
```

This file lives in `evals/baseline.jsonl` in the repo from day 1.

---

## Phase 2 — Backend scaffold + naive RAG (1 day)

### Step 1: scaffold FastAPI

```
/skill scaffold-fastapi
project_slug: supportbot
include_celery: yes
include_otel: yes
```

Or paste [`backend/fastapi/PROMPT.md`](../backend/fastapi/PROMPT.md).

### Step 2: add Qdrant

Read [`databases/qdrant/README.md`](../databases/qdrant/README.md). Add a `qdrant` service to `docker-compose.dev.yml`. Create the `documents` collection (1536-dim, Cosine).

### Step 3: ingest the docs

Write a one-off script `scripts/ingest_docs.py`:
- Walk the company's docs (markdown, HTML)
- Chunk to ~500 tokens
- Embed with `text-embedding-3-small`
- Upsert to Qdrant with `payload: {text, source, ...}`

Per [`ai-agents/rag-patterns.md`](../ai-agents/rag-patterns.md) — 500-token chunks with 50-token overlap is the safe default.

### Step 4: naive RAG endpoint

```python
@router.post("/v1/ask")
async def ask(payload: AskRequest, user: CurrentUser):
    embedding = await embed(payload.query)
    hits = await qdrant.search("documents", query_vector=embedding, limit=5,
        query_filter=Filter(must=[FieldCondition(key="tenant_id", match=MatchValue(value=user.tenant_id))]))
    context = "\n\n".join(h.payload["text"] for h in hits)
    answer = await llm(SYSTEM_PROMPT, [{"role": "user", "content": f"Question: {payload.query}\n\nContext:\n{context}"}])
    return {"answer": answer, "sources": [h.payload["source"] for h in hits]}
```

### Step 5: run baseline evals

Per [`ai-agents/evals.md`](../ai-agents/evals.md): write `evals/run.py` that hits `/v1/ask` for each baseline case, scores via LLM-judge, prints accuracy.

Expected baseline: 50–70% on the easy set, 30-50% on hard. **This is your starting point.** Every prompt or pipeline change gets compared against it.

---

## Phase 3 — Improve RAG (2 days)

### Step 1: add reranking

Read the reranking section of [`ai-agents/rag-patterns.md`](../ai-agents/rag-patterns.md). Add Cohere Rerank between vector search and LLM:

```python
candidates = await qdrant.search(..., limit=50)   # was 5
reranked = await cohere.rerank(query, candidates, top_n=5)
context = format(reranked)
```

Re-run evals. Expect +10-20 percentage points on hard queries.

### Step 2: add hybrid (BM25 + vector)

Per the same guide. Qdrant 1.10+ supports sparse vectors. Re-run evals.

### Step 3: contextual retrieval (if budget allows)

Per the same guide — add per-chunk context at index time. Re-ingest. Re-run evals. Anthropic reports 35-50% reduction in failures.

Stop iterating when evals plateau. **Don't add complexity that doesn't move metrics.**

---

## Phase 4 — Tool use (1 day)

Now turn the answerer into an agent that can act.

### Step 1: design the tools

Per [`ai-agents/tool-use.md`](../ai-agents/tool-use.md):

| Tool | Purpose |
|------|---------|
| `lookup_user(email_substring)` | Find user record (the agent only sees their own tenant's users) |
| `get_user_orders(user_id)` | Retrieve user's recent orders |
| `create_support_ticket(subject, description, priority)` | Open a ticket |
| `escalate_to_human(reason)` | Hand off to a human operator |

Each tool: tight schema, clear description, structured output, errors-as-returns.

### Step 2: agent loop

Per [`ai-agents/agent-architectures.md`](../ai-agents/agent-architectures.md) — ReAct pattern. Use Claude Sonnet's native tool use:

```python
async def run_agent(query: str, user: User, max_steps: int = 8):
    messages = [{"role": "user", "content": query}]
    for step in range(max_steps):
        resp = await client.messages.create(
            model="claude-sonnet-4-6",
            tools=make_tools(user),     # tools scoped to acting user
            messages=messages,
        )
        if resp.stop_reason == "end_turn":
            return resp
        # execute tool calls, append results
        ...
    raise RuntimeError("max steps")
```

**Critical**: tools constructed **per-request with `user` baked in**. Never pass `user_id` to the model.

### Step 3: integrate with RAG

Make the RAG retrieval itself a tool: `search_docs(query)`. Now the agent decides when to retrieve, possibly doing multiple targeted searches. This is "agentic retrieval" from `rag-patterns.md`.

### Step 4: re-run evals

Now your evals must score multi-step interactions. Add cases like "User asks about an order" — agent should call `lookup_user`, then `get_user_orders`, then answer. Score whether it took the right path.

---

## Phase 5 — Memory (1 day)

Add cross-session memory so the agent remembers prior conversations.

### Step 1: stand up Graphiti + Mem0

Read [`memory-layer/01-dual-memory-architecture.md`](../memory-layer/01-dual-memory-architecture.md) — full architecture.

Read [`memory-layer/03-docker-compose-setup.md`](../memory-layer/03-docker-compose-setup.md) — add Neo4j (Graphiti) + extend Qdrant for Mem0.

### Step 2: memory write path

After each chat session:
- Mem0: store mentions immediately (TTL 24h)
- Queue Graphiti sync (Celery): `graphiti_sync_task.delay(transcript)` — extracts facts, stores in Neo4j

### Step 3: memory read path

At start of each chat:
- Voice/fast: Mem0 only (cached facts)
- Text/normal: Graphiti for temporal queries; Mem0 fallback

Per [`memory-layer/01-dual-memory-architecture.md`](../memory-layer/01-dual-memory-architecture.md) "memory flow" section.

### Step 4: extend evals

Add multi-session cases: "User said in session 1 they prefer email contact. In session 2, agent should default to email." Score whether the agent uses the prior preference.

---

## Phase 6 — Observability (half day)

### Step 1: Langfuse for LLM traces

```
/skill wire-langfuse
```

Or read [`observability/04-langfuse.md`](../observability/04-langfuse.md). Wrap every LLM call with `@observe()`. Wrap every tool call as a span. Now every conversation in production is a navigable trace.

### Step 2: Sentry for errors

```
/skill wire-sentry
```

Per [`observability/03-sentry.md`](../observability/03-sentry.md). Catches uncaught exceptions in the agent loop, tool handlers, etc.

### Step 3: cost dashboard

Langfuse computes cost per call automatically (knows model pricing). Set up an alert: "if cost per user per day > $X, alert."

Per [`ai-agents/agent-architectures.md`](../ai-agents/agent-architectures.md) — set hard caps in code so a runaway loop can't blow the budget.

---

## Phase 7 — Frontend chat widget (1 day)

### Step 1: scaffold the Next.js admin

Already covered in `examples/end-to-end-saas-app.md` — same pattern. Add a `/chat` page with a streaming chat UI.

### Step 2: streaming responses

Use Vercel AI SDK or roll your own SSE. The agent's `/v1/ask` endpoint should stream tokens (FastAPI: `StreamingResponse`).

### Step 3: source citations

When the agent's answer cites sources, link them in the UI ("Source: docs/billing/refunds.md"). Builds trust + lets users verify.

### Step 4: feedback (thumbs up/down)

After each answer, show 👍/👎. POST feedback to backend → log to Langfuse:

```python
langfuse.score(trace_id=trace_id, name="user_feedback", value=1.0 if thumbs_up else 0.0)
```

This builds a labeled dataset over time — feeds back into evals.

---

## Phase 8 — Deployment (half day)

Same as `examples/end-to-end-saas-app.md` Phase 4-5. Plus:

- Make sure `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `LANGFUSE_*`, `COHERE_API_KEY` are in production secrets (`security/secrets-management.md`)
- Add Qdrant + Neo4j to production docker-compose
- Configure backups for Qdrant snapshots and Neo4j dumps

---

## Phase 9 — Security pass (half day)

Read [`security/security-review-checklist.md`](../security/security-review-checklist.md). Specifically for AI:

- ✅ PII not sent to third-party LLMs without contracts (Claude has DPA; OpenAI has DPA — document)
- ✅ Cost caps per user per day
- ✅ Tools scoped to acting user (not model-controllable)
- ✅ Tool outputs tagged as untrusted in system prompt (prompt injection defense — see [`ai-agents/tool-use.md`](../ai-agents/tool-use.md))
- ✅ Rate limit on `/v1/ask` (10/min/user)
- ✅ Refuse adversarial prompts (covered by your eval set?)

Threat model the agent specifically per [`security/threat-modeling.md`](../security/threat-modeling.md) "RAG agent" example.

---

## Phase 10 — Production iteration (forever)

The loop:

1. **User feedback** flows in (👍/👎, escalation rate)
2. **Sample 20 production traces** weekly via Langfuse
3. **Identify failure patterns**:
   - Hallucinations? → tighten retrieval, add faithfulness check
   - Wrong tool called? → improve tool descriptions
   - Multi-step loops? → cap steps, prompt for synthesis
4. **Add failures to eval set**
5. **Iterate prompt / pipeline**, re-run evals
6. **A/B test** the new variant on 5% of traffic (`ai-agents/evals.md`)
7. **Promote** if it wins; **revert** if it doesn't

Quarterly: full eval set refresh (drop stale, add 20 new from prod).

---

## Time budget

| Phase | Duration | What you get |
|-------|----------|--------------|
| 0 — Decisions + eval set | 1 day | Decision doc, 20-example baseline |
| 1 — Build evals | 0.5 day | `evals/baseline.jsonl` |
| 2 — Backend + naive RAG | 1 day | Working answer endpoint |
| 3 — Improve RAG | 2 days | Reranking + hybrid + contextual |
| 4 — Tools + agent loop | 1 day | Multi-step tool-using agent |
| 5 — Memory | 1 day | Cross-session memory |
| 6 — Observability | 0.5 day | Traces + errors + cost |
| 7 — Frontend chat | 1 day | Streaming chat widget |
| 8 — Deployment | 0.5 day | Production hosted |
| 9 — Security | 0.5 day | Pass checklist |
| **Total to v1** | **~9 days** | Production AI agent |

Then **iteration loop forever** — that's where the real value compounds.

---

## What's intentionally NOT covered

- **Specific LLM provider quirks** — every model has gotchas; check provider docs
- **Fine-tuning** — usually unnecessary; better RAG + prompt engineering wins first
- **Multi-modal** (image input/output) — adds significant complexity; treat as separate project
- **Voice agents** — different latency budget + different stack (Pipecat, LiveKit); see [`memory-layer/01-dual-memory-architecture.md`](../memory-layer/01-dual-memory-architecture.md) for the voice prefetch pattern
- **Multi-agent orchestration** — usually premature ([`ai-agents/agent-architectures.md`](../ai-agents/agent-architectures.md))

These get their own walkthroughs as the repo grows.

---

## Anti-patterns this walkthrough avoids

- ❌ Building the agent before evals (evals come Phase 1)
- ❌ Going straight to multi-agent / fancy patterns (start single-agent, single tool)
- ❌ Adding RAG complexity without measuring (each step re-runs evals)
- ❌ Storing PII in Langfuse without scrubbing (Phase 6 includes scrub config)
- ❌ Tools that accept `user_id` from the model (Phase 4: per-request tools with baked-in user)
- ❌ No cost cap (Phase 6)
- ❌ Shipping without a pre-launch security pass (Phase 9)

The phases enforce the discipline.
