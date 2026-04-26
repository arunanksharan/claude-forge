# End-to-End: Building "OrderFlow", a B2B SaaS

> Hypothetical project. Demonstrates how to chain claudeforge prompts from "empty repo" to "deployed in production with monitoring." We don't build it — we walk through which prompts to apply at each step.

## The hypothetical product

**OrderFlow** — a B2B order-management SaaS:
- Multi-tenant (each customer = a tenant with users + orders)
- Web app for staff (Next.js)
- Mobile app for delivery drivers (React Native)
- API for backoffice + the apps (FastAPI)
- Postgres for data, Redis for cache + queues, Stripe for billing
- Self-hosted on a single VPS for v1

Concrete enough to anchor the walkthrough. Don't take this as a template for any specific project — adapt to yours.

---

## Phase 0 — Decisions before any code (1 day)

You haven't opened an editor yet. Read the deciders:

| Decision | Reference |
|----------|-----------|
| Backend framework: FastAPI vs NestJS vs Express | [`backend/fastapi/README.md`](../backend/fastapi/README.md), `nestjs/README.md`, `nodejs-express/README.md` — pick based on team language preference + ecosystem fit. **Picked: FastAPI.** |
| Web frontend | [`frontend/nextjs/README.md`](../frontend/nextjs/README.md). **Picked: Next.js 15 + App Router.** |
| Mobile | [`mobile/README.md`](../mobile/README.md). RN vs Flutter Riverpod vs Bloc. **Picked: Flutter + Riverpod** (drivers app needs to feel native). |
| Database | [`databases/README.md`](../databases/README.md). **Picked: Postgres** (default OLTP) + **Redis** (cache, queues). |
| Async | [`async-and-queues/workers-comparison.md`](../async-and-queues/workers-comparison.md). **Picked: Celery + Redis broker** (Python backend). |
| Observability | [`observability/README.md`](../observability/README.md). **Picked: Sentry** (errors) + **SigNoz** (metrics+traces). |
| Deployment target | [`deployment/README.md`](../deployment/README.md). **Picked: Single Hetzner VPS, Docker Compose.** |

**Output of this phase**: a 1-page decision doc you can reference later.

---

## Phase 1 — Backend scaffold (1 day)

### Step 1: scaffold the FastAPI project

In Claude Code:

```
/skill scaffold-fastapi
project_slug: orderflow
db_name: orderflow_dev
api_port: 8000
include_celery: yes
include_auth: yes
include_otel: yes
```

Or paste [`backend/fastapi/PROMPT.md`](../backend/fastapi/PROMPT.md) directly.

**What you get**: full project skeleton — `pyproject.toml` with locked deps, `src/orderflow/` layered tree, `alembic/` set up, `Dockerfile`, `docker-compose.dev.yml`, `Makefile`, one example feature (`users/`) end-to-end as a pattern.

### Step 2: define the domain models

Read [`backend/fastapi/02-sqlalchemy-and-alembic.md`](../backend/fastapi/02-sqlalchemy-and-alembic.md) — model patterns, FK, ENUMs, indexing.

Write `models/tenant.py`, `models/user.py`, `models/order.py`, `models/order_item.py`. For each: a Pydantic schema in `schemas/`, a repository in `repositories/`, a service in `services/`. Then routes in `api/v1/`.

Each layer is one PR — small, reviewable.

### Step 3: auth

Read [`backend/fastapi/04-auth-and-middleware.md`](../backend/fastapi/04-auth-and-middleware.md). Hand-rolled JWT with refresh tokens. Add `@CurrentUser` dependency. Add tenant-scoped auth (every query filtered by tenant from JWT).

For multi-tenancy: skim [`backend/fastapi/02-sqlalchemy-and-alembic.md`](../backend/fastapi/02-sqlalchemy-and-alembic.md) "multi-tenancy" section — pick row-filter or RLS.

### Step 4: queues for async work

Read [`backend/fastapi/05-async-and-celery.md`](../backend/fastapi/05-async-and-celery.md) and [`async-and-queues/celery.md`](../async-and-queues/celery.md). Set up Celery for:
- Sending order confirmation emails
- Webhook delivery to tenant-configured URLs
- Stripe billing reconciliation (nightly)

Three queues: `emails`, `webhooks`, `billing`. Workers separate per queue.

### Step 5: tests

Read [`backend/fastapi/06-testing-pytest.md`](../backend/fastapi/06-testing-pytest.md). Set up pytest with real Postgres in Docker. Write integration tests for the auth flow + creating an order. **Don't aim for 100% coverage yet** — get the green path covered, edge cases come as you ship.

**Output of Phase 1**: working backend locally with `make dev`, a few endpoints, tests passing.

---

## Phase 2 — Web frontend (2 days)

### Step 1: scaffold Next.js

```
/skill scaffold-nextjs
project_slug: orderflow-admin
app_type: admin
include_auth: yes
brand_primary_hex: #0EA5E9
deployment_target: self-hosted
```

