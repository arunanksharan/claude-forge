# Memory Layer — claudeforge guides

Patterns for giving AI agents durable, queryable memory that survives across sessions, channels, and conflicts in user-stated facts.

## Files in this folder

| File | What it is |
|------|-----------|
| [`01-dual-memory-architecture.md`](./01-dual-memory-architecture.md) | The core pattern: Graphiti (truth) + Mem0 (speed cache). Identity resolution, query routing, write/read paths, voice prefetch flow, PII compliance |
| [`02-entity-and-edge-types.md`](./02-entity-and-edge-types.md) | 31 entity types + 31 edge types modeled as Pydantic schemas for LLM-driven extraction. Telecom + personal + emotional + AI-relationship domains |
| [`03-docker-compose-setup.md`](./03-docker-compose-setup.md) | Full local dev stack: Neo4j + MongoDB + Redis + Qdrant + SigNoz, all wired up |

## Quick decision summary

- **Pure cache** (no temporal queries, no conflict resolution): use **Mem0 alone**
- **Pure knowledge graph** (no latency constraint): use **Graphiti alone** (~300ms retrieval)
- **Voice or real-time agent** with cross-session memory: use **both** — Mem0 for the hot path, Graphiti as source of truth, async sync between them

## Why this pattern exists

A naive memory layer concatenates raw chat history into the prompt. That breaks at scale: prompts get huge, contradictions accumulate (user says "I live in Tokyo" then "I just moved to Berlin"), and there's no way to ask *temporal* questions ("when did I switch jobs?").

The dual-memory architecture solves this by:
- Storing **mentions** ephemerally (short TTL, raw user statements)
- Extracting **validated facts** asynchronously into a knowledge graph
- Resolving conflicts via bi-temporal metadata (`valid_at`, `invalid_at`)
- Serving the cached, validated facts back to the agent on the next turn

The detailed reasoning, latency budgets, and code patterns are in `01-dual-memory-architecture.md`.
