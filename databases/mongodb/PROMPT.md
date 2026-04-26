# MongoDB — Master Setup & Integration Prompt

> **Copy this file into Claude Code. Replace `{{placeholders}}`. The model will set up MongoDB (containerized or Atlas-hosted), wire it to your app, create init scripts, and verify health.**

---

## Context

You are setting up MongoDB for a project. **Default to Postgres** (per [`databases/README.md`](./README.md)) — only proceed with MongoDB if the data is genuinely document-shaped with embedded sub-documents that don't normalize cleanly. Examples: chat messages with embedded reactions/attachments, deeply nested user profiles with arbitrary attributes, schema-less ingestion buckets.

If something is ambiguous, **ask once, then proceed**.

## Project parameters

```
project_slug:       {{project-slug}}
db_name:            {{db-name}}
mongo_version:      8.0                         # current GA in 2026
hosting:            {{docker|atlas|self-hosted-replica-set}}
language:           {{python|node|go|java}}
odm:                {{beanie|mongoose|motor|none}}
include_search:     {{yes-or-no}}               # Atlas Search (Atlas only) or none
```

---

## Locked stack

| Concern | Pick | Why |
|---------|------|-----|
| Version | **MongoDB 8.0** | Current GA, faster aggregation, queryable encryption |
| Image | **`mongo:8.0`** | Official |
| Driver (Python) | **Motor** (async) over PyMongo | Or **Beanie** if you want Pydantic models |
| Driver (Node) | Official **`mongodb`** driver | Or **Mongoose** if you want schemas + middleware |
| Hosting | **Atlas** for production (free tier generous; managed backups + replicas) | Self-host only if compliance requires |
| Replica set | **Required for production** (Atlas does this) | Single-node = data loss risk |
| Backup | Atlas snapshots OR `mongodump` for self-hosted | |
| Migration | No formal migrations; use idempotent ingestion scripts + collection validators | |

## Rejected

| Option | Why not |
|--------|---------|
| `mongo:latest` | Pin major version — breaking changes happen |
| Single-node prod | No HA, no backup; always replica set in prod |
| Pymongo (sync) for new async apps | Use Motor or Beanie |
| Embedding unbounded arrays (e.g., comments per post) | Reference instead — 16MB doc limit |
| Free-form schemas without validators | Add JSON Schema validators — saves debugging time |
| `find().toArray()` on huge collections | Stream with cursor |

---

## Directory layout

```
{{project-slug}}/infra/mongodb/
├── docker-compose.dev.yml
├── mongod.conf                            # custom config (replica set keyFile, etc.)
├── init-scripts/
│   ├── 01-create-app-db.sh                # creates {{db-name}} + app user
│   └── 02-create-collections.sh           # initial collections + indexes + validators
├── backup.sh                              # daily mongodump
└── README.md
```

---

## Key files

### `infra/mongodb/docker-compose.dev.yml`

```yaml
services:
  mongodb:
    image: mongo:8.0
    container_name: {{project-slug}}-mongodb
    restart: unless-stopped
    ports:
      - '127.0.0.1:27017:27017'
    volumes:
      - mongodb_data:/data/db
      - mongodb_config:/data/configdb
      - ./init-scripts:/docker-entrypoint-initdb.d:ro
    environment:
      MONGO_INITDB_ROOT_USERNAME: ${MONGO_ROOT_USER:-admin}
      MONGO_INITDB_ROOT_PASSWORD: ${MONGO_ROOT_PASSWORD:?MONGO_ROOT_PASSWORD required}
      MONGO_INITDB_DATABASE: {{db-name}}
      APP_DB_USER: ${APP_DB_USER:-app}
      APP_DB_PASSWORD: ${APP_DB_PASSWORD:?APP_DB_PASSWORD required}
    command: mongod --wiredTigerCacheSizeGB 1 --bind_ip 0.0.0.0
    healthcheck:
      test: ['CMD', 'mongosh', '--quiet', '--eval', "db.adminCommand('ping').ok"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 40s
    deploy:
      resources:
        limits: { cpus: '2', memory: 2G }
        reservations: { cpus: '0.5', memory: 512M }

volumes:
  mongodb_data:
  mongodb_config:
```

