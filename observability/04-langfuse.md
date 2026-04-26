# Langfuse — LLM / Agent Observability

> Trace LLM calls, prompts, completions, agent steps. Score outputs, run evals, manage prompt versions. The right tool when you're building anything LLM-shaped.

## When to use Langfuse

You have:
- LLM calls (OpenAI, Anthropic, etc.) in production
- Multi-step agents / chains / RAG
- A need to debug "why did the model say this?"
- A need to evaluate prompt changes A/B
- A need to track cost and latency per call

You don't have these → don't add it. Don't speculatively instrument.

## Why Langfuse over alternatives

| Tool | Verdict |
|------|---------|
| **Langfuse** | Pick this. Open-source, self-hostable, OpenTelemetry-compatible, strong tracing + scoring. |
| **LangSmith** | LangChain-native; great if you're heavily LangChain-bound; pricier. |
| **Helicone** | Proxy-based; simpler; less depth. |
| **Phoenix (Arize)** | Open source; eval-focused; fewer integrations. |
| **WhyLabs** | More for traditional ML; less LLM-focused. |
| **Roll your own** with PostHog / OTel | Possible but you'll rebuild Langfuse half-way. |

## Hosting

| Option | When |
|--------|------|
| **Langfuse Cloud** | Default — generous free tier, zero ops |
| **Self-hosted** (Docker compose) | Privacy-sensitive data, compliance |

Self-hosted is straightforward — Postgres + ClickHouse + Langfuse server. Use the official compose.

## Setup

### Python

```bash
uv add langfuse
```

```python
# src/{{project-slug}}/integrations/langfuse_client.py
from langfuse import Langfuse
from {{project-slug}}.config import get_settings

settings = get_settings()

langfuse = Langfuse(
    public_key=settings.langfuse_public_key,
    secret_key=settings.langfuse_secret_key,
    host=settings.langfuse_host,                 # https://cloud.langfuse.com or self-hosted
)
```

### Node / TypeScript

```bash
pnpm add langfuse
```

```typescript
import { Langfuse } from 'langfuse';

export const langfuse = new Langfuse({
  publicKey: process.env.LANGFUSE_PUBLIC_KEY,
  secretKey: process.env.LANGFUSE_SECRET_KEY,
  baseUrl: process.env.LANGFUSE_HOST,
});
```

## Tracing patterns

### Decorator-style (Python — easy)

```python
from langfuse.decorators import langfuse_context, observe

@observe()
async def process_query(query: str, user_id: str) -> str:
    langfuse_context.update_current_observation(
        user_id=user_id,
        metadata={"version": "v2"},
    )

    context = await retrieve_context(query)
    answer = await call_llm(query, context)
    return answer

@observe(as_type="generation")
async def call_llm(query: str, context: str) -> str:
    langfuse_context.update_current_observation(
        model="gpt-4o-mini",
        input={"query": query, "context_chars": len(context)},
        metadata={"prompt_version": "v3"},
    )
    response = await openai.chat.completions.create(...)
    langfuse_context.update_current_observation(
        output=response.choices[0].message.content,
        usage={
            "input": response.usage.prompt_tokens,
            "output": response.usage.completion_tokens,
        },
    )
    return response.choices[0].message.content
```

The decorator auto-creates a trace + spans. `as_type="generation"` marks it as an LLM call (so cost is computed).

### Manual style

```python
trace = langfuse.trace(name="rag-query", user_id=user_id)

retrieval_span = trace.span(name="retrieve", input={"query": query})
context = await retrieve(query)
retrieval_span.end(output={"docs": [d["id"] for d in context]})

generation = trace.generation(
    name="answer",
    model="gpt-4o-mini",
    input=[{"role": "user", "content": query}],
    metadata={"prompt_version": "v3"},
)
response = await openai.chat.completions.create(...)
generation.end(
    output=response.choices[0].message.content,
    usage_details={
        "input": response.usage.prompt_tokens,
        "output": response.usage.completion_tokens,
    },
)

trace.update(output=response.choices[0].message.content)
```

### LangChain / LlamaIndex / Vercel AI SDK integrations

Langfuse has native integrations:

```python
# LangChain — automatic trace
from langfuse.callback import CallbackHandler
handler = CallbackHandler()
chain.invoke({"input": query}, config={"callbacks": [handler]})
```

```typescript
// Vercel AI SDK
import { LangfuseExporter } from 'langfuse-vercel';
import { registerOTel } from '@vercel/otel';

registerOTel({ traceExporter: new LangfuseExporter() });
```

## Scoring + feedback

```python
# inline (during processing)
trace.score(name="hallucination", value=0.0, comment="all facts verified")

# from user feedback (later)
langfuse.score(
    trace_id=trace_id,
    name="user_thumbs",
    value=1.0,                  # 1.0 = thumbs up, 0.0 = thumbs down
    comment="said it was helpful",
)
```

