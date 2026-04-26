# Deploy Next.js to a VPS

> Self-hosted Next.js 15 with `output: 'standalone'`, behind nginx, with PM2 or systemd.

## Decision: Vercel vs self-hosted

| Vercel | Self-hosted |
|--------|-------------|
| Zero ops | You handle ops |
| Edge runtime, ISR, image optimization "just work" | Image optimization needs Sharp + cache config; ISR needs disk persistence |
| Pay per usage | Fixed VPS cost |
| Best for marketing + medium traffic | Best when other services are also self-hosted, or for cost control |

If you're picking up this guide, you've decided on self-hosted. The patterns below assume that.

## Step 1 — `next.config.ts`

```typescript
import type { NextConfig } from 'next';

const config: NextConfig = {
  output: 'standalone',                  // bundles deps + minimal Node server
  reactStrictMode: true,
  poweredByHeader: false,                // don't leak Next.js
  compress: false,                       // nginx does gzip; let it
  images: {
    remotePatterns: [
      { protocol: 'https', hostname: 'cdn.{{your-domain}}' },
    ],
  },
};

export default config;
```

`output: 'standalone'` is the key. It produces `.next/standalone/` containing a minimal Node server with only the deps you actually use. The Dockerfile / deploy then copies just that.

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
ENV NEXT_TELEMETRY_DISABLED=1
RUN corepack enable && pnpm build

FROM node:22-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
RUN addgroup --system --gid 1001 nodejs && adduser --system --uid 1001 nextjs

COPY --from=builder /app/public ./public
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

USER nextjs
EXPOSE 3000
ENV PORT=3000
ENV HOSTNAME=0.0.0.0
STOPSIGNAL SIGTERM
CMD ["node", "server.js"]
```

The output of `output: 'standalone'` includes a `server.js` — that's what you run.

## Step 3 — Deploy via Docker Compose

```yaml
# docker-compose.prod.yml
services:
  web:
    image: {{project-slug}}-web:${IMAGE_TAG:-latest}
    container_name: {{project-slug}}-web
    restart: unless-stopped
    expose:
      - "3000"
    environment:
      - NEXT_PUBLIC_API_URL
      - NEXT_PUBLIC_APP_URL
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:3000/api/health"]
      interval: 10s
      retries: 3
      start_period: 30s
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
    depends_on: [web]
    networks: [app-net]

networks:
  app-net:
