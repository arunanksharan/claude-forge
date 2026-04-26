# Deploy FastAPI to a VPS

> Gunicorn + uvicorn workers, behind nginx, managed by systemd or Docker Compose.

## Architecture

```
[client] ─→ nginx (443) ─→ gunicorn (8000) ─→ uvicorn worker × N
                                                   ↓
                                                 FastAPI
                                                   ↓
                                              Postgres + Redis
```

- **nginx**: TLS, gzip, static files, rate limiting, request timeouts
- **gunicorn**: process supervisor — manages worker lifecycle, restarts crashed workers
- **uvicorn workers**: actually run the ASGI app

## Step 1 — Production deps

In `pyproject.toml`:

```toml
dependencies = [
    # ... your normal deps
    "gunicorn>=23",
    "uvicorn[standard]>=0.32",
]
```

Add `[standard]` to uvicorn for `uvloop` (faster event loop) and `httptools` (faster HTTP parsing).

## Step 2 — Gunicorn config

`gunicorn.conf.py`:

```python
import multiprocessing
import os

# bind to localhost — nginx is the only thing that talks to us
bind = "127.0.0.1:8000"

# workers = (2 × CPUs) + 1 for IO-bound; (1 × CPU) for CPU-bound async
workers = int(os.getenv("WORKERS", multiprocessing.cpu_count() * 2 + 1))
worker_class = "uvicorn.workers.UvicornWorker"

# graceful timeout — must be > slowest expected request
timeout = 60
graceful_timeout = 30

# keep alive — match nginx upstream keepalive
keepalive = 5

# recycle workers periodically (memory leaks, fragmentation)
max_requests = 1000
max_requests_jitter = 100

# preload app — workers share memory
preload_app = True

# log
accesslog = "-"        # stdout
errorlog = "-"
loglevel = os.getenv("LOG_LEVEL", "info")

# capture print/stdout
capture_output = True

# don't chmod stdout (for systemd)
forwarded_allow_ips = "127.0.0.1"

# graceful shutdown coordination
def on_exit(server):
    server.log.info("shutting down")
```

### Why these settings

| Setting | Why |
|---------|-----|
| `bind = 127.0.0.1:8000` | Don't expose directly — nginx is the public face |
| `worker_class = UvicornWorker` | gunicorn's HTTP server is sync; uvicorn worker turns it into ASGI |
| `workers = 2 × CPU + 1` | Standard formula for IO-bound servers (most APIs) |
| `preload_app = True` | Forks workers from a single parent — saves memory; requires app to be import-safe (no DB connections at import time) |
| `max_requests = 1000` | Recycles worker after N requests — fights memory leaks |
| `keepalive = 5` | Matches typical nginx upstream keepalive |
| `forwarded_allow_ips = 127.0.0.1` | Trust X-Forwarded-* only from nginx |

## Step 3 — Dockerfile

```dockerfile
FROM python:3.12-slim AS builder

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_COMPILE_BYTECODE=1

WORKDIR /app
RUN pip install --no-cache-dir uv

COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev

COPY . .

# ----------------------------------------

FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PATH="/app/.venv/bin:$PATH"

# non-root user
RUN groupadd -g 1001 app && useradd -u 1001 -g app -m -s /bin/bash app

WORKDIR /app

COPY --from=builder --chown=app:app /app/.venv /app/.venv
COPY --from=builder --chown=app:app /app/src /app/src
COPY --from=builder --chown=app:app /app/alembic /app/alembic
COPY --from=builder --chown=app:app /app/alembic.ini /app/
COPY --from=builder --chown=app:app /app/gunicorn.conf.py /app/

USER app
EXPOSE 8000
STOPSIGNAL SIGTERM

# entrypoint runs migrations then starts gunicorn
COPY --chown=app:app docker/entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

CMD ["/app/entrypoint.sh"]
```

`docker/entrypoint.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# wait for DB (in case it starts after API)
until pg_isready -h "${DB_HOST:-db}" -U "${DB_USER:-postgres}" 2>/dev/null; do
  echo "waiting for db..."
  sleep 1
done

# run migrations
alembic upgrade head

# start gunicorn
exec gunicorn src.{{project-slug}}.main:app -c gunicorn.conf.py
```

## Step 4 — Docker Compose (prod)

