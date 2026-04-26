# Node.js + Express Project — Master Scaffold Prompt

> **Copy this entire file into Claude Code (or any LLM). Replace `{{placeholders}}`. The model scaffolds an Express project with the same layered architecture as the FastAPI/NestJS guides — but without a framework's IoC container.**

---

## Context for the model

You are scaffolding a Node.js project on top of Express. Without Nest's DI container, **discipline is the only thing keeping the code layered.** Your job is to enforce that discipline mechanically — explicit module boundaries, factory functions for wiring, no globals.

If something is ambiguous, **ask once, then proceed**.

## Project parameters

```
project_name:       {{project-name}}
project_slug:       {{project-slug}}
description:        {{one-line-description}}
db_name:            {{db-name}}
api_port:           {{api-port}}
node_version:       22
include_bullmq:     {{yes-or-no}}
include_auth:       {{yes-or-no}}
include_otel:       {{yes-or-no}}
orm_choice:         {{drizzle|prisma|kysely}}     # default: drizzle
```

---

## Locked stack

| Concern | Pick | Why |
|---------|------|-----|
| Runtime | **Node.js 22 LTS** | Current LTS |
| Package manager | **pnpm** | Fastest, strict |
| Framework | **Express 5** (or **Fastify** if you want speed-first) | Express has the broadest ecosystem; Fastify is faster + better types if you're starting clean |
| ORM | **Drizzle** (default) — *or* Prisma — *or* Kysely (raw SQL with types) | Drizzle is closest-to-SQL with full TS types; Prisma has best DX; Kysely is type-safe SQL builder |
| Validation | **zod** | The de facto standard outside Nest |
| Config | `dotenv-flow` + `zod` schema | Type-safe env access |
| Logging | **pino** | Fast, structured |
| Background jobs | **BullMQ** | Same reasoning as Nest guide |
| HTTP client | **undici** (built into Node) | Faster than axios; native fetch is also fine |
| Testing | **Vitest** + **Supertest** | Vitest is faster than Jest; same API |
| Linting | **ESLint** flat config + **Prettier** | |
| Type checking | **TypeScript 5.6+** strict | |
| Process manager (prod) | **PM2** (single VPS) or systemd | |
| Observability | **OpenTelemetry** | |

## Rejected

| Library | Why not |
|---------|---------|
| Express 4 with sync middleware patterns | Express 5 handles async errors natively; use it. |
| `body-parser` standalone | Express 5 has built-in `express.json()` |
| `nodemon` | Use `tsx watch` |
| `ts-node` for production | Compile with `tsc` then run `node dist/`. `tsx` only in dev. |
| `joi` | Use zod. |
| `pino-pretty` in production | Pretty-printing is for dev; ship JSON to log aggregator. |
| `morgan` | Use pino's HTTP logger via `pino-http`. |
| `helmet` for free | Yes, install it — but configure deliberately, defaults are conservative. |
| Sequelize, TypeORM | Use Drizzle/Prisma/Kysely. |
| `winston` | Use pino. |
| `agenda` | Use BullMQ unless you specifically need MongoDB-backed scheduling. |
| `bcryptjs` (pure JS) | Use `bcrypt` (native bindings) or `argon2`. |
| Hand-rolled DI containers (`tsyringe`, `inversify`) | If you need DI this badly, use NestJS instead. |
| `class-validator` outside Nest | The decorator setup is heavy without Nest; zod is leaner. |

---

## Directory layout

```
{{project-slug}}/
├── package.json
├── pnpm-lock.yaml
├── tsconfig.json
├── tsup.config.ts                 # production build
├── eslint.config.js
├── .prettierrc
├── .env.example
├── .gitignore
├── docker-compose.dev.yml
├── Dockerfile
├── Makefile
├── drizzle.config.ts              # if Drizzle
├── drizzle/                       # generated migrations
├── src/
│   ├── server.ts                  # bootstrap
│   ├── app.ts                     # express app factory (no listen)
│   ├── config/
│   │   ├── env.ts                 # zod env schema + parse
│   │   └── index.ts
│   ├── db/
│   │   ├── client.ts              # drizzle/prisma instance
│   │   └── schema/
│   │       ├── index.ts
│   │       └── users.ts
│   ├── middleware/
│   │   ├── error-handler.ts
│   │   ├── request-id.ts
│   │   ├── logging.ts             # pino-http
│   │   ├── auth.ts                # JWT verify → req.user
│   │   └── rate-limit.ts
│   ├── lib/                       # cross-cutting helpers (no business logic)
│   │   ├── errors.ts              # AppError + subclasses
│   │   ├── jwt.ts
│   │   ├── password.ts
│   │   ├── pagination.ts
│   │   └── async-handler.ts       # wrap async route handlers
│   ├── modules/                   # one folder per feature
│   │   └── users/
│   │       ├── users.routes.ts    # router factory
│   │       ├── users.controller.ts
│   │       ├── users.service.ts
│   │       ├── users.repository.ts
│   │       ├── users.schemas.ts   # zod schemas
│   │       └── index.ts           # public exports + factory
│   ├── queue/                     # if include_bullmq
│   │   ├── connection.ts
│   │   ├── queues.ts
│   │   └── workers/
│   │       └── email.worker.ts
│   └── routes.ts                  # mounts module routers
└── test/
    ├── setup.ts
    ├── factories/
    └── integration/
        └── users.test.ts
```

