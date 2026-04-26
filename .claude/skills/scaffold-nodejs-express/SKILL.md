---
name: scaffold-nodejs-express
description: Use when the user wants to scaffold a new Node.js + Express project with the claudeforge factory-function wiring (no DI container), Drizzle ORM, zod validation, hand-rolled JWT auth (no Passport), BullMQ workers as separate processes, Vitest + Supertest e2e against real Postgres, pino logging, OpenTelemetry. Triggers on "new express project", "scaffold node express", "express backend", "express with drizzle".
---

# Scaffold Node + Express Project (claudeforge)

Follow the master prompt at `backend/nodejs-express/PROMPT.md`. Steps:

1. **Confirm parameters**: `project_name`, `project_slug` (kebab-case), `db_name`, `api_port`, ORM choice (default Drizzle), include flags for BullMQ / auth / OTel.
2. **Read** `backend/nodejs-express/PROMPT.md` — directory tree, deps, key files (package.json, env, app.ts, server.ts, routes.ts, error handler, lib/errors, async-handler, factory pattern for users module).
3. **Read deep-dives** as needed:
   - `01-project-layout.md` — factory function pattern, no DI container
   - `02-drizzle-and-migrations.md` — schema + queries
   - `03-validation-with-zod.md`
   - `04-auth-jwt.md` (if include_auth) — hand-rolled, no Passport
   - `05-bullmq-workers.md` (if include_bullmq)
   - `06-testing-vitest-supertest.md`
4. **Generate**: scaffold tree, `package.json` with locked deps, db client + schema, app factory, server bootstrap with graceful shutdown, Users module (factory functions: repository → service → controller → router), error handler, auth middleware if requested, BullMQ workers if requested.
5. **Verify**: `pnpm install`, `pnpm db:generate && pnpm db:migrate`, `pnpm test`, `pnpm lint` — clean.
6. **Hand off**: setup steps.

Enforce the factory pattern strictly — no top-level singletons, no DI containers, no `utils/` junk drawer.