```yaml
# docker-compose.prod.yml
services:
  api:
    image: {{project-slug}}-api:${IMAGE_TAG:-latest}
    container_name: {{project-slug}}-api
    restart: unless-stopped
    expose: ["8000"]
    environment:
      - DATABASE_URL
      - REDIS_URL
      - JWT_SECRET
      - SENTRY_DSN
      - ENV=production
      - LOG_LEVEL=info
      - WORKERS=4
    healthcheck:
      test: ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8000/api/health', timeout=3)"]
      interval: 10s
      retries: 3
      start_period: 60s
    deploy:
      resources: { limits: { memory: 1G } }
    networks: [app-net]

  worker:
    image: {{project-slug}}-api:${IMAGE_TAG:-latest}
    container_name: {{project-slug}}-worker
    restart: unless-stopped
    command:
      - celery
      - -A
      - {{project-slug}}.workers.celery_app
      - worker
      - --loglevel=info
      - -c
      - "4"
    environment:
      - DATABASE_URL
      - REDIS_URL
    depends_on:
      api: { condition: service_healthy }
    deploy:
      resources: { limits: { memory: 512M } }
    networks: [app-net]

  beat:
    image: {{project-slug}}-api:${IMAGE_TAG:-latest}
    container_name: {{project-slug}}-beat
    restart: unless-stopped
    command:
      - celery
      - -A
      - {{project-slug}}.workers.celery_app
      - beat
      - --loglevel=info
    environment:
      - DATABASE_URL
      - REDIS_URL
    depends_on:
      api: { condition: service_healthy }
    deploy:
      resources: { limits: { memory: 128M } }
    networks: [app-net]

  nginx:
    image: nginx:1.27-alpine
    restart: unless-stopped
    ports: ["80:80", "443:443"]
    volumes:
      - ./nginx/conf.d:/etc/nginx/conf.d:ro
      - /etc/letsencrypt:/etc/letsencrypt:ro
      - /var/www/certbot:/var/www/certbot:ro
    depends_on: [api]
    networks: [app-net]

networks:
  app-net:
```

**One beat, multiple workers.** Beat is the scheduler — exactly one. Workers process the jobs — scale as needed.

## Step 4 (alternative) — systemd (no Docker)

```ini
# /etc/systemd/system/{{project-slug}}.service
[Unit]
Description={{project-name}} FastAPI
After=network.target postgresql.service redis.service

[Service]
Type=simple
User=deploy
Group=deploy
WorkingDirectory=/var/www/{{project-slug}}
EnvironmentFile=/var/www/{{project-slug}}/.env
ExecStartPre=/var/www/{{project-slug}}/.venv/bin/alembic upgrade head
ExecStart=/var/www/{{project-slug}}/.venv/bin/gunicorn src.{{project-slug}}.main:app -c /var/www/{{project-slug}}/gunicorn.conf.py
ExecReload=/bin/kill -HUP $MAINPID
KillMode=mixed
TimeoutStopSec=30
Restart=on-failure
RestartSec=5s

LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
```

```ini
# /etc/systemd/system/{{project-slug}}-worker@.service
# templated — start one instance per queue: systemctl start {{project-slug}}-worker@emails
[Unit]
Description={{project-name}} Celery worker (%i)
After=network.target redis.service

[Service]
Type=simple
User=deploy
Group=deploy
WorkingDirectory=/var/www/{{project-slug}}
EnvironmentFile=/var/www/{{project-slug}}/.env
ExecStart=/var/www/{{project-slug}}/.venv/bin/celery -A {{project-slug}}.workers.celery_app worker --loglevel=info -Q %i -c 4 -n %i@%h
KillMode=mixed
TimeoutStopSec=30
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now {{project-slug}}
sudo systemctl enable --now {{project-slug}}-worker@emails
sudo systemctl enable --now {{project-slug}}-worker@billing
```

## Step 5 — nginx config

Same shape as the cross-cutting `nginx-reverse-proxy.md` example. Key adjustments for FastAPI:

```nginx
server {
    listen 443 ssl http2;
    server_name {{your-domain}};

    # SSL setup ...

    client_max_body_size 25M;       # bump for file uploads
    client_body_timeout 60s;

    # FastAPI's docs (Swagger UI) — restrict in prod
    location /docs {
        # allow only office IPs
        allow 192.0.2.0/24;
        deny all;
        proxy_pass http://api:8000;
    }
    location /redoc {
        allow 192.0.2.0/24;
        deny all;
        proxy_pass http://api:8000;
    }
    location /openapi.json {
        allow 192.0.2.0/24;
        deny all;
        proxy_pass http://api:8000;
    }

    # main API
    location / {
        proxy_pass http://api:8000;     # or 127.0.0.1:8000 without Docker
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Connection "";
        proxy_buffering on;
        proxy_read_timeout 60s;
    }

    # SSE endpoint
    location /api/v1/events/stream {
        proxy_pass http://api:8000;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header X-Accel-Buffering no;
        proxy_buffering off;
        proxy_cache off;
        proxy_read_timeout 24h;
    }
}
```

