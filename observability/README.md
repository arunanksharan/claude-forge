# Observability — claudeforge guides

Production observability patterns for backend services, with concrete instrumentation code.

## Files in this folder

| File | What it is | Read when |
|------|-----------|-----------|
| [`01-signoz-opentelemetry.md`](./01-signoz-opentelemetry.md) | Full OTel + SigNoz setup: tracing, metrics, custom spans, SLIs/SLOs, dashboards, alerts | All-in-one observability with SigNoz |
| `02-prometheus-grafana.md` | *(Phase 5)* Prometheus + Grafana + Tempo stack — the "open" alternative to SigNoz | Self-hosted with cloud-native tooling |
| `03-sentry.md` | *(Phase 5)* Sentry for error tracking, releases, performance — frontend + backend | Error tracking + user-facing apps |
| `04-langfuse.md` | *(Phase 5)* Langfuse for LLM/agent observability — prompts, completions, traces, evals | Building LLM applications |

## Quick decision summary

- **Single tool, all-in-one, low ops:** SigNoz (`01-`)
- **Self-hosted, cloud-native:** Prometheus + Grafana + Tempo (`02-`) — more pieces, more flexibility
- **SaaS, error-focused, frontend + backend:** Sentry (`03-`) — pairs well with either of the above
- **LLM-specific:** Langfuse (`04-`) — *adds to* the above, doesn't replace

You typically want **two**: one for general APM/tracing/metrics (SigNoz *or* Prom+Grafana), and **Sentry** for error tracking. Add **Langfuse** if you have LLM workloads that need prompt/completion-level visibility.
