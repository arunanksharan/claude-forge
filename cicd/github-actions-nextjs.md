# GitHub Actions for Next.js

> Two paths: deploying to Vercel (zero-config) or self-hosted (build → push image → SSH deploy). Both covered.

## Path 1 — Vercel (managed)

Vercel auto-deploys via its GitHub integration:

1. Connect repo at vercel.com → New Project
2. Push to PR → Preview deployment
3. Push to main → Production deployment

What you'd add in CI is **pre-deploy validation**:

```yaml
# .github/workflows/ci.yml
name: CI

on:
  pull_request:
    branches: [main]

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v4
        with: { version: 9 }
      - uses: actions/setup-node@v4
        with:
          node-version: 22
          cache: 'pnpm'
      - run: pnpm install --frozen-lockfile
      - run: pnpm lint
      - run: pnpm type-check
      - run: pnpm test

  e2e:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v4
        with: { version: 9 }
      - uses: actions/setup-node@v4
        with: { node-version: 22, cache: 'pnpm' }
      - run: pnpm install --frozen-lockfile
      - run: pnpm exec playwright install --with-deps chromium
      - run: pnpm e2e
        env:
          BASE_URL: ${{ github.event.pull_request.head.ref }}-{{org}}.vercel.app
```

Vercel handles the actual build/deploy.

For Vercel-managed env vars, use **Vercel's UI** (not GitHub Secrets) — they're scoped per environment (preview/production).

## Path 2 — Self-hosted (full pipeline)

### `.github/workflows/ci.yml`

```yaml
name: CI

on:
  pull_request: { branches: [main] }
  push:        { branches: [main] }

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

jobs:
  lint-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v4
        with: { version: 9 }
      - uses: actions/setup-node@v4
        with: { node-version: 22, cache: 'pnpm' }
      - run: pnpm install --frozen-lockfile
      - run: pnpm lint
      - run: pnpm type-check
      - run: pnpm test
      - run: pnpm build           # smoke-test the build

  e2e:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v4
        with: { version: 9 }
      - uses: actions/setup-node@v4
        with: { node-version: 22, cache: 'pnpm' }
      - run: pnpm install --frozen-lockfile
      - run: pnpm exec playwright install --with-deps chromium
      - run: pnpm e2e
```

### `.github/workflows/build-and-push.yml`

```yaml
name: Build & Push

on:
  push: { branches: [main] }
  workflow_dispatch:

permissions:
  contents: read
  packages: write

jobs:
  build:
    runs-on: ubuntu-latest
    outputs:
      tag: ${{ steps.meta.outputs.version }}
    steps:
      - uses: actions/checkout@v4
      - uses: docker/setup-buildx-action@v3
      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - id: meta
        uses: docker/metadata-action@v5
        with:
          images: ghcr.io/${{ github.repository }}/web
          tags: |
            type=sha,prefix=main-
            type=raw,value=latest,enable={{is_default_branch}}

      - uses: docker/build-push-action@v6
        with:
          context: .
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
          build-args: |
            NEXT_PUBLIC_API_URL=${{ vars.NEXT_PUBLIC_API_URL }}
            NEXT_PUBLIC_APP_URL=${{ vars.NEXT_PUBLIC_APP_URL }}
```

### Important: `NEXT_PUBLIC_*` is **build-time**

`NEXT_PUBLIC_*` values are baked into the JS bundle at `pnpm build` time. They must be available as build args:

```dockerfile
# Dockerfile
FROM node:22-alpine AS builder
ARG NEXT_PUBLIC_API_URL
ARG NEXT_PUBLIC_APP_URL
ENV NEXT_PUBLIC_API_URL=$NEXT_PUBLIC_API_URL
ENV NEXT_PUBLIC_APP_URL=$NEXT_PUBLIC_APP_URL
RUN pnpm build
```

Server-only env vars (no `NEXT_PUBLIC_` prefix) are runtime — pass via compose `environment:`.

This means you build a **separate image per environment** if `NEXT_PUBLIC_*` differs:

