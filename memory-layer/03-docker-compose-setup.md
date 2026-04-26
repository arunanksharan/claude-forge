# Docker Compose Development Setup (Memory Service Stack)

> **Adapted from a real production memory service. Port allocations starting at 9000 are illustrative — pick whatever range avoids conflicts with your other services.**
>
> This compose file gives you Neo4j (Graphiti), MongoDB, Redis, Qdrant (Mem0), and SigNoz observability all wired up locally. Use it as a starting point for any agent / memory project.

## Overview

This document describes the Docker Compose setup for local development of an AI memory service. It includes all required dependencies with a consistent port convention starting at 9000 (chosen to avoid conflict with common dev ports — adjust freely).

---

## Port Convention

All services use ports starting at 9000 for consistency and to avoid conflicts:

| Port | Service | Protocol | Description |
|------|---------|----------|-------------|
| **9000** | memory-service | HTTP | Main Memory Service API |
| **9001** | Neo4j | HTTP | Browser UI |
| **9002** | Neo4j | Bolt | Database protocol |
| **9003** | MongoDB | TCP | Database |
| **9004** | Redis | TCP | Cache |
| **9005** | Qdrant | HTTP | Vector DB API |
| **9006** | Qdrant | gRPC | Vector DB gRPC |
| **9007** | SigNoz OTel Collector | gRPC | OTLP receiver |
| **9008** | SigNoz OTel Collector | HTTP | OTLP receiver |
| **9009** | SigNoz Query Service | HTTP | Query API |
| **9010** | SigNoz Frontend | HTTP | Observability UI |
| **9011** | Graphiti Service | gRPC | Knowledge Graph processor |

---

## Quick Start

### Prerequisites

- Docker Desktop or Docker Engine + Docker Compose
- OpenAI API key (for embeddings and entity extraction)

### 1. Set Environment Variables

Create a `.env` file in the project root:

```bash
# .env
OPENAI_API_KEY=sk-your-openai-api-key
```

### 2. Start All Services

```bash
# Start all services in background
docker compose -f docker-compose.dev.yml up -d

# View logs
docker compose -f docker-compose.dev.yml logs -f

# View specific service logs
docker compose -f docker-compose.dev.yml logs -f memory-service
```

### 3. Verify Services

```bash
# Check all services are running
docker compose -f docker-compose.dev.yml ps

# Health check endpoints
curl http://localhost:9000/health           # Memory Service
curl http://localhost:9001                  # Neo4j Browser
curl http://localhost:9005/                 # Qdrant
```

### 4. Access UIs

| Service | URL | Credentials |
|---------|-----|-------------|
| Memory Service API Docs | http://localhost:9000/docs | - |
| Neo4j Browser | http://localhost:9001 | neo4j / changeme_dev_password |
| SigNoz Dashboard | http://localhost:9010 | - |
| Qdrant Dashboard | http://localhost:9005/dashboard | - |

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     MEMORY SERVICE - DEV STACK                       │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                    MEMORY-SERVICE (:9000)                    │   │
│   │                          FastAPI + Python                            │   │
│   └───────────────────────────────┬─────────────────────────────────────┘   │
│                                   │                                          │
│     ┌─────────────────────────────┼─────────────────────────────────────┐   │
│     │                             │                                      │   │
│     ▼                             ▼                                      ▼   │
│  ┌──────────┐              ┌──────────┐                            ┌────────┐│
│  │  NEO4J   │              │ MONGODB  │                            │ REDIS  ││
│  │ :9001/02 │              │  :9003   │                            │ :9004  ││
│  │          │              │          │                            │        ││
│  │Knowledge │              │ Users    │                            │ Cache  ││
│  │  Graph   │              │ Episodes │                            │ Queue  ││
│  │(Graphiti)│              │ Memories │                            │Prefetch││
│  └─────▲────┘              └──────────┘                            └────────┘│
│        │                                                                     │
│        │                                                                     │
│  ┌─────┴──────┐         ┌──────────┐                                        │
│  │  GRAPHITI  │         │  QDRANT  │                                        │
│  │  SERVICE   │         │ :9005/06 │                                        │
│  │   :9011    │         │          │                                        │
│  │            │         │ Vector   │                                        │
│  │ Knowledge  │         │ Search   │                                        │
│  │ Extraction │         │ (Mem0)   │                                        │
│  └────────────┘         └──────────┘                                        │
│                                                                              │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                        SIGNOZ OBSERVABILITY                          │   │
│   │                                                                      │   │
│   │   ┌──────────────┐    ┌─────────────┐    ┌──────────────┐           │   │
│   │   │ OTel Collect │    │ClickHouse   │    │  Frontend    │           │   │
│   │   │  :9007/08    │───▶│  (internal) │───▶│   :9010      │           │   │
│   │   │              │    │             │    │              │           │   │
│   │   │ Traces       │    │ Storage     │    │ Dashboards   │           │   │
│   │   │ Metrics      │    │             │    │ Alerts       │           │   │
│   │   │ Logs         │    │             │    │              │           │   │
│   │   └──────────────┘    └─────────────┘    └──────────────┘           │   │
│   │                                                                      │   │
│   │                    Query Service: :9009                              │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Service Details