### `infra/mongodb/init-scripts/01-create-app-db.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

mongosh --quiet \
  --username "$MONGO_INITDB_ROOT_USERNAME" \
  --password "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin <<EOF
use ${MONGO_INITDB_DATABASE};
db.createUser({
  user: "${APP_DB_USER}",
  pwd: "${APP_DB_PASSWORD}",
  roles: [ { role: "readWrite", db: "${MONGO_INITDB_DATABASE}" } ]
});
print("✓ app user created");
EOF
```

### `infra/mongodb/init-scripts/02-create-collections.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

mongosh --quiet \
  --username "$MONGO_INITDB_ROOT_USERNAME" \
  --password "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin <<EOF
use ${MONGO_INITDB_DATABASE};

// users with JSON Schema validator
db.createCollection("users", {
  validator: {
    \$jsonSchema: {
      bsonType: "object",
      required: ["email", "createdAt"],
      properties: {
        email: { bsonType: "string", pattern: "^[^@]+@[^@]+\\\\..+$" },
        createdAt: { bsonType: "date" },
        isActive: { bsonType: "bool" },
      }
    }
  },
  validationAction: "error"
});

db.users.createIndex({ email: 1 }, { unique: true });
db.users.createIndex({ tenantId: 1, createdAt: -1 });

// sessions with TTL
db.createCollection("sessions");
db.sessions.createIndex({ expiresAt: 1 }, { expireAfterSeconds: 0 });
db.sessions.createIndex({ userId: 1 });

print("✓ collections + indexes created");
EOF
```

### `infra/mongodb/backup.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/var/backups/mongodb}"
RETENTION_DAYS="${RETENTION_DAYS:-14}"
DB_NAME="${DB_NAME:?DB_NAME required}"

mkdir -p "$BACKUP_DIR"
TS=$(date -u +%Y%m%dT%H%M%SZ)
DEST="$BACKUP_DIR/${DB_NAME}-${TS}"

docker exec {{project-slug}}-mongodb mongodump \
    --uri="mongodb://${MONGO_ROOT_USER}:${MONGO_ROOT_PASSWORD}@localhost:27017/${DB_NAME}?authSource=admin" \
    --gzip \
    --archive="/tmp/${DB_NAME}-${TS}.archive.gz"

docker cp {{project-slug}}-mongodb:/tmp/${DB_NAME}-${TS}.archive.gz "${DEST}.archive.gz"

find "$BACKUP_DIR" -type f -mtime +${RETENTION_DAYS} -delete
echo "✓ backed up to ${DEST}.archive.gz"
```

---

## Generation steps

1. **Confirm parameters**.
2. **Create directory tree**.
3. **Write `docker-compose.dev.yml`, init scripts, `backup.sh`.**
4. **Bring up MongoDB**: `docker compose -f infra/mongodb/docker-compose.dev.yml up -d`.
5. **Verify**: `docker exec {{project-slug}}-mongodb mongosh -u $APP_DB_USER -p ... --authenticationDatabase {{db-name}}` and `show collections`.
6. **Set the connection string**:
   ```
   MONGODB_URL=mongodb://app:****@localhost:27017/{{db-name}}?authSource={{db-name}}
   ```
7. **Wire the app** (Beanie/Mongoose/Motor — see `04-language-clients.md`).
8. **Initial collections + indexes** are created by init scripts; add new ones in app code.
9. **Schedule backup** (cron / systemd timer).
10. **Hand off** with: connection string, replica-set upgrade path, monitoring guidance.

---

## Companion deep-dives

- [`README.md`](./README.md) — overview + when to choose MongoDB
- [`01-schema-design.md`](./01-schema-design.md) — embed-vs-reference, schema patterns, validators
- [`02-queries-and-aggregation.md`](./02-queries-and-aggregation.md) — find/aggregation pipelines, indexing (ESR rule), $lookup
- [`03-operations.md`](./03-operations.md) — replica sets, sharding, backups, monitoring
- [`04-language-clients.md`](./04-language-clients.md) — Motor (Python), Beanie, Mongoose, official drivers — connection patterns

For migrating off MongoDB to Postgres (when you've outgrown it), see [`databases/mongodb/README.md`](./README.md) "When to migrate to Postgres" section.
