# Observability with SigNoz + OpenTelemetry

> **Adapted from a production voice-first AI service with strict latency budgets. The OpenTelemetry instrumentation, custom metrics, dashboards, alerts, and trace propagation patterns are real and currently shipping.**
>
> SigNoz is one valid choice — if you prefer Prometheus + Grafana + Tempo, the OpenTelemetry instrumentation code is identical and only the exporter endpoint changes. See companion files in this folder for Sentry and Langfuse.

## Overview

SigNoz provides a unified observability platform with:
- **Distributed Tracing**: Track requests across all services
- **Metrics**: Monitor latency, throughput, and resource usage
- **Logging**: Centralized logs with trace correlation

The example below is for a voice-first system where latency budgets are tight (<200ms for voice retrieval). The same instrumentation works for any FastAPI / Python service.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         OBSERVABILITY ARCHITECTURE                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   INSTRUMENTED SERVICES                                                      │
│   ┌───────────────────┐  ┌───────────────────┐  ┌───────────────────┐       │
│   │ memory-          │  │ graphiti-service  │  │ voice-pipeline    │       │
│   │ service           │  │ (gRPC)            │  │ (Pipecat)         │       │
│   │                   │  │                   │  │                   │       │
│   │ FastAPI + OTEL    │  │ gRPC + OTEL       │  │ Python + OTEL     │       │
│   └─────────┬─────────┘  └─────────┬─────────┘  └─────────┬─────────┘       │
│             │                      │                      │                  │
│             │    Traces/Metrics/Logs (OTLP)               │                  │
│             └──────────────────────┼──────────────────────┘                  │
│                                    ▼                                         │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                    OTEL COLLECTOR (:9007/:9008)                      │   │
│   │                                                                      │   │
│   │  Receivers:     Processors:        Exporters:                        │   │
│   │  - OTLP gRPC    - Batch            - ClickHouse (traces)            │   │
│   │  - OTLP HTTP    - Memory Limiter   - ClickHouse (metrics)           │   │
│   │  - Prometheus   - Resource         - ClickHouse (logs)              │   │
│   │                 - Filter           - Logging (debug)                │   │
│   └───────────────────────────────────────────────────────────────────┬─┘   │
│                                                                       │      │
│                                                                       ▼      │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                         CLICKHOUSE                                   │   │
│   │                    (Time-Series Storage)                             │   │
│   │                                                                      │   │
│   │  Tables:                                                             │   │
│   │  - signoz_traces.signoz_index_v2 (trace spans)                       │   │
│   │  - signoz_metrics.samples_v4 (metrics)                               │   │
│   │  - signoz_logs.logs (log entries)                                    │   │
│   └───────────────────────────────────────────────────────────────────┬─┘   │
│                                                                       │      │
│                                                                       ▼      │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                    SIGNOZ FRONTEND (:9010)                           │   │
│   │                                                                      │   │
│   │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌────────────┐  │   │
│   │  │  Services   │  │   Traces    │  │   Metrics   │  │    Logs    │  │   │
│   │  │  Dashboard  │  │   Explorer  │  │  Dashboard  │  │  Explorer  │  │   │
│   │  └─────────────┘  └─────────────┘  └─────────────┘  └────────────┘  │   │
│   │                                                                      │   │
│   │  ┌─────────────┐  ┌─────────────┐                                   │   │
│   │  │   Alerts    │  │   Custom    │                                   │   │
│   │  │   Manager   │  │ Dashboards  │                                   │   │
│   │  └─────────────┘  └─────────────┘                                   │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Python Instrumentation Setup

### 1. Install Dependencies

```bash
pip install opentelemetry-api \
            opentelemetry-sdk \
            opentelemetry-exporter-otlp-proto-grpc \
            opentelemetry-instrumentation-fastapi \
            opentelemetry-instrumentation-httpx \
            opentelemetry-instrumentation-pymongo \
            opentelemetry-instrumentation-redis \
            opentelemetry-instrumentation-grpc
```

### 2. Initialize OpenTelemetry

Create `app/telemetry.py`:

