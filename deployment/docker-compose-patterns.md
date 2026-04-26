# Docker Compose Patterns

> Multi-service compose layouts, healthchecks, named volumes, env management, prod vs dev compose files.

## Two compose files: dev and prod

Don't try to make one file do both. Two files, optionally with shared bits.

```
docker-compose.dev.yml    # for local dev: ports exposed, hot reload, no resource limits
docker-compose.prod.yml   # for production: only the app exposed, healthchecks, resource limits
docker-compose.yml        # shared base — optional, see "Override pattern" below
```

## Override pattern

If you want to share most config:

```yaml
# docker-compose.yml — shared base
services:
  api:
    image: ${IMAGE:-{{project-slug}}-api:latest}
    restart: unless-stopped
    environment:
      DATABASE_URL: ${DATABASE_URL}
      REDIS_URL: ${REDIS_URL}
    networks: [internal]

networks:
  internal:
```

```yaml
# docker-compose.dev.yml — extends base for dev
services:
  api:
    build: .
    volumes:
      - ./src:/app/src
    ports:
      - "8000:8000"
    environment:
      ENV: development
      DEBUG: "true"
```

```yaml
# docker-compose.prod.yml — extends base for prod
services:
  api:
    deploy:
      resources: { limits: { memory: 1G, cpus: '0.5' } }
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:8000/health"]
      interval: 10s
      retries: 3
```

Run with both:

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```

For most projects, just keep dev and prod as **separate self-contained files**. The override pattern is only worth it for big setups.

## Dev compose template

```yaml
# docker-compose.dev.yml
services:
  api:
    build:
      context: .
      dockerfile: Dockerfile.dev
    container_name: {{project-slug}}-api
    ports:
      - "8000:8000"
    environment:
      DATABASE_URL: postgresql://postgres:postgres@db:5432/{{db-name}}
      REDIS_URL: redis://redis:6379/0
      ENV: development
    volumes:
      - ./src:/app/src                    # hot reload
      - ./alembic:/app/alembic
    depends_on:
      db: { condition: service_healthy }
      redis: { condition: service_started }
    networks: [app-net]

  db:
    image: postgres:16-alpine
    container_name: {{project-slug}}-db
    ports:
      - "5432:5432"
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: {{db-name}}
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 3s
      retries: 5
    networks: [app-net]

  redis:
    image: redis:7-alpine
    container_name: {{project-slug}}-redis
    ports:
      - "6379:6379"
    volumes:
      - redisdata:/data
    networks: [app-net]

  # optional, for queue inspection in dev
  redis-commander:
    image: rediscommander/redis-commander:latest
    container_name: {{project-slug}}-redis-commander
    ports:
      - "8081:8081"
    environment:
      REDIS_HOSTS: local:redis:6379
    depends_on: [redis]
    networks: [app-net]

volumes:
  pgdata:
  redisdata:

networks:
  app-net:
    driver: bridge
```

### Why these specific defaults

| Setting | Why |
|---------|-----|
| `container_name` set explicitly | Easier to `docker logs <name>` |
| `depends_on` with `service_healthy` | Don't start the API until the DB is accepting connections |
| `healthcheck` on DB | `service_healthy` needs a `healthcheck` defined |
| Named volumes (not bind mounts for data) | Survive `docker compose down`; bind mounts cause perf issues on macOS/Windows |
| Alpine images | Smaller, faster to pull |
| Source bind mount (`./src:/app/src`) | Hot reload — uvicorn `--reload`, nodemon, etc. |

## Prod compose template

```yaml
# docker-compose.prod.yml
services:
  api:
    image: {{project-slug}}-api:${IMAGE_TAG:-latest}
    container_name: {{project-slug}}-api
    restart: unless-stopped
    expose:
      - "8000"                            # internal only — nginx exposes externally
    environment:
      - DATABASE_URL
      - REDIS_URL
      - JWT_SECRET
      - SENTRY_DSN
      - ENV=production
      - LOG_LEVEL=info
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:8000/health"]
      interval: 10s
      timeout: 3s
      retries: 3
      start_period: 30s
    deploy:
      resources:
        limits: { memory: 1G, cpus: '1.0' }
        reservations: { memory: 256M }
    logging:
      driver: json-file
      options: { max-size: "10m", max-file: "3" }
    networks: [app-net]

  worker:
    image: {{project-slug}}-api:${IMAGE_TAG:-latest}
    container_name: {{project-slug}}-worker
    restart: unless-stopped
    command: ["celery", "-A", "{{project-slug}}.workers.celery_app", "worker", "--loglevel=info", "-Q", "default", "-c", "4"]
    environment:
      - DATABASE_URL
      - REDIS_URL
    depends_on:
      api: { condition: service_healthy }
    deploy:
      resources: { limits: { memory: 512M } }
    logging:
      driver: json-file
      options: { max-size: "10m", max-file: "3" }
    networks: [app-net]

  nginx:
    image: nginx:1.27-alpine
    container_name: {{project-slug}}-nginx
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/conf.d:/etc/nginx/conf.d:ro
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - /etc/letsencrypt:/etc/letsencrypt:ro
      - /var/www/certbot:/var/www/certbot:ro
    depends_on: [api]
    networks: [app-net]

