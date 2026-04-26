# claudeforge

> Production-grade prompts, blueprints, and stack opinions for shipping real software with Claude Code.

`claudeforge` is a curated, opinionated library of detailed prompts and architecture blueprints for the frameworks and tools I actually ship with. Every prompt has been battle-tested on real production systems — not toy examples.

The repo is **markdown-first** so the content works in Claude Code, Cursor, Windsurf, plain ChatGPT, or any editor that lets you copy-paste. A thin layer of [Claude Code Skills](./.claude/skills/) wraps the workflow-shaped prompts (scaffolding, deployment, SSL setup) so they auto-invoke when you're using Claude Code.

**170 files, ~40,000 lines, MIT-public-domain (Unlicense).**

---

## Why this exists

Most "awesome prompts" repos are shallow one-liners. The prompts here are full architectural specs:

- **Library evaluations** — what to use, what to reject, and *why* (with bundle sizes and tradeoffs).
- **Layered project scaffolds** — routes / services / repositories / models, not just "here's a `main.py`".
- **End-to-end deployment** — docker-compose + nginx + PM2 + SSH + Let's Encrypt, per framework.
- **Decision tables** — when to pick Celery vs BullMQ vs Redis Streams; Riverpod vs Bloc; Prom/Grafana vs SigNoz.
- **Real config files** — sanitized docker-compose, nginx server blocks, init scripts pulled from a production stack, not invented examples.

The goal: drop a single prompt file into Claude Code and get a system that's still maintainable six months later.

---

## Quickstart — pick your path

### "I want a new web app"

```
backend/{fastapi,nestjs,nodejs-express}/PROMPT.md   # pick one
+ frontend/nextjs/PROMPT.md
+ databases/postgres/PROMPT.md
+ deployment/per-framework/deploy-{your-framework}.md
+ cicd/github-actions-{your-framework}.md
+ security/security-review-checklist.md
```

Or follow the chain in [`examples/end-to-end-saas-app.md`](./examples/end-to-end-saas-app.md) — a 9-phase walkthrough naming each prompt at each step.

### "I want a mobile app + backend"

```
mobile/flutter-riverpod/PROMPT.md  (or flutter-bloc / react-native)
+ backend/fastapi/PROMPT.md
+ databases/postgres/PROMPT.md
+ infra-recipes/shared-stack/         # ready-to-deploy docker-compose
```

Walk-through: [`examples/end-to-end-mobile-with-backend.md`](./examples/end-to-end-mobile-with-backend.md).

### "I want an AI agent (RAG + tool use + memory)"

```
ai-agents/rag-patterns.md            # RAG variants beyond naive
+ ai-agents/tool-use.md              # tool design + security
+ ai-agents/agent-architectures.md   # ReAct / plan-execute
+ ai-agents/evals.md                 # build evals BEFORE the agent
+ memory-layer/01-dual-memory-architecture.md  # cross-session memory
+ databases/qdrant/PROMPT.md         # or postgres/05-pgvector-and-rag.md
+ databases/neo4j/PROMPT.md          # for knowledge graphs
+ observability/04-langfuse.md       # LLM-specific observability
```

Walk-through: [`examples/end-to-end-ai-agent.md`](./examples/end-to-end-ai-agent.md).

### "I want to deploy to a fresh VPS today"

```
deployment/ssh-and-remote-server-setup.md   # 30-min Ubuntu hardening
+ infra-recipes/shared-stack/                # one compose, all the services
+ deployment/nginx-reverse-proxy.md
+ deployment/lets-encrypt-ssl.md
+ infra-recipes/scripts/create-postgres-db.sh   # per-app DBs in seconds
```

### "I want to self-host my own SaaS replacements"

```
infra-recipes/self-hosted/signoz/      # Datadog alternative
+ infra-recipes/self-hosted/docmost/   # Notion alternative
+ infra-recipes/self-hosted/twenty-crm/  # HubSpot alternative
+ infra-recipes/self-hosted/plane/     # Jira / Linear alternative
+ infra-recipes/self-hosted/n8n/       # Zapier alternative
```

All connect to one shared Postgres + Redis + MinIO. Run on a single $20-40/mo VPS.

---

## What's inside