### Neo4j (Knowledge Graph)

Neo4j stores the Graphiti knowledge graph with temporal relationships.

```bash
# Connect via Cypher shell
docker exec -it neo4j cypher-shell -u neo4j -p changeme_dev_password

# Example query - Get all user nodes
MATCH (u:AppUser) RETURN u LIMIT 10;

# Example query - Get user's facts
MATCH (u:AppUser {unified_user_id: 'usr_123'})-[r]->(n)
WHERE r.invalid_at IS NULL
RETURN u, r, n;
```

**Browser Access:** http://localhost:9001

### MongoDB (Document Store)

MongoDB stores user profiles, episodes, and Mem0-style memories.

```bash
# Connect via mongosh
docker exec -it mongodb mongosh -u app -p changeme_dev_password

# Switch to database
use app_memory

# Example queries
db.unified_users.find({}).limit(5)
db.memories.find({unified_user_id: "usr_123"})
db.episodes.find({}).sort({started_at: -1}).limit(3)
```

**Collections:**
- `unified_users` - Core user identity
- `channel_identities` - Cross-channel identity mapping
- `memories` - Mem0-style memories (mentions + validated facts)
- `episodes` - Conversation sessions
- `user_profiles` - Extended user info
- `avatar_relationships` - User-Avatar relationship state
- `sync_jobs` - Graphiti sync queue
- `audit_log` - PDPA/APPI compliance logging

### Redis (Cache Layer)

Redis provides caching for voice prefetch and Graphiti sync queue.

```bash
# Connect via redis-cli
docker exec -it redis redis-cli

# Example commands
KEYS prefetch:*
GET prefetch:context:sg:usr_123
LRANGE graphiti:sync:queue 0 -1
TTL prefetch:context:sg:usr_123
```

**Key Patterns:**
- `prefetch:context:{tenant}:{user}` - Voice prefetch cache (TTL: 5min)
- `graphiti:sync:queue` - Job queue (FIFO list)
- `graphiti:sync:job:{job_id}` - Job data (TTL: 7 days)
- `mem0:cache:{tenant}:{user}` - Mem0 query cache (TTL: 1min)

### Qdrant (Vector Database)

Qdrant provides vector similarity search for Mem0 integration.

```bash
# Check collections via API
curl http://localhost:9005/collections

# Search example
curl -X POST http://localhost:9005/collections/memories/points/search \
  -H "Content-Type: application/json" \
  -d '{
    "vector": [0.1, 0.2, ...],
    "limit": 5,
    "filter": {
      "must": [
        {"key": "tenant_id", "match": {"value": "sg"}},
        {"key": "unified_user_id", "match": {"value": "usr_123"}}
      ]
    }
  }'
```

**Dashboard:** http://localhost:9005/dashboard

### SigNoz (Observability)

SigNoz provides distributed tracing, metrics, and logging with an OpenTelemetry-native approach.

**Dashboard:** http://localhost:9010

**Key Features:**
- Distributed traces across all services
- Latency percentiles (p50, p95, p99)
- Error rate monitoring
- Custom dashboards for voice latency
- Log aggregation with trace correlation

**Instrumenting Your Code:**

```python
# Python instrumentation
from opentelemetry import trace
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter

# Auto-instrument FastAPI
FastAPIInstrumentor.instrument_app(app)

# Custom spans
tracer = trace.get_tracer(__name__)
with tracer.start_as_current_span("prefetch_context") as span:
    span.set_attribute("user_id", user_id)
    span.set_attribute("latency_ms", latency)
    # ... your code
```