networks:
  app-net:
    driver: bridge
```

In prod, **DB and Redis usually live outside compose** (managed services or a separate compose on a different host). Include them in compose only for single-VPS setups.

## Healthchecks for every service

| Service | Healthcheck |
|---------|-------------|
| Postgres | `pg_isready -U postgres` |
| MySQL | `mysqladmin ping -h localhost` |
| Redis | `redis-cli ping` |
| MongoDB | `mongosh --eval 'db.adminCommand({ ping: 1 })'` |
| Custom HTTP API | `wget -qO- http://localhost:PORT/health` or `curl -f` |
| nginx | `nginx -t || exit 1` |

```yaml
healthcheck:
  test: ["CMD-SHELL", "redis-cli ping | grep PONG"]
  interval: 5s
  timeout: 3s
  retries: 5
  start_period: 10s    # don't count failures during startup
```

## Environment variables

Three patterns:

### `.env` file (dev)

```yaml
services:
  api:
    env_file: .env
```

`.env` lives next to the compose file. **Never commit `.env`** — commit `.env.example`.

### Inline (less typing for short lists)

```yaml
environment:
  - ENV=development
  - LOG_LEVEL=debug
```

### From host (prod, secrets-style)

```yaml
environment:
  - DATABASE_URL                       # value comes from host's environment
  - JWT_SECRET
```

The host's `DATABASE_URL` is read at `docker compose up` time. Useful when secrets come from a vault / systemd EnvironmentFile.

For real secret management, use Docker secrets (Swarm) or a proper secret store (Vault, AWS Secrets Manager) — not env files in prod.

## Networks

By default each compose creates a network. Multi-compose setups need explicit networks:

```yaml
networks:
  app-net:
    driver: bridge
```

To share a network between two compose files (e.g. nginx in one, app in another):

```yaml
# in compose A
networks:
  shared:
    name: shared-net    # explicit name

# in compose B
networks:
  shared:
    external: true
    name: shared-net
```

## Volumes

| Use | When |
|-----|------|
| **Named volume** (`pgdata`) | DB data, anything that should survive |
| **Bind mount** (`./src:/app/src`) | Hot reload in dev only |
| **Anonymous volume** (`/app/node_modules`) | Hide host's `node_modules` from container |

The third pattern is critical for Node:

```yaml
volumes:
  - ./src:/app/src
  - /app/node_modules     # anonymous — uses container's node_modules, not host's
```

Otherwise the macOS/Windows `node_modules` (different platform) overwrites the linux container's.

## Resource limits

```yaml
deploy:
  resources:
    limits: { memory: 512M, cpus: '0.5' }
    reservations: { memory: 128M }
```

Without limits, one runaway service can OOM the whole host.

For Compose v2 (without Swarm), `deploy.resources.limits` *is* honored when running `docker compose` (despite older docs). If it's not, use the `mem_limit` and `cpus:` shortcuts.

## Logging

```yaml
logging:
  driver: json-file
  options:
    max-size: "10m"
    max-file: "3"
```

Otherwise Docker's default JSON log files grow without bound and fill the disk.

For production: ship logs to a central system (Loki, CloudWatch, Datadog) via a logging driver:

```yaml
logging:
  driver: loki
  options:
    loki-url: "http://loki:3100/loki/api/v1/push"
```

## Common compose commands

```bash
# bring up all services in background
docker compose up -d

# specific service only
docker compose up -d api

# follow logs
docker compose logs -f api

# rebuild without cache
docker compose build --no-cache api

# rebuild + restart
docker compose up -d --build api

# stop everything
docker compose down

# stop + delete volumes (DESTROYS DATA)
docker compose down -v

# exec into a running container
docker compose exec api bash

# run a one-off command
docker compose run --rm api alembic upgrade head

# show resource usage
docker stats

# show service status
docker compose ps
```

## Makefile wrapper

```makefile
COMPOSE_DEV  := docker compose -f docker-compose.dev.yml
COMPOSE_PROD := docker compose -f docker-compose.prod.yml

.PHONY: dev dev-down dev-logs prod prod-down migrate

dev:
	$(COMPOSE_DEV) up -d --build
	$(COMPOSE_DEV) logs -f api

dev-down:
	$(COMPOSE_DEV) down

dev-logs:
	$(COMPOSE_DEV) logs -f $(svc)

prod:
	$(COMPOSE_PROD) up -d --build

prod-down:
	$(COMPOSE_PROD) down

migrate:
	$(COMPOSE_DEV) run --rm api alembic upgrade head

shell:
	$(COMPOSE_DEV) exec api bash
```

`make dev` brings everything up + tails logs. `make migrate` runs migrations. `make shell` drops you into the API container.

## Dockerfile patterns

Multi-stage build, minimal final image:

### Python (FastAPI)

```dockerfile
# Dockerfile
FROM python:3.12-slim AS builder

WORKDIR /app
RUN pip install --no-cache-dir uv

COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev

COPY . .

FROM python:3.12-slim
WORKDIR /app
COPY --from=builder /app/.venv /app/.venv
COPY --from=builder /app/src /app/src
COPY --from=builder /app/alembic /app/alembic
COPY --from=builder /app/alembic.ini /app/

ENV PATH="/app/.venv/bin:$PATH"
EXPOSE 8000

# graceful shutdown
STOPSIGNAL SIGTERM

CMD ["gunicorn", "src.{{project-slug}}.main:app", "-k", "uvicorn.workers.UvicornWorker", "-w", "4", "-b", "0.0.0.0:8000"]
```

### Node (Nest / Express)

```dockerfile
FROM node:22-alpine AS builder

WORKDIR /app
COPY package.json pnpm-lock.yaml ./
RUN corepack enable && pnpm install --frozen-lockfile

COPY . .
RUN pnpm build && pnpm prune --prod

FROM node:22-alpine
WORKDIR /app

COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/package.json ./

EXPOSE 3000
STOPSIGNAL SIGTERM
CMD ["node", "dist/main.js"]
```

### Next.js (standalone output)

```dockerfile
FROM node:22-alpine AS builder
WORKDIR /app

COPY package.json pnpm-lock.yaml ./
RUN corepack enable && pnpm install --frozen-lockfile
COPY . .
RUN pnpm build

FROM node:22-alpine
WORKDIR /app
ENV NODE_ENV=production

COPY --from=builder /app/public ./public
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static

EXPOSE 3000
STOPSIGNAL SIGTERM
CMD ["node", "server.js"]
```

Requires `output: 'standalone'` in `next.config.ts`.

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| Compose v1 commands (`docker-compose`) | Use `docker compose` (v2, plugin) |
| `version: '3.8'` deprecation warning | Remove the `version` line — it's ignored in v2 |
| Build context too large (sends GBs) | Add `.dockerignore` (`node_modules`, `.git`, `dist`, etc.) |
| `node_modules` from host overrides container's | Anonymous volume `/app/node_modules` |
| Containers can't reach each other by name | Same network — explicit `networks` block |
| DB connections refused on first start | `depends_on` with `condition: service_healthy` |
| Logs disappear after restart | Use named volume for `/var/log` or a logging driver |
| `unless-stopped` ignored on reboot | Docker daemon `restart` policy must include the daemon starting on boot |
| Disk full from old images | `docker system prune -a` (remove unused images) — schedule it |
| Secrets in image layers | Use multi-stage; don't `COPY .env` into the final image |