| Area | Contents |
|------|----------|
| [`frontend/`](./frontend) | **Next.js** (PROMPT + 6 sub-files: stack evaluation, design system spec, animations, mobile-responsive, forms+state, MCP testing) — **Angular** (PROMPT + signals/state + Vitest testing) |
| [`backend/`](./backend) | **FastAPI**, **NestJS**, **Node.js + Express** — each with master scaffold prompt + 6 deep-dive guides on layout, ORM, validation, auth, async/queues, testing |
| [`databases/`](./databases) | **Postgres, MongoDB, Redis, Qdrant, Neo4j** — each with PROMPT.md + 4-5 deep sub-files (schema design, queries+indexes, operations, language clients) |
| [`async-and-queues/`](./async-and-queues) | **Celery, BullMQ, Redis Streams** + decision matrix vs Kafka/RabbitMQ/Temporal |
| [`deployment/`](./deployment) | docker-compose patterns, nginx reverse proxy, PM2, SSH bootstrap, Let's Encrypt + per-framework deploy guides (Next.js, FastAPI, NestJS, Node) |
| [`mobile/`](./mobile) | **Flutter Riverpod** (PROMPT + providers + offline-first), **Flutter Bloc** (PROMPT + bloc_test patterns), **React Native** (PROMPT + EAS Build/Update) |
| [`observability/`](./observability) | SigNoz + OTel, Prometheus + Grafana + Tempo + Loki, Sentry, Langfuse |
| [`memory-layer/`](./memory-layer) | Graphiti + Mem0 dual-memory architecture, 31 entity/edge types, dev compose stack |
| [`testing/`](./testing) | Agent-driven E2E via Chrome DevTools MCP + Puppeteer MCP + per-framework conventional |
| [`cicd/`](./cicd) | GitHub Actions per framework, deploy automation, secrets + environments |
| [`ai-agents/`](./ai-agents) | Agent architectures, RAG variants (naive → hybrid → contextual → agentic → GraphRAG), tool use, evals, prompt engineering |
| [`security/`](./security) | Pre-launch checklist, STRIDE threat modeling, secrets management, OWASP top 10 quickref |
| [`infra-recipes/`](./infra-recipes) | **Sanitized docker-compose + scripts from a real production deployment**: shared-stack (Postgres+pgvector / Mongo / Redis / Qdrant / MinIO / n8n), self-hosted SigNoz/Plane/Twenty/Docmost, nginx templates (HTTPS / WebSocket / SSE / TURN-TLS), LiveKit production config, helper scripts |
| [`examples/`](./examples) | End-to-end walkthroughs that chain the prompts to build real systems (SaaS / AI agent / mobile + backend) |
| [`.claude/skills/`](./.claude/skills) | 16 Claude Code Skills wrapping the workflow-shaped prompts for auto-invocation |
| [`meta/`](./meta) | How to use these prompts, prompt-engineering philosophy, Skills explained |

---

## The locked stack (what's opinionated)

These are the defaults across all guides. Override per-project as needed — the rejected-library tables tell you when *not* to deviate.

### Backend

| Concern | Pick | Why |
|---------|------|-----|
| Python framework | **FastAPI** | async-first, Pydantic-native, OpenAPI free |
| Python ORM | **SQLAlchemy 2.0 async** + **asyncpg** + **Alembic** | mature, full async path |
| Python package manager | **uv** | 10-100× faster than pip |
| Python tests | **pytest** + **pytest-asyncio** + real Postgres in Docker | catches bugs mocks miss |
| Node framework (rich DI) | **NestJS** + **Prisma** | enterprise-grade structure |
| Node framework (lean) | **Express 5** + **Drizzle** | factory-function wiring, no DI container |
| Node tests | **Vitest** + **Supertest** | faster than Jest |
| Auth | **Hand-rolled JWT** for simple, **fastapi-users / @nestjs/passport** for complex | |
| Background jobs (Python) | **Celery** + Redis | mature, extensive ecosystem |
| Background jobs (Node) | **BullMQ** | active, Redis-backed, great DX |
| Cross-service events | **Redis Streams** with consumer groups (light) or **Kafka** (heavy) | |

### Frontend / Mobile