## Layering rules

Same as before. Express has no IoC, so wire it manually with **factory functions**:

```typescript
// modules/users/index.ts
import { db } from '../../db/client';
import { makeUsersRepository } from './users.repository';
import { makeUsersService } from './users.service';
import { makeUsersController } from './users.controller';
import { makeUsersRouter } from './users.routes';

export function createUsersModule() {
  const repo = makeUsersRepository(db);
  const service = makeUsersService(repo);
  const controller = makeUsersController(service);
  const router = makeUsersRouter(controller);
  return { service, router };  // expose what the rest of the app needs
}
```

Each layer is a **factory function** taking its dependencies, returning an object of methods. This gives you DI without a container.

---

## Key files

### `package.json`

```json
{
  "name": "{{project-slug}}",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "engines": { "node": ">=22" },
  "packageManager": "pnpm@9",
  "scripts": {
    "dev": "tsx watch src/server.ts",
    "build": "tsup",
    "start": "node dist/server.js",
    "lint": "eslint .",
    "format": "prettier --write \"src/**/*.ts\"",
    "test": "vitest run",
    "test:watch": "vitest",
    "test:cov": "vitest run --coverage",
    "db:generate": "drizzle-kit generate",
    "db:migrate": "drizzle-kit migrate",
    "db:studio": "drizzle-kit studio"
  },
  "dependencies": {
    "express": "^5",
    "zod": "^3.23",
    "pino": "^9",
    "pino-http": "^10",
    "helmet": "^8",
    "compression": "^1.7",
    "cors": "^2.8",
    "dotenv-flow": "^4",
    "drizzle-orm": "^0.36",
    "postgres": "^3.4",
    "jsonwebtoken": "^9",
    "bcrypt": "^5",
    "bullmq": "^5",
    "ioredis": "^5",
    "@opentelemetry/api": "^1.9",
    "@opentelemetry/sdk-node": "^0.57",
    "@opentelemetry/auto-instrumentations-node": "^0.55"
  },
  "devDependencies": {
    "@types/bcrypt": "^5",
    "@types/compression": "^1.7",
    "@types/cors": "^2.8",
    "@types/express": "^5",
    "@types/jsonwebtoken": "^9",
    "@types/node": "^22",
    "@types/supertest": "^6",
    "drizzle-kit": "^0.28",
    "eslint": "^9",
    "@typescript-eslint/eslint-plugin": "^8",
    "@typescript-eslint/parser": "^8",
    "prettier": "^3",
    "supertest": "^7",
    "tsup": "^8",
    "tsx": "^4",
    "typescript": "^5.6",
    "vitest": "^2"
  }
}
```

### `src/config/env.ts`

```typescript
import { z } from 'zod';
import 'dotenv-flow/config';

const envSchema = z.object({
  NODE_ENV: z.enum(['development', 'staging', 'production', 'test']).default('development'),
  PORT: z.coerce.number().default({{api-port}}),
  DATABASE_URL: z.string().url(),
  REDIS_URL: z.string().url().default('redis://localhost:6379'),
  JWT_SECRET: z.string().min(32),
  JWT_ACCESS_EXPIRES: z.string().default('15m'),
  JWT_REFRESH_EXPIRES: z.string().default('30d'),
  LOG_LEVEL: z.enum(['fatal','error','warn','info','debug','trace']).default('info'),
  OTEL_ENABLED: z.coerce.boolean().default(false),
  OTEL_ENDPOINT: z.string().default('http://localhost:4317'),
  CORS_ORIGINS: z.string().transform(s => s.split(',').map(s => s.trim()).filter(Boolean)).default(''),
});

const parsed = envSchema.safeParse(process.env);
if (!parsed.success) {
  console.error('Invalid env:', parsed.error.flatten().fieldErrors);
  process.exit(1);
}

export const env = parsed.data;
export type Env = typeof env;
```

