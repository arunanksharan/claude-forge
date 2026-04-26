# n8n — Self-hosted Workflow Automation

> n8n is **already included** in the [shared-stack docker-compose](../../shared-stack/docker-compose.yml) — it's a common workflow tool that pairs naturally with shared infrastructure. This README covers operational notes.

## Why include n8n in shared-stack

- Uses the shared Postgres + Redis (no extra services)
- Common useful glue tool — webhooks, schedules, light ETL
- Runs as a single container with low resource usage

## Setup

Already running if you brought up shared-stack:

```bash
docker compose -f shared-stack/docker-compose.yml ps
# look for app-n8n
```

Init script `01-create-n8n-db.sh` creates the n8n Postgres user + DB on first boot.

## Configuration in `.env`

```bash
N8N_HOST=n8n.example.com
N8N_PROTOCOL=https
N8N_PORT=5678
N8N_BASIC_AUTH_ACTIVE=true
N8N_BASIC_AUTH_USER=admin
N8N_BASIC_AUTH_PASSWORD=CHANGEME
N8N_WEBHOOK_URL=https://n8n.example.com/
N8N_TIMEZONE=UTC

# DB (uses shared-stack postgres)
N8N_DB_NAME=n8n
N8N_DB_USER=n8n
N8N_DB_PASSWORD=CHANGEME

# Redis queue mode (uses shared-stack redis)
# Already configured in docker-compose.yml — just need REDIS_PASSWORD
```

## nginx site

```nginx
# /etc/nginx/sites-available/n8n.example.com
server {
    listen 443 ssl http2;
    server_name n8n.example.com;

    ssl_certificate /etc/letsencrypt/live/n8n.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/n8n.example.com/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;

    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml;
    gzip_min_length 1000;

    location / {
        proxy_pass http://127.0.0.1:5678;
        proxy_http_version 1.1;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # WebSocket for the editor UI
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";

        # Long timeouts for long-running workflows
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 600s;

        proxy_buffering off;
        proxy_cache off;
    }
}
```

Use the [`websocket.conf`](../../nginx-templates/websocket.conf) template — n8n needs WS for the editor.

## Queue mode (recommended for production)

Already enabled in shared-stack — n8n uses BullMQ-on-Redis for execution. To run multiple workers (horizontal scaling):

```yaml
# in docker-compose.yml — add a separate worker service
n8n-worker:
  image: n8nio/n8n:latest
  command: ["worker"]
  environment:
    EXECUTIONS_MODE: queue
    QUEUE_BULL_REDIS_HOST: app-redis
    QUEUE_BULL_REDIS_PORT: 6379
    QUEUE_BULL_REDIS_PASSWORD: ${REDIS_PASSWORD}
    DB_TYPE: postgresdb
    DB_POSTGRESDB_HOST: app-postgres
    # ... same DB env as the main n8n service ...
```

For most use cases: single n8n container is fine.

## Backup

n8n state lives in:
1. Postgres (workflows, credentials, executions) — backed up via `pg_dump n8n`
2. Persistent volume `n8n_data` (settings, encryption key)

```bash
# backup
docker run --rm -v shared-stack_n8n_data:/data -v $PWD:/backup alpine \
    tar czf /backup/n8n-data-$(date -u +%FT%H%M%SZ).tar.gz /data

# DB
docker exec app-postgres pg_dump -U postgres -d n8n -F c > /var/backups/n8n-$(date -u +%FT%H%M%SZ).dump
```

**Critical**: the encryption key in `n8n_data/config` encrypts stored credentials. Lose it = lose all encrypted credentials.

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| Webhook URL wrong (causes "no response") | Set `N8N_WEBHOOK_URL` to public URL; behind nginx, set `N8N_PROTOCOL=https` and `N8N_TRUST_PROXY=true` |
| Settings file permissions warning | `chmod 600 /home/node/.n8n/config` inside container |
| Lost encryption key after restore | Encrypted credentials become invalid; users must re-enter |
| Disk fills with execution data | `EXECUTIONS_DATA_PRUNE=true` + `EXECUTIONS_DATA_MAX_AGE=168` (hours) |
| Slow editor UI behind nginx | Verify WebSocket upgrade headers; check `proxy_buffering off` |
| Workflows trigger but don't complete | Check Redis connection; check `EXECUTIONS_MODE=queue` |
| Some nodes need extra OS packages | Use `n8nio/n8n` image; for edge cases, build custom image |
