# NestJS Project — Master Scaffold Prompt

> **Copy this entire file into Claude Code (or any LLM). Replace `{{placeholders}}`. The model will scaffold a production-grade NestJS project following modular feature folders + dependency injection.**

---

## Context for the model

You are scaffolding a new NestJS project. The project follows a **modular monolith** pattern: each feature is a self-contained module with its own controller, service, repository, DTOs, and entities. Your job is to generate the full scaffold per the rules below. Do not invent extra layers. Do not skip layers. Do not pick libraries other than the ones listed.

If something is ambiguous, **ask once, then proceed**.

## Project parameters

```
project_name:       {{project-name}}
project_slug:       {{project-slug}}            # kebab-case, used in package.json
description:        {{one-line-description}}
db_name:            {{db-name}}
api_port:           {{api-port}}                # e.g. 3000
node_version:       22                          # current LTS
include_bullmq:     {{yes-or-no}}               # background jobs
include_auth:       {{yes-or-no}}               # JWT auth
include_otel:       {{yes-or-no}}               # OpenTelemetry
orm_choice:         {{prisma|drizzle|typeorm}}  # prisma is the default
```

---

## Locked stack

| Concern | Pick | Why |
|---------|------|-----|
| Runtime | **Node.js 22 LTS** | Current LTS as of 2025-2026 |
| Package manager | **pnpm** | Fastest, strict by default, monorepo-friendly |
| Framework | **NestJS 10+** | The IoC container is the value; controllers + providers + modules |
| ORM | **Prisma** (default) — *or* Drizzle (lighter) — *or* TypeORM (legacy) | Prisma has the best DX; Drizzle is closer-to-SQL with strong types; TypeORM only if existing project |
| DB driver | Postgres via the ORM | |
| Validation | **class-validator** + **class-transformer** | Native to Nest; pairs with DTOs |
| Config | **@nestjs/config** + **zod** for validation | Type-safe env access |
| Logging | **pino** + **nestjs-pino** | Fast, structured, small |
| Background jobs | **BullMQ** (`@nestjs/bullmq`) | Redis-backed, well-maintained, replaces deprecated `bull` |
| Cache | **@nestjs/cache-manager** + Redis store | |
| HTTP client | **undici** (built into Node) or **@nestjs/axios** | Undici is faster; axios is convenient |
| Testing | **Jest** + **@nestjs/testing** + **Supertest** | Standard |
| Linting | **ESLint** (flat config) + **Prettier** | |
| Type checking | **TypeScript 5.6+** with `strict: true` | |
| Observability | **OpenTelemetry** + **@nestjs/terminus** for healthchecks | |

## Rejected

| Library | Why not |
|---------|---------|
| Express directly (without Nest) | Use `backend/nodejs-express/` if you don't want Nest. |
| Fastify under Nest | Officially supported, but most Nest middleware assumes Express. Stick with Express adapter unless you know you need Fastify. |
| `bull` (v3, classic) | Deprecated. Use `bullmq`. |
| `bee-queue` | Smaller community, fewer features than BullMQ. |
| `joi` | Use class-validator (decorator-based, fits Nest) or zod for non-DTO validation. |
| `winston` | Use pino — much faster, structured. |
| `axios` (without `@nestjs/axios`) | Use undici (built-in) or `@nestjs/axios` for the wrapped DX. |
| Sequelize | Worse types than Prisma/Drizzle, slower. |
| MikroORM | Fine but smaller community. Prisma is easier to find help for. |
| `moment` | Use `date-fns` or built-in `Intl.DateTimeFormat`. |
| `lodash` | Modern Node has most of what you need. Selectively import (`lodash-es`) only if needed. |
| npm or yarn classic | Use pnpm. |
| `ts-node-dev` | Use `tsx` or Nest's built-in `--watch`. |
| `nodemon` | Same — Nest CLI handles watch mode. |

---

## Directory layout (generate exactly)

