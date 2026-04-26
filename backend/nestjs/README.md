# NestJS — claudeforge guides

Production-grade NestJS scaffolding with modular feature folders + dependency injection.

## Files

| File | What it is | Read when |
|------|-----------|-----------|
| [`PROMPT.md`](./PROMPT.md) | Master scaffold prompt — paste into Claude Code | Starting a new NestJS project |
| [`01-project-layout.md`](./01-project-layout.md) | Modules, providers, DI, when to use repository pattern | Architecture decisions, onboarding |
| [`02-prisma-and-migrations.md`](./02-prisma-and-migrations.md) | Schema design, migrations, transactions, queries | Working with the data layer |
| [`03-validation-and-dtos.md`](./03-validation-and-dtos.md) | class-validator + class-transformer, response DTOs | Designing API shapes |
| [`04-auth-jwt-passport.md`](./04-auth-jwt-passport.md) | JWT strategy, guards, RBAC, custom decorators | Adding authentication |
| [`05-bullmq-queues.md`](./05-bullmq-queues.md) | Queue setup, processors, repeatable jobs, flows | Adding background work |
| [`06-testing-jest-supertest.md`](./06-testing-jest-supertest.md) | Unit + e2e against real DB | Writing tests |

## Quick decision summary

- **Node 22 LTS** with **pnpm**
- **Prisma** as default ORM (Drizzle if you prefer SQL-close)
- **class-validator** for DTOs, **zod** for non-DTO validation
- **pino** + **nestjs-pino** for logging
- **@nestjs/jwt** + **passport-jwt** for auth, with global guards
- **BullMQ** for queues
- **Jest** + **Supertest** for tests, real Postgres
- **OpenTelemetry** for tracing/metrics
- **TypeScript strict mode**

## Anti-patterns rejected

- `bull` (deprecated), `bee-queue`, Sequelize, MikroORM (smaller community)
- `joi` (use class-validator or zod), `winston` (use pino), `axios` standalone (use undici/`@nestjs/axios`)
- `moment`, `lodash` (selective imports only)
- npm/yarn classic (use pnpm)
- `nodemon`, `ts-node-dev` (Nest CLI handles watch)
- Reusing entities as DTOs
- One giant `ServicesModule` exporting everything
- Auth-by-opt-in (use global guard with `@Public()` opt-out)