### `src/app.ts`

```typescript
import express, { Express } from 'express';
import helmet from 'helmet';
import cors from 'cors';
import compression from 'compression';
import { pinoHttp } from 'pino-http';
import { logger } from './lib/logger';
import { requestId } from './middleware/request-id';
import { errorHandler, notFoundHandler } from './middleware/error-handler';
import { mountRoutes } from './routes';
import { env } from './config/env';

export function createApp(): Express {
  const app = express();

  app.disable('x-powered-by');
  app.set('trust proxy', 1);          // honor X-Forwarded-* from nginx

  app.use(requestId);
  app.use(pinoHttp({ logger, customLogLevel: (req, res, err) => {
    if (res.statusCode >= 500 || err) return 'error';
    if (res.statusCode >= 400) return 'warn';
    return 'info';
  }}));
  app.use(helmet());
  app.use(cors({ origin: env.CORS_ORIGINS.length ? env.CORS_ORIGINS : false, credentials: true }));
  app.use(compression());
  app.use(express.json({ limit: '1mb' }));
  app.use(express.urlencoded({ extended: false, limit: '1mb' }));

  mountRoutes(app);

  app.use(notFoundHandler);
  app.use(errorHandler);

  return app;
}
```

### `src/server.ts`

```typescript
import 'reflect-metadata';
import { createServer } from 'node:http';
import { createApp } from './app';
import { env } from './config/env';
import { logger } from './lib/logger';

if (env.OTEL_ENABLED) {
  await import('./telemetry');   // top-level await; sets up OTEL before app
}

const app = createApp();
const server = createServer(app);

server.listen(env.PORT, () => {
  logger.info({ port: env.PORT, env: env.NODE_ENV }, '{{project-name}} listening');
});

const shutdown = async (signal: string) => {
  logger.info({ signal }, 'shutting down');
  server.close(err => {
    if (err) { logger.error({ err }, 'server close error'); process.exit(1); }
    process.exit(0);
  });
  setTimeout(() => process.exit(1), 30_000).unref();
};

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
```

### `src/routes.ts`

```typescript
import { Express, Router } from 'express';
import { createUsersModule } from './modules/users';
import { createAuthModule } from './modules/auth';
import { healthRouter } from './modules/health';

export function mountRoutes(app: Express) {
  const v1 = Router();

  v1.use('/health', healthRouter);

  const users = createUsersModule();
  v1.use('/users', users.router);

  const auth = createAuthModule({ usersService: users.service });
  v1.use('/auth', auth.router);

  app.use('/api/v1', v1);
}
```

### `src/middleware/error-handler.ts`

```typescript
import { ErrorRequestHandler, RequestHandler } from 'express';
import { ZodError } from 'zod';
import { AppError } from '../lib/errors';

export const notFoundHandler: RequestHandler = (req, res) => {
  res.status(404).json({ error: { code: 'not_found', message: `${req.method} ${req.path}` } });
};

export const errorHandler: ErrorRequestHandler = (err, req, res, _next) => {
  if (err instanceof AppError) {
    res.status(err.statusCode).json({ error: { code: err.code, message: err.message } });
    return;
  }
  if (err instanceof ZodError) {
    res.status(400).json({ error: { code: 'validation_error', message: 'invalid request', details: err.flatten() } });
    return;
  }
  req.log?.error({ err }, 'unhandled error');
  res.status(500).json({ error: { code: 'internal_error', message: 'internal error' } });
};
```

### `src/lib/errors.ts`

```typescript
export class AppError extends Error {
  code = 'app_error';
  statusCode = 500;
  constructor(message: string) { super(message); this.name = this.constructor.name; }
}
export class NotFound extends AppError { code = 'not_found'; statusCode = 404; }
export class Unauthorized extends AppError { code = 'unauthorized'; statusCode = 401; }
export class Forbidden extends AppError { code = 'forbidden'; statusCode = 403; }
export class Conflict extends AppError { code = 'conflict'; statusCode = 409; }
export class BadRequest extends AppError { code = 'bad_request'; statusCode = 400; }
```

### `src/modules/users/users.schemas.ts`