```
{{project-slug}}/
├── package.json
├── pnpm-lock.yaml
├── pnpm-workspace.yaml             # if monorepo
├── tsconfig.json
├── tsconfig.build.json
├── nest-cli.json
├── eslint.config.js                # flat config
├── .prettierrc
├── .env.example
├── .gitignore
├── docker-compose.dev.yml
├── Dockerfile
├── Makefile
├── prisma/                         # if Prisma
│   ├── schema.prisma
│   ├── migrations/
│   └── seed.ts
├── src/
│   ├── main.ts                     # bootstrap
│   ├── app.module.ts               # root module
│   ├── config/
│   │   ├── configuration.ts        # config object
│   │   └── env.schema.ts           # zod schema
│   ├── common/
│   │   ├── decorators/             # @CurrentUser, @Public, @Roles
│   │   ├── filters/                # global exception filter
│   │   ├── guards/                 # JwtAuthGuard, RolesGuard
│   │   ├── interceptors/           # logging, transform, timeout
│   │   ├── pipes/                  # validation, custom parsers
│   │   ├── middlewares/            # request id, etc.
│   │   ├── exceptions/             # AppException base + subclasses
│   │   ├── pagination/             # PageDto, paginate helper
│   │   └── types/
│   ├── prisma/                     # PrismaService wrapper module
│   │   ├── prisma.module.ts
│   │   └── prisma.service.ts
│   ├── auth/                       # if include_auth
│   │   ├── auth.module.ts
│   │   ├── auth.controller.ts
│   │   ├── auth.service.ts
│   │   ├── strategies/jwt.strategy.ts
│   │   └── dto/
│   ├── users/                      # example feature module
│   │   ├── users.module.ts
│   │   ├── users.controller.ts
│   │   ├── users.service.ts
│   │   ├── users.repository.ts
│   │   ├── dto/
│   │   │   ├── create-user.dto.ts
│   │   │   ├── update-user.dto.ts
│   │   │   └── user-response.dto.ts
│   │   └── entities/user.entity.ts
│   ├── queue/                      # if include_bullmq
│   │   ├── queue.module.ts
│   │   └── processors/
│   │       └── email.processor.ts
│   └── health/
│       ├── health.module.ts
│       └── health.controller.ts
└── test/
    ├── jest-e2e.json
    ├── e2e/
    │   ├── setup.ts
    │   └── users.e2e-spec.ts
    └── unit/
        └── users.service.spec.ts
```

## Layering rules (per feature module)

| Layer | Allowed to import from | Not allowed |
|-------|----------------------|-------------|
| `*.controller.ts` | `*.service`, `dto/`, `common/` | `*.repository.ts` directly, `entities/` directly |
| `*.service.ts` | `*.repository.ts`, `entities/`, other modules' services (via DI) | DTOs (use plain typed objects at service boundary) |
| `*.repository.ts` | Prisma/Drizzle client, `entities/` | services, controllers, DTOs |
| `dto/*.dto.ts` | nothing else | services, repositories |
| `entities/*.entity.ts` | base entity, ORM | nothing else |

The repository layer is **optional with Prisma** since Prisma's API already abstracts the DB. Use it when:
- You have complex queries that don't fit cleanly in services
- You want to mock data access in tests
- You expect to swap the ORM later (rare)

For simple CRUD + Prisma, it's defensible to skip the repo and use `PrismaService` directly in the service. Be consistent within a project.

---

## Key files

### `package.json`

```json
{
  "name": "{{project-slug}}",
  "version": "0.1.0",
  "description": "{{one-line-description}}",
  "private": true,
  "engines": { "node": ">=22" },
  "packageManager": "pnpm@9",
  "scripts": {
    "build": "nest build",
    "start": "nest start",
    "dev": "nest start --watch",
    "debug": "nest start --debug --watch",
    "start:prod": "node dist/main",
    "lint": "eslint .",
    "format": "prettier --write \"src/**/*.ts\" \"test/**/*.ts\"",
    "test": "jest",
    "test:watch": "jest --watch",
    "test:cov": "jest --coverage",
    "test:e2e": "jest --config ./test/jest-e2e.json",
    "prisma:generate": "prisma generate",
    "prisma:migrate": "prisma migrate dev",
    "prisma:studio": "prisma studio"
  },
  "dependencies": {
    "@nestjs/common": "^10.4",
    "@nestjs/core": "^10.4",
    "@nestjs/platform-express": "^10.4",
    "@nestjs/config": "^3.3",
    "@nestjs/terminus": "^10.2",
    "@nestjs/throttler": "^6",
    "reflect-metadata": "^0.2",
    "rxjs": "^7.8",
    "class-validator": "^0.14",
    "class-transformer": "^0.5",
    "zod": "^3.23",
    "pino": "^9",
    "nestjs-pino": "^4",
    "@prisma/client": "^5.22",
    "@nestjs/jwt": "^10.2",
    "@nestjs/passport": "^10.0",
    "passport": "^0.7",
    "passport-jwt": "^4",
    "bcrypt": "^5",
    "@nestjs/bullmq": "^10",
    "bullmq": "^5",
    "ioredis": "^5",
    "@opentelemetry/api": "^1.9",
    "@opentelemetry/sdk-node": "^0.57",
    "@opentelemetry/auto-instrumentations-node": "^0.55",
    "@opentelemetry/exporter-trace-otlp-grpc": "^0.57"
  },
  "devDependencies": {
    "@nestjs/cli": "^10.4",
    "@nestjs/testing": "^10.4",
    "@types/bcrypt": "^5",
    "@types/express": "^5",
    "@types/jest": "^29",
    "@types/node": "^22",
    "@types/passport-jwt": "^4",
    "@types/supertest": "^6",
    "eslint": "^9",
    "@typescript-eslint/eslint-plugin": "^8",
    "@typescript-eslint/parser": "^8",
    "jest": "^29",
    "prettier": "^3",
    "prisma": "^5.22",
    "supertest": "^7",
    "ts-jest": "^29",
    "tsconfig-paths": "^4",
    "typescript": "^5.6"
  }
}
```

