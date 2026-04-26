# Deploy Node.js + Express to a VPS

> Plain Node/Express behind PM2 + nginx. Workers as separate processes.

## Architecture

Same as the Nest deployment shape:

```
[client] ─→ nginx (443) ─→ Node cluster (3000) × N
                                 ↓
                              Postgres + Redis
                                 ↑
                          BullMQ workers (separate)
```

The Express app is whatever your `src/server.ts` builds. The deployment patterns are nearly identical to the Nest guide — this file covers the differences.

## Step 1 — Build

Use `tsup` (or `esbuild`, or `tsc`) to bundle into `dist/`:

```typescript
// tsup.config.ts
import { defineConfig } from 'tsup';

export default defineConfig({
  entry: ['src/server.ts', 'src/queue/workers/*.ts'],
  format: ['esm'],
  target: 'node22',
  outDir: 'dist',
  splitting: false,
  sourcemap: true,
  clean: true,
  shims: true,
  external: ['bcrypt', 'sharp'],   // native binaries — keep external
});
```

```bash
pnpm build
node dist/server.js     # smoke test
```

For an Express app, `tsc` alone is fine too:

```json
// tsconfig.json
"compilerOptions": { "outDir": "./dist", "module": "ESNext", "moduleResolution": "bundler" }
```

## Step 2 — Dockerfile

```dockerfile
FROM node:22-alpine AS deps
WORKDIR /app
COPY package.json pnpm-lock.yaml ./
RUN corepack enable && pnpm install --frozen-lockfile

FROM node:22-alpine AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN corepack enable && pnpm drizzle-kit generate && pnpm build && pnpm prune --prod

FROM node:22-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production

# bcrypt needs python + make at install time but not runtime
# if Dockerfile fails on bcrypt install, switch to node:22-slim or use bcryptjs

RUN addgroup --system --gid 1001 nodejs && adduser --system --uid 1001 app

COPY --from=builder --chown=app:nodejs /app/node_modules ./node_modules
COPY --from=builder --chown=app:nodejs /app/dist ./dist
COPY --from=builder --chown=app:nodejs /app/drizzle ./drizzle
COPY --from=builder --chown=app:nodejs /app/package.json ./

USER app
EXPOSE 3000
STOPSIGNAL SIGTERM

CMD ["node", "dist/server.js"]
```

## Step 3 — Docker Compose

Same shape as the Nest example:

```yaml
services:
  api:
    image: {{project-slug}}:${IMAGE_TAG:-latest}
    expose: ["3000"]
    environment:
      - DATABASE_URL
      - REDIS_URL
      - JWT_SECRET
      - NODE_ENV=production
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:3000/api/v1/health"]
      interval: 10s
      retries: 3
      start_period: 30s
    networks: [app-net]

  worker-emails:
    image: {{project-slug}}:${IMAGE_TAG:-latest}
    command: ["node", "dist/queue/workers/email.worker.js"]
    environment:
      - DATABASE_URL
      - REDIS_URL
    networks: [app-net]

  worker-billing:
    image: {{project-slug}}:${IMAGE_TAG:-latest}
    command: ["node", "dist/queue/workers/billing.worker.js"]
    networks: [app-net]

  nginx:
    image: nginx:1.27-alpine
    ports: ["80:80", "443:443"]
    volumes:
      - ./nginx/conf.d:/etc/nginx/conf.d:ro
      - /etc/letsencrypt:/etc/letsencrypt:ro
    depends_on: [api]
    networks: [app-net]
```

## Step 4 — PM2 (without Docker)

See `pm2-process-management.md` for the ecosystem template — it's already Express-shaped.

```bash
cd /var/www/{{project-slug}}
git pull
pnpm install --frozen-lockfile
pnpm db:migrate
pnpm build
pm2 reload ecosystem.config.cjs --update-env
pm2 save
```

## Step 5 — nginx config

```nginx
server {
    listen 443 ssl http2;
    server_name {{your-domain}};

    # SSL ...

    client_max_body_size 25M;

    location / {
        proxy_pass http://api:3000;     # or 127.0.0.1:3000 without Docker
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Connection "";
        proxy_read_timeout 60s;
    }

    # WebSocket (if you have one)
    location /ws {
        proxy_pass http://api:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 24h;
    }
}
```

