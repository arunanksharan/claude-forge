# Prometheus + Grafana + Tempo

> The "open" observability stack — Prometheus for metrics, Grafana for dashboards/alerts, Tempo for traces, Loki for logs. SigNoz alternative when you want self-hosted, cloud-native, modular tooling.

## Why this stack (vs SigNoz / vs SaaS)

| Stack | Pros | Cons |
|-------|------|------|
| **Prom + Grafana + Tempo + Loki** (this guide) | Modular, decompose-able, well-known, rich ecosystem | More moving pieces; you build it |
| **SigNoz** (`01-signoz-opentelemetry.md`) | Single bundled product, OTel-native, easier to start | Younger, narrower ecosystem |
| **Datadog / New Relic / Honeycomb (SaaS)** | Zero ops | Pricey at scale, vendor lock-in |
| **Elastic Stack (ELK)** | Powerful logs | Java-heavy, expensive to operate |

For self-hosted at small/medium scale: **Prom + Grafana** is the safe pick. For all-in-one with less ops: **SigNoz**. For "just make it work and pay": **Datadog**.

## What does what

| Tool | Role |
|------|------|
| **Prometheus** | Pulls metrics from your apps (HTTP `/metrics`); stores them as time-series |
| **Grafana** | Dashboards, alerts, plug all the data sources together |
| **Tempo** | Trace storage backend (OpenTelemetry-compatible) |
| **Loki** | Log aggregation (Prometheus's log sibling) |
| **OpenTelemetry Collector** | Pipeline that receives OTLP from your apps, exports to Tempo/Prom/Loki |
| **Alertmanager** | Routes alerts to Slack, PagerDuty, etc. |

## Docker Compose (local dev)

```yaml
# docker-compose.observability.yml
services:
  prometheus:
    image: prom/prometheus:latest
    ports: ["9090:9090"]
    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus-data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.retention.time=15d'
      - '--web.enable-remote-write-receiver'

  grafana:
    image: grafana/grafana:latest
    ports: ["3001:3000"]
    volumes:
      - ./grafana/provisioning:/etc/grafana/provisioning:ro
      - grafana-data:/var/lib/grafana
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=changeme
      - GF_USERS_ALLOW_SIGN_UP=false
    depends_on: [prometheus, tempo, loki]

  tempo:
    image: grafana/tempo:latest
    ports:
      - "3200:3200"        # tempo HTTP
      - "4317:4317"        # OTLP gRPC
      - "4318:4318"        # OTLP HTTP
    volumes:
      - ./tempo/tempo.yaml:/etc/tempo.yaml:ro
      - tempo-data:/var/tempo
    command: ["-config.file=/etc/tempo.yaml"]

  loki:
    image: grafana/loki:latest
    ports: ["3100:3100"]
    volumes:
      - ./loki/loki.yaml:/etc/loki/local-config.yaml:ro
      - loki-data:/loki
    command: ["-config.file=/etc/loki/local-config.yaml"]

  otel-collector:
    image: otel/opentelemetry-collector-contrib:latest
    ports:
      - "4317"             # gRPC (internal)
      - "4318"             # HTTP (internal)
    volumes:
      - ./otel/config.yaml:/etc/otelcol-contrib/config.yaml:ro
    command: ["--config=/etc/otelcol-contrib/config.yaml"]
    depends_on: [prometheus, tempo, loki]

volumes:
  prometheus-data:
  grafana-data:
  tempo-data:
  loki-data:
```

### `prometheus/prometheus.yml`

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'self'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'app'
    static_configs:
      - targets: ['host.docker.internal:8000']      # macOS/Win — use host network on Linux
    metrics_path: '/metrics'

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']
```

### `tempo/tempo.yaml`

```yaml
server:
  http_listen_port: 3200

distributor:
  receivers:
    otlp:
      protocols:
        grpc: {}
        http: {}

ingester:
  trace_idle_period: 10s
  max_block_duration: 5m

storage:
  trace:
    backend: local
    local:
      path: /var/tempo/blocks
    wal:
      path: /var/tempo/wal
```

### `otel/config.yaml`

```yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

processors:
  batch:
    timeout: 10s
    send_batch_size: 1024
  memory_limiter:
    check_interval: 1s
    limit_percentage: 80

exporters:
  otlp/tempo:
    endpoint: tempo:4317
    tls: { insecure: true }
  prometheusremotewrite:
    endpoint: http://prometheus:9090/api/v1/write
    tls: { insecure: true }
  loki:
    endpoint: http://loki:3100/loki/api/v1/push

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [memory_limiter, batch]
      exporters: [otlp/tempo]
    metrics:
      receivers: [otlp]
      processors: [memory_limiter, batch]
      exporters: [prometheusremotewrite]
    logs:
      receivers: [otlp]
      processors: [memory_limiter, batch]
      exporters: [loki]
```

## App-side instrumentation

### Python (FastAPI)

```bash
uv add opentelemetry-distro opentelemetry-exporter-otlp opentelemetry-instrumentation-fastapi
opentelemetry-bootstrap -a install
```

```python
# src/{{project-slug}}/telemetry.py
import os
from opentelemetry import trace, metrics
from opentelemetry.sdk.resources import Resource, SERVICE_NAME
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import OTLPMetricExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.sqlalchemy import SQLAlchemyInstrumentor
from opentelemetry.instrumentation.redis import RedisInstrumentor
from opentelemetry.instrumentation.httpx import HTTPXClientInstrumentor


def setup_telemetry(app, settings):
    resource = Resource.create({
        SERVICE_NAME: settings.otel_service_name,
        "deployment.environment": settings.env,
    })
    endpoint = settings.otel_endpoint           # http://otel-collector:4317

    # tracing
    trace_provider = TracerProvider(resource=resource)
    trace_provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter(endpoint=endpoint, insecure=True)))
    trace.set_tracer_provider(trace_provider)

    # metrics
    reader = PeriodicExportingMetricReader(
        OTLPMetricExporter(endpoint=endpoint, insecure=True),
        export_interval_millis=15000,
    )
    metrics.set_meter_provider(MeterProvider(resource=resource, metric_readers=[reader]))

    FastAPIInstrumentor.instrument_app(app)
    SQLAlchemyInstrumentor().instrument()
    RedisInstrumentor().instrument()
    HTTPXClientInstrumentor().instrument()
