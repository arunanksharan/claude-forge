# Deploy NestJS to a VPS

> NestJS in cluster mode (or Docker Compose), behind nginx, with BullMQ workers as separate processes.

## Architecture

```
[client] ─→ nginx (443) ─→ Nest cluster (3000) × N
                                 ↓
                              Postgres + Redis
                                 ↑
                          BullMQ workers (separate processes)
```

- **nginx**: TLS, static, rate limit, timeouts
- **Nest cluster**: many Node processes for HTTP, sharing port via cluster module / PM2
- **Workers**: separate processes pulling from BullMQ queues — scale independently

## Step 1 — Production build

```json
// package.json
"scripts": {
  "build": "nest build",
  "start:prod": "node dist/main.js"
}
```

Verify the build:

```bash
pnpm build
node dist/main.js
```

Should listen on the configured port.

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
RUN corepack enable && pnpm prisma generate && pnpm build && pnpm prune --prod

FROM node:22-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production

RUN addgroup --system --gid 1001 nodejs && adduser --system --uid 1001 nest

COPY --from=builder --chown=nest:nodejs /app/node_modules ./node_modules
COPY --from=builder --chown=nest:nodejs /app/dist ./dist
COPY --from=builder --chown=nest:nodejs /app/package.json ./
COPY --from=builder --chown=nest:nodejs /app/prisma ./prisma

USER nest
EXPOSE 3000
STOPSIGNAL SIGTERM

CMD ["node", "dist/main.js"]
```

`pnpm prune --prod` removes devDependencies. The `prisma generate` step bakes in the generated client.

## Step 3 — Docker Compose

```yaml
# docker-compose.prod.yml
services:
  api:
    image: {{project-slug}}:${IMAGE_TAG:-latest}
    container_name: {{project-slug}}-api
    restart: unless-stopped
    expose: ["3000"]
    environment:
      - DATABASE_URL
      - REDIS_URL
      - JWT_SECRET
      - SENTRY_DSN
      - NODE_ENV=production
      - LOG_LEVEL=info
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:3000/api/v1/health"]
      interval: 10s
      retries: 3
      start_period: 30s
    deploy:
      resources: { limits: { memory: 1G } }
    networks: [app-net]

  worker:
    image: {{project-slug}}:${IMAGE_TAG:-latest}
    container_name: {{project-slug}}-worker
    restart: unless-stopped
    # Nest workers can be the same image with a different command
    command: ["node", "dist/main.js", "--worker"]
    environment:
      - DATABASE_URL
      - REDIS_URL
      - WORKER_QUEUES=emails,billing
    depends_on:
      api: { condition: service_healthy }
    deploy:
      resources: { limits: { memory: 512M } }
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

## Step 4 — Nest worker mode

A common pattern: same image, but if `--worker` flag, only run the queue module (no HTTP).

```typescript
// src/main.ts
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';
import { WorkerModule } from './worker.module';

async function bootstrap() {
  const isWorker = process.argv.includes('--worker');

  if (isWorker) {
    // standalone app — no HTTP server
    const app = await NestFactory.createApplicationContext(WorkerModule);
    await app.init();
    console.log('worker started');
    process.on('SIGTERM', async () => { await app.close(); process.exit(0); });
  } else {
    const app = await NestFactory.create(AppModule);
    // ... global pipes, prefix, etc.
    await app.listen(3000);
  }
}

bootstrap().catch(err => { console.error(err); process.exit(1); });
```

`WorkerModule` imports just `QueueModule` and `PrismaModule` — no controllers.

Then deploy two: API + worker, same image, different command.

## Step 5 — PM2 (no Docker alternative)

```javascript
// ecosystem.config.cjs
module.exports = {
  apps: [
    {
      name: '{{project-slug}}-api',
      script: 'dist/main.js',
      cwd: '/var/www/{{project-slug}}',
      instances: 'max',
      exec_mode: 'cluster',
      env: { NODE_ENV: 'production', PORT: 3000 },
      env_file: '.env',
      max_memory_restart: '512M',
      kill_timeout: 10000,
    },
    {
      name: '{{project-slug}}-worker',
      script: 'dist/main.js',
      args: '--worker',
      cwd: '/var/www/{{project-slug}}',
      instances: 2,
      exec_mode: 'fork',
      env: { NODE_ENV: 'production' },
      env_file: '.env',
      max_memory_restart: '512M',
      kill_timeout: 30000,
    },
  ],
};
```

## Step 6 — Cluster mode + WebSockets

If your Nest app uses `@nestjs/websockets`, cluster mode breaks unless you use the Redis adapter:

```bash
pnpm add @socket.io/redis-adapter ioredis
```