| Concern | Pick |
|---------|------|
| Web framework | **Next.js 15+ App Router** on **React 19** |
| UI components | **shadcn/ui** (Radix + CVA + Tailwind 4) — *not* MUI/Mantine/antd/Chakra |
| Server state | **TanStack Query v5** |
| Client state | **Zustand** |
| Forms | **react-hook-form** + **zod** |
| Animation | **framer-motion** |
| Mobile (Flutter) | **Flutter 3.27+** with **Riverpod 2** (codegen) or **Bloc 8** |
| Mobile (RN) | **Expo SDK 52+** + **expo-router** + **TanStack Query** + **MMKV** |
| Angular | **Angular 18+** standalone + **signals** + **NgRx Signal Store** |

### Databases

| Need | Pick |
|------|------|
| Default OLTP | **Postgres 17** (with **pgvector** for embeddings up to ~1M) |
| Document model with deep nesting | **MongoDB 8.0** (think twice — Postgres+jsonb covers more than you'd guess) |
| Cache, sessions, queues, locks | **Redis 8.0** |
| Vector search at scale (>1M) | **Qdrant** |
| Graph workloads (knowledge graphs, agent memory, fraud) | **Neo4j 5.26 LTS** + Graphiti |

### Infra / Deployment

| Concern | Pick |
|---------|------|
| Single-VPS hosting | **Hetzner / DigitalOcean / Vultr** + **Docker Compose** |
| Reverse proxy | **nginx** (or Caddy for zero-config SSL) |
| TLS | **Let's Encrypt** via certbot |
| Process management (Node) | **PM2** in cluster mode |
| CI/CD | **GitHub Actions** + GHCR for images, OIDC for cloud auth |

### Observability + AI

| Concern | Pick |
|---------|------|
| Errors | **Sentry** (frontend + backend + mobile) |
| APM (managed) | **Datadog / New Relic** |
| APM (self-hosted, all-in-one) | **SigNoz** |
| APM (self-hosted, modular) | **Prometheus + Grafana + Tempo + Loki** + OpenTelemetry |
| LLM tracing | **Langfuse** (prompts, completions, datasets, evals) |
| Memory for AI agents | **Graphiti** (Neo4j) + **Mem0** (Qdrant) — dual-store architecture |
| Embedding model | **OpenAI text-embedding-3-small** (1536d, cosine) — start here |
| Reranker | **Cohere Rerank v3** — high-leverage; almost always worth adding |

### Versions tracked (2026)

Postgres 17 · MongoDB 8.0 · Redis 8.0 · Qdrant latest · Neo4j 5.26 LTS · Next.js 15 · React 19 · Expo SDK 52 · Flutter 3.27+ · Angular 18+ · Node.js 22 LTS · Python 3.12+

---

## How to use

### Option 1 — Copy into your prompt (works anywhere)

The lowest-friction path. Open the relevant `PROMPT.md`, copy contents into Claude Code / Cursor / Windsurf / ChatGPT / Aider, fill in `{{placeholders}}`.

```
You: <paste backend/fastapi/PROMPT.md>

Now scaffold this for project "{{project-slug}}" = "orderflow",
db_name = "orderflow_dev", api_port = 8000, include Celery + JWT auth.
```

You don't need Claude Code to use this repo. That's intentional.

### Option 2 — Use as Claude Code Skills (auto-invocation)

For workflow-shaped prompts (scaffolding, deployment, SSL setup), the repo ships [Skill wrappers](./.claude/skills/). Claude Code auto-invokes the matching one based on intent.

```bash
# project-scoped (skills available only inside one project)
ln -s /path/to/claudeforge/.claude/skills /path/to/your-project/.claude/skills

# or user-scoped (skills available everywhere)
cp -r /path/to/claudeforge/.claude/skills/* ~/.claude/skills/
```

Then in Claude Code:

> "Set up a FastAPI project with the layered architecture I usually use."

Claude inspects available Skill descriptions, picks `scaffold-fastapi`, follows its instructions. You don't have to remember the Skill name.

**Available Skills (16):** scaffold-fastapi, scaffold-nestjs, scaffold-nodejs-express, scaffold-nextjs, scaffold-flutter-riverpod, scaffold-flutter-bloc, scaffold-react-native, scaffold-angular, deploy-vps-bootstrap, deploy-docker-nginx-ssl, wire-sentry, wire-otel-prom-grafana, wire-langfuse, setup-celery, setup-bullmq, setup-redis-streams.

See [`meta/claude-code-skills-explained.md`](./meta/claude-code-skills-explained.md) for what Skills can/can't do.

### Option 3 — Reference reading (architecture specs)

Some files are not prompts — they're architecture specs you read *before* implementation:

- [`frontend/nextjs/02-design-system-spec.md`](./frontend/nextjs/02-design-system-spec.md) — full design token system (1700+ lines)
- [`memory-layer/01-dual-memory-architecture.md`](./memory-layer/01-dual-memory-architecture.md) — read before designing AI agent memory
- [`ai-agents/rag-patterns.md`](./ai-agents/rag-patterns.md) — RAG variants and when to pick which
- [`async-and-queues/workers-comparison.md`](./async-and-queues/workers-comparison.md) — Celery vs BullMQ vs Streams vs Kafka

Treat them like a senior engineer's notes.

### Option 4 — End-to-end walkthroughs

[`examples/`](./examples/) contains three full chains:

| Walkthrough | Time | Phases | What you build |
|-------------|------|--------|----------------|
| [`end-to-end-saas-app.md`](./examples/end-to-end-saas-app.md) | ~10 days | 9 | A B2B SaaS (FastAPI + Next.js + Flutter + multi-tenant Postgres + Stripe billing) |
| [`end-to-end-ai-agent.md`](./examples/end-to-end-ai-agent.md) | ~9 days | 10 | RAG + tool-use customer support agent with cross-session memory and evals |
| [`end-to-end-mobile-with-backend.md`](./examples/end-to-end-mobile-with-backend.md) | ~9 days | 7 | Offline-first Flutter app + FastAPI backend + shared CI/CD |

Each names exactly which prompt to use at each step. Adapt the sequence to your project.

---

## What makes this different from other prompt libraries

| Most "awesome prompts" repos | claudeforge |
|------------------------------|-------------|
| Shallow one-liners | Full architectural specs (200-1700 lines per file) |
| Generic "you are an expert" framing | Concrete `PROMPT.md` with directory tree, locked deps, generation steps |
| Library lists with no opinion | Library evaluations with bundle sizes + rejection rationales |
| No deployment story | Per-framework end-to-end deploy guides (compose + nginx + PM2 + SSL) |
| No evals / observability | Eval frameworks, Sentry, OTel, Langfuse with code |
| Toy examples | Real production configs sanitized into reusable templates |
| No security | Pre-launch checklist + STRIDE threat modeling + OWASP 10 quickref |
| Locked to one tool | Markdown-first → works in Claude Code, Cursor, Windsurf, ChatGPT |

---

## Anti-patterns rejected

Throughout the repo. A few representative bans:

| Library | Why rejected |
|---------|--------------|
| `antd` / `material-ui` / `chakra-ui` | Runtime CSS-in-JS conflicts with Tailwind |
| `psycopg2` (sync) | Use `asyncpg` for async, `psycopg3` for both |
| `bull` (v3 classic) | Deprecated; use BullMQ |
| `nodemon`, `ts-node` in production | Use `tsx watch` (dev) and `node dist/` (prod) |
| `bcryptjs` (pure JS) | Slow; use native `bcrypt` or `argon2` |
| `bcrypt` with rounds < 10 | Easily brute-forced |
| `formik` | Dead project; use react-hook-form |
| `lenis` (scroll hijacking) | Breaks accessibility, anchor links, screen readers |
| `react-icons` | Barrel-file import problem; use `lucide-react` |
| `axios` standalone | Use `undici` (Node) or native `fetch` |
| `winston` | Use `pino` — much faster, structured |
| Long-lived AWS keys in CI | Use OIDC |
| `:latest` Docker tag in production | Pin to `<branch>-<sha>` |
| Polymorphic associations in Postgres | Anti-pattern; use real FKs per relationship |
| Soft delete by default | Causes more bugs than it solves; prefer real DELETE + audit log |
| Multi-agent before single-agent ceilings out | Premature complexity |
| Building agents without evals | You can't iterate without measurement |

---

## Conventions

- **Placeholders** use `{{double-braces}}`. Examples: `{{project-name}}`, `{{db-name}}`, `{{domain}}`.
- **Decision tables** appear at the top of every guide so you can pick fast.
- **"Do not use" lists** are first-class — saying *no* to popular libraries is half the value.
- **Per-framework deployment** guides live in `deployment/per-framework/` because nginx config for Next.js is meaningfully different from FastAPI uvicorn behind nginx.
- **Common pitfalls** table at the bottom of every guide — what tripped me up so it doesn't trip you up.
- **Layered architecture** enforced strictly in backend guides (routes → services → repositories → models). Discipline is what keeps a codebase navigable past 50K LOC.

---

## Repository structure (top-level)

```
claudeforge/
├── README.md                         # this file
├── LICENSE                           # The Unlicense
├── CONTRIBUTING.md
│
├── frontend/                         # Next.js, Angular
├── backend/                          # FastAPI, NestJS, Express
├── databases/                        # Postgres, Mongo, Redis, Qdrant, Neo4j
├── mobile/                           # Flutter (Riverpod, Bloc), React Native
├── async-and-queues/                 # Celery, BullMQ, Streams, decision matrix
├── deployment/                       # compose, nginx, PM2, SSH, SSL, per-framework
├── observability/                    # SigNoz, Prom+Grafana, Sentry, Langfuse
├── memory-layer/                     # Graphiti + Mem0 architecture
├── testing/                          # MCP-driven E2E + per-framework
├── cicd/                             # GitHub Actions + deploy automation
├── ai-agents/                        # architectures, RAG, tool use, evals
├── security/                         # checklist, STRIDE, secrets, OWASP 10
├── infra-recipes/                    # sanitized prod docker-compose + scripts
│   ├── shared-stack/                 # 1 compose: PG+pgvector+Mongo+Redis+Qdrant+MinIO+n8n
│   ├── self-hosted/                  # SigNoz, Docmost, Twenty CRM, Plane, n8n
│   ├── nginx-templates/              # HTTPS, WebSocket, SSE, TURN-TLS
│   ├── livekit/                      # WebRTC server config
│   └── scripts/                      # create-postgres-db, etc.
├── examples/                         # end-to-end walkthroughs
├── .claude/skills/                   # 16 Skill wrappers
└── meta/                             # how-to-use, philosophy, skills-explained
```

Per-framework / per-database folders all follow the same shape:

```
{folder}/
├── README.md                         # overview + decision summary
├── PROMPT.md                         # paste-into-Claude master scaffold prompt
├── 01-{topic}.md                     # deep-dive
├── 02-{topic}.md                     # deep-dive
├── ...
```

---

## Stats

- **170 files** across 17 top-level directories
- **~40,000 lines** of opinionated content
- **24 commits** on `main`
- **License**: [The Unlicense](./LICENSE) (public domain dedication; no attribution required)
- **Companion prompts**: 16 Claude Code Skills, all with auto-invocation descriptions
- **Versions tracked**: latest stable as of 2026

---

## License

[**The Unlicense**](./LICENSE) — public domain dedication. Use these in commercial work, fork them, modify them, ship them as-is. No attribution required, no copyleft, no legal strings.

A link back is appreciated but not legally required.

---

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md). The bar is high:

- **Opinionated** — pick one stack and explain why
- **Tested in production** — not "this looked good in a tutorial"
- **Explains the *why*** — not just the *how*
- **Lists rejections** — what you considered and why you didn't pick it
- **Sanitized of personal/company identifiers**

Areas where help is welcome:
- New framework guides (Phoenix LiveView, Rails 8, Spring Boot, Go + Fiber, Hono)
- New deployment targets (Fly.io, Railway, Hetzner Robot, bare metal)
- More mobile (native iOS/Android, Ionic, Tauri)
- Battle stories — bugs caught (or missed) by these patterns

---

## Acknowledgments

Built collaboratively with [Claude Code](https://claude.com/claude-code) over multiple iterative sessions, reviewing real production codebases for the patterns + library choices.

Inspired by:
- The shadcn/ui philosophy ("you own the code")
- The 12-factor app methodology
- Years of "I keep typing the same prompt" frustration

If this saves you a week of bikeshedding, share it with a colleague. That's the only "thanks" I want.

---

## Links

- **Repo**: https://github.com/arunanksharan/claude-forge
- **Issues / suggestions**: https://github.com/arunanksharan/claude-forge/issues
- **Author**: [@arunanksharan](https://github.com/arunanksharan)
