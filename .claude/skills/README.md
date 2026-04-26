# claudeforge — Claude Code Skills

> *Phase 1+ — populated as workflow guides land.* Each Skill here is a thin auto-invocation wrapper around a longer markdown guide elsewhere in the repo.

## How to install

```bash
# Project-scoped
ln -s /path/to/claudeforge/.claude/skills /path/to/your-project/.claude/skills

# User-scoped (available everywhere)
cp -r /path/to/claudeforge/.claude/skills/* ~/.claude/skills/
```

## Planned skills

| Skill | Triggers on |
|-------|-------------|
| `scaffold-fastapi` | "new fastapi project", "scaffold fastapi", "fastapi backend" |
| `scaffold-nextjs` | "new nextjs project", "scaffold nextjs", "next.js app" |
| `scaffold-nestjs` | "new nestjs project", "scaffold nest" |
| `scaffold-flutter-riverpod` | "new flutter project with riverpod" |
| `scaffold-flutter-bloc` | "new flutter project with bloc" |
| `deploy-docker-nginx-ssl` | "deploy to vps", "set up nginx + ssl", "lets encrypt" |
| `wire-sentry` | "add sentry", "set up error tracking" |
| `wire-otel-signoz` | "add observability", "instrument with opentelemetry" |
| `wire-langfuse` | "add llm observability", "set up langfuse" |
| `setup-bullmq` | "add background jobs to nest" |
| `setup-celery` | "add background jobs to fastapi" |

See `meta/claude-code-skills-explained.md` for what Skills can/can't do and how to author your own.
