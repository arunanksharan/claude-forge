# How to use these prompts

Three usage modes, in increasing order of automation.

## 1. Copy-paste (works anywhere)

The lowest-friction path. Open the relevant `PROMPT.md`, copy the contents into your LLM session (Claude Code, Cursor, Windsurf, ChatGPT, Aider — anything), and tell the model what `{{placeholders}}` mean.

**Example flow:**

```
You: <paste backend/fastapi/PROMPT.md>

Now scaffold this for project "{{project-name}}" = "orderflow",
using PostgreSQL with database "{{db-name}}" = "orderflow_dev".
Skip the Celery section — I'll add async later.
```

You don't need Claude Code to use this repo. That's intentional.

## 2. Reference reading (architecture specs)

Some files in this repo are not prompts — they're architecture specs you read *before* and *during* implementation. Examples:

- `frontend/nextjs/02-design-system-spec.md` — read once, refer back when adding a new component.
- `memory-layer/dual-memory-architecture.md` — read before designing your AI agent's memory.
- `observability/signoz-or-grafana.md` — read when picking your observability stack.

These won't fit cleanly into a single prompt. Treat them like a senior engineer's notes.

## 3. Claude Code Skills (auto-invocation)

For workflow-shaped prompts (scaffolding, deployment, SSL setup), the repo ships Skill wrappers in `.claude/skills/`. To use them:

```bash
# Project-scoped: skills available only inside one project
ln -s /path/to/claudeforge/.claude/skills /path/to/your-project/.claude/skills

# Or user-scoped: skills available everywhere
cp -r /path/to/claudeforge/.claude/skills/* ~/.claude/skills/
```

Then, in Claude Code, just describe your intent in natural language:

> "Set up a FastAPI project with the layered architecture I usually use."

Claude inspects available Skill descriptions, picks the matching one, and follows its instructions. You don't have to remember the Skill name.

See `meta/claude-code-skills-explained.md` for what Skills can and can't do.

## Picking the right starting point

| Goal | Start at |
|------|----------|
| New web app, full-stack | `frontend/nextjs/PROMPT.md` + `backend/fastapi/PROMPT.md` |
| Just an API | Pick one of `backend/{fastapi,nestjs,nodejs-express}/PROMPT.md` |
| Mobile app | `mobile/{flutter-riverpod,flutter-bloc,react-native}/PROMPT.md` |
| Deploying to a VPS | `deployment/per-framework/deploy-{framework}.md` |
| Adding background jobs | `async-and-queues/{celery,bullmq,redis-streams}.md` |
| Adding monitoring | `observability/{sentry,prometheus-grafana,langfuse}.md` |
| AI agent memory | `memory-layer/dual-memory-architecture.md` |

## When the prompts disagree with you

These are opinions. If your project genuinely needs Material UI, or a different ORM, or Bun instead of Node — override the prompt. The decision tables exist so you can disagree with full information, not so you have to follow them.

The `## Tradeoffs / when not to use this` section at the bottom of each guide is the negotiating room.