In your app, capture user feedback (thumbs up/down on a chat message) and send to Langfuse. Builds a labeled dataset over time.

## Prompt management

Store prompts in Langfuse, version-controlled, fetched at runtime:

```python
# write a new version
langfuse.create_prompt(
    name="rag-answer",
    prompt="You are a helpful assistant. Use only the context below to answer:\n\n{context}\n\nQ: {query}",
    config={"model": "gpt-4o-mini", "temperature": 0.0},
    labels=["production"],
)

# fetch at runtime
prompt = langfuse.get_prompt("rag-answer", label="production")
filled = prompt.compile(context=context, query=query)
response = await openai.chat.completions.create(
    model=prompt.config["model"],
    messages=[{"role": "user", "content": filled}],
)
```

Now non-engineers (PMs, support) can edit prompts in the Langfuse UI without redeploying. Roll back to a previous version with one click.

**Cache prompts** so you're not fetching every request — `langfuse.get_prompt(..., cache_ttl_seconds=300)`.

## Datasets + evals

Build a dataset of `{input, expected_output}` pairs from production traces:

```python
# create dataset
langfuse.create_dataset(name="rag-eval-v1", description="500 production queries")

# add items
langfuse.create_dataset_item(
    dataset_name="rag-eval-v1",
    input={"query": "..."},
    expected_output={"answer": "..."},
)
```

Then run evals:

```python
dataset = langfuse.get_dataset("rag-eval-v1")
for item in dataset.items:
    with item.observe(run_name="prompt-v3-experiment"):
        result = await process_query(item.input["query"])
        # auto-scored by Langfuse evaluators or manually:
        langfuse.score(name="similarity", value=cosine_sim(result, item.expected_output["answer"]))
```

Compare runs in the UI: prompt v3 vs v4 across 500 queries, side by side.

## Cost tracking

Langfuse computes token cost per LLM call (knows pricing per model). Aggregate views:

- Cost per user
- Cost per feature
- Cost per prompt
- Cost over time

Set custom pricing if using a provider Langfuse doesn't know:

```python
langfuse.create_model(
    model_name="custom-llm-v1",
    match_pattern="custom-llm-v1",
    input_price=0.00001,    # $ per token
    output_price=0.00003,
)
```

## Sampling

For high-traffic apps, sample traces:

```python
import random

if random.random() < 0.1:    # 10%
    trace = langfuse.trace(...)
else:
    trace = None
```

Or use the SDK's built-in sampling. Always trace **errors and edge cases** at 100% — sample only the happy path.

## Async / batch flushing

```python
# at shutdown
langfuse.flush()                      # ensure pending data is sent

# context manager
with langfuse:
    process_batch()
# auto-flushes on exit
```

In FastAPI lifespan:

```python
@asynccontextmanager
async def lifespan(app):
    yield
    langfuse.flush()
```

In Node:

```typescript
process.on('SIGTERM', async () => {
  await langfuse.shutdownAsync();
});
```

Otherwise data may be lost on quick shutdowns.

## Privacy + scrubbing

Langfuse stores prompts and completions verbatim. For sensitive data:

```python
# scrub before logging
def scrub(text: str) -> str:
    return re.sub(r"\b\w+@\w+\.\w+\b", "[email]", text)

trace.update(input={"query": scrub(query)})
```

Or use Langfuse's masking config (server-side regex masking for PII fields).

For absolute privacy: self-host. Langfuse Cloud is SOC 2 Type II certified but the data lives on their infra.

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| Traces missing in UI | `langfuse.flush()` before shutdown; check `host` is correct |
| Cost computation 0 | Model name must match Langfuse's known models, or define custom |
| Slow because of synchronous logging | SDK is async by default; `flush()` only at shutdown |
| Sensitive data in prompts | Scrub before passing to Langfuse |
| Prompt cache stale after edit | Set `cache_ttl_seconds` lower, or invalidate manually |
| LangChain trace incomplete | Make sure callback handler is set on every chain |
| Sampled too aggressively → can't debug | Always trace errors + 5xx at 100% |
| Token usage wrong | Pass `usage` from the LLM response — Langfuse can't count |
| Multi-tenant trace mixing | Set `user_id` and `session_id` on every trace |
| Self-hosted Postgres bloat | Configure retention / archival; Langfuse has tools |

## Pairing with other observability

Langfuse covers **LLM-specific** observability. For everything else:

- **Sentry** for application errors (including LLM exceptions you re-raise)
- **Prom + Grafana** or **SigNoz** for general APM (request rate, latency, DB metrics)
- **Langfuse** for prompt analysis, completion quality, agent step debugging

Don't try to put everything in Langfuse. It excels at LLM, not at HTTP-API-level metrics.