Or paste [`frontend/nextjs/PROMPT.md`](../frontend/nextjs/PROMPT.md).

**What you get**: Next.js 15 + React 19 with locked stack (shadcn/ui, TanStack Query, Zustand, react-hook-form + zod, etc.).

### Step 2: design system

Read [`frontend/nextjs/02-design-system-spec.md`](../frontend/nextjs/02-design-system-spec.md) — adapt the token system to OrderFlow's brand. The 1700-line spec is reference; you copy + adapt the parts you need.

### Step 3: auth flow

Read [`frontend/nextjs/05-forms-and-state.md`](../frontend/nextjs/05-forms-and-state.md). Build login + signup with react-hook-form + zod, store JWT in httpOnly cookie via API route, use middleware for auth-gated routes.

### Step 4: data flows

Read [`frontend/nextjs/05-forms-and-state.md`](../frontend/nextjs/05-forms-and-state.md) — TanStack Query patterns. Set up `lib/api-client.ts` to talk to the FastAPI backend. Build the `/orders` page (Server Component fetching initial list + Client Component for interactions).

### Step 5: animation polish

Read [`frontend/nextjs/03-animations-and-motion.md`](../frontend/nextjs/03-animations-and-motion.md). Add page transitions via `template.tsx`, fade-in for the orders list, a sonner toast for "order created."

### Step 6: mobile responsive

Read [`frontend/nextjs/04-mobile-responsive.md`](../frontend/nextjs/04-mobile-responsive.md). Verify the admin app works on tablets (not phones — drivers use the Flutter app). Bottom-sheet for actions on tablet view.

### Step 7: tests

Read [`frontend/nextjs/06-testing-with-chrome-devtools-mcp.md`](../frontend/nextjs/06-testing-with-chrome-devtools-mcp.md). Vitest for components, Playwright for one critical flow (login → create order → see in list). Use Chrome DevTools MCP for exploratory testing as you build.

**Output of Phase 2**: web app talks to backend, login works, can CRUD orders.

---

## Phase 3 — Mobile app (2-3 days)

### Step 1: scaffold Flutter (Riverpod)

```
/skill scaffold-flutter-riverpod
app_name: orderflow_driver
package_id: com.orderflow.driver
include_auth: yes
include_local_db: yes
api_base_url: https://api.orderflow.example.com
```

Or paste [`mobile/flutter-riverpod/PROMPT.md`](../mobile/flutter-riverpod/PROMPT.md).

**What you get**: Flutter project with feature-first folders, freezed models, dio + retrofit, drift for local cache, go_router.

### Step 2: auth + offline-first

The drivers app needs to work without network (offline order list, sync when online). Build:

- `features/auth/` — same shape as the web auth
- `features/orders/` — drift DAO + repository syncing with API; Riverpod controller exposes the local data as the source of truth, sync runs in background

Reference: the auth feature in the scaffold prompt; extend with the drift DAO.

### Step 3: route + status updates

Drivers update order status (`picked_up`, `in_transit`, `delivered`). Each tap triggers:
- Optimistic local update
- Background sync to API
- Conflict resolution if API rejects (e.g., order was cancelled)

### Step 4: native integrations

GPS for delivery photo + signature capture. Use `geolocator`, `image_picker`, `signature` packages. These are outside the prompt — Flutter ecosystem is huge, search pub.dev.

### Step 5: tests

Widget tests for the order list, integration test (`integration_test/`) for the auth flow against a mocked API. Maestro for E2E if you set it up.

**Output of Phase 3**: drivers app works end-to-end (auth, list orders, update status), offline-capable.

---

## Phase 4 — Production deployment (1 day)

### Step 1: bootstrap the VPS

```
/skill deploy-vps-bootstrap
```

Or follow [`deployment/ssh-and-remote-server-setup.md`](../deployment/ssh-and-remote-server-setup.md) manually. End state: Ubuntu 24.04 server, deploy user, UFW + fail2ban, Docker installed.

### Step 2: deploy the backend

```
/skill deploy-docker-nginx-ssl
framework: fastapi
domain: api.orderflow.example.com
```

Or follow [`deployment/per-framework/deploy-fastapi.md`](../deployment/per-framework/deploy-fastapi.md). End state: FastAPI behind nginx with Let's Encrypt SSL on `api.orderflow.example.com`.

### Step 3: deploy the web app

Same skill, framework: `nextjs`, domain: `app.orderflow.example.com`. See [`deployment/per-framework/deploy-nextjs.md`](../deployment/per-framework/deploy-nextjs.md) for Next.js standalone build specifics.

### Step 4: mobile distribution

For Flutter via Firebase App Distribution (testers) or TestFlight + Play Console (public). Outside this repo — search "Flutter EAS / Firebase App Distribution."

### Step 5: monitoring

```
/skill wire-sentry
```

Add Sentry to FastAPI ([`observability/03-sentry.md`](../observability/03-sentry.md)), Next.js, and Flutter. Each one has a section in `03-sentry.md`.

```
/skill wire-otel-prom-grafana
```

