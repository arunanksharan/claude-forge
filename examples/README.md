# Examples — claudeforge guides

> How to chain claudeforge prompts to build real software end-to-end. Not the actual built software — the **playbook for chaining**.

## Files

| File | What it is |
|------|-----------|
| [`end-to-end-saas-app.md`](./end-to-end-saas-app.md) | Walkthrough: building a hypothetical "OrderFlow" SaaS from zero to production, naming each prompt at each step |
| [`end-to-end-ai-agent.md`](./end-to-end-ai-agent.md) | Walkthrough: building a customer-support AI agent (RAG + memory + tool use + evals + prod monitoring) |
| [`end-to-end-mobile-with-backend.md`](./end-to-end-mobile-with-backend.md) | Walkthrough: Flutter app + FastAPI backend + shared deployment pipeline |

## Why these exist

Most "awesome lists" of prompts give you 50 prompts and zero guidance on how to **chain** them. The hard part isn't picking *one* prompt — it's knowing which prompts to apply, in what order, and where to overlap.

These walkthroughs show:
- The **sequence** — which prompt comes first, which depends on which
- The **hand-offs** — what the output of one feeds into the next
- The **decision points** — where you'd diverge depending on requirements
- The **shortcuts** — when you can skip a step
- The **anti-patterns** — places it's tempting to skip and shouldn't

## How to use them

1. Skim the example closest to your project shape
2. Identify the prompts referenced — bookmark them
3. Adapt the sequence to your actual requirements
4. Use the example as a checklist to make sure you don't skip anything important

These are **not implementation guides**. They name the prompts; the prompts themselves contain the implementation guidance.
