# Testing NestJS with Jest + Supertest

> Unit tests with `@nestjs/testing`, e2e with Supertest against a real DB.

## What to test where

| Type | Tool | Use for |
|------|------|---------|
| **Unit** (service, with mocked deps) | Jest + `Test.createTestingModule` with overrides | Pure logic in services |
| **e2e** (full app, real Prisma, test Postgres) | Supertest + `Test.createTestingModule` for the whole app | Most tests — they catch the integration bugs |

Default to e2e against a real DB. Mocks only when the real thing is slow or unreliable (external HTTP).

## Unit test example

```typescript
// users.service.spec.ts
import { Test } from '@nestjs/testing';
import { UsersService } from './users.service';
import { PrismaService } from '../prisma/prisma.service';
import { ConflictException } from '@nestjs/common';

describe('UsersService', () => {
  let service: UsersService;
  let prisma: { user: { findUnique: jest.Mock; create: jest.Mock } };

  beforeEach(async () => {
    prisma = { user: { findUnique: jest.fn(), create: jest.fn() } };

    const module = await Test.createTestingModule({
      providers: [
        UsersService,
        { provide: PrismaService, useValue: prisma },
      ],
    }).compile();

    service = module.get(UsersService);
  });

  it('rejects duplicate email', async () => {
    prisma.user.findUnique.mockResolvedValue({ id: 'x', email: 'a@a.com' });

    await expect(service.register('a@a.com', 'hunter22')).rejects.toBeInstanceOf(ConflictException);
    expect(prisma.user.create).not.toHaveBeenCalled();
  });

  it('creates user with hashed password', async () => {
    prisma.user.findUnique.mockResolvedValue(null);
    prisma.user.create.mockResolvedValue({ id: 'new', email: 'a@a.com' });

    const user = await service.register('a@a.com', 'hunter22');

    expect(user.id).toBe('new');
    expect(prisma.user.create).toHaveBeenCalledWith({
      data: { email: 'a@a.com', hashedPassword: expect.any(String) },
    });
    const createdData = prisma.user.create.mock.calls[0][0].data;
    expect(createdData.hashedPassword).not.toBe('hunter22');
  });
});
```

## e2e test setup

### `test/jest-e2e.json`

```json
{
  "moduleFileExtensions": ["js", "json", "ts"],
  "rootDir": ".",
  "testEnvironment": "node",
  "testRegex": ".e2e-spec.ts$",
  "transform": { "^.+\\.(t|j)s$": "ts-jest" },
  "globalSetup": "<rootDir>/e2e/global-setup.ts",
  "globalTeardown": "<rootDir>/e2e/global-teardown.ts",
  "setupFilesAfterEach": ["<rootDir>/e2e/setup.ts"]
}
```

### `test/e2e/global-setup.ts`

Runs once before the e2e suite:

```typescript
import { execSync } from 'child_process';

export default async () => {
  process.env.NODE_ENV = 'test';
  process.env.DATABASE_URL = process.env.TEST_DATABASE_URL ?? 'postgresql://postgres:postgres@localhost:5432/{{db-name}}_test';

  // apply migrations to the test DB
  execSync('pnpm prisma migrate deploy', { stdio: 'inherit', env: process.env });
};
```

### `test/e2e/setup.ts`

Runs before each test — clears all tables:

```typescript
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

afterEach(async () => {
  // truncate all tables in dependency order
  // for many tables, use a single TRUNCATE ... CASCADE
  await prisma.$executeRawUnsafe(`
    TRUNCATE TABLE "users", "orders", "sessions" RESTART IDENTITY CASCADE;
  `);
});

afterAll(async () => {
  await prisma.$disconnect();
});
```

For a tighter loop, wrap each test in a transaction that rolls back. Prisma supports this via interactive transactions but it's awkward to compose with Nest's DI — TRUNCATE per-test is simpler and fast enough for most apps.

### `test/e2e/users.e2e-spec.ts`