### `src/config/env.schema.ts`

```typescript
import { z } from 'zod';

export const envSchema = z.object({
  NODE_ENV: z.enum(['development', 'staging', 'production', 'test']).default('development'),
  PORT: z.coerce.number().default({{api-port}}),

  DATABASE_URL: z.string().url(),

  REDIS_URL: z.string().url().default('redis://localhost:6379'),

  JWT_SECRET: z.string().min(32),
  JWT_ACCESS_EXPIRES: z.string().default('15m'),
  JWT_REFRESH_EXPIRES: z.string().default('30d'),

  OTEL_ENABLED: z.coerce.boolean().default(false),
  OTEL_ENDPOINT: z.string().default('http://localhost:4317'),
  OTEL_SERVICE_NAME: z.string().default('{{project-slug}}'),

  LOG_LEVEL: z.enum(['fatal', 'error', 'warn', 'info', 'debug', 'trace']).default('info'),
});

export type Env = z.infer<typeof envSchema>;
```

### `src/config/configuration.ts`

```typescript
import { envSchema } from './env.schema';

export default () => {
  const result = envSchema.safeParse(process.env);
  if (!result.success) {
    console.error('Invalid environment variables:', result.error.flatten().fieldErrors);
    throw new Error('Invalid environment configuration');
  }
  return result.data;
};
```

### `src/main.ts`

```typescript
import 'reflect-metadata';
import { NestFactory } from '@nestjs/core';
import { ValidationPipe, VersioningType } from '@nestjs/common';
import { Logger } from 'nestjs-pino';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create(AppModule, { bufferLogs: true });

  app.useLogger(app.get(Logger));

  app.setGlobalPrefix('api');
  app.enableVersioning({ type: VersioningType.URI, defaultVersion: '1' });

  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,           // strip unknown properties
      forbidNonWhitelisted: true, // 400 on unknown
      transform: true,            // coerce primitives
      transformOptions: { enableImplicitConversion: true },
    }),
  );

  app.enableShutdownHooks();

  const port = Number(process.env.PORT ?? {{api-port}});
  await app.listen(port);
  console.log(`{{project-name}} listening on http://localhost:${port}`);
}

bootstrap().catch((err) => {
  console.error('bootstrap failed', err);
  process.exit(1);
});
```

### `src/app.module.ts`

```typescript
import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { LoggerModule } from 'nestjs-pino';
import { ThrottlerModule } from '@nestjs/throttler';
import configuration from './config/configuration';
import { PrismaModule } from './prisma/prisma.module';
import { UsersModule } from './users/users.module';
import { AuthModule } from './auth/auth.module';
import { HealthModule } from './health/health.module';
import { QueueModule } from './queue/queue.module';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true, load: [configuration] }),
    LoggerModule.forRoot({
      pinoHttp: {
        level: process.env.LOG_LEVEL ?? 'info',
        transport:
          process.env.NODE_ENV === 'development'
            ? { target: 'pino-pretty', options: { colorize: true } }
            : undefined,
        redact: ['req.headers.authorization', 'req.headers.cookie'],
      },
    }),
    ThrottlerModule.forRoot([{ ttl: 60_000, limit: 100 }]),
    PrismaModule,
    AuthModule,
    UsersModule,
    QueueModule,
    HealthModule,
  ],
})
export class AppModule {}
```

### `src/prisma/prisma.service.ts`

```typescript
import { Injectable, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { PrismaClient } from '@prisma/client';

@Injectable()
export class PrismaService extends PrismaClient implements OnModuleInit, OnModuleDestroy {
  async onModuleInit(): Promise<void> {
    await this.$connect();
  }
  async onModuleDestroy(): Promise<void> {
    await this.$disconnect();
  }
}
```

### `prisma/schema.prisma`

```prisma
generator client {
  provider = "prisma-client-js"
}

datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}

model User {
  id             String   @id @default(uuid()) @db.Uuid
  email          String   @unique
  hashedPassword String
  isActive       Boolean  @default(true)
  role           Role     @default(USER)
  createdAt      DateTime @default(now())
  updatedAt      DateTime @updatedAt

  @@map("users")
}

