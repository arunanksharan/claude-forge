# Node.js + Express — claudeforge guides

Production-grade Express scaffolding with factory-function wiring (no DI container).

## Files

| File | What it is | Read when |
|------|-----------|-----------|
| [`PROMPT.md`](./PROMPT.md) | Master scaffold prompt | Starting a new Express project |
| [`01-project-layout.md`](./01-project-layout.md) | Factory function pattern, no DI container | Architecture, onboarding |
| [`02-drizzle-and-migrations.md`](./02-drizzle-and-migrations.md) | Drizzle ORM, schema, queries, migrations | Working with the data layer |
| [`03-validation-with-zod.md`](./03-validation-with-zod.md) | zod schemas, sharing with frontend | Designing API shapes |
| [`04-auth-jwt.md`](./04-auth-jwt.md) | Hand-rolled JWT auth (no Passport), RBAC | Adding authentication |
| [`05-bullmq-workers.md`](./05-bullmq-workers.md) | Queue + worker setup in plain Node | Adding background work |
| [`06-testing-vitest-supertest.md`](./06-testing-vitest-supertest.md) | Vitest + Supertest, real DB | Writing tests |

## Quick decision summary

- **Node 22 LTS**, **pnpm**, **Express 5**
- **Drizzle** ORM (or Prisma; Kysely if you want pure SQL builder)
- **zod** for validation everywhere
- **pino** + **pino-http** for logging
- **bcrypt** + **jsonwebtoken** (no Passport)
- **BullMQ** for queues — workers in separate processes via PM2
- **Vitest** + **Supertest** for tests
- **OpenTelemetry** for observability
- **TypeScript strict**

## Anti-patterns rejected

- DI containers (`tsyringe`, `inversify`) — use NestJS if you need DI badly
- Passport for simple JWT — hand-roll it
- `nodemon`, `ts-node` in production
- `morgan`, `winston`, `joi`, `body-parser` standalone
- `axios` standalone (use undici)
- Hand-rolled top-level singletons
- `utils/` junk drawer

## When to use this vs NestJS

| Pick Express | Pick NestJS |
|--------------|-------------|
| <30 feature modules | 30+ modules, growing |
| Single team, code review enforces conventions | Multiple teams need guard rails |
| You want to see exactly what's happening | You want structure to fall out of conventions |
| Performance-sensitive (Express is leaner) | DX-sensitive (Nest is more guided) |
