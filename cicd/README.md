# CI/CD — claudeforge guides

GitHub Actions workflows + deploy automation. The pattern: lint + type-check + test on every PR, build + push image on merge to main, deploy via SSH to a VPS or registry push to a managed service.

## Files

| File | What it is |
|------|-----------|
| [`github-actions-fastapi.md`](./github-actions-fastapi.md) | Lint+type+test+build+deploy pipeline for FastAPI |
| [`github-actions-nestjs.md`](./github-actions-nestjs.md) | Same shape for NestJS / Node+Express |
| [`github-actions-nextjs.md`](./github-actions-nextjs.md) | Build + deploy for Next.js (Vercel + self-hosted variants) |
| [`deploy-automation.md`](./deploy-automation.md) | SSH-based deploy script, blue-green via Docker, zero-downtime PM2 reload |
| [`secrets-and-environments.md`](./secrets-and-environments.md) | GitHub Secrets, environments, OIDC for cloud, separate prod/staging configs |

## Decision summary

| Concern | Pick |
|---------|------|
| CI host | **GitHub Actions** (default, free for public, free-tier for private) |
| Container registry | **GitHub Container Registry (GHCR)** — free, integrated, fast |
| Deploy target | **Self-hosted VPS** via SSH (full control) — *or* Vercel/Fly/Railway (managed) |
| Secrets | **GitHub Encrypted Secrets** + Environments for prod gating |
| Cloud auth | **OIDC** — no long-lived AWS/GCP keys in CI |
| Deploy strategy | **Rolling/blue-green** via compose `--no-deps` or PM2 reload |

## Anti-patterns rejected

- **CircleCI / Travis / Jenkins** for new projects — GHA is right next to your code, free at small scale
- **Docker Hub** for private images — rate limits + cost; use GHCR
- **Long-lived AWS keys in CI** — use OIDC
- **Deploying via FTP / rsync** — use SSH + a deploy script with health checks
- **Skipping pre-deploy DB migrations** — always migrate before app deploy