```

For Prometheus-style `/metrics` endpoint (in addition to OTLP push):

```bash
uv add prometheus-fastapi-instrumentator
```

```python
from prometheus_fastapi_instrumentator import Instrumentator

Instrumentator().instrument(app).expose(app, endpoint="/metrics")
```

Now Prometheus can scrape `/metrics` directly.

### Node (Nest / Express)

```bash
pnpm add @opentelemetry/api @opentelemetry/sdk-node @opentelemetry/auto-instrumentations-node @opentelemetry/exporter-trace-otlp-grpc @opentelemetry/exporter-metrics-otlp-grpc
```

```typescript
// src/telemetry.ts — import this FIRST in main.ts
import { NodeSDK } from '@opentelemetry/sdk-node';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-grpc';
import { OTLPMetricExporter } from '@opentelemetry/exporter-metrics-otlp-grpc';
import { PeriodicExportingMetricReader } from '@opentelemetry/sdk-metrics';
import { getNodeAutoInstrumentations } from '@opentelemetry/auto-instrumentations-node';
import { Resource } from '@opentelemetry/resources';
import { SemanticResourceAttributes } from '@opentelemetry/semantic-conventions';

const sdk = new NodeSDK({
  resource: new Resource({
    [SemanticResourceAttributes.SERVICE_NAME]: process.env.OTEL_SERVICE_NAME ?? 'app',
    [SemanticResourceAttributes.DEPLOYMENT_ENVIRONMENT]: process.env.NODE_ENV ?? 'dev',
  }),
  traceExporter: new OTLPTraceExporter({ url: process.env.OTEL_ENDPOINT ?? 'http://localhost:4317' }),
  metricReader: new PeriodicExportingMetricReader({
    exporter: new OTLPMetricExporter({ url: process.env.OTEL_ENDPOINT ?? 'http://localhost:4317' }),
    exportIntervalMillis: 15000,
  }),
  instrumentations: [getNodeAutoInstrumentations({
    '@opentelemetry/instrumentation-fs': { enabled: false },     // noisy
  })],
});

sdk.start();
process.on('SIGTERM', () => sdk.shutdown().catch(console.error));
```

```typescript
// src/main.ts
import './telemetry';   // MUST be first import
import { NestFactory } from '@nestjs/core';
// ...
```

For Prometheus `/metrics` endpoint:

```bash
pnpm add prom-client
```

Use `@willsoto/nestjs-prometheus` (Nest) or expose manually in Express:

```typescript
import client from 'prom-client';
client.collectDefaultMetrics();

app.get('/metrics', async (_req, res) => {
  res.set('Content-Type', client.register.contentType);
  res.end(await client.register.metrics());
});
```

## Custom metrics

```python
# Python
from opentelemetry import metrics
meter = metrics.get_meter("app")