```

Add a healthcheck route:

```typescript
// src/app/api/health/route.ts
export const dynamic = 'force-dynamic';
export const revalidate = 0;
export async function GET() {
  return Response.json({ status: 'ok' });
}
```

## Step 3 (alternative) — Deploy without Docker, with PM2

Build on the server:

```bash
cd /var/www/{{project-slug}}
git pull
pnpm install --frozen-lockfile
pnpm build
pm2 reload ecosystem.config.cjs --update-env
```

`ecosystem.config.cjs`:

```javascript
module.exports = {
  apps: [
    {
      name: '{{project-slug}}-web',
      script: '.next/standalone/server.js',
      cwd: '/var/www/{{project-slug}}',
      instances: 'max',
      exec_mode: 'cluster',
      env: { NODE_ENV: 'production', PORT: 3000 },
      max_memory_restart: '512M',
      kill_timeout: 10000,
    },
  ],
};
```

Cluster mode works for Next because it's stateless.

## Step 4 — nginx config

```nginx
# /etc/nginx/sites-available/{{your-domain}}.conf
server {
    listen 80;
    server_name {{your-domain}} www.{{your-domain}};
    location /.well-known/acme-challenge/ { root /var/www/certbot; }
    location / { return 301 https://$host$request_uri; }
}

server {
    listen 443 ssl http2;
    server_name {{your-domain}};

    ssl_certificate     /etc/letsencrypt/live/{{your-domain}}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/{{your-domain}}/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;

    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    client_max_body_size 10M;

    # static assets — long cache
    location /_next/static/ {
        proxy_pass http://web:3000;
        proxy_cache_valid 200 1y;
        add_header Cache-Control "public, max-age=31536000, immutable";
    }

    location /static/ {
        alias /var/www/{{project-slug}}/public/;
        expires 30d;
        add_header Cache-Control "public, immutable";
    }

    # everything else
    location / {
        proxy_pass http://web:3000;     # or 127.0.0.1:3000 if not Docker
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Connection "";
        proxy_buffering on;
        proxy_read_timeout 60s;
    }
}
```

## Step 5 — Image optimization

Next's `next/image` requires Sharp at runtime. With `output: 'standalone'`, Sharp is included automatically. Verify:

```bash
docker exec {{project-slug}}-web ls node_modules/sharp
```

For images served from your `public/`, no config needed. For remote images, allowlist in `next.config.ts` `images.remotePatterns`.

For very heavy image processing, offload to a CDN (Cloudflare Images, Vercel/imgix). Self-hosted Sharp at scale is fine for ~hundreds of unique images per day; not for millions.

## Step 6 — Cache + ISR

If you use ISR (`revalidate`), Next writes regenerated pages to disk. With Docker, the cache is per-container — restarts lose it. Options:

1. **Mount a volume** for `.next/cache`:

```yaml
services:
  web:
    volumes:
      - next-cache:/app/.next/cache

volumes:
  next-cache:
```

2. **Use a custom cache handler** (Redis-backed):

```typescript
// next.config.ts
const config: NextConfig = {
  output: 'standalone',
  cacheHandler: require.resolve('./cache-handler.js'),
  cacheMaxMemorySize: 0,    // disable in-memory; rely on Redis
};
```

`cache-handler.js` implements a CacheHandler interface backed by Redis. Use `@neshca/cache-handler` for a pre-built one.

For multi-instance setups: option 2 is required (otherwise instances have inconsistent caches).

## Step 7 — Server Actions / Route Handlers

These work transparently. No special config needed for self-hosting.

For large request bodies (file uploads), bump nginx + Next's body size:

```nginx
client_max_body_size 50M;
```

```typescript
// next.config.ts
experimental: {
  serverActions: { bodySizeLimit: '50mb' },
},
```

## Step 8 — Environment variables

Two flavors in Next:

| Prefix | Where exposed |
|--------|---------------|
| `NEXT_PUBLIC_*` | Bundled into client JS at build time — visible to users |
| no prefix | Server-only (Server Components, Route Handlers, Server Actions) |

**Build-time vs runtime:**

- `NEXT_PUBLIC_*` is baked in at `pnpm build` — the build needs to know the value
- Server-only env vars are read at runtime — change them without rebuilding

For Docker:

```yaml
services:
  web:
    build:
      context: .
      args:
        - NEXT_PUBLIC_API_URL=${NEXT_PUBLIC_API_URL}
    environment:
      - DATABASE_URL                    # server-only, runtime
```

Then in Dockerfile:

```dockerfile
FROM ... AS builder
ARG NEXT_PUBLIC_API_URL
ENV NEXT_PUBLIC_API_URL=$NEXT_PUBLIC_API_URL
RUN pnpm build
```

## Step 9 — Logs

Next logs to stdout (in standalone mode). Docker captures via the json-file driver. Forward to Loki / CloudWatch / Datadog as needed.

For structured logs, intercept with `winston` or `pino` in a custom server:

```typescript
// instead of node server.js, use a custom server.ts that wraps next() with pino
```

Usually not worth it — let Next's default logs go through, ship them upstream.

## Step 10 — Zero-downtime deploys

PM2 cluster mode handles this:

```bash
pm2 reload {{project-slug}}-web --update-env
```

Docker Compose with `--no-deps`:

```bash
docker compose -f docker-compose.prod.yml up -d --no-deps --build web
```

Build a new image first, then swap. Brief window where both old + new exist; nginx happily routes between them via the keep-alive pool. Old container exits after handling its in-flight requests.

For true zero-downtime in Docker, run two replicas behind nginx upstream + take down one at a time:

```nginx
upstream web {
    server web1:3000 max_fails=2 fail_timeout=10s;
    server web2:3000 max_fails=2 fail_timeout=10s;
}
```

Then deploy: stop `web1`, deploy new image as `web1`, wait for healthy, repeat for `web2`.

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| `output: 'standalone'` not set | Image is huge + needs full `node_modules` to run |
| Sharp missing in container | Standalone bundles it; if not, install `sharp` explicitly |
| ISR cache lost on restart | Mount volume or use Redis cache handler |
| `NEXT_PUBLIC_*` value baked in wrong | Set at build time, not runtime |
| Body too large on file upload | nginx `client_max_body_size` + Next `bodySizeLimit` |
| Hot reload working in dev but build fails | Run `pnpm build` locally before push to catch RSC errors |
| Telemetry calls to vercel from prod | `NEXT_TELEMETRY_DISABLED=1` |
| Memory creeping up over time | Set `max_memory_restart` (PM2) or use compose `mem_limit`; investigate Server Component caching |
| Slow first request after deploy | Warm up: hit `/` after deploy before flipping traffic |
| `Image is not configured for hostname` | Add to `images.remotePatterns` in `next.config.ts` |