```typescript
// in main.ts
import { IoAdapter } from '@nestjs/platform-socket.io';
import { ServerOptions } from 'socket.io';
import { createAdapter } from '@socket.io/redis-adapter';
import { createClient } from 'ioredis';

class RedisIoAdapter extends IoAdapter {
  private adapterConstructor: ReturnType<typeof createAdapter>;

  async connectToRedis(): Promise<void> {
    const pubClient = createClient(process.env.REDIS_URL!);
    const subClient = pubClient.duplicate();
    this.adapterConstructor = createAdapter(pubClient, subClient);
  }

  createIOServer(port: number, options?: ServerOptions): any {
    const server = super.createIOServer(port, options);
    server.adapter(this.adapterConstructor);
    return server;
  }
}

// in bootstrap
const adapter = new RedisIoAdapter(app);
await adapter.connectToRedis();
app.useWebSocketAdapter(adapter);
```

Now multiple Nest cluster workers can share WebSocket state via Redis pub/sub.

## Step 7 — nginx config

```nginx
server {
    listen 443 ssl http2;
    server_name {{your-domain}};

    # SSL ...

    client_max_body_size 25M;

    # API routes
    location /api/ {
        proxy_pass http://api:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Connection "";
        proxy_read_timeout 60s;
    }

    # WebSocket
    location /socket.io/ {
        proxy_pass http://api:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 24h;
        proxy_send_timeout 24h;
    }

    # Bull Board (admin queue UI) — restrict
    location /admin/queues/ {
        # IP allowlist + basic auth
        allow 192.0.2.0/24;
        deny all;
        auth_basic "Restricted";
        auth_basic_user_file /etc/nginx/.htpasswd;
        proxy_pass http://api:3000;
        proxy_set_header Host $host;
    }
}
```

## Step 8 — App-side: trust proxy

```typescript
// main.ts
const app = await NestFactory.create(AppModule, { rawBody: true });
app.set('trust proxy', 1);   // trust the first proxy (nginx)
```

Then `req.ip` is the real client IP, not nginx's.

## Step 9 — Health endpoint

`@nestjs/terminus` is the canonical way:

```bash
pnpm add @nestjs/terminus
```

```typescript
// src/health/health.module.ts
import { Module } from '@nestjs/common';
import { TerminusModule } from '@nestjs/terminus';
import { HealthController } from './health.controller';

@Module({
  imports: [TerminusModule],
  controllers: [HealthController],
})
export class HealthModule {}
```

```typescript
// src/health/health.controller.ts
import { Controller, Get } from '@nestjs/common';
import { HealthCheck, HealthCheckService, HttpHealthIndicator, MemoryHealthIndicator } from '@nestjs/terminus';
import { Public } from '../common/decorators/public.decorator';
import { PrismaHealthIndicator } from './prisma.health';

@Controller({ path: 'health', version: '1' })
export class HealthController {
  constructor(
    private health: HealthCheckService,
    private prisma: PrismaHealthIndicator,
    private memory: MemoryHealthIndicator,
  ) {}

  @Public()
  @Get()
  @HealthCheck()
  check() {
    return this.health.check([
      () => this.prisma.isHealthy('db'),
      () => this.memory.checkHeap('memory_heap', 200 * 1024 * 1024),
    ]);
  }
}
```

```typescript
// src/health/prisma.health.ts
import { Injectable } from '@nestjs/common';
import { HealthIndicator, HealthIndicatorResult, HealthCheckError } from '@nestjs/terminus';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class PrismaHealthIndicator extends HealthIndicator {
  constructor(private prisma: PrismaService) { super(); }

  async isHealthy(key: string): Promise<HealthIndicatorResult> {
    try {
      await this.prisma.$queryRaw`SELECT 1`;
      return this.getStatus(key, true);
    } catch (err) {
      throw new HealthCheckError('db check failed', this.getStatus(key, false, { error: (err as Error).message }));
    }
  }
}
```

## Step 10 — Migrations on deploy

Same as FastAPI: run `prisma migrate deploy` in CI before starting new containers, or in an entrypoint:

```bash
# entrypoint.sh
set -euo pipefail
pnpm prisma migrate deploy
exec node dist/main.js
```

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| Cluster + in-memory state | State is per-worker — use Redis |
| WebSocket disconnects on reload | PM2 reload only works for HTTP; WS clients reconnect on disconnect — handle in client |
| Prisma binary missing | The Alpine image needs `apk add openssl` for some Prisma deployments. Or use `node:22-slim`. |
| `@nestjs/terminus` lib peer issues | Pin major version to match your Nest version |
| Worker process imports HTTP modules | Split into `WorkerModule` to avoid heavy startup |
| Memory leak from GraphQL subscriptions | Bound subscription cardinality; restart workers periodically |
| Swagger/OpenAPI exposed in prod | Disable conditionally in `main.ts` |
| `req.ip` is `127.0.0.1` | `app.set('trust proxy', 1)` |
| Bull Board open to internet | Always behind auth + IP allowlist |
| Build size > 1GB | `pnpm prune --prod` after build; check for accidentally bundled devDeps |
