# Claude Code Skills explained

This repo can be used as plain markdown anywhere, **or** as a set of [Claude Code Skills](https://docs.claude.com/en/docs/claude-code/skills) for users who want auto-invocation. This file explains the difference, so you can decide what to use.

## What is a Skill?

A Claude Code Skill is a markdown file with YAML frontmatter that lives in `.claude/skills/{name}/SKILL.md` (project-scoped) or `~/.claude/skills/{name}/SKILL.md` (user-scoped).

```markdown
---
name: scaffold-fastapi
description: Use when the user wants to scaffold a new FastAPI project with layered architecture, SQLAlchemy 2.0 async, Alembic migrations, pytest, and Docker setup. Triggers on phrases like "new fastapi project", "fastapi scaffold", "set up fastapi backend".
---

# Scaffold FastAPI Project

(instructions here)
```

The `description` field is the **trigger**. Claude Code auto-loads the Skill when the user's message matches the description's intent. You don't have to type the Skill name.

## Skills vs plain markdown

| Concern | Plain markdown | Skill |
|---------|---------------|-------|
| Works in Claude Code | Yes (paste it in) | Yes (auto-invoked) |
| Works in Cursor / Windsurf / ChatGPT | Yes | No |
| Auto-loaded based on intent | No (user has to know to copy it) | Yes (Claude picks it up) |
| Best for | Architecture specs, reference reading | Workflow tasks (scaffold, deploy, test) |
| Discoverability | `ls` and grep | Visible in `/skills` list |

## Why this repo uses both

The content here is split into two shapes:

**Workflow-shaped (Skills are great here):**
- Scaffold a Next.js / FastAPI / NestJS project
- Set up docker-compose + nginx + Let's Encrypt
- Wire up Sentry / Prometheus / Langfuse
- Generate Flutter project with Riverpod or Bloc

**Reference-shaped (Skills add no value, plain markdown wins):**
- Design system spec (1700+ lines of color tokens, motion curves, semantic mapping)
- Library evaluation tables (shadcn vs Mantine vs antd, with reasoning)
- Memory layer architecture (dual-store reasoning, conflict resolution)
- Decision frameworks (when to pick BullMQ vs Celery vs Redis Streams)

Forcing the reference-shaped content into Skills would be:

1. **Wasteful** — Skills are designed to be lazy-loaded; long specs defeat that.
2. **Bad UX** — users *want* to read these, not delegate them.
3. **Lock-in** — anyone not using Claude Code loses access.

## Authoring a good Skill

The trigger is the `description` field. It must:

- Name the **domain** (FastAPI, nginx, Postgres) — exact terms users will use.
- List **trigger phrases** — "scaffold", "set up", "new project", "wire up".
- State the **outcome** — what the Skill produces.

**Bad description:**
> "FastAPI helper"

**Good description:**
> "Use when the user wants to scaffold a new FastAPI project with layered architecture (routes/services/repositories/models), SQLAlchemy 2.0 async, Alembic migrations, pytest test setup, and a Docker dev environment. Triggers on phrases like 'new fastapi project', 'scaffold fastapi backend', 'fastapi with postgres'."

## Progressive disclosure

A Skill's SKILL.md should be **short** (~30 lines) and reference longer guides:

```markdown
---
name: scaffold-fastapi
description: ...
---

# Scaffold FastAPI Project

Follow these steps:

1. Read the full architectural spec at `backend/fastapi/PROMPT.md` for the
   complete project layout, dependencies, and conventions.
2. Confirm with the user: project name, database name, port, whether to
   include Celery from the start.
3. Generate the project per the spec.
4. Run `alembic init` and create the first migration.
5. Verify `pytest` runs (it will report no tests collected — that's fine).
```

The Skill is a dispatcher; the markdown spec is the depth.

## Installing this repo's Skills

```bash
# Option A: project-scoped (skills available only in this project)
cd /path/to/your-project
ln -s /path/to/claudeforge/.claude/skills .claude/skills

# Option B: user-scoped (skills available everywhere)
cp -r /path/to/claudeforge/.claude/skills/* ~/.claude/skills/
```

Confirm with `/skills` in Claude Code — you should see the claudeforge skills listed.

## What Skills cannot do

- **Skills cannot guarantee invocation.** Claude decides based on the description match. If your message is ambiguous, it might not fire.
- **Skills cannot rewrite Claude's tool permissions.** They run inside whatever permission mode you're in.
- **Skills cannot persist state** between sessions. Use memory or files for that.
- **Skills are not hooks.** For deterministic "always run X before Y" behavior, use the `hooks` system in `settings.json`, not a Skill.
