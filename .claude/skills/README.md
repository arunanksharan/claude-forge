# claudeforge — Claude Code Skills

Each Skill here is a thin auto-invocation wrapper around a longer markdown guide elsewhere in the repo. Skills are useful for **workflow-shaped** tasks (scaffolding, deployment, wiring an integration). For **reference-shaped** content (design system spec, library evaluations, decision matrices), the markdown guides are better — read them directly.

## How to install

```bash
# Project-scoped
ln -s /path/to/claudeforge/.claude/skills /path/to/your-project/.claude/skills

# User-scoped (available everywhere)
cp -r /path/to/claudeforge/.claude/skills/* ~/.claude/skills/
```

## Available skills

| Skill | Triggers on |
|-------|-------------|
| [`scaffold-fastapi`](./scaffold-fastapi/SKILL.md) | "new fastapi project", "scaffold fastapi", "fastapi backend" |
| [`scaffold-nestjs`](./scaffold-nestjs/SKILL.md) | "new nestjs project", "scaffold nest", "nestjs backend" |
| [`scaffold-nodejs-express`](./scaffold-nodejs-express/SKILL.md) | "new express project", "scaffold node express", "express backend" |
| [`scaffold-nextjs`](./scaffold-nextjs/SKILL.md) | "new nextjs project", "scaffold next.js", "next 15 app" |
| [`scaffold-flutter-riverpod`](./scaffold-flutter-riverpod/SKILL.md) | "new flutter project with riverpod", "flutter app" |
| [`scaffold-flutter-bloc`](./scaffold-flutter-bloc/SKILL.md) | "new flutter project with bloc", "flutter cubit" |
| [`scaffold-react-native`](./scaffold-react-native/SKILL.md) | "new react native project", "new expo project", "scaffold rn app" |
| [`scaffold-angular`](./scaffold-angular/SKILL.md) | "new angular project", "scaffold angular", "angular 18 app" |
| [`deploy-vps-bootstrap`](./deploy-vps-bootstrap/SKILL.md) | "set up new vps", "bootstrap server", "harden ubuntu server" |
| [`deploy-docker-nginx-ssl`](./deploy-docker-nginx-ssl/SKILL.md) | "deploy to vps", "set up nginx + ssl", "lets encrypt" |
| [`wire-sentry`](./wire-sentry/SKILL.md) | "add sentry", "set up error tracking" |
| [`wire-otel-prom-grafana`](./wire-otel-prom-grafana/SKILL.md) | "add observability", "instrument with opentelemetry" |
| [`wire-langfuse`](./wire-langfuse/SKILL.md) | "add llm observability", "trace prompts" |
| [`setup-celery`](./setup-celery/SKILL.md) | "add celery", "set up background jobs python" |
| [`setup-bullmq`](./setup-bullmq/SKILL.md) | "add background jobs", "add bullmq" |
| [`setup-redis-streams`](./setup-redis-streams/SKILL.md) | "redis streams", "cross-service events" |

See `meta/claude-code-skills-explained.md` for what Skills can/can't do and how to author your own.