## Step 6 — App-side: trust proxy headers

FastAPI / Starlette won't trust `X-Forwarded-*` by default. Add the trusted-host middleware:

```python
from fastapi.middleware.trustedhost import TrustedHostMiddleware
from starlette.middleware.proxy_headers import ProxyHeadersMiddleware

app.add_middleware(ProxyHeadersMiddleware, trusted_hosts=["127.0.0.1", "nginx"])
app.add_middleware(TrustedHostMiddleware, allowed_hosts=["{{your-domain}}", "*.{{your-domain}}"])
```

Then `request.client.host` reflects the real client IP, and `request.url.scheme` is `https` (not `http`).

## Step 7 — Health endpoint

```python
# src/{{project-slug}}/api/v1/health.py
from fastapi import APIRouter, Depends, status
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession
from {{project-slug}}.deps import DbSession

router = APIRouter(tags=["health"])


@router.get("/health", status_code=status.HTTP_200_OK)
async def health(session: DbSession):
    await session.execute(text("SELECT 1"))
    return {"status": "ok"}


@router.get("/ready", status_code=status.HTTP_200_OK)
async def ready():
    return {"status": "ready"}
```

`/health` checks deps. `/ready` confirms the process is up. nginx hits these for load balancer health.

## Step 8 — Migrations on deploy

Two strategies:

1. **Run migrations in entrypoint** (shown above): every container start runs `alembic upgrade head`. Simple. Risk: two containers starting simultaneously race on the alembic_version lock — Postgres handles this via `LOCK` but it's noisy.

2. **Run migrations in CI/CD**: a pipeline step runs `alembic upgrade head` before deploying new app code. Cleaner separation. Add a check that confirms current db revision matches what the new code expects:

```bash
# in CI, after migrations
ACTUAL=$(alembic current --verbose | head -1 | awk '{print $1}')
EXPECTED=$(alembic heads | awk '{print $1}')
[ "$ACTUAL" = "$EXPECTED" ] || exit 1
```

For zero-downtime: always migrate **expand → migrate → contract** (see `02-sqlalchemy-and-alembic.md`).

## Step 9 — Logs

gunicorn logs to stdout. With Docker, the json-file driver captures + rotates. With systemd, journald captures.

For structured logs, use structlog and configure gunicorn:

```python
# in your structlog setup
import structlog
import logging

logging.getLogger("gunicorn.access").handlers = []  # suppress gunicorn's plain access log
logging.getLogger("gunicorn.error").handlers = []   # suppress its error log
# both will fall through to your structlog handler
```

Or use `python-json-logger` to format gunicorn's logs as JSON.

## Step 10 — Zero-downtime reload

gunicorn supports SIGHUP for graceful reload (waits for in-flight requests, swaps workers):

```bash
# systemd
sudo systemctl reload {{project-slug}}

# Docker — build new image, then:
docker compose -f docker-compose.prod.yml up -d --no-deps --build api
```

For the docker case, brief connection blip during container swap. For true zero-downtime: blue-green with two replicas.

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| `forwarded_allow_ips` not set | gunicorn ignores `X-Forwarded-*` — IPs and scheme wrong in app |
| Worker count too high | More workers ≠ more throughput; CPU-saturate or memory-bloat your VPS |
| `preload_app=True` and DB connection in module init | Connection won't survive forking — defer with lifespan |
| Slow startup (> 30s) | `start_period` in healthcheck must be longer; otherwise marked unhealthy |
| Migrations fail with "table exists" | Alembic version table out of sync — `alembic stamp head` (carefully) |
| OOM during migration | Some migrations need a lot of memory (large index rebuild) — increase memory or split |
| Docs leaked in prod | Disable in `main.py` if `ENV != 'development'`: `app = FastAPI(docs_url=None, redoc_url=None)` |
| Real client IP shows as `127.0.0.1` | `ProxyHeadersMiddleware` not added, or `forwarded_allow_ips` not set in gunicorn |
| WebSocket disconnects | nginx `proxy_read_timeout`; gunicorn worker timeout |
| Celery worker can't connect to Redis | Same env vars as API; verify `REDIS_URL` reachable from worker container |