```typescript
import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import * as request from 'supertest';
import { AppModule } from '../../src/app.module';

describe('Users (e2e)', () => {
  let app: INestApplication;

  beforeAll(async () => {
    const moduleRef = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = moduleRef.createNestApplication();
    app.setGlobalPrefix('api');
    app.useGlobalPipes(new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true, transform: true }));
    await app.init();
  });

  afterAll(async () => {
    await app.close();
  });

  describe('POST /api/v1/users', () => {
    it('creates a user (201)', async () => {
      const res = await request(app.getHttpServer())
        .post('/api/v1/users')
        .send({ email: 'alice@example.com', password: 'hunter22a' })
        .expect(201);

      expect(res.body).toMatchObject({
        email: 'alice@example.com',
        isActive: true,
      });
      expect(res.body.id).toMatch(/^[0-9a-f-]{36}$/);
      expect(res.body.hashedPassword).toBeUndefined();
    });

    it('rejects duplicate email (409)', async () => {
      await request(app.getHttpServer()).post('/api/v1/users').send({
        email: 'alice@example.com',
        password: 'hunter22a',
      });

      await request(app.getHttpServer())
        .post('/api/v1/users')
        .send({ email: 'alice@example.com', password: 'anything12' })
        .expect(409);
    });

    it('rejects malformed body (400)', async () => {
      await request(app.getHttpServer())
        .post('/api/v1/users')
        .send({ email: 'not-an-email', password: 'short' })
        .expect(400);
    });
  });
});
```

## Authenticated test client

```typescript
async function login(app: INestApplication, email: string, password: string) {
  const res = await request(app.getHttpServer())
    .post('/api/v1/auth/login')
    .send({ email, password })
    .expect(201);
  return res.body.accessToken;
}

it('GET /me requires auth', async () => {
  await request(app.getHttpServer()).get('/api/v1/users/me').expect(401);
});

it('GET /me returns the current user', async () => {
  await request(app.getHttpServer()).post('/api/v1/users').send({ email: 'a@a.com', password: 'hunter22a' });
  const token = await login(app, 'a@a.com', 'hunter22a');

  const res = await request(app.getHttpServer())
    .get('/api/v1/users/me')
    .set('Authorization', `Bearer ${token}`)
    .expect(200);

  expect(res.body.email).toBe('a@a.com');
});
```

## Mocking external services in e2e

Override providers in the test module:

```typescript
const moduleRef = await Test.createTestingModule({
  imports: [AppModule],
})
  .overrideProvider(MailerService)
  .useValue({ sendWelcome: jest.fn() })
  .compile();
```

Or use `nock` / `msw` to intercept HTTP at the boundary. `nock` is simpler for Node-only testing.

## Database fixtures

For non-trivial tests, factory functions:

```typescript
// test/factories/user.factory.ts
import { PrismaClient, User } from '@prisma/client';
import * as bcrypt from 'bcrypt';

let counter = 0;

export async function makeUser(prisma: PrismaClient, overrides: Partial<User> = {}): Promise<User> {
  counter++;
  return prisma.user.create({
    data: {
      email: overrides.email ?? `user${counter}@example.com`,
      hashedPassword: overrides.hashedPassword ?? await bcrypt.hash('hunter22', 4),  // low rounds in test
      isActive: overrides.isActive ?? true,
      ...overrides,
    },
  });
}
```

Use:

```typescript
const user = await makeUser(prisma, { role: 'ADMIN' });
```

## Coverage

```bash
pnpm test --coverage
```

Aim for 80%+ on services. Don't chase 100%.

```json
// in jest config
"coverageThreshold": {
  "global": {
    "branches": 70,
    "functions": 80,
    "lines": 80,
    "statements": 80
  }
}
```

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| Tests pass locally, fail in CI | DB state leak. Verify `afterEach` TRUNCATE runs. |
| Slow startup (>10s for first test) | NestJS module compilation is heavy. `beforeAll` per file, not per test. |
| `Cannot find module '@prisma/client'` | Run `pnpm prisma generate` in CI before tests |
| Tests share state via `beforeAll` user creation | Move to `beforeEach` per test for isolation |
| Bcrypt slow in tests (10× test time) | Use rounds=4 in test env (`if (process.env.NODE_ENV === 'test') rounds = 4`) |
| Mocked Prisma drifts from real schema | Prefer e2e against real DB; mock only at HTTP boundaries |
| Open handles after tests (Jest hangs) | `app.close()` in `afterAll` + ensure all queues/connections are closed |
| Tests pass but linter fails on test file | Add `eslint-config-jest` or `plugin:jest/recommended` |
