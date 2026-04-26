# Testing with Vitest + Supertest

> Vitest is a faster Jest with the same API. Pair with Supertest for HTTP-level integration tests.

## Why Vitest

| Option | Verdict |
|--------|---------|
| **Vitest** | Pick this. Faster startup, ESM-native, identical API to Jest, built on Vite. |
| **Jest** | Mature; slower; CommonJS-default; ESM is awkward. |
| **Node test runner** (`node --test`) | Built-in, zero deps. Limited UI/coverage tooling — fine for tiny libs. |
| **uvu** / **tap** | Niche. |

## Setup

```bash
pnpm add -D vitest @vitest/coverage-v8 supertest @types/supertest
```

`vitest.config.ts`:

```typescript
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    globals: true,
    environment: 'node',
    setupFiles: ['./test/setup.ts'],
    coverage: {
      provider: 'v8',
      reporter: ['text', 'html'],
      thresholds: { lines: 70, functions: 80, branches: 70, statements: 70 },
      exclude: ['node_modules/', 'dist/', 'drizzle/', 'test/'],
    },
    poolOptions: { threads: { singleThread: false } },
    testTimeout: 10000,
  },
});
```

`test/setup.ts`:

```typescript
import { afterAll, beforeAll, beforeEach } from 'vitest';
import { execSync } from 'node:child_process';
import postgres from 'postgres';
import { drizzle } from 'drizzle-orm/postgres-js';
import * as schema from '../src/db/schema';

process.env.NODE_ENV = 'test';
process.env.DATABASE_URL = process.env.TEST_DATABASE_URL ?? 'postgresql://postgres:postgres@localhost:5432/{{db-name}}_test';

let pg: ReturnType<typeof postgres>;
export let testDb: ReturnType<typeof drizzle>;

beforeAll(async () => {
  execSync('pnpm drizzle-kit migrate', { stdio: 'inherit', env: process.env });
  pg = postgres(process.env.DATABASE_URL!);
  testDb = drizzle(pg, { schema });
});

beforeEach(async () => {
  await pg`TRUNCATE TABLE users, orders, sessions RESTART IDENTITY CASCADE`;
});

afterAll(async () => {
  await pg?.end();
});
```

## Unit test (service in isolation)

```typescript
// src/modules/users/users.service.test.ts
import { describe, it, expect, vi } from 'vitest';
import { makeUsersService } from './users.service';

describe('users.service', () => {
  it('rejects duplicate email', async () => {
    const repo = {
      findByEmail: vi.fn().mockResolvedValue({ id: 'x' }),
      create: vi.fn(),
    };
    const service = makeUsersService(repo as any);

    await expect(service.register({ email: 'a@a.com', password: 'hunter22' }))
      .rejects.toThrow(/email already in use/);
    expect(repo.create).not.toHaveBeenCalled();
  });

  it('hashes password before insert', async () => {
    const repo = {
      findByEmail: vi.fn().mockResolvedValue(null),
      create: vi.fn().mockResolvedValue({ id: 'new', email: 'a@a.com' }),
    };
    const service = makeUsersService(repo as any);

    await service.register({ email: 'a@a.com', password: 'hunter22' });

    const arg = repo.create.mock.calls[0][0];
    expect(arg.email).toBe('a@a.com');
    expect(arg.hashedPassword).not.toBe('hunter22');
    expect(arg.hashedPassword).toMatch(/^\$2[aby]\$/);  // bcrypt prefix
  });
});
```

## Integration test (HTTP through real DB)

```typescript
// test/integration/users.test.ts
import { describe, it, expect, beforeAll } from 'vitest';
import request from 'supertest';
import type { Express } from 'express';
import { createApp } from '../../src/app';

let app: Express;

beforeAll(() => {
  app = createApp();
});

describe('POST /api/v1/users', () => {
  it('creates a user', async () => {
    const res = await request(app)
      .post('/api/v1/users')
      .send({ email: 'alice@example.com', password: 'hunter22a' })
      .expect(201);

    expect(res.body.id).toMatch(/^[0-9a-f-]{36}$/);
    expect(res.body.email).toBe('alice@example.com');
    expect(res.body.hashedPassword).toBeUndefined();
  });

  it('rejects malformed body', async () => {
    const res = await request(app)
      .post('/api/v1/users')
      .send({ email: 'not-an-email', password: 'short' })
      .expect(400);

    expect(res.body.error.code).toBe('validation_error');
  });

  it('rejects duplicate email', async () => {
    await request(app).post('/api/v1/users').send({ email: 'alice@example.com', password: 'hunter22a' });

    const res = await request(app)
      .post('/api/v1/users')
      .send({ email: 'alice@example.com', password: 'anything12' })
      .expect(409);

    expect(res.body.error.code).toBe('conflict');
  });
});
```

## Authenticated requests

```typescript
async function login(email: string, password: string): Promise<string> {
  const res = await request(app).post('/api/v1/auth/login').send({ email, password }).expect(200);
  return res.body.accessToken;
}

it('GET /me requires auth', async () => {
  await request(app).get('/api/v1/users/me').expect(401);
});

it('GET /me returns the user', async () => {
  await request(app).post('/api/v1/users').send({ email: 'a@a.com', password: 'hunter22a' });
  const token = await login('a@a.com', 'hunter22a');

  const res = await request(app)
    .get('/api/v1/users/me')
    .set('Authorization', `Bearer ${token}`)
    .expect(200);

  expect(res.body.email).toBe('a@a.com');
});
```

## Mocking external HTTP

`nock` for HTTP-level interception:

```bash
pnpm add -D nock
```

```typescript
import nock from 'nock';

beforeEach(() => nock.cleanAll());

it('sends webhook', async () => {
  const scope = nock('https://example.com').post('/hook').reply(200, { ok: true });

  await service.notify(...);

  expect(scope.isDone()).toBe(true);
});
```

Or `msw` for a more declarative API.

## Database fixtures

```typescript
// test/factories/user.ts
import { hashPassword } from '../../src/lib/password';
import { testDb } from '../setup';
import { users, type NewUser } from '../../src/db/schema';

let counter = 0;

export async function makeUser(overrides: Partial<NewUser> = {}) {
  counter++;
  const [user] = await testDb.insert(users).values({
    email: overrides.email ?? `user${counter}@example.com`,
    hashedPassword: overrides.hashedPassword ?? await hashPassword('hunter22'),
    ...overrides,
  }).returning();
  return user;
}
```

## Watch mode + UI

```bash
pnpm test:watch     # vitest
pnpm vitest --ui    # browser UI for inspecting runs
```

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| Tests pass locally, fail in CI | DB state leak. Verify `beforeEach` truncate runs. |
| Slow startup | First test in a file pays for tsx + compilation. Use `vitest --watch` locally; in CI run all tests in one go. |
| `import.meta.url` errors | Make sure `tsconfig.json` has `"module": "ESNext"` and `"moduleResolution": "bundler"` |
| Connection pool exhausted | Each test file shares a pool — use `singleThread: false` in `poolOptions` only if your tests are connection-isolated |
| `vi.mock` not hoisted | Vitest hoists `vi.mock` automatically; if it doesn't, it's because of dynamic imports — use `vi.doMock` |
| Bcrypt slow | Lower rounds in `test/setup.ts`: process.env.BCRYPT_ROUNDS = '4' |
| Jest assertions don't work | They mostly do — but Vitest has its own matchers; check `expect(x).toMatchObject(...)` works |
| Open handles after tests | `await pg.end()` in `afterAll`; `worker.close()` for any BullMQ |
| Sandboxes leak between tests | Each test creates its own data; use the truncate `beforeEach` |