```yaml
# in build job, build twice with different args, tag separately
- run: |
    docker build --build-arg NEXT_PUBLIC_API_URL=https://api-staging.example.com -t web:staging-${{ github.sha }} .
    docker build --build-arg NEXT_PUBLIC_API_URL=https://api.example.com -t web:prod-${{ github.sha }} .
```

Or: keep `NEXT_PUBLIC_*` env-agnostic (e.g. relative `/api/v1`) so one image works everywhere.

### `.github/workflows/deploy.yml`

```yaml
name: Deploy

on:
  push: { tags: ['v*'] }
  workflow_dispatch:
    inputs:
      target: { type: choice, options: [staging, production], default: staging }

concurrency:
  group: deploy-${{ inputs.target || 'production' }}
  cancel-in-progress: false

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: ${{ inputs.target || 'production' }}
    steps:
      - uses: webfactory/ssh-agent@v0.9.0
        with:
          ssh-private-key: ${{ secrets.DEPLOY_SSH_KEY }}

      - run: ssh-keyscan -H ${{ secrets.DEPLOY_HOST }} >> ~/.ssh/known_hosts

      - run: |
          ssh deploy@${{ secrets.DEPLOY_HOST }} bash -s <<'ENDSSH'
            set -euo pipefail
            cd /var/www/{{project-slug}}
            export IMAGE_TAG="main-${GITHUB_SHA::7}"

            # pull new image
            docker compose -f docker-compose.prod.yml pull web

            # rolling swap (no DB to migrate for Next.js usually)
            docker compose -f docker-compose.prod.yml up -d --no-deps --remove-orphans web

            # health
            sleep 5
            for i in 1 2 3 4 5; do
              if curl -fsSL http://localhost:3000/api/health > /dev/null; then
                echo "healthy"; exit 0
              fi
              sleep 5
            done
            docker compose -f docker-compose.prod.yml down
            exit 1
          ENDSSH

      - name: Notify Sentry
        if: success()
        run: |
          curl -X POST "https://sentry.io/api/0/organizations/$ORG/releases/" \
            -H "Authorization: Bearer ${{ secrets.SENTRY_AUTH_TOKEN }}" \
            -d "{\"version\":\"web@$GITHUB_SHA\",\"projects\":[\"web\"]}"
```

## Lighthouse CI (optional but high-value)

Catch performance regressions:

```yaml
lighthouse:
  runs-on: ubuntu-latest
  needs: lint-test
  steps:
    - uses: actions/checkout@v4
    - uses: actions/setup-node@v4
      with: { node-version: 22 }
    - run: npm install -g @lhci/cli
    - run: |
        lhci autorun \
          --collect.url=http://localhost:3000 \
          --assert.preset=lighthouse:recommended \
          --assert.assertions.categories:performance.minScore=0.9 \
          --assert.assertions.categories:accessibility.minScore=0.95
```

Tune thresholds per project. Run on PR — block merge if perf drops.

## Bundle size budget

Use `next-bundle-analyzer` or `size-limit`:

```json
// package.json
"size-limit": [
  { "path": ".next/static/chunks/main-*.js", "limit": "150 kB" },
  { "path": ".next/static/chunks/pages/_app-*.js", "limit": "200 kB" }
]
```

```yaml
- run: pnpm build && pnpm size-limit
```

Block merge if bundle balloons.

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| `NEXT_PUBLIC_*` value missing in CI build | Pass as `build-args` in `docker/build-push-action` |
| Image cache misses every build | Layer order: copy `package.json` + `pnpm-lock.yaml` first, install, THEN copy source |
| Vercel preview URL changes per PR | Use Playwright's `BASE_URL` env var; or use Vercel's deployment URL output |
| Sharp missing in standalone build | Standalone bundles it; if errors, add to `next.config.ts` `experimental.serverComponentsExternalPackages: ['sharp']` |
| ISR cache lost between deploys | Mount volume on `.next/cache` or use Redis cache handler (see `deployment/per-framework/deploy-nextjs.md`) |
| `pnpm build` OOM | Bump runner to 4-core, or use Vercel/Netlify (their builders have more memory) |
| Edge runtime function deployed to Node runtime | Check `export const runtime = 'edge'` is set on edge routes; build logs show actual runtime |
