# Prompt Engineering for Production

> Beyond "be helpful and accurate" — the techniques that actually move the needle in production: structure, examples, output control, prefilling, model-specific patterns.

## The high-leverage techniques

In rough order of impact:

1. **Crisp task definition** — what the model is doing, in plain prose
2. **Output format specification** — JSON schema or example, strict
3. **Few-shot examples** — show, don't tell
4. **XML structure** for complex prompts (Anthropic) / Markdown sections
5. **Chain-of-thought** for reasoning tasks
6. **Prefilling** the assistant turn for format control
7. **Model selection** — match model to task

## 1. Task definition

Bad:

```
You are a helpful AI assistant. Help the user with their query.
```

Good:

```
You classify customer support tickets into one of these categories:
billing, technical, account, sales, other.

Read the ticket text and output the category in JSON: {"category": "billing"}.
If the ticket spans multiple categories, choose the dominant one.
If you cannot classify, output "other".
```

State:
- The role (classifier, summarizer, code generator)
- The input (one ticket text)
- The output (JSON shape)
- Edge cases (multiple categories, can't classify)

## 2. Output format

For machine-readable outputs, **always** use:

| Approach | When |
|----------|------|
| **Structured outputs** (OpenAI `response_format: { type: "json_schema" }`, Anthropic tool use) | First choice — model is constrained at decode time |
| **Pydantic + Instructor** (Python) | Same idea, framework-managed |
| **JSON in prompt + parse** | Fallback; less reliable, may need retries |
| **Free-form text** | Only when output is truly free-form |

```python
from pydantic import BaseModel
from openai import OpenAI

class TicketClassification(BaseModel):
    category: Literal["billing", "technical", "account", "sales", "other"]
    confidence: float
    reasoning: str

client = OpenAI()
completion = client.chat.completions.parse(
    model="gpt-4o-2024-08-06",
    messages=[
        {"role": "system", "content": "Classify customer tickets."},
        {"role": "user", "content": ticket_text},
    ],
    response_format=TicketClassification,
)
result = completion.choices[0].message.parsed   # already a TicketClassification
```

For Claude (no structured outputs API yet for general models — use tool use):

```python
client.messages.create(
    model="claude-sonnet-4-6",
    tools=[{
        "name": "submit_classification",
        "description": "Submit the ticket classification",
        "input_schema": TicketClassification.model_json_schema(),
    }],
    tool_choice={"type": "tool", "name": "submit_classification"},
    messages=[...],
)
```

The `tool_choice` forces the model to call this exact tool. Output is guaranteed-shape.

## 3. Few-shot examples

For non-trivial tasks, show 2-5 examples:

```
Classify customer tickets:

<example>
<ticket>I was charged twice for my March subscription. Please refund.</ticket>
<output>{"category": "billing", "confidence": 0.99, "reasoning": "Explicitly mentions billing issue with charge and refund request"}</output>
</example>

<example>
<ticket>The app crashes when I tap export</ticket>
<output>{"category": "technical", "confidence": 0.95, "reasoning": "App malfunction"}</output>
</example>

<example>
<ticket>Can you delete my account? I no longer need this service.</ticket>
<output>{"category": "account", "confidence": 0.98, "reasoning": "Account deletion request"}</output>
</example>

Now classify this ticket:
<ticket>{user_input}</ticket>
```

Examples beat instructions. Pick examples that:
- Cover the categories you care about
- Include at least one tricky case
- Match the format of the real input

## 4. XML structure (Claude) / Sections (general)

For long, complex prompts, structure beats prose:

```
<role>
You are a SQL query reviewer for a SaaS analytics product.
</role>

<context>
The product database is Postgres 16. Common tables include:
- users (id, email, created_at)
- events (id, user_id, name, properties, occurred_at)
- subscriptions (id, user_id, plan, status)
</context>

<task>
Review the SQL query below for correctness, performance, and security.
</task>

<criteria>
- Correctness: does it answer the stated question?
- Performance: are indexes used? any N+1 risk?
- Security: any SQL injection risk? is RLS bypassed?
</criteria>

<query>
{user_query}
</query>

<output>
Return JSON with keys: correct, performance_notes, security_notes, suggested_improvements.
</output>
```

Claude is trained on XML-style prompts and benefits a lot. Other models also work well with it. Markdown headers (`## Role`, `## Task`) work too.

## 5. Chain-of-thought

For reasoning tasks (math, multi-step logic, code review), prompt the model to think before answering:

```
Solve step by step. Show your reasoning before the final answer.
```

Or with structured outputs:

```python
class Answer(BaseModel):
    reasoning: str       # forces CoT
    answer: float
```

Modern models (GPT-5, Claude Opus 4) often CoT internally — explicit CoT helps less. Test with your evals.

For Anthropic's "extended thinking" / OpenAI's "reasoning models" (o-series): these CoT internally; don't add explicit CoT.

## 6. Prefilling (Claude-specific)

You can put words in the assistant's mouth:

```python
client.messages.create(
    messages=[
        {"role": "user", "content": "Output JSON only."},
        {"role": "assistant", "content": "{"},        # prefill
    ],
)
```

The model continues from `{`. Forces JSON output. Useful when:
- You can't use structured outputs
- You want to skip intro text ("Here's your answer: ...")
- You want the model to start with a specific framing

## 7. Model selection

| Task | Model |
|------|-------|
| Trivial classification, summarization | Smallest fast model (Haiku, GPT-5 nano) |
| Standard chat, RAG, tool use | Mid-tier (Sonnet, GPT-5) |
| Complex reasoning, code, agents | Top tier (Opus, GPT-5 Pro / o-series) |
| Cost-critical at high volume | Smaller model + heavier prompt engineering |

**Don't default to the biggest model.** A well-prompted smaller model often matches a poorly-prompted bigger one at a fraction of the cost.

## Common patterns

### "Refuse if X" gates

```
Before answering:
- If the query asks for medical, legal, or financial advice that requires a professional → respond: "Please consult a [doctor/lawyer/advisor]."
- If the query is about another user's data → respond: "I can't access other users' data."

Otherwise, answer the query using the context below.
```

Make refusals explicit and unambiguous.

### Output length constraints

```
Respond in under 100 words.
```

Or in code form:

```
Respond with at most 3 bullet points, each under 20 words.
```

Models follow length instructions reasonably but inconsistently. Combine with a hard token limit (`max_tokens`).

### Variable injection (templating)

Use a templating library (Jinja, str.format) — don't concatenate strings:

```python
from string import Template

PROMPT = Template("""
You are answering questions about $product_name.

Question: $query

Context:
$context
""")

prompt = PROMPT.substitute(product_name="Acme Pro", query=user_query, context=retrieved_context)
```

Or **store prompts in Langfuse** (`observability/04-langfuse.md`) — version-controlled, editable by non-engineers, with built-in templating.

## Prompt caching (cost discipline)

For prompts with a stable prefix (system prompt + retrieved context + question), enable prompt caching:

```python
# Anthropic
client.messages.create(
    model="claude-sonnet-4-6",
    system=[
        {"type": "text", "text": LONG_SYSTEM_PROMPT, "cache_control": {"type": "ephemeral"}},
    ],
    messages=[...],
)

# OpenAI auto-caches when the prefix is repeated; explicit prompt_cache_key for routing
```

Cached input tokens cost ~10% of regular. For high-traffic apps with stable system prompts, this is a 10x cost reduction.

## Anti-patterns

| | |
|---|---|
| **"You are a brilliant expert"** | Doesn't help. State the task. |
| **"Be concise"** | Vague — quantify ("under 100 words") |
| **"Don't hallucinate"** | Models don't know they're hallucinating. Use grounding + citations instead. |
| **"This is very important"** | Anxiety transfer; doesn't change behavior |
| **Stuffing 20 instructions** | Beyond ~5-7, models start ignoring some. Prioritize. Or break into multiple calls. |
| **Prompt-only tone control** | If tone matters, use few-shot examples — much more reliable |
| **Free-form output then string parse** | Use structured outputs; saves countless retry hours |
| **No examples for a complex task** | The single highest-leverage missing piece in most prompts |

## Iteration discipline

1. **Write the prompt + 5 eval examples.**
2. **Run evals.** Note score.
3. **Identify the lowest-scoring case.** What's wrong?
4. **Tweak the prompt** (add an example, clarify, restructure).
5. **Re-run evals.** Did the targeted case improve? Did anything regress?
6. **Commit** the prompt + the eval result. (Track in git: `prompts/v3.md`, `evals/results/v3.json`.)

Without this loop you'll cargo-cult prompt advice and have no idea if it helps.

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| Prompt change broke evals → no version control | Commit prompts to git; tag versions |
| Different prompts for similar tasks | Extract shared prefix; centralize in templates / Langfuse |
| Long prompt with most of it irrelevant per call | Split into per-task prompts; or use prompt caching |
| Model ignoring an instruction buried in the middle | Move to start or end; use structure (XML / sections) |
| JSON output sometimes truncated | Increase `max_tokens`; consider streaming |
| Few-shot examples have a leak (give away answer) | Curate carefully; don't recycle eval examples as few-shots |
| Inconsistent output across runs | `temperature=0`; pin model version explicitly (`gpt-5-2025-XX-XX`) |
| Prompts work on big model, fail on small | Engineer down: more examples, more structure, smaller scope per call |