```python
"""OpenTelemetry instrumentation for Memory Service."""

import os
from opentelemetry import trace, metrics
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.resources import Resource, SERVICE_NAME, SERVICE_VERSION
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import OTLPMetricExporter
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.pymongo import PymongoInstrumentor
from opentelemetry.instrumentation.redis import RedisInstrumentor
from opentelemetry.instrumentation.httpx import HTTPXClientInstrumentor
import structlog

logger = structlog.get_logger(__name__)


def setup_telemetry(app=None):
    """Initialize OpenTelemetry with SigNoz exporter."""

    # Skip if disabled
    if os.getenv("OTEL_ENABLED", "true").lower() != "true":
        logger.info("OpenTelemetry disabled")
        return

    # Resource identifies this service
    resource = Resource.create({
        SERVICE_NAME: os.getenv("OTEL_SERVICE_NAME", "memory-service"),
        SERVICE_VERSION: os.getenv("SERVICE_VERSION", "1.0.0"),
        "deployment.environment": os.getenv("ENV", "development"),
        "service.namespace": "app",
    })

    # OTLP endpoint (SigNoz collector)
    otlp_endpoint = os.getenv(
        "OTEL_EXPORTER_OTLP_ENDPOINT",
        "http://localhost:9007"
    )

    # -------------------------------------------------------------------------
    # TRACING
    # -------------------------------------------------------------------------
    trace_provider = TracerProvider(resource=resource)
    trace_exporter = OTLPSpanExporter(
        endpoint=otlp_endpoint,
        insecure=True,  # Use TLS in production
    )
    trace_provider.add_span_processor(BatchSpanProcessor(trace_exporter))
    trace.set_tracer_provider(trace_provider)

    # -------------------------------------------------------------------------
    # METRICS
    # -------------------------------------------------------------------------
    metric_reader = PeriodicExportingMetricReader(
        OTLPMetricExporter(
            endpoint=otlp_endpoint,
            insecure=True,
        ),
        export_interval_millis=15000,  # Export every 15s
    )
    meter_provider = MeterProvider(
        resource=resource,
        metric_readers=[metric_reader],
    )
    metrics.set_meter_provider(meter_provider)

    # -------------------------------------------------------------------------
    # AUTO-INSTRUMENTATION
    # -------------------------------------------------------------------------
    # FastAPI
    if app:
        FastAPIInstrumentor.instrument_app(app)
        logger.info("FastAPI instrumented")

    # MongoDB
    PymongoInstrumentor().instrument()
    logger.info("PyMongo instrumented")

    # Redis
    RedisInstrumentor().instrument()
    logger.info("Redis instrumented")

    # HTTPX (for outgoing HTTP calls)
    HTTPXClientInstrumentor().instrument()
    logger.info("HTTPX instrumented")

    logger.info(
        "OpenTelemetry initialized",
        endpoint=otlp_endpoint,
        service_name=os.getenv("OTEL_SERVICE_NAME", "memory-service"),
    )


# Global tracer and meter for custom instrumentation
def get_tracer(name: str = __name__):
    return trace.get_tracer(name)


def get_meter(name: str = __name__):
    return metrics.get_meter(name)
```

### 3. Add to FastAPI App

In `app/main.py`:

```python
from fastapi import FastAPI
from app.telemetry import setup_telemetry

app = FastAPI(title="Memory Service")

# Initialize telemetry on startup
@app.on_event("startup")
async def startup():
    setup_telemetry(app)
```

---

## Custom Metrics

### Voice Latency Metrics (Critical)

```python
# app/services/metrics.py

from opentelemetry import metrics
from app.telemetry import get_meter

meter = get_meter("app.memory")

# Histograms for latency tracking
voice_prefetch_latency = meter.create_histogram(
    name="app.voice.prefetch_latency_ms",
    description="Time to prefetch voice context",
    unit="ms",
)

voice_retrieval_latency = meter.create_histogram(
    name="app.voice.retrieval_latency_ms",
    description="Time to retrieve memories for voice",
    unit="ms",
)

graphiti_sync_latency = meter.create_histogram(
    name="app.graphiti.sync_latency_ms",
    description="Time for Graphiti async sync",
    unit="ms",
)

# Counters
memory_operations = meter.create_counter(
    name="app.memory.operations_total",
    description="Total memory operations",
)

graphiti_extractions = meter.create_counter(
    name="app.graphiti.extractions_total",
    description="Total Graphiti entity extractions",
)

# Gauges (via up_down_counter for OTEL compatibility)
active_prefetch_jobs = meter.create_up_down_counter(
    name="app.voice.active_prefetch_jobs",
    description="Currently running prefetch jobs",
)

sync_queue_depth = meter.create_up_down_counter(
    name="app.graphiti.sync_queue_depth",
    description="Items in Graphiti sync queue",
)


# Usage example
def record_voice_prefetch(latency_ms: float, tenant_id: str, success: bool):
    """Record voice prefetch metrics."""
    voice_prefetch_latency.record(
        latency_ms,
        attributes={
            "tenant_id": tenant_id,
            "success": str(success),
        }
    )


def record_memory_operation(operation: str, source: str, tenant_id: str):
    """Record memory operation counter."""
    memory_operations.add(
        1,
        attributes={
            "operation": operation,  # "add", "search", "delete"
            "source": source,        # "mem0", "graphiti", "cache"
            "tenant_id": tenant_id,
        }
    )
```

