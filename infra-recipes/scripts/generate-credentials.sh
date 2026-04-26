#!/usr/bin/env bash
# Generate a complete .env from scratch with strong random passwords
# Usage: ./generate-credentials.sh > shared-stack/.env

set -euo pipefail

generate_password() {
    openssl rand -hex 24
}

cat <<EOF
# ===================================================================
# Generated $(date -u +%FT%H%M%SZ) — DO NOT COMMIT
# ===================================================================

# Postgres
POSTGRES_USER=postgres
POSTGRES_PASSWORD=$(generate_password)
POSTGRES_DB=postgres
POSTGRES_PORT=5432

N8N_DB_NAME=n8n
N8N_DB_USER=n8n
N8N_DB_PASSWORD=$(generate_password)

# MongoDB
MONGO_INITDB_ROOT_USERNAME=admin
MONGO_INITDB_ROOT_PASSWORD=$(generate_password)
MONGO_INITDB_DATABASE=app
MONGODB_PORT=27017

# Redis
REDIS_PASSWORD=$(generate_password)
REDIS_PORT=6379

# Qdrant
QDRANT_API_KEY=$(generate_password)
QDRANT_HTTP_PORT=6333
QDRANT_GRPC_PORT=6334

# MinIO
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=$(generate_password)
MINIO_API_PORT=9000
MINIO_CONSOLE_PORT=9001

# n8n
N8N_HOST=localhost
N8N_PROTOCOL=http
N8N_PORT=5678
N8N_BASIC_AUTH_ACTIVE=true
N8N_BASIC_AUTH_USER=admin
N8N_BASIC_AUTH_PASSWORD=$(generate_password)
N8N_WEBHOOK_URL=http://localhost:5678/
N8N_TIMEZONE=UTC
EOF
