# Prompt engineering philosophy

Why these prompts are long, opinionated, and structured the way they are.

## 1. Opinions beat options

A prompt that says "you can use Postgres or MySQL or SQLite" forces the LLM to either pick arbitrarily or pause and ask. A prompt that says **"use Postgres 16, with `asyncpg` driver, and SQLAlchemy 2.0 async sessions, because [reasons]"** lets the model just *go*.

Opinions are reversible. If you want SQLite, override the prompt. But the prompt should default to one thing.

## 2. Negative space matters

Half the value of these prompts is the **"do not use"** sections. LLMs trained on the public internet know about Formik, Material UI, antd, react-icons, Lerna, Nodemon. If you don't actively reject them, the model will quietly suggest them. Listing rejected libraries with reasoning prevents drift.

## 3. Layered architecture, always

Every backend prompt enforces:

```
routes / controllers   ← thin, only HTTP concerns
services               ← business logic, framework-agnostic
repositories           ← data access only, swap-able
models / schemas       ← shape of data
```

This isn't dogma. It's that LLMs given a flat structure produce flat code that becomes unmaintainable at ~5000 LOC. Forcing a layered scaffold up front makes the codebase still navigable at 50,000 LOC.

## 4. File trees up front

Every framework prompt opens with a directory tree. Claude (and any LLM) generates more consistent code when it can "see" where each file belongs before writing the first line.

## 5. Decision tables, not prose

Tradeoff tables are scannable, copy-pasteable, and force you to articulate the comparison axis. Prose hides the comparison.

## 6. Placeholders, not real values

`{{project-name}}` not `myproject`. The instant a placeholder looks like a real value, users (and LLMs) start treating it as canonical and forget to substitute. Double braces are visually loud — they jump out as something to fill in.

## 7. The "PROMPT.md vs guides" split

Each framework folder has:

- **`PROMPT.md`** — the *single* file you paste into an LLM. Self-contained, references the rest by file path.
- **`01-foo.md`, `02-bar.md`, ...** — deeper guides on individual concerns. Read by humans, optionally referenced by the prompt.

This split means: humans can browse, but you also have a single artifact to feed an LLM in one shot.

## 8. Sanitization is a feature

Every guide has been stripped of company / project / personal identifiers. This isn't just legal hygiene — it's a forcing function for **generality**. If your "prompt" only works for your specific project, it's not a prompt, it's documentation. Templating it forces you to identify what's truly reusable vs what's project-specific.

## 9. Don't outsource judgment

These prompts make decisions *for* you so you don't have to think about them every time. But they don't make decisions *for* the model. The model still has to understand your specific project, ask clarifying questions, and adapt. The prompt is a *bias*, not a *script*.

## 10. Re-evaluate quarterly

Library ecosystems shift. shadcn/ui is the right answer in 2025–2026; it might not be in 2028. Each guide ends with a `*Last evaluated: YYYY-MM-DD*` line. If you're reading something more than a year stale, double-check before building on it.
