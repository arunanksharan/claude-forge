# GitHub Actions for NestJS / Node + Express

> Same shape as the FastAPI guide — different commands. Lint + type + test on PR, build + push on main, deploy via SSH.

## `.github/workflows/ci.yml`

```yaml
name: CI

on:
  pull_request:
    branches: [main]
  push:
    branches: [main]

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

jobs:
  lint-test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16-alpine
        env:
          POSTGRES_USER: postgres
          POSTGRES_PASSWORD: postgres
          POSTGRES_DB: {{db-name}}_test
        ports: ['5432:5432']
        options: >-
          --health-cmd "pg_isready -U postgres"
          --health-interval 5s
          --health-retries 10

      redis:
        image: redis:7-alpine
        ports: ['6379:6379']

    steps:
      - uses: actions/checkout@v4

      - uses: pnpm/action-setup@v4
        with:
          version: 9

      - uses: actions/setup-node@v4
        with:
          node-version: 22
          cache: 'pnpm'

      - run: pnpm install --frozen-lockfile

      # NestJS-only: regenerate Prisma client
      - run: pnpm prisma generate

      - name: Lint
        run: pnpm lint

      - name: Type check
        run: pnpm tsc --noEmit

      - name: Migrate
        env:
          DATABASE_URL: postgresql://postgres:postgres@localhost:5432/{{db-name}}_test
        run: pnpm prisma migrate deploy

      - name: Tests
        env:
          DATABASE_URL: postgresql://postgres:postgres@localhost:5432/{{db-name}}_test
          REDIS_URL: redis://localhost:6379
          JWT_SECRET: test-secret-min-32-chars-changeme-now
        run: pnpm test --coverage

      - name: E2E tests
        env:
          DATABASE_URL: postgresql://postgres:postgres@localhost:5432/{{db-name}}_test
          REDIS_URL: redis://localhost:6379
        run: pnpm test:e2e

      - name: Build
        run: pnpm build
```

### Express variant

Same template, swap:
- `pnpm prisma generate` / `pnpm prisma migrate deploy` → `pnpm db:generate` / `pnpm db:migrate` (Drizzle)
- `pnpm test:e2e` → just `pnpm test` (Vitest covers both unit and integration)

## `.github/workflows/build-and-push.yml`

Identical to the FastAPI build workflow — Docker is Docker. Reference: `cicd/github-actions-fastapi.md` for the full build job.

The only difference: image name `ghcr.io/${{ github.repository }}/api` may become `/web` or `/{{project-slug}}` depending on convention.

## `.github/workflows/deploy.yml`

Same shell-out-to-SSH structure as FastAPI, with framework-specific commands:

```yaml
- name: Deploy
  run: |
    ssh deploy@${{ secrets.DEPLOY_HOST }} bash -s <<'ENDSSH'
      set -euo pipefail
      cd /var/www/{{project-slug}}
      export IMAGE_TAG="${{ steps.tag.outputs.tag }}"

      # pull
      docker compose -f docker-compose.prod.yml pull api worker

      # migrations
      docker compose -f docker-compose.prod.yml run --rm api pnpm prisma migrate deploy

      # rolling restart
      docker compose -f docker-compose.prod.yml up -d --no-deps --remove-orphans api worker

      # health check
      sleep 5
      for i in 1 2 3 4 5; do
        if docker exec {{project-slug}}-api wget -qO- http://localhost:3000/api/v1/health > /dev/null 2>&1; then
          echo "healthy"
          exit 0
        fi
        sleep 5
      done
      docker compose -f docker-compose.prod.yml down
      exit 1
    ENDSSH
```

## PM2 variant (no Docker)

If you deploy to a VPS without Docker, use PM2:

```yaml
- name: Deploy via PM2
  run: |
    ssh deploy@${{ secrets.DEPLOY_HOST }} bash -s <<'ENDSSH'
      set -euo pipefail
      cd /var/www/{{project-slug}}

      git fetch --tags
      git reset --hard ${{ steps.tag.outputs.tag }}

      pnpm install --frozen-lockfile
      pnpm prisma generate
      pnpm prisma migrate deploy
      pnpm build

      pm2 reload ecosystem.config.cjs --update-env
      pm2 save

      # health check
      sleep 3
      curl -f http://localhost:3000/api/v1/health || (echo "unhealthy"; exit 1)
    ENDSSH
```

`pm2 reload` is **zero-downtime** for cluster mode (one worker swapped at a time, draining gracefully).

## Cache strategy

For pnpm, `cache: 'pnpm'` in `setup-node` caches `~/.local/share/pnpm/store` — keyed by `pnpm-lock.yaml` hash. Subsequent CI runs skip download.

For Docker buildx: `cache-from: type=gha` and `cache-to: type=gha,mode=max` use GitHub's cache.

For Prisma client codegen: it's fast (~5s) so caching isn't worth the complexity. Just regenerate.

## Performance budget

A well-tuned NestJS pipeline:
- Lint + type check: ~30s (after cache)
- Tests with real Postgres: ~60s for ~100 tests
- E2E: ~60-90s
- Build: ~30s
- **Total: ~3–4 minutes**

If you're seeing 10+ minutes:
- Check that the pnpm cache is hitting
- Are tests running serially that could parallelize?
- Is the test DB being recreated per test (vs truncated)?

## Common pitfalls

Same as the FastAPI guide. Plus:

| Pitfall | Fix |
|---------|-----|
| `pnpm install` slow even with cache | `cache: 'pnpm'` requires lockfile to be in repo root; check `cache-dependency-path` |
| `pnpm prisma generate` runs every step | Run once, the generated client is in `node_modules` — subsequent steps re-use |
| Out-of-memory in test job | Bump runner: `runs-on: ubuntu-latest-4-cores` (paid) or split test job |
| Docker layer cache misses on every build | `cache-from: type=gha` + ensure `pnpm-lock.yaml` is copied before source in Dockerfile |
| Build artifact too big | `pnpm prune --prod` between build stage and runner stage in multi-stage Dockerfile |
