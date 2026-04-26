# Infra Recipes — claudeforge

> Ready-to-use, sanitized docker-compose files, init scripts, nginx templates, and helper scripts pulled from a real production multi-service deployment. Pair with the database / framework / deployment guides for full context.

These are NOT generic boilerplate — they are the actual files that run in production with names and credentials replaced by `${VAR}` placeholders. Adapt to your needs.

## Folders

| Folder | What it is |
|--------|-----------|
| [`shared-stack/`](./shared-stack) | The core shared infrastructure: Postgres+pgvector, MongoDB, Redis, Qdrant, MinIO, n8n. One docker-compose, one network, all apps connect to it. |
| [`self-hosted/`](./self-hosted) | Per-app compose files for self-hosted apps (SigNoz, Plane PM, Twenty CRM, Docmost wiki, n8n) that connect to `shared-stack/` |
| [`nginx-templates/`](./nginx-templates) | Reusable nginx server-block templates: HTTPS, WebSocket, SSE, TURN-TLS, generic reverse proxy |
| [`livekit/`](./livekit) | LiveKit production config (TURN over TLS, Redis-backed rooms) |
| [`scripts/`](./scripts) | Helper scripts: create per-project DB (Postgres + Mongo), bring services up safely, generate credentials, init DBs |

## How to use

1. **Copy `shared-stack/` to your server**: `/opt/infra/`
2. **Customize `shared-stack/.env`**: passwords, DB names, ports
3. **Bring up shared services**: `docker compose -f shared-stack/docker-compose.yml up -d`
4. **For each app** that uses shared infra (e.g., n8n, Plane CRM, Docmost): create the per-project DB via `scripts/create-postgres-db.sh <name>`, then `docker compose -f self-hosted/<app>/docker-compose.yml up -d`
5. **For nginx**: pick a template from `nginx-templates/`, drop into `/etc/nginx/sites-available/<domain>`, `ln -s` to `sites-enabled`, run certbot per [`deployment/lets-encrypt-ssl.md`](../deployment/lets-encrypt-ssl.md)

## Architecture

```
                    nginx (443)  ←  Let's Encrypt
                       │
       ┌───────────────┼───────────────┬──────────────┐
       │               │               │              │
   app.example.com  wiki.example.com  crm.example.com  plane.example.com
   (your app)      (Docmost)         (Twenty CRM)     (Plane)
       │               │               │              │
       └───────────────┴───────┬───────┴──────────────┘
                               │
                               ▼
   ┌─────────────────────────────────────────────────────────────────┐
   │                     shared-stack network                         │
   │                                                                  │
   │   postgres+pgvector  ●  mongodb  ●  redis  ●  qdrant  ●  minio  │
   │                                                                  │
   └─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
                     observability (SigNoz / Prom)
```

Multiple self-hosted apps share one Postgres + one Redis (each with their own DB / namespace) — saves resources at small/medium scale.

## When to use vs roll your own

Use these recipes when:
- You're standing up a new VPS for multiple services
- You want sanity-checked configs that have run in production
- You're deciding "should I run my own X or use SaaS"

Roll your own when:
- Your scale or compliance demands something specific
- You're learning (read these as references)
- You only need a single service (don't bring the whole shared stack just for Postgres)

## Sanitization notes

These files were extracted from a real production deployment and sanitized:
- Project name replaced with `app` (rename to your project)
- Domain replaced with `example.com`
- Real passwords replaced with `${VAR_NAME}` env placeholders
- Specific server IPs replaced with `${SERVER_IP}` placeholders
- Email addresses are placeholders

**Never commit your real `.env` to git.** Use the `.env.example` as a template.

## Companion guides

| You want | Read |
|----------|------|
| Why shared Postgres / how to model multi-tenancy | [`databases/postgres/`](../databases/postgres/) |
| Specific app setup (FastAPI, NestJS, Next.js) | [`backend/`](../backend/), [`frontend/`](../frontend/) |
| Deployment to a fresh VPS | [`deployment/ssh-and-remote-server-setup.md`](../deployment/ssh-and-remote-server-setup.md) |
| nginx + SSL setup | [`deployment/nginx-reverse-proxy.md`](../deployment/nginx-reverse-proxy.md) + [`deployment/lets-encrypt-ssl.md`](../deployment/lets-encrypt-ssl.md) |
| Observability with SigNoz | [`observability/01-signoz-opentelemetry.md`](../observability/01-signoz-opentelemetry.md) |