### Using Custom Spans

```python
# In your service code
from app.telemetry import get_tracer
from opentelemetry import trace

tracer = get_tracer("app.memory.prefetch")


async def prefetch_voice_context(tenant_id: str, user_id: str) -> dict:
    """Prefetch context for voice call with full tracing."""

    with tracer.start_as_current_span("prefetch_voice_context") as span:
        # Add attributes for filtering/analysis
        span.set_attribute("tenant_id", tenant_id)
        span.set_attribute("user_id", user_id)
        span.set_attribute("channel", "voice")

        try:
            # Nested span for Graphiti fetch
            with tracer.start_as_current_span("fetch_graphiti_facts") as graphiti_span:
                facts = await graphiti_client.get_current_facts(user_id)
                graphiti_span.set_attribute("facts_count", len(facts))

            # Nested span for MongoDB fetch
            with tracer.start_as_current_span("fetch_user_profile") as mongo_span:
                profile = await mongodb.get_user_profile(tenant_id, user_id)
                mongo_span.set_attribute("has_profile", profile is not None)

            # Nested span for Redis cache
            with tracer.start_as_current_span("cache_context") as redis_span:
                await redis.cache_prefetch_context(tenant_id, user_id, context)
                redis_span.set_attribute("ttl_seconds", 300)

            span.set_status(trace.Status(trace.StatusCode.OK))
            return context

        except Exception as e:
            span.set_status(trace.Status(trace.StatusCode.ERROR, str(e)))
            span.record_exception(e)
            raise
```

---

## Key SLIs and SLOs

### Service Level Indicators (SLIs)

| SLI | Description | Target |
|-----|-------------|--------|
| `voice_prefetch_p99` | 99th percentile prefetch latency | < 500ms |
| `voice_retrieval_p99` | 99th percentile voice retrieval | < 200ms |
| `graphiti_sync_p99` | 99th percentile sync latency | < 5000ms |
| `error_rate` | % of requests returning 5xx | < 1% |
| `availability` | % of successful health checks | > 99.9% |

### Service Level Objectives (SLOs)

```yaml
# SigNoz SLO Configuration
slos:
  - name: voice-prefetch-latency
    description: Voice prefetch must complete within budget
    indicator:
      type: latency
      metric: app.voice.prefetch_latency_ms
      threshold: 500  # ms
      percentile: 99
    target: 99.5  # % of requests

  - name: voice-retrieval-latency
    description: Voice retrieval must be fast
    indicator:
      type: latency
      metric: app.voice.retrieval_latency_ms
      threshold: 200  # ms
      percentile: 99
    target: 99.9  # % of requests

  - name: memory-service-availability
    description: Memory service must be available
    indicator:
      type: availability
      good_events: http.status_code < 500
      total_events: all requests
    target: 99.9  # %

  - name: graphiti-sync-success
    description: Graphiti sync must succeed
    indicator:
      type: success_rate
      metric: app.graphiti.extractions_total
      success_filter: success=true
    target: 99.0  # %
```

---

## Pre-built Dashboards

### Voice Latency Dashboard

Create in SigNoz UI or via JSON:

```json
{
  "title": "Voice Latency Overview",
  "panels": [
    {
      "title": "Prefetch Latency (p50, p95, p99)",
      "type": "timeseries",
      "query": "histogram_quantile(0.99, sum(rate(app_voice_prefetch_latency_ms_bucket[5m])) by (le))"
    },
    {
      "title": "Retrieval Latency by Tenant",
      "type": "timeseries",
      "query": "histogram_quantile(0.95, sum(rate(app_voice_retrieval_latency_ms_bucket[5m])) by (le, tenant_id))"
    },
    {
      "title": "Prefetch Success Rate",
      "type": "stat",
      "query": "sum(rate(app_voice_prefetch_latency_ms_count{success='true'}[5m])) / sum(rate(app_voice_prefetch_latency_ms_count[5m]))"
    },
    {
      "title": "Active Prefetch Jobs",
      "type": "gauge",
      "query": "app_voice_active_prefetch_jobs"
    }
  ]
}
```

### Memory Operations Dashboard

