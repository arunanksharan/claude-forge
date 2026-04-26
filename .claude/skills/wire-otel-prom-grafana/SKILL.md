---
name: wire-otel-prom-grafana
description: Use when the user wants to add OpenTelemetry instrumentation + Prometheus + Grafana + Tempo + Loki observability to an app. Sets up OTel SDK in the app, OTel Collector pipeline, dashboards, alerts. Triggers on "add observability", "instrument with opentelemetry", "set up prometheus grafana", "add metrics and tracing".
---

# Wire OpenTelemetry + Prometheus + Grafana + Tempo + Loki (claudeforge)

Follow `observability/02-prometheus-grafana.md` (or `01-signoz-opentelemetry.md` if user prefers SigNoz). Steps:

1. **Confirm with user**:
   - Stack: SigNoz (all-in-one) or PG+T+L (modular)?
   - Self-hosted or hosted (Grafana Cloud)?
   - Existing infrastructure?
2. **Set up the observability stack** (if self-hosted):
   - Use the `docker-compose.observability.yml` from `02-prometheus-grafana.md` as the starting point
   - Configure Prometheus, Tempo, Loki, OTel Collector, Grafana with provisioning
3. **Instrument the app**:
   - **Python (FastAPI)**: `opentelemetry-distro` + auto-instrument: `opentelemetry-bootstrap -a install` + `setup_telemetry()` in app startup
   - **Node**: `@opentelemetry/sdk-node` + `auto-instrumentations-node`, `import './telemetry'` first in main.ts
   - Add custom metrics for business KPIs (orders, signups, etc.)
4. **Configure Grafana**:
   - Provision data sources (Prom, Tempo, Loki) via files in `grafana/provisioning/datasources/`
   - Provision starter dashboards (Node Exporter Full, framework-specific dashboards from grafana.com)
   - Set up alert rules in Prometheus + Alertmanager → Slack/PagerDuty
5. **Verify**:
   - App's `/metrics` endpoint reachable from Prometheus
   - Traces appear in Tempo via Grafana's Explore tab
   - Logs in Loki searchable by service
   - One end-to-end trace: HTTP request → DB query span → linked log
6. **Set SLOs**: define `error rate < 1%`, `p99 latency < 500ms` etc. as recording rules + alerts.

Don't put high-cardinality labels (user_id, request_id) on metrics — explodes Prometheus. Use trace attributes for that.