---

## Common Operations

### Start/Stop Services

```bash
# Start all
docker compose -f docker-compose.dev.yml up -d

# Stop all
docker compose -f docker-compose.dev.yml down

# Restart specific service
docker compose -f docker-compose.dev.yml restart memory-service

# View logs
docker compose -f docker-compose.dev.yml logs -f [service_name]
```

### Reset Data

```bash
# Remove all data (destructive!)
docker compose -f docker-compose.dev.yml down -v

# Reset specific service data
docker volume rm neo4j-data
docker volume rm mongodb-data
docker volume rm qdrant-data
```

### Debug a Service

```bash
# Shell into container
docker exec -it memory-service bash

# Check container logs
docker logs memory-service --tail 100

# Monitor resource usage
docker stats
```

### Update Services

```bash
# Pull latest images
docker compose -f docker-compose.dev.yml pull

# Rebuild custom images
docker compose -f docker-compose.dev.yml build --no-cache memory-service

# Update and restart
docker compose -f docker-compose.dev.yml up -d --build
```

---

## Environment Variables Reference

### memory-service

| Variable | Description | Default |
|----------|-------------|---------|
| `MONGODB_URI` | MongoDB connection string | mongodb://... |
| `MONGODB_DATABASE` | Database name | app_memory |
| `REDIS_URL` | Redis connection string | redis://redis:6379/0 |
| `QDRANT_HOST` | Qdrant hostname | qdrant |
| `QDRANT_PORT` | Qdrant HTTP port | 6333 |
| `NEO4J_URI` | Neo4j Bolt URI | bolt://neo4j:7687 |
| `NEO4J_USER` | Neo4j username | neo4j |
| `NEO4J_PASSWORD` | Neo4j password | changeme_dev_password |
| `GRAPHITI_SERVICE_URL` | Graphiti gRPC URL | graphiti-service:50051 |
| `OPENAI_API_KEY` | OpenAI API key | (required) |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | OTel collector endpoint | http://signoz-otel-collector:4317 |
| `LOG_LEVEL` | Logging level | DEBUG |
| `ENV` | Environment name | development |

---

## Troubleshooting

### Service Won't Start

```bash
# Check logs
docker compose -f docker-compose.dev.yml logs [service_name]

# Check health
docker compose -f docker-compose.dev.yml ps

# Verify dependencies are healthy
docker inspect mongodb | jq '.[0].State.Health'
```

### Connection Issues

```bash
# Test network connectivity
docker exec memory-service ping mongodb

# Check DNS resolution
docker exec memory-service nslookup mongodb

# Verify ports are exposed
docker port memory-service
```

### Memory Issues

```bash
# Check resource usage
docker stats

# Increase memory limits in docker-compose.dev.yml
services:
  memory-service:
    deploy:
      resources:
        limits:
          memory: 2G
```

### Neo4j Issues

```bash
# Check Neo4j logs
docker logs neo4j

# Reset Neo4j completely
docker compose -f docker-compose.dev.yml rm -f neo4j
docker volume rm neo4j-data neo4j-logs
docker compose -f docker-compose.dev.yml up -d neo4j
```

---

## Integration with VoiceApp

VoiceApp (voice pipeline) connects to memory-service via HTTP. Configure VoiceApp's environment:

```bash
# VoiceApp .env
MEMORY_SERVICE_URL=http://localhost:9000
MEMORY_SERVICE_TIMEOUT_MS=500  # Voice latency budget
```

For Docker-to-Docker communication (when VoiceApp is also containerized):

```bash
# Use Docker network name
MEMORY_SERVICE_URL=http://memory-service:8000
```

---

## Production Considerations

This development setup is **NOT** production-ready. For production:

1. **Neo4j**: Use Neo4j Aura or a managed Neo4j cluster
2. **MongoDB**: Use MongoDB Atlas or a replica set
3. **Redis**: Use Redis Cluster or managed Redis
4. **Qdrant**: Use Qdrant Cloud or a distributed setup
5. **SigNoz**: Deploy to Kubernetes with proper ClickHouse clustering
6. **Secrets**: Use a proper secrets manager (Vault, AWS Secrets Manager)
7. **TLS**: Enable TLS for all connections
8. **Backups**: Implement automated backup strategies
