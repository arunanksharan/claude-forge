---
name: scaffold-nestjs
description: Use when the user wants to scaffold a new NestJS project with the claudeforge modular feature folders + DI architecture, Prisma ORM (default) or Drizzle, class-validator DTOs, JWT/Passport auth with global guard, BullMQ for queues, Jest + Supertest e2e against real Postgres, pino logging, OpenTelemetry. Triggers on "new nestjs project", "scaffold nest", "nestjs backend", "nest with prisma".
---

# Scaffold NestJS Project (claudeforge)

Follow the master prompt at `backend/nestjs/PROMPT.md`. Steps:

1. **Confirm parameters**: `project_name`, `project_slug` (kebab-case), `db_name`, `api_port`, ORM choice (default Prisma), include flags for BullMQ / auth / OTel.
2. **Read** `backend/nestjs/PROMPT.md` — full directory tree, deps, key files (package.json, env schema, app.module, prisma service, users module).
3. **Read deep-dives** as needed:
   - `01-project-layout.md` — module structure, DI, when to use repositories
   - `02-prisma-and-migrations.md` — schema design, migrations
   - `03-validation-and-dtos.md` — class-validator + class-transformer
   - `04-auth-jwt-passport.md` (if include_auth) — global guards, RBAC
   - `05-bullmq-queues.md` (if include_bullmq)
   - `06-testing-jest-supertest.md`
4. **Generate**: scaffold tree, `package.json` with locked deps, prisma schema with one example model, Users feature module (controller/service/dto/entity), AuthModule with global JwtAuthGuard + `@Public()` opt-out, HealthModule via terminus, queue module if requested.
5. **Verify**: `pnpm install`, `pnpm prisma generate && pnpm prisma migrate dev --name init`, `pnpm test`, `pnpm lint` — clean.
6. **Hand off**: setup steps for the user.

Use Prisma unless the user picked Drizzle/TypeORM. Skip the repository layer for simple CRUD with Prisma; document why.
