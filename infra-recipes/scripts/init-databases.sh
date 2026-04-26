#!/usr/bin/env bash
# Bulk initialize per-project databases across Postgres + MongoDB
# Usage: ./init-databases.sh project1 project2 project3 ...

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$#" -eq 0 ]; then
    echo "Usage: $0 <project_name> [project_name ...]"
    echo ""
    echo "Creates a Postgres DB + MongoDB DB for each project name."
    exit 1
fi

for project in "$@"; do
    echo ""
    echo "═════════════════════════════════════"
    echo "  Initializing: $project"
    echo "═════════════════════════════════════"
    "$SCRIPT_DIR/create-postgres-db.sh" "$project"
    "$SCRIPT_DIR/create-mongo-db.sh" "$project"
    echo ""
    echo "  Redis: use database number $(printf '%d' $RANDOM | head -c 1)"
    echo "    redis://:\$REDIS_PASSWORD@app-redis:6379/N"
    echo ""
done

echo ""
echo "✅ All projects initialized."
echo ""
echo "Verify:"
echo "  docker exec app-postgres psql -U postgres -c '\\l'"
echo "  docker exec app-mongodb mongosh -u admin -p '\$MONGO_INITDB_ROOT_PASSWORD' --authenticationDatabase admin --eval 'db.adminCommand({listDatabases:1}).databases.forEach(d => print(d.name))'"
