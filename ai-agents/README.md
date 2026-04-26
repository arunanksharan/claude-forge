# AI Agents — claudeforge guides

Patterns for building production LLM applications beyond "wrap a chat completion." Architecture, RAG variants, tool use, evaluation.

## Files

| File | What it is |
|------|-----------|
| [`agent-architectures.md`](./agent-architectures.md) | ReAct, plan-execute, multi-agent, when to pick which |
| [`rag-patterns.md`](./rag-patterns.md) | Naive RAG, hybrid search, multi-query, contextual, agentic, GraphRAG |
| [`tool-use.md`](./tool-use.md) | Function calling, tool design, MCP servers, security, error handling |
| [`evals.md`](./evals.md) | Eval frameworks, datasets, judges (LLM-as-judge), regression tests |
| [`prompt-engineering.md`](./prompt-engineering.md) | XML structure, few-shot, CoT, prefilling, output format control |

## Companion: memory layer

For agent memory specifically, see [`memory-layer/`](../memory-layer/) — Graphiti + Mem0 dual-memory architecture for cross-session, cross-channel agent state.

## Decision summary

- **Single LLM call**: don't call it an "agent" — just call the LLM
- **LLM + retrieval**: RAG (`rag-patterns.md`)
- **LLM + tool use**: function calling / agents (`tool-use.md`, `agent-architectures.md`)
- **Multi-step workflows with retries/state**: durable execution (Temporal / Inngest), not just an agent loop
- **Multiple specialized agents collaborating**: multi-agent (`agent-architectures.md`) — but think hard before adding orchestration complexity

## Anti-patterns rejected

- **"Let's build an agent for everything"** — most problems are better solved by deterministic code + a tactical LLM call
- **Naive `while True: agent.run()`** without step limits → cost explosion + infinite loops
- **No evals before shipping** — you can't iterate on prompts without measurement
- **PII in prompts/logs** — same scrubbing rules as the rest of the stack
- **Tool descriptions that lie** — the model trusts them; lying tools = unreliable agent
