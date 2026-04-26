# Contributing to claudeforge

Thanks for considering a contribution. This repo is intentionally opinionated — it's not "every framework, every option," it's "the choices we'd make on a real production system, with the reasoning."

## Quality bar

A guide is ready to merge when it has:

1. **A decision table at the top** — what to use, what to skip, what's conditional.
2. **The "why"** — bundle size, performance, ecosystem health, ergonomics, lock-in risk. Saying *no* requires more justification than saying *yes*.
3. **A copy-paste-ready prompt** in `PROMPT.md` for the framework, with `{{placeholders}}` for project-specific values.
4. **Realistic file layout** — show the directory tree, not just snippets.
5. **A "do not use" list** — name competitors and explain the rejection.

## What to contribute

- New framework guides (Phoenix LiveView, Rails 8, Spring Boot, Go + Fiber, etc.)
- New deployment targets (Fly.io, Railway, Hetzner, bare-metal)
- Variants of existing guides (e.g. FastAPI + SQLModel, FastAPI + Beanie/MongoDB)
- Real-world battle stories — bugs that would have been caught by these patterns

## What NOT to contribute

- Toy examples
- "Here's how to do X in 5 frameworks" — pick one and go deep
- Library lists without evaluation
- AI-generated content that hasn't been touched by a human who shipped the framework

## Sanitization checklist (when migrating from your own private repos)

- [ ] No personal names, emails, SSH key paths
- [ ] No company-specific project names — use `{{placeholders}}` or generic names like `myapp`
- [ ] No internal URLs, internal port allocations (use them as *example* with a note)
- [ ] No credentials, even fake-looking ones (`changeme`, `xxx`, etc.)
- [ ] No proprietary architecture details that would expose business logic
- [ ] Keep opinionated stack choices — that's the value

## Style

- Markdown, GFM tables, fenced code blocks with language hints
- Short paragraphs. Lots of tables. Decision-first, prose second.
- No emoji unless you're labeling status (`[ ]`, `[x]`).
- Headings: `#` for title, `##` for major sections, `###` for subsections. Don't go deeper than `####`.

## Adding a Skill wrapper

If your guide is a workflow (scaffolding, deployment, setup), add a Claude Code Skill at `.claude/skills/{name}/SKILL.md`. The Skill should be **short** (~30 lines) and reference the longer guide. See existing skills for the pattern.
