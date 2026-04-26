# GitHub Actions for FastAPI

> Pipeline: lint + type-check + test on PR, build + push image on merge, deploy via SSH.

## `.github/workflows/ci.yml` — runs on every PR + push

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
          --health-timeout 3s
          --health-retries 10

      redis:
        image: redis:7-alpine
        ports: ['6379:6379']

    steps:
      - uses: actions/checkout@v4

      - name: Install uv
        uses: astral-sh/setup-uv@v3
        with:
          version: latest
          enable-cache: true

      - name: Set up Python
        run: uv python install 3.12

      - name: Install deps
        run: uv sync --frozen --all-extras --dev

      - name: Lint
        run: |
          uv run ruff check .
          uv run ruff format --check .

      - name: Type check
        run: uv run mypy src

      - name: Run migrations
        env:
          DATABASE_URL: postgresql+asyncpg://postgres:postgres@localhost:5432/{{db-name}}_test
        run: uv run alembic upgrade head

      - name: Tests
        env:
          DATABASE_URL: postgresql+asyncpg://postgres:postgres@localhost:5432/{{db-name}}_test
          REDIS_URL: redis://localhost:6379/0
          JWT_SECRET: test-secret-min-32-chars-changeme-now
        run: uv run pytest --cov=src --cov-report=term-missing --cov-fail-under=70

      - name: Upload coverage
        if: github.event_name == 'pull_request'
        uses: codecov/codecov-action@v4
        with:
          token: ${{ secrets.CODECOV_TOKEN }}
          fail_ci_if_error: false
```

### Why each piece

| Setting | Why |
|---------|-----|
| `concurrency: cancel-in-progress` | Pushes to a PR cancel the previous run — saves CI minutes |
| `services: postgres` | Real DB in CI — catches bugs mocks miss |
| `astral-sh/setup-uv@v3` with caching | uv is 10-100x faster than pip; caching speeds reruns |
| Migrations before tests | Catches migration drift in CI |
| `--cov-fail-under=70` | Coverage floor; raise as the project matures |
| Codecov on PR only | No noise on main |

## `.github/workflows/build-and-push.yml` — on merge to main

```yaml
name: Build & Push

on:
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read
  packages: write
  id-token: write          # for OIDC

jobs:
  build:
    runs-on: ubuntu-latest
    outputs:
      image_tag: ${{ steps.meta.outputs.version }}
      image_digest: ${{ steps.build.outputs.digest }}
    steps:
      - uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Log in to GHCR
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Extract metadata
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ghcr.io/${{ github.repository }}/api
          tags: |
            type=sha,prefix={{branch}}-
            type=raw,value=latest,enable={{is_default_branch}}
            type=ref,event=branch
            type=ref,event=tag

      - name: Build and push
        id: build
        uses: docker/build-push-action@v6
        with:
          context: .
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
          provenance: true
          sbom: true

      - name: Sign image with cosign
        uses: sigstore/cosign-installer@v3
      - run: cosign sign --yes ghcr.io/${{ github.repository }}/api@${{ steps.build.outputs.digest }}
```

### Image tagging strategy

- `main-<sha>` — every commit to main
- `latest` — the most recent main
- `v1.2.3` — when you push a git tag

Deploy by pinning to `main-<sha>`; never deploy `:latest` to prod (you can't reproduce what was running).

## `.github/workflows/deploy.yml` — manual / on tag

```yaml
name: Deploy

on:
  push:
    tags: ['v*']
  workflow_dispatch:
    inputs:
      image_tag:
        description: 'Image tag to deploy (default: latest sha on main)'
        required: false
        type: string
      target:
        description: 'Target environment'
        required: true
        type: choice
        options: [staging, production]
        default: staging

