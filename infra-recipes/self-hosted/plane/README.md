# Plane — Self-hosted Project Management

> Notes on running Plane (Jira/Linear alternative) alongside the shared-stack.

## Why a separate README

Plane's docker-compose is **large** (10+ services: web, api, worker, beat, live-server, minio, rabbitmq, etc.) and lives in their official repo. Rather than vendor a sanitized version that drifts, this README documents:

- How to integrate Plane with the shared-stack (use shared Postgres + Redis)
- Which Plane env vars matter
- Common pitfalls

## Get the official compose

```bash
cd /opt
git clone https://github.com/makeplane/plane plane-app
cd plane-app
git checkout v0.27   # pin a release; check current LTS
```

Use their `setup.sh` for first-time setup, then customize.

## Integration with shared-stack

Override these env vars in `plane.env`:

```bash
# Use shared Postgres (DB created via ./scripts/create-postgres-db.sh planedb)
DATABASE_URL=postgresql://planedb:****@app-postgres:5432/planedb
PGHOST=app-postgres
PGUSER=planedb
PGPASSWORD=****
PGDATABASE=planedb
PGPORT=5432

# Use shared Redis (DB 3)
REDIS_URL=redis://:****@app-redis:6379/3

# Plane needs RabbitMQ — let it run its own
# AMQP_URL=amqp://plane:plane@plane-mq:5672/

# MinIO — Plane has its own, but you can point at shared-stack MinIO instead
USE_MINIO=1
AWS_S3_ENDPOINT_URL=http://app-minio:9000
AWS_ACCESS_KEY_ID=minioadmin
AWS_SECRET_ACCESS_KEY=****
AWS_S3_BUCKET_NAME=plane-uploads
```

In Plane's `docker-compose.yml`, ensure all services join the `app-network`:

```yaml
networks:
  default:
    name: app-network
    external: true
```

Then `docker compose --env-file plane.env up -d` brings Plane up — plane services use shared Postgres/Redis, plus their own RabbitMQ.

## Setup flow

1. Bring up shared-stack
2. `./scripts/create-postgres-db.sh planedb` to create DB
3. Create `plane-uploads` bucket in MinIO console (`http://localhost:9001`)
4. Copy Plane's official compose into `/opt/plane-app`
5. Customize `plane.env` per above
6. `docker compose --env-file plane.env up -d`
7. Browse to `http://localhost:80` and create the admin account
8. Add nginx site for `plane.example.com` → upstream port 80

## nginx config

Plane runs its frontend + API behind a single nginx in their compose. Forward your external nginx to it:

```nginx
# /etc/nginx/sites-available/plane.example.com
server {
    listen 443 ssl http2;
    server_name plane.example.com;

    ssl_certificate /etc/letsencrypt/live/plane.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/plane.example.com/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;

    client_max_body_size 100M;

    location / {
        proxy_pass http://127.0.0.1:80;       # plane's exposed port
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # WebSocket for Plane's live-server
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 24h;
    }
}
```

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| RabbitMQ connection refused | Plane's RabbitMQ takes time; wait 60s on first start |
| Static files 404 | Ensure Plane's nginx mount picked up assets correctly; rebuild |
| MinIO bucket missing | Create in console before starting Plane |
| Email not sending | Set SMTP env vars; some features require email |
| Live-server WebSocket fails | nginx must have WS upgrade headers |
| Migrations fail on upgrade | Pin Plane version; review their changelog |