enum Role {
  USER
  ADMIN
}
```

### `src/users/users.service.ts`

```typescript
import { Injectable, ConflictException } from '@nestjs/common';
import * as bcrypt from 'bcrypt';
import { PrismaService } from '../prisma/prisma.service';
import { User } from '@prisma/client';

@Injectable()
export class UsersService {
  constructor(private readonly prisma: PrismaService) {}

  async register(email: string, password: string): Promise<User> {
    const existing = await this.prisma.user.findUnique({ where: { email } });
    if (existing) throw new ConflictException('email already in use');

    const hashedPassword = await bcrypt.hash(password, 12);
    return this.prisma.user.create({ data: { email, hashedPassword } });
  }

  async findById(id: string): Promise<User | null> {
    return this.prisma.user.findUnique({ where: { id } });
  }
}
```

### `src/users/users.controller.ts`

```typescript
import { Body, Controller, Get, Post, UseGuards } from '@nestjs/common';
import { UsersService } from './users.service';
import { CreateUserDto } from './dto/create-user.dto';
import { UserResponseDto } from './dto/user-response.dto';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { CurrentUser } from '../common/decorators/current-user.decorator';

@Controller({ path: 'users', version: '1' })
export class UsersController {
  constructor(private readonly usersService: UsersService) {}

  @Post()
  async create(@Body() dto: CreateUserDto): Promise<UserResponseDto> {
    const user = await this.usersService.register(dto.email, dto.password);
    return UserResponseDto.from(user);
  }

  @Get('me')
  @UseGuards(JwtAuthGuard)
  async me(@CurrentUser() user: { id: string }): Promise<UserResponseDto> {
    const fresh = await this.usersService.findById(user.id);
    return UserResponseDto.from(fresh!);
  }
}
```

### `src/users/dto/create-user.dto.ts`

```typescript
import { IsEmail, IsString, MinLength, MaxLength } from 'class-validator';

export class CreateUserDto {
  @IsEmail()
  email!: string;

  @IsString()
  @MinLength(8)
  @MaxLength(128)
  password!: string;
}
```

### `src/users/dto/user-response.dto.ts`

```typescript
import { Expose, plainToInstance } from 'class-transformer';
import { User } from '@prisma/client';

export class UserResponseDto {
  @Expose() id!: string;
  @Expose() email!: string;
  @Expose() isActive!: boolean;
  @Expose() createdAt!: Date;

  static from(user: User): UserResponseDto {
    return plainToInstance(UserResponseDto, user, { excludeExtraneousValues: true });
  }
}
```

`excludeExtraneousValues: true` strips `hashedPassword` and anything else not `@Expose()`d. Critical for never leaking secrets.

---

## Generation steps

1. **Confirm parameters** with the user.
2. **Create the directory tree.**
3. **Write `package.json`, `tsconfig.json`, `nest-cli.json`, `eslint.config.js`.**
4. **Write `prisma/schema.prisma`** with the User model + any features the user mentioned.
5. **Write `main.ts`, `app.module.ts`, `prisma.module.ts`, `prisma.service.ts`.**
6. **Generate one example feature module (`users/`)** — controller, service, dto, fully wired. Include auth scaffolding if `include_auth=yes`.
7. **Write `health.module.ts`** with `@nestjs/terminus` (DB ping + Redis ping).
8. **Write the queue module** if `include_bullmq=yes`.
9. **Write `test/jest-e2e.json` and one e2e test** for `/api/v1/users`.
10. **Write `Dockerfile`, `docker-compose.dev.yml`, `Makefile`, `README.md`.**
11. **Run `pnpm install`.**
12. **Run `pnpm prisma generate && pnpm prisma migrate dev --name init`.**
13. **Run `pnpm test`** — the example test should pass.
14. **Run `pnpm lint`** — should be clean.

---

## Companion deep-dive files

- [`01-project-layout.md`](./01-project-layout.md) — modules, providers, DI, when to use repository pattern with Prisma
- [`02-prisma-and-migrations.md`](./02-prisma-and-migrations.md) — schema design, migrations, transactions, common queries
- [`03-validation-and-dtos.md`](./03-validation-and-dtos.md) — class-validator patterns, transformers, custom decorators
- [`04-auth-jwt-passport.md`](./04-auth-jwt-passport.md) — JWT strategy, guards, RBAC, custom decorators
- [`05-bullmq-queues.md`](./05-bullmq-queues.md) — queue setup, processors, repeatable jobs, flow producers
- [`06-testing-jest-supertest.md`](./06-testing-jest-supertest.md) — unit vs e2e, test module, real DB strategy