```json
{
  "title": "Memory Operations",
  "panels": [
    {
      "title": "Operations by Type",
      "type": "piechart",
      "query": "sum(rate(app_memory_operations_total[5m])) by (operation)"
    },
    {
      "title": "Operations by Source",
      "type": "timeseries",
      "query": "sum(rate(app_memory_operations_total[5m])) by (source)"
    },
    {
      "title": "Graphiti Sync Queue Depth",
      "type": "timeseries",
      "query": "app_graphiti_sync_queue_depth"
    },
    {
      "title": "Graphiti Extraction Rate",
      "type": "stat",
      "query": "sum(rate(app_graphiti_extractions_total[5m]))"
    }
  ]
}
```

---

## Alerting Rules

### Critical Alerts

```yaml
# SigNoz Alert Rules
alerts:
  - name: VoicePrefetchLatencyHigh
    description: Voice prefetch p99 latency exceeds 500ms
    query: |
      histogram_quantile(0.99,
        sum(rate(app_voice_prefetch_latency_ms_bucket[5m])) by (le)
      ) > 500
    for: 5m
    severity: critical
    annotations:
      summary: "Voice prefetch latency is degraded"
      runbook: "Check Graphiti service, Neo4j, and network connectivity"

  - name: VoiceRetrievalLatencyHigh
    description: Voice retrieval p99 latency exceeds 200ms
    query: |
      histogram_quantile(0.99,
        sum(rate(app_voice_retrieval_latency_ms_bucket[5m])) by (le)
      ) > 200
    for: 5m
    severity: critical
    annotations:
      summary: "Voice retrieval latency is degraded"
      runbook: "Check Mem0/Qdrant performance and Redis cache"

  - name: GraphitiSyncQueueBacklog
    description: Graphiti sync queue has backlog
    query: app_graphiti_sync_queue_depth > 100
    for: 10m
    severity: warning
    annotations:
      summary: "Graphiti sync queue is backing up"
      runbook: "Check Graphiti service health and Neo4j write performance"

  - name: HighErrorRate
    description: Error rate exceeds 1%
    query: |
      sum(rate(http_requests_total{status=~"5.."}[5m]))
      /
      sum(rate(http_requests_total[5m])) > 0.01
    for: 5m
    severity: critical
    annotations:
      summary: "High error rate detected"
      runbook: "Check service logs and trace errors"
```

---

## Trace Context Propagation

### HTTP Headers

For services calling memory-service:

```python
import httpx
from opentelemetry.propagate import inject

async def call_memory_service(user_id: str, query: str):
    headers = {}
    inject(headers)  # Injects trace context

    async with httpx.AsyncClient() as client:
        response = await client.post(
            "http://memory-service:8000/v1/voice/query",
            headers=headers,
            json={"user_id": user_id, "query": query}
        )
    return response.json()
```

### gRPC Metadata

For Graphiti service calls:

```python
from opentelemetry.propagate import inject

def call_graphiti_service(episode_body: str):
    metadata = []
    carrier = {}
    inject(carrier)

    for key, value in carrier.items():
        metadata.append((key.lower(), value))

    response = graphiti_stub.AddEpisode(
        request,
        metadata=metadata,
    )
    return response
```

---

## Debugging with Traces

### Finding Slow Requests

In SigNoz Traces Explorer:

1. Filter by service: `memory-service`
2. Filter by operation: `POST /v1/voice/prefetch`
3. Sort by duration (descending)
4. Click on slow trace to see span waterfall

### Correlating Logs with Traces

All logs include trace context:

```python
import structlog
from opentelemetry import trace

logger = structlog.get_logger()

def log_with_trace(message: str, **kwargs):
    """Log with trace context for correlation."""
    span = trace.get_current_span()
    ctx = span.get_span_context()

    logger.info(
        message,
        trace_id=format(ctx.trace_id, '032x'),
        span_id=format(ctx.span_id, '016x'),
        **kwargs
    )
```

In SigNoz, click "View Logs" on any trace to see correlated logs.

---

## Accessing SigNoz

| Component | URL | Purpose |
|-----------|-----|---------|
| Frontend | http://localhost:9010 | Main dashboard |
| Query Service | http://localhost:9009 | API for dashboards |
| OTel Collector (gRPC) | localhost:9007 | Send traces/metrics |
| OTel Collector (HTTP) | localhost:9008 | Send traces/metrics |

### First-Time Setup

1. Open http://localhost:9010
2. Go to Settings → Ingestion Keys
3. Verify data is being received
4. Create dashboards for your use case