Or, since Phase 0 picked SigNoz: follow [`observability/01-signoz-opentelemetry.md`](../observability/01-signoz-opentelemetry.md) — instrument FastAPI with OpenTelemetry, ship to SigNoz.

**Output of Phase 4**: live in production with HTTPS, error tracking, and APM.

---

## Phase 5 — CI/CD (1 day)

### Step 1: backend pipeline

Read [`cicd/github-actions-fastapi.md`](../cicd/github-actions-fastapi.md). Three workflows:
- `ci.yml` — runs on PR (lint, type, test against real Postgres)
- `build-and-push.yml` — runs on main (builds Docker, pushes to GHCR)
- `deploy.yml` — runs on tag (SSHs to server, runs migration, swaps containers)

### Step 2: frontend pipeline

Read [`cicd/github-actions-nextjs.md`](../cicd/github-actions-nextjs.md). Same shape, with Lighthouse CI as a quality gate.

### Step 3: secrets

Read [`cicd/secrets-and-environments.md`](../cicd/secrets-and-environments.md). Set up GitHub Environments (`staging`, `production`) with required reviewers on production. Per-env secrets (`DATABASE_URL`, `JWT_SECRET`, etc.).

### Step 4: deploy automation

Read [`cicd/deploy-automation.md`](../cicd/deploy-automation.md). Server has `/var/www/orderflow/scripts/deploy.sh`. CI just SSHs and runs it. Health-check + rollback built in.

**Output of Phase 5**: every PR gates on tests; merging to main builds + tags an image; deployment is one approval click.

---

## Phase 6 — Pre-launch security (half day)

Read [`security/security-review-checklist.md`](../security/security-review-checklist.md). Walk through every item. Fix gaps. Document accepted risks.

Read [`security/threat-modeling.md`](../security/threat-modeling.md). Run a 30-min STRIDE pass on:
- Login + password reset
- Order create + status change
- Webhook delivery (you fetch user-supplied URLs — SSRF risk)

Fix the highest-likelihood / highest-impact threats. Document the rest.

Read [`security/secrets-management.md`](../security/secrets-management.md). Verify:
- Different JWT secret in staging vs prod
- `.env` files `chmod 600`
- gitleaks runs in CI
- GitHub secret scanning enabled

**Output of Phase 6**: launch-ready, with documented threat model + filled checklist.

---

## Phase 7 — Stripe billing (1 day)

Outside this repo's current scope (Stripe is broad). The flow:
- Read Stripe's docs for SaaS subscription billing
- Implement webhook receiver (verify signature! — see `security/owasp-top-10-quickref.md` A08)
- Use Celery for sync (`reconcile_subscription` task)
- Use Sentry for capture
- Pen-test the webhook endpoint

Future: a `payment-processing/` folder in claudeforge could codify this.

---

## Phase 8 — Iterate (forever)

Now you're shipping. Per feature, the loop:

1. **Design**: 30-min STRIDE pass ([`security/threat-modeling.md`](../security/threat-modeling.md))
2. **Implement**: layer-by-layer per the framework guides
3. **Test**: write unit + integration tests; use Chrome DevTools MCP for exploratory ([`testing/e2e-with-chrome-devtools-mcp.md`](../testing/e2e-with-chrome-devtools-mcp.md))
4. **Review**: code review; run evals if AI-touching
5. **Ship**: PR → CI → merge → auto-deploy to staging → reviewed deploy to prod
6. **Monitor**: Sentry + SigNoz dashboards
7. **Postmortem** any incident; add a regression test

Quarterly:
- Rotate non-OIDC secrets
- Refresh threat model
- Test backups
- Review IAM

---

## Time budget summary

| Phase | Duration | What you get |
|-------|----------|--------------|
| 0 — Decisions | 1 day | Decision doc, no code |
| 1 — Backend scaffold | 1 day | Working API locally |
| 2 — Web frontend | 2 days | Web app talks to backend |
| 3 — Mobile app | 2-3 days | Drivers app works |
| 4 — Production deploy | 1 day | Live with HTTPS + monitoring |
| 5 — CI/CD | 1 day | Auto-deploy on merge |
| 6 — Security review | 0.5 day | Launch checklist done |
| 7 — Billing | 1 day | Subscriptions working |
| **Total** | **~10 days** | A real shipping SaaS |

A solo dev with this repo can take a project from idea to production in ~2 weeks. Without the prompts, expect 3-6 weeks of bikeshedding library choices, recreating layered scaffolds, debugging deploy configs.

The value isn't speed — it's **correctness without thinking too hard about every decision.**

---

## What this example skips

- The actual product domain decisions (what tables, what API surface) — you'd think through these per project
- Frontend design specifics (use the design system spec as a starting point + iterate with users)
- Stripe specifics (broad domain; future claudeforge folder)
- ML/AI features (see `examples/end-to-end-ai-agent.md`)
- Marketing site (separate Next.js project, simpler version of the admin app's setup)

The point of the walkthrough isn't completeness — it's the **structure of how prompts compose into a project**.