orders_counter = meter.create_counter("orders.created", unit="1", description="orders created")
order_total = meter.create_histogram("orders.total_cents", unit="cents")

orders_counter.add(1, {"status": "paid", "tenant": tenant_id})
order_total.record(order.total_cents, {"tenant": tenant_id})
```

```typescript
// Node
import { metrics } from '@opentelemetry/api';
const meter = metrics.getMeter('app');

const ordersCounter = meter.createCounter('orders.created');
const orderTotal = meter.createHistogram('orders.total_cents');

ordersCounter.add(1, { status: 'paid', tenant: tenantId });
orderTotal.record(order.totalCents, { tenant: tenantId });
```

## Grafana dashboards

Provision dashboards from JSON (so they're version-controlled):

```yaml
# grafana/provisioning/dashboards/default.yaml
apiVersion: 1
providers:
  - name: 'default'
    folder: ''
    type: file
    options:
      path: /etc/grafana/provisioning/dashboards
```

Drop dashboard JSONs into `grafana/provisioning/dashboards/`. They auto-load on startup.

For data sources:

```yaml
# grafana/provisioning/datasources/default.yaml
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    url: http://prometheus:9090
    isDefault: true
  - name: Tempo
    type: tempo
    url: http://tempo:3200
  - name: Loki
    type: loki
    url: http://loki:3100
```

### Useful starter dashboards

- **Node Exporter Full** (#1860 on grafana.com) — host metrics
- **OpenTelemetry Collector** dashboard
- **PostgreSQL** (#9628)
- **Redis** (#763)

Browse https://grafana.com/grafana/dashboards/ — most popular software has community dashboards.

## SLOs

Define SLOs in code (sloth, openslo) or visually in Grafana. Example: 99.9% requests under 500ms.

```promql
# error budget burn (1h)
1 - (
  sum(rate(http_requests_total{status!~"5.."}[1h]))
  /
  sum(rate(http_requests_total[1h]))
)
```

## Alerting

Alertmanager routes alerts (defined in Prometheus rules) to Slack, PagerDuty, email.

```yaml
# prometheus/rules/app.yml
groups:
  - name: app
    rules:
      - alert: HighErrorRate
        expr: |
          sum(rate(http_requests_total{status=~"5.."}[5m]))
          /
          sum(rate(http_requests_total[5m])) > 0.01
        for: 5m
        labels: { severity: critical }
        annotations:
          summary: "5xx error rate >1% on {{ $labels.service }}"

      - alert: HighLatencyP99
        expr: |
          histogram_quantile(0.99,
            sum(rate(http_server_duration_seconds_bucket[5m])) by (le)
          ) > 1.0
        for: 10m
        labels: { severity: warning }
        annotations:
          summary: "p99 latency > 1s"
```

## Logs — Loki

Ship logs from your app via the OTel collector (above) or via **Promtail** (a Loki-specific shipper that tails files).

For Docker logs, configure the loki driver:

```yaml
services:
  api:
    logging:
      driver: loki
      options:
        loki-url: "http://loki:3100/loki/api/v1/push"
        loki-batch-size: "400"
```

Query in Grafana:

```logql
{container="api"} |~ "ERROR|WARN"
```

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| Prometheus can't scrape `/metrics` | Network: from container, `localhost:8000` is the container itself — use service name or `host.docker.internal` |
| Cardinality explosion | Don't put high-cardinality values (user IDs, request IDs) in metric labels |
| Tempo storage fills | Set retention; Tempo doesn't auto-trim |
| Loki ingestion rate-limited | Tune `loki.yaml` limits; or batch logs |
| OTel collector OOM | `memory_limiter` processor + queue limits on exporters |
| `prometheus_fastapi_instrumentator` slow | It records per-request — already includes labels; don't add more |
| Grafana queries slow | Pre-aggregate via recording rules in Prometheus |
| OTLP gRPC fails behind a proxy | Use OTLP HTTP endpoint instead (port 4318) |
| Trace not linked to log | Both must include `trace_id` — most OTel SDKs do this automatically |
| Service map empty | Spans need `service.name` resource attribute set |

## Production hosting

Self-hosted at small scale: Docker Compose on a beefy VPS (8GB RAM minimum for the full stack).

At larger scale:
- **Prometheus**: federated, with **Thanos** or **Mimir** for long-term storage + multi-tenancy
- **Tempo**: object-storage backend (S3-compatible) for cheap retention
- **Loki**: same — object-storage for long retention
- **Grafana Cloud** / **Aiven Grafana** if you want managed

The same instrumentation works regardless — only the backend changes.
