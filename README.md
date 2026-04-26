# claudeforge

> Production-grade prompts, blueprints, and stack opinions for shipping real software with Claude Code.

`claudeforge` is a curated, opinionated library of detailed prompts and architecture blueprints for the frameworks and tools I actually ship with. Every prompt has been battle-tested on real production systems — not toy examples.

The repo is **markdown-first** so the content works in Claude Code, Cursor, Windsurf, plain ChatGPT, or any editor that lets you copy-paste. A thin layer of [Claude Code Skills](./.claude/skills/) wraps the workflow-shaped prompts (scaffolding, deployment, SSL setup) so they auto-invoke when you're using Claude Code.

---

## Why this exists

Most "awesome prompts" repos are shallow one-liners. The prompts here are full architectural specs:

- **Library evaluations** — what to use, what to reject, and *why* (with bundle sizes and tradeoffs).
- **Layered project scaffolds** — routes / services / repositories / models, not just "here's a `main.py`".
- **End-to-end deployment** — docker-compose + nginx + PM2 + SSH + Let's Encrypt, per framework.
- **Decision tables** — when to pick Celery vs BullMQ vs Redis Streams; Riverpod vs Bloc; Prom/Grafana vs SigNoz.

The goal is that you can drop a single prompt file into Claude Code and get a system that's still maintainable six months later.

---

## What's inside

93 markdown files, ~24,000 lines of opinionated production-grade guidance.

| Area | Contents |
|------|----------|
| [`frontend/`](./frontend) | Next.js (PROMPT, stack, design system, animations, responsive, forms+state, testing), Angular (standalone + signals) |
| [`backend/`](./backend) | FastAPI, NestJS, Node.js + Express — each with master scaffold prompt + 6 deep-dive guides on layout, ORM, validation, auth, async/queues, testing |
| [`databases/`](./databases) | PostgreSQL, MongoDB, Redis, Qdrant — schema patterns, indexing, ops, when to pick which |
| [`async-and-queues/`](./async-and-queues) | Celery, BullMQ, Redis Streams + decision matrix vs Kafka/RabbitMQ/Temporal |
| [`deployment/`](./deployment) | docker-compose, nginx reverse proxy, PM2, SSH bootstrap, Let's Encrypt SSL + per-framework deploy guides (Next.js, FastAPI, NestJS, Node) |
| [`mobile/`](./mobile) | Flutter (Riverpod variant), Flutter (Bloc variant), React Native (Expo SDK 52) |
| [`observability/`](./observability) | SigNoz + OpenTelemetry, Prometheus + Grafana + Tempo + Loki, Sentry, Langfuse |
| [`memory-layer/`](./memory-layer) | Graphiti + Mem0 dual-memory architecture, 31 entity/edge types, dev docker-compose |
| [`testing/`](./testing) | Agent-driven E2E via Chrome DevTools MCP and Puppeteer MCP + per-framework conventional testing |
| [`.claude/skills/`](./.claude/skills) | 16 Claude Code Skills wrapping the workflow-shaped prompts |
| [`meta/`](./meta) | How to use these prompts, philosophy, Skills explained |

---

## How to use

### Option 1 — Copy into your prompt

1. Find the relevant guide (e.g. `backend/fastapi/PROMPT.md`).
2. Copy it into your Claude Code session, or any other LLM IDE.
3. Customize the `{{placeholders}}` (project name, db name, ports, etc.).
4. Iterate.

### Option 2 — Use as a Claude Code Skill (workflow prompts only)

Symlink or copy `.claude/skills/` into your project's `.claude/skills/` (or `~/.claude/skills/` for global). Claude will auto-invoke the matching skill when you describe an intent like *"scaffold a FastAPI project"* or *"set up nginx + Let's Encrypt"*.

### Option 3 — Browse the architecture specs

The longer specs (design system, memory-layer architecture, observability) are reference reading. Skim before you build, then keep open as you implement.

---

## Conventions

- **Placeholders** use `{{double-braces}}`. Example: `{{project-name}}`, `{{db-name}}`, `{{domain}}`.
- **Decision tables** appear at the top of every guide so you can pick fast.
- **"Do not use" lists** are first-class — saying *no* to popular libraries is half the value.
- **Per-framework deployment** guides live in `deployment/per-framework/` because nginx config for Next.js is meaningfully different from FastAPI uvicorn behind nginx.

---

## License

[The Unlicense](./LICENSE) — public domain dedication. Use these in commercial work, fork them, modify them, ship them as-is. No attribution required. A link back is appreciated but not legally required.

---

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md). The bar is: opinionated, tested in production, and explains *why* — not just *how*.
