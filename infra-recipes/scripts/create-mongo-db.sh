#!/usr/bin/env bash
# Create a per-project MongoDB database + user
# Usage: ./create-mongo-db.sh <project_name> [db_name]

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
CONTAINER="${MONGO_CONTAINER:-app-mongodb}"

if [ -f "$PROJECT_DIR/.env" ]; then
    # shellcheck disable=SC1091
    source "$PROJECT_DIR/.env"
else
    echo "❌ no .env at $PROJECT_DIR/.env"
    exit 1
fi

DB_PASSWORD="${DB_PASSWORD:-$(openssl rand -hex 24)}"

echo "Creating MongoDB '$DB_NAME' for project '$PROJECT_NAME'..."

docker exec -i "$CONTAINER" mongosh --quiet \
    -u "$MONGO_INITDB_ROOT_USERNAME" \
    -p "$MONGO_INITDB_ROOT_PASSWORD" \
    --authenticationDatabase admin <<EOF
use ${DB_NAME};
if (db.getUser("${DB_USER}") == null) {
    db.createUser({
        user: "${DB_USER}",
        pwd: "${DB_PASSWORD}",
        roles: [ { role: "readWrite", db: "${DB_NAME}" } ]
    });
    print("✓ created user ${DB_USER}");
} else {
    print("ℹ user ${DB_USER} already exists");
}
db.createCollection("_init");
EOF

cat <<EOF

✅ Done!

Connection strings:
  # from host
  MONGODB_URL=mongodb://${DB_USER}:${DB_PASSWORD}@localhost:${MONGODB_PORT:-27017}/${DB_NAME}?authSource=${DB_NAME}

  # from another container on app-network
  MONGODB_URL=mongodb://${DB_USER}:${DB_PASSWORD}@app-mongodb:27017/${DB_NAME}?authSource=${DB_NAME}

EOF