## Step 6 — App-side: trust proxy + graceful shutdown

```typescript
// src/app.ts
const app = express();
app.set('trust proxy', 1);   // honor X-Forwarded-* from nginx
```

```typescript
// src/server.ts (excerpted from Express PROMPT.md)
const server = createServer(app);
server.listen(env.PORT, () => {
  logger.info({ port: env.PORT }, 'listening');
  if (process.send) process.send('ready');   // PM2 wait_ready
});

const shutdown = async (signal: string) => {
  logger.info({ signal }, 'shutting down');
  server.close(err => {
    if (err) { logger.error({ err }); process.exit(1); }
    process.exit(0);
  });
  setTimeout(() => process.exit(1), 30_000).unref();
};

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
```

Without `server.close()`, PM2's `kill_timeout` triggers a SIGKILL → in-flight requests dropped.

## Step 7 — Health endpoint

```typescript
// src/modules/health/index.ts
import { Router } from 'express';
import { db } from '../../db/client';
import { sql } from 'drizzle-orm';

export const healthRouter = Router();

healthRouter.get('/', async (_req, res) => {
  try {
    await db.execute(sql`SELECT 1`);
    res.json({ status: 'ok', uptime: process.uptime() });
  } catch (err) {
    res.status(503).json({ status: 'degraded', error: (err as Error).message });
  }
});
```

Mount at `/api/v1/health`. nginx and PM2 hit this.

## Step 8 — Migrations on deploy

Run `pnpm db:migrate` (Drizzle) or `pnpm prisma migrate deploy` in CI before deploying. Alternatively in entrypoint:

```bash
#!/usr/bin/env bash
set -euo pipefail
pnpm db:migrate
exec node dist/server.js
```

## Step 9 — Logs

pino → stdout. With Docker, json-file driver. With PM2, pm2-logrotate. Forward to Loki/CloudWatch as needed.

In dev, pretty-print:

```typescript
// src/lib/logger.ts
import pino from 'pino';
import { env } from '../config/env';

export const logger = pino({
  level: env.LOG_LEVEL,
  transport:
    env.NODE_ENV === 'development'
      ? { target: 'pino-pretty', options: { colorize: true } }
      : undefined,
  redact: ['req.headers.authorization', 'req.headers.cookie', 'req.body.password'],
});
```

In prod, leave as JSON — log aggregator parses it.

## Step 10 — Zero-downtime

PM2 cluster mode `pm2 reload` handles it (see `pm2-process-management.md`). For Docker:

```bash
docker compose -f docker-compose.prod.yml up -d --no-deps --build api
```

For true zero-downtime in Docker, run two replicas behind nginx upstream and roll one at a time:

```nginx
upstream api {
    server api1:3000 max_fails=2 fail_timeout=10s;
    server api2:3000 max_fails=2 fail_timeout=10s;
}

location / { proxy_pass http://api; }
```

Deploy:

```bash
docker compose stop api1
# ... build new image, redeploy api1, wait healthy ...
docker compose stop api2
# ... same for api2 ...
```

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| `bcrypt` build fails in Alpine | `apk add --no-cache python3 make g++` in builder; or switch to `bcryptjs` (slower); or use `node:22-slim` |
| `sharp` errors at runtime | Native module — Alpine needs the right base or use `node:22-slim` |
| PM2 cluster + WebSocket | Use Redis pub/sub adapter (e.g. `socket.io-redis`) |
| Prod PM2 reads dev `.env` | `env_file` is set per-app in ecosystem; verify with `pm2 describe <app>` |
| `process.env.NODE_ENV` undefined | Set in `ecosystem.config.cjs` `env` block; PM2 doesn't inherit shell env |
| Build artifacts stale across deploys | `rm -rf dist/` in deploy script before `pnpm build` |
| Worker imports app code that loads HTTP framework | Workers should import services/repos, not Express; verify your worker entrypoint isn't loading the whole `app.ts` |
| `EADDRINUSE` on reload | Old process didn't exit — check graceful shutdown; PM2 `kill_timeout` |
| Docker build context huge | `.dockerignore` for `node_modules`, `.git`, `dist`, `.env` |