```typescript
import { z } from 'zod';

export const createUserSchema = z.object({
  email: z.string().email(),
  password: z.string().min(8).max(128),
});

export const updateUserSchema = z.object({
  email: z.string().email().optional(),
  isActive: z.boolean().optional(),
});

export type CreateUserInput = z.infer<typeof createUserSchema>;
export type UpdateUserInput = z.infer<typeof updateUserSchema>;

export interface UserResponse {
  id: string;
  email: string;
  isActive: boolean;
  createdAt: Date;
}
```

### `src/modules/users/users.service.ts`

```typescript
import bcrypt from 'bcrypt';
import { Conflict, Unauthorized } from '../../lib/errors';
import type { UsersRepository } from './users.repository';
import type { CreateUserInput } from './users.schemas';

export interface UsersService {
  register(input: CreateUserInput): Promise<{ id: string; email: string }>;
  authenticate(email: string, password: string): Promise<{ id: string; email: string }>;
}

export function makeUsersService(repo: UsersRepository): UsersService {
  return {
    async register({ email, password }) {
      if (await repo.findByEmail(email)) throw new Conflict('email already in use');
      const hashedPassword = await bcrypt.hash(password, 12);
      return repo.create({ email, hashedPassword });
    },

    async authenticate(email, password) {
      const user = await repo.findByEmail(email);
      if (!user || !(await bcrypt.compare(password, user.hashedPassword))) {
        throw new Unauthorized('invalid credentials');
      }
      return { id: user.id, email: user.email };
    },
  };
}
```

### `src/modules/users/users.controller.ts`

```typescript
import type { Request, Response, NextFunction } from 'express';
import { createUserSchema } from './users.schemas';
import type { UsersService } from './users.service';
import { asyncHandler } from '../../lib/async-handler';

export function makeUsersController(service: UsersService) {
  return {
    create: asyncHandler(async (req: Request, res: Response) => {
      const dto = createUserSchema.parse(req.body);
      const user = await service.register(dto);
      res.status(201).json({ id: user.id, email: user.email });
    }),

    me: asyncHandler(async (req: Request, res: Response) => {
      // req.user injected by auth middleware
      res.json(req.user);
    }),
  };
}
```

### `src/lib/async-handler.ts`

```typescript
// Express 5 handles async errors natively, but explicit is clearer:
import type { Request, Response, NextFunction, RequestHandler } from 'express';
export const asyncHandler =
  (fn: (req: Request, res: Response, next: NextFunction) => Promise<unknown>): RequestHandler =>
  (req, res, next) => fn(req, res, next).catch(next);
```

### `src/modules/users/users.routes.ts`

```typescript
import { Router } from 'express';
import { authMiddleware } from '../../middleware/auth';

export function makeUsersRouter(controller: ReturnType<typeof makeUsersController>) {
  const router = Router();
  router.post('/', controller.create);
  router.get('/me', authMiddleware, controller.me);
  return router;
}
```

---

## Generation steps

1. **Confirm parameters.**
2. **Create directory tree.**
3. **Write `package.json`, `tsconfig.json`, `tsup.config.ts`, `eslint.config.js`.**
4. **Write `src/config/env.ts`, `src/lib/logger.ts`, `src/lib/errors.ts`, `src/lib/async-handler.ts`.**
5. **Write `src/db/client.ts` and one schema file.**
6. **Write `src/app.ts`, `src/server.ts`, `src/routes.ts`, `src/middleware/*`.**
7. **Generate one example feature (`modules/users/`)** — full layered scaffold.
8. **Add auth module if `include_auth=yes`.**
9. **Add queue setup if `include_bullmq=yes`.**
10. **Write `test/setup.ts` and one integration test.**
11. **Write `Dockerfile`, `docker-compose.dev.yml`, `Makefile`, `README.md`.**
12. **Run `pnpm install`.**
13. **Run `pnpm db:generate && pnpm db:migrate`.**
14. **Run `pnpm test`** — should pass.
15. **Run `pnpm lint`** — clean.

---

## Companion deep-dive files

- [`01-project-layout.md`](./01-project-layout.md) — factory function pattern, no DI container
- [`02-drizzle-and-migrations.md`](./02-drizzle-and-migrations.md) — schema, migrations, queries
- [`03-validation-with-zod.md`](./03-validation-with-zod.md) — schemas, parsing in controllers, sharing with frontend
- [`04-auth-jwt.md`](./04-auth-jwt.md) — JWT middleware, refresh tokens, RBAC
- [`05-bullmq-workers.md`](./05-bullmq-workers.md) — queue + worker patterns (similar to Nest version)
- [`06-testing-vitest-supertest.md`](./06-testing-vitest-supertest.md) — Vitest + Supertest patterns
