#!/usr/bin/env bash
# Selectively start services from shared-stack
# Usage: ./check-and-start-services.sh [postgres redis mongo qdrant minio n8n all]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")/shared-stack"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

container_for() {
    case "$1" in
        postgres) echo "app-postgres" ;;
        redis)    echo "app-redis" ;;
        mongo)    echo "app-mongodb" ;;
        qdrant)   echo "app-qdrant" ;;
        minio)    echo "app-minio" ;;
        n8n)      echo "app-n8n" ;;
        *)        echo "" ;;
    esac
}

is_running() {
    docker ps --format '{{.Names}}' | grep -q "^$1$"
}

start_service() {
    local svc=$1
    local container
    container=$(container_for "$svc")
    if [ -z "$container" ]; then
        echo -e "${RED}unknown service: $svc${NC}"
        return 1
    fi

    if is_running "$container"; then
        echo -e "${GREEN}✓ $container already running${NC}"
    else
        echo -e "${YELLOW}→ starting $svc...${NC}"
        cd "$PROJECT_DIR"
        docker compose up -d "$svc"

        # wait for healthy
        for i in {1..30}; do
            if [ "$(docker inspect -f '{{.State.Health.Status}}' "$container" 2>/dev/null || echo none)" = "healthy" ]; then
                echo -e "${GREEN}✓ $container healthy${NC}"
                break
            fi
            sleep 2
        done
    fi
}

# Default: all services if no args
SERVICES=("$@")
if [ ${#SERVICES[@]} -eq 0 ] || [[ " ${SERVICES[*]} " =~ " all " ]]; then
    SERVICES=(postgres redis mongo qdrant minio n8n)
fi

echo -e "${BLUE}🚀 Starting shared infrastructure services${NC}"
echo ""

for svc in "${SERVICES[@]}"; do
    start_service "$svc"
done

echo ""
echo -e "${BLUE}📊 Final status:${NC}"
cd "$PROJECT_DIR"
docker compose ps