concurrency:
  group: deploy-${{ inputs.target || 'production' }}
  cancel-in-progress: false        # never cancel a deploy mid-flight

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: ${{ inputs.target || 'production' }}
    steps:
      - uses: actions/checkout@v4

      - name: Resolve image tag
        id: tag
        run: |
          if [ -n "${{ inputs.image_tag }}" ]; then
            echo "tag=${{ inputs.image_tag }}" >> $GITHUB_OUTPUT
          elif [ "${{ github.ref_type }}" = "tag" ]; then
            echo "tag=${{ github.ref_name }}" >> $GITHUB_OUTPUT
          else
            echo "tag=main-${GITHUB_SHA::7}" >> $GITHUB_OUTPUT
          fi

      - name: Set up SSH
        uses: webfactory/ssh-agent@v0.9.0
        with:
          ssh-private-key: ${{ secrets.DEPLOY_SSH_KEY }}

      - name: Add server to known hosts
        run: ssh-keyscan -H ${{ secrets.DEPLOY_HOST }} >> ~/.ssh/known_hosts

      - name: Deploy
        run: |
          ssh deploy@${{ secrets.DEPLOY_HOST }} bash -s <<'ENDSSH'
            set -euo pipefail
            cd /var/www/{{project-slug}}
            export IMAGE_TAG="${{ steps.tag.outputs.tag }}"
            echo "deploying $IMAGE_TAG"

            # pull new image
            docker compose -f docker-compose.prod.yml pull api worker

            # run migrations BEFORE swapping the app
            docker compose -f docker-compose.prod.yml run --rm api alembic upgrade head

            # rolling restart of api + worker (compose handles ordering)
            docker compose -f docker-compose.prod.yml up -d --no-deps --remove-orphans api worker

            # health check
            sleep 5
            for i in 1 2 3 4 5; do
              if docker exec {{project-slug}}-api wget -qO- http://localhost:8000/health > /dev/null 2>&1; then
                echo "healthy"
                exit 0
              fi
              echo "waiting for health... attempt $i"
              sleep 5
            done
            echo "deploy failed health check; rolling back"
            docker compose -f docker-compose.prod.yml down
            exit 1
          ENDSSH

      - name: Notify on failure
        if: failure()
        uses: slackapi/slack-github-action@v1.27.0
        with:
          payload: |
            {"text":"❌ deploy of {{project-slug}} to ${{ inputs.target || 'production' }} failed: ${{ github.run_url }}"}
        env:
          SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}

      - name: Tag Sentry release
        if: success()
        run: |
          curl -X POST "https://sentry.io/api/0/organizations/$ORG/releases/" \
            -H "Authorization: Bearer ${{ secrets.SENTRY_AUTH_TOKEN }}" \
            -H "Content-Type: application/json" \
            -d "{\"version\":\"{{project-slug}}@${{ steps.tag.outputs.tag }}\",\"projects\":[\"{{project-slug}}\"]}"
```

### Why GitHub Environments

`environment: production` — gates the deploy job behind:
- Required reviewers (set in repo settings)
- Wait timer
- Deployment branch restrictions
- Per-environment secrets

For `production`: require 1 reviewer, restrict to `main` branch + tags. For `staging`: no gates, auto-deploy.

## Required GitHub Secrets

Set in repo Settings → Secrets and variables → Actions:

| Secret | Purpose |
|--------|---------|
| `DEPLOY_SSH_KEY` | Private key for `deploy@server` (matching `~/.ssh/authorized_keys` on server) |
| `DEPLOY_HOST` | Server hostname / IP |
| `SLACK_WEBHOOK_URL` | For deploy notifications |
| `SENTRY_AUTH_TOKEN` | For release tagging |
| `CODECOV_TOKEN` | If using Codecov |

For per-environment secrets (different prod vs staging values), use **Environment secrets** instead of Repository secrets.

## OIDC for cloud (when not just SSH)

If you deploy to AWS/GCP, use OIDC instead of long-lived keys:

```yaml
permissions:
  id-token: write
  contents: read

steps:
  - uses: aws-actions/configure-aws-credentials@v4
    with:
      role-to-assume: arn:aws:iam::123456789:role/github-deploy
      aws-region: us-east-1
```

Set up the role in AWS with a trust policy on `token.actions.githubusercontent.com`. No secrets to rotate.

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| Tests pass locally, fail in CI | DB state leak, missing service container, env var mismatch |
| Slow CI (10+ min) | Cache deps (`enable-cache: true`); split slow tests into separate job |
| Building a different image than tested | Use the **same Dockerfile** for CI build + deploy; tag and pin |
| Deploying `:latest` | Always pin to `<branch>-<sha>` so you can roll back |
| Migration runs concurrently from 2 instances | Use single-instance migration step (compose `run --rm`) before app swap |
| Secret accidentally logged | Use `add-mask::***` directives; or use `actions/setup-*` that mask automatically |
| Force-push to main triggers deploy | Use protected branches + required reviews on main |
| Secrets leaked in PR from a fork | Don't expose secrets to `pull_request` from forks; use `pull_request_target` carefully |
| Deploy runs while previous in-flight | `concurrency: cancel-in-progress: false` for deploys (don't cancel mid-flight!) |
| No rollback path | Deploy script should handle health-check failure with `compose down`; keep previous image tag noted |
