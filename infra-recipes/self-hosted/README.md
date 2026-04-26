# Self-Hosted Apps — claudeforge infra-recipes

> Per-app docker-compose files for self-hostable open-source SaaS alternatives. Each connects to the [`shared-stack/`](../shared-stack/) infrastructure (Postgres, Redis, MinIO).

## Apps included

| Folder | App | Purpose | Default domain |
|--------|-----|---------|----------------|
| [`signoz/`](./signoz) | **SigNoz** | Observability (traces, metrics, logs) | `telemetry.example.com` |
| [`docmost/`](./docmost) | **Docmost** | Wiki / documentation (Notion alternative) | `wiki.example.com` |
| [`plane/`](./plane) | **Plane** | Project management (Jira / Linear alternative) | `plane.example.com` |
| [`twenty-crm/`](./twenty-crm) | **Twenty** | CRM (HubSpot alternative) | `crm.example.com` |

These are real-world configs — sanitized, documented prerequisites, with healthchecks + resource limits.

## Setup pattern (same for each)

1. **Have shared-stack running**: `docker compose -f shared-stack/docker-compose.yml up -d`
2. **Create per-app DB** (most apps need a Postgres DB):
   ```bash
   ./scripts/create-postgres-db.sh <app-name>     # e.g. docmost, plane, twenty
   ```
3. **(If app needs MinIO bucket)**: create the bucket via MinIO console or `mc` CLI
4. **Customize the app's `.env`** with the connection strings from step 2 + secrets
5. **Bring up**: `docker compose -f self-hosted/<app>/docker-compose.yml --env-file <app>.env up -d`
6. **Add nginx site**: copy template from [`../nginx-templates/`](../nginx-templates/), customize for the app's port
7. **Issue SSL**: `sudo certbot --nginx -d <app>.example.com`

## Why self-host these

| Pro | Con |
|-----|-----|
| Data ownership / compliance | You manage uptime + backups |
| No per-seat pricing | Operational burden |
| Customization freedom | No SLA / support unless paid |
| Often equivalent or better than SaaS for small teams | Some features lag the SaaS version |

For most teams: self-host the unified stack on a single $20-40/mo VPS, save $1000+/yr in subscriptions, accept the ops cost.

## App-specific notes

### SigNoz (`signoz/`)
- Replaces Datadog / New Relic for self-hosted observability
- Lightweight version included (just OTel collector → debug); full stack requires ClickHouse — see SigNoz docs
- Reference config in [`observability/01-signoz-opentelemetry.md`](../../observability/01-signoz-opentelemetry.md)

### Docmost (`docmost/`)
- Real-time collaborative wiki
- Needs SMTP for invite emails
- Storage: local filesystem (default) or S3 (point at MinIO)

### Plane (`plane/`)
- Self-hosted project management; replaces Jira/Linear
- Needs RabbitMQ (included in Plane's compose) + Redis (shared) + Postgres (shared) + MinIO (its own instance)
- Onboarding: visit `/god-mode/setup`

### Twenty CRM (`twenty-crm/`)
- Self-hosted CRM (HubSpot alternative)
- Needs Postgres (shared) + Redis (shared) + S3 storage (MinIO)
- Sign-up disabled by default (`IS_SIGN_UP_DISABLED=true`)

## Common operational tasks

### Backups

Each app's data lives primarily in the shared Postgres + MinIO. Backup those, you backup the apps.

```bash
# Backup all per-app DBs at once
for db in docmost plane twenty; do
    docker exec app-postgres pg_dump -U postgres -d $db -F c > /var/backups/$db-$(date -u +%FT%H%M%SZ).dump
done
```

### Updates

```bash
# pull new image
docker compose -f self-hosted/<app>/docker-compose.yml pull

# restart with new image (zero-downtime if you have multiple replicas; brief blip otherwise)
docker compose -f self-hosted/<app>/docker-compose.yml up -d
```

Check the app's release notes for breaking changes (DB migrations, env var changes).

### Resource budget

Per app, typically:
- 0.5-1 CPU
- 512 MB - 2 GB RAM
- 5-20 GB disk (mostly user uploads)

Five self-hosted apps + shared-stack on one VPS: 8-16 GB RAM, 4 CPU, 100 GB disk usually sufficient for small/medium teams.
