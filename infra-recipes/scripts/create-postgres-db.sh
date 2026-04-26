#!/usr/bin/env bash
# Create a per-project Postgres DB + user
# Usage: ./create-postgres-db.sh <project_name> [db_name]
# Examples:
#   ./create-postgres-db.sh myapp                # creates 'myapp_db' + user 'myapp'
#   ./create-postgres-db.sh myapp my_custom_db   # creates 'my_custom_db' + user 'myapp'

set -euo pipefail

if [ -z "${1:-}" ]; then
    echo "Usage: $0 <project_name> [db_name]"
    exit 1
fi

PROJECT_NAME="$1"
DB_NAME="${2:-${PROJECT_NAME}_db}"
DB_USER="$PROJECT_NAME"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")/shared-stack"
CONTAINER="${POSTGRES_CONTAINER:-app-postgres}"

# Load env
if [ -f "$PROJECT_DIR/.env" ]; then
    # shellcheck disable=SC1091
    source "$PROJECT_DIR/.env"
else
    echo "❌ no .env at $PROJECT_DIR/.env"
    exit 1
fi

# Generate password if not provided
DB_PASSWORD="${DB_PASSWORD:-$(openssl rand -hex 24)}"

echo "Creating Postgres DB '$DB_NAME' for project '$PROJECT_NAME'..."

docker exec -i -e PGPASSWORD="$POSTGRES_PASSWORD" "$CONTAINER" \
    psql -U "$POSTGRES_USER" -d postgres <<EOF
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${DB_USER}') THEN
        CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASSWORD}';
    END IF;
END
\$\$;

SELECT 'CREATE DATABASE ${DB_NAME} OWNER ${DB_USER}'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${DB_NAME}')\gexec

GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};

\c ${DB_NAME}
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";
CREATE EXTENSION IF NOT EXISTS "vector";
GRANT CREATE ON SCHEMA public TO ${DB_USER};
EOF

cat <<EOF

✅ Done!

Connection strings:
  # from host
  DATABASE_URL=postgresql://${DB_USER}:${DB_PASSWORD}@localhost:${POSTGRES_PORT:-5432}/${DB_NAME}

  # from another container on app-network
  DATABASE_URL=postgresql://${DB_USER}:${DB_PASSWORD}@app-postgres:5432/${DB_NAME}

  # SQLAlchemy async
  DATABASE_URL=postgresql+asyncpg://${DB_USER}:${DB_PASSWORD}@app-postgres:5432/${DB_NAME}

EOF
