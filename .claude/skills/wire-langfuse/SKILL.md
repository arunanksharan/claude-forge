---
name: wire-langfuse
description: Use when the user wants to add Langfuse to an LLM application — trace prompts/completions, score outputs, manage prompt versions, build evaluation datasets, track cost. Covers Python and TypeScript SDKs and integrations with LangChain, LlamaIndex, Vercel AI SDK. Triggers on "add langfuse", "llm observability", "trace prompts", "prompt management".
---

# Wire Up Langfuse for LLM Observability (claudeforge)

Follow `observability/04-langfuse.md`. Steps:

1. **Confirm with user**:
   - Stack: Python or Node/TS?
   - Hosting: Langfuse Cloud (default) or self-hosted?
   - Existing LLM framework: raw OpenAI / Anthropic SDK, LangChain, LlamaIndex, or Vercel AI SDK?
   - Have keys (`LANGFUSE_PUBLIC_KEY`, `LANGFUSE_SECRET_KEY`, `LANGFUSE_HOST`)?
2. **Install + configure** the SDK:
   - Python: `uv add langfuse` + create `langfuse_client.py` with the Langfuse instance
   - Node: `pnpm add langfuse` + create `langfuse.ts` exporting the client
3. **Instrument LLM calls**:
   - Use `@observe()` decorator (Python) or manual `trace.generation()` (Python/TS) for each LLM call
   - Pass `model`, `input`, `output`, `usage` (input/output tokens)
   - Add `user_id`, `session_id`, `metadata` (prompt version, feature flag) for filtering
4. **Set up integrations** if relevant:
   - LangChain: `CallbackHandler` from langfuse — pass to `chain.invoke({}, config={'callbacks': [handler]})`
   - LlamaIndex: similar callback
   - Vercel AI SDK: `LangfuseExporter` via `@vercel/otel`
5. **Add scoring**: capture user feedback (thumbs up/down) and send via `langfuse.score(...)`. Inline scores for hallucination/quality if you have heuristics.
6. **Set up prompt management** (optional but high-leverage): move static prompts into Langfuse, fetch via `langfuse.get_prompt(name, label='production', cache_ttl_seconds=300)`. Lets non-engineers iterate.
7. **Build a baseline eval dataset**: create dataset from production traces (`langfuse.create_dataset_item(...)`); use to compare prompt versions.
8. **Configure flushing**: call `langfuse.flush()` in shutdown handler / FastAPI lifespan / `process.on('SIGTERM')`.
9. **Scrub PII** in inputs before passing to Langfuse if needed. Set sample rate for high-traffic apps.

Verify in the Langfuse UI: traces, completions, costs visible. Set up alerts on cost / failure rate if available.
