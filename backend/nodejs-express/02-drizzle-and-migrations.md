# Drizzle ORM + Migrations

> Type-safe, SQL-close ORM. Schema, queries, migrations.

## Why Drizzle

| Option | Verdict |
|--------|---------|
| **Drizzle** | Pick this. SQL-close, full TS types, tiny runtime, no codegen step required for queries. |
| **Prisma** | Best DX overall but heavier (codegen + runtime). Also a great choice. |
| **Kysely** | Pure type-safe SQL builder. Best if you want zero ORM abstraction. |
| **TypeORM** | Legacy. |
| **Sequelize** | Worse types. Skip. |

For a new Express + TypeScript project where you'd rather think in SQL than in an ORM DSL: **Drizzle**.

For a project where you want guard rails and migrations to "just work": **Prisma**.

The patterns below cover Drizzle. The Prisma patterns are in `backend/nestjs/02-prisma-and-migrations.md`.

## Setup

```bash
pnpm add drizzle-orm postgres
pnpm add -D drizzle-kit
```

`drizzle.config.ts`:

```typescript
import { defineConfig } from 'drizzle-kit';
import { env } from './src/config/env';

export default defineConfig({
  schema: './src/db/schema/*',
  out: './drizzle',
  dialect: 'postgresql',
  dbCredentials: { url: env.DATABASE_URL },
  casing: 'snake_case',
  verbose: true,
  strict: true,
});
```

`casing: 'snake_case'` makes Drizzle map `createdAt` → `created_at` automatically. Standard Postgres convention.

## Schema

```typescript
// src/db/schema/users.ts
import { pgTable, uuid, text, boolean, timestamp, index, pgEnum } from 'drizzle-orm/pg-core';
import { relations } from 'drizzle-orm';
import { orders } from './orders';

export const roleEnum = pgEnum('role', ['user', 'admin']);

export const users = pgTable('users', {
  id: uuid().primaryKey().defaultRandom(),
  email: text().notNull().unique(),
  hashedPassword: text().notNull(),
  isActive: boolean().notNull().default(true),
  role: roleEnum().notNull().default('user'),
  createdAt: timestamp({ withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp({ withTimezone: true }).notNull().defaultNow().$onUpdate(() => new Date()),
}, (t) => ({
  isActiveIdx: index().on(t.isActive, t.createdAt),
}));

export const usersRelations = relations(users, ({ many }) => ({
  orders: many(orders),
}));

export type User = typeof users.$inferSelect;
export type NewUser = typeof users.$inferInsert;
```

```typescript
// src/db/schema/orders.ts
import { pgTable, uuid, bigint, timestamp, index, pgEnum } from 'drizzle-orm/pg-core';
import { relations } from 'drizzle-orm';
import { users } from './users';

export const orderStatusEnum = pgEnum('order_status', ['pending', 'paid', 'shipped', 'cancelled']);

export const orders = pgTable('orders', {
  id: uuid().primaryKey().defaultRandom(),
  userId: uuid().notNull().references(() => users.id, { onDelete: 'cascade' }),
  totalCents: bigint({ mode: 'bigint' }).notNull(),
  status: orderStatusEnum().notNull().default('pending'),
  createdAt: timestamp({ withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp({ withTimezone: true }).notNull().defaultNow().$onUpdate(() => new Date()),
}, (t) => ({
  userCreatedIdx: index().on(t.userId, t.createdAt),
  statusIdx: index().on(t.status),
}));

export const ordersRelations = relations(orders, ({ one }) => ({
  user: one(users, { fields: [orders.userId], references: [users.id] }),
}));

export type Order = typeof orders.$inferSelect;
export type NewOrder = typeof orders.$inferInsert;
```

```typescript
// src/db/schema/index.ts
export * from './users';
export * from './orders';
```

```typescript
// src/db/client.ts
import postgres from 'postgres';
import { drizzle } from 'drizzle-orm/postgres-js';
import * as schema from './schema';
import { env } from '../config/env';

const queryClient = postgres(env.DATABASE_URL, { max: 10 });
export const db = drizzle(queryClient, { schema });
export type Database = typeof db;
```

## Migrations

```bash
# generate from schema diff
pnpm drizzle-kit generate --name "add orders"

# apply pending migrations
pnpm drizzle-kit migrate

# inspect schema vs DB
pnpm drizzle-kit check
```

Generated SQL goes in `drizzle/`. **Read every generated file before committing.** Drizzle is good but you'll occasionally want to:

- Make an index `CONCURRENTLY`
- Add data migration steps
- Tweak ENUM additions

For migrations Drizzle can't auto-generate (data backfills, etc.), write SQL by hand:

```bash
pnpm drizzle-kit generate --custom --name "backfill order totals"
```

Edit the generated empty SQL file.

## Querying

### Basic CRUD

```typescript
import { eq, and, desc, sql } from 'drizzle-orm';
import { db } from './client';
import { users, orders } from './schema';

// findFirst with filter
const user = await db.query.users.findFirst({
  where: eq(users.email, email),
});

// findMany with multiple filters
const recent = await db.query.orders.findMany({
  where: and(eq(orders.userId, userId), eq(orders.status, 'paid')),
  orderBy: desc(orders.createdAt),
  limit: 10,
});

// insert
const [newUser] = await db.insert(users).values({ email, hashedPassword }).returning();

// update
await db.update(users).set({ isActive: false }).where(eq(users.id, userId));

// delete
await db.delete(users).where(eq(users.id, userId));
```

### Relations (eager loading)

```typescript
const user = await db.query.users.findFirst({
  where: eq(users.id, userId),
  with: {
    orders: {
      where: eq(orders.status, 'paid'),
      orderBy: desc(orders.createdAt),
      limit: 10,
    },
  },
});
// user.orders is fully typed
```

### Pagination

Cursor:

```typescript
const page = await db.query.orders.findMany({
  where: cursor ? and(eq(orders.userId, userId), gt(orders.id, cursor)) : eq(orders.userId, userId),
  orderBy: orders.id,
  limit: 50,
});
```

Offset:

```typescript
const [items, [{ count }]] = await Promise.all([
  db.query.orders.findMany({ where: eq(orders.userId, userId), limit: size, offset: (page - 1) * size }),
  db.select({ count: sql<number>`count(*)::int` }).from(orders).where(eq(orders.userId, userId)),
]);
```

### Transactions

```typescript
await db.transaction(async (tx) => {
  const [user] = await tx.insert(users).values({ email, hashedPassword }).returning();
  await tx.insert(auditLog).values({ userId: user.id, action: 'register' });
});
```

If anything throws, the transaction rolls back.

Set isolation level:

```typescript
await db.transaction(async (tx) => { ... }, { isolationLevel: 'serializable' });
```

### Raw SQL

```typescript
import { sql } from 'drizzle-orm';

const rows = await db.execute<{ count: number }>(sql`
  SELECT COUNT(*)::int as count FROM orders WHERE created_at > ${since}
`);
```

The `${value}` interpolation is parameterized — safe.

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| `BigInt` doesn't `JSON.stringify` | Add `BigInt.prototype.toJSON = function() { return this.toString(); }` once at boot |
| Connection pool exhaustion | Tune `postgres()` `max:` to fit your app's concurrency |
| `findFirst` returns `undefined`, code expects truthy | Be explicit: `if (!user) throw new NotFound(...)` |
| Decimal precision loss | Use `bigint` for cents, never `numeric` cast through JS `number` |
| Slow `findMany` with deep `with` | Drizzle issues separate queries per relation — sometimes you want a single join (use `select` + manual join) |
| Migrations drift from schema | `drizzle-kit check` in CI; generate fails if uncommitted schema changes |
| Schema imports in test affect prod | Use a separate test DB; never share connection strings |

## Hand-written queries when Drizzle isn't enough

For complex queries (window functions, recursive CTEs, full-text search), drop to raw SQL with `sql` template:

```typescript
const results = await db.execute(sql`
  SELECT user_id, COUNT(*) as order_count, SUM(total_cents) as total
  FROM orders
  WHERE created_at > ${since}
  GROUP BY user_id
  HAVING COUNT(*) > 5
  ORDER BY total DESC
  LIMIT 100
`);
```

## Multi-tenancy

If your tables have a `tenantId`, every query must filter on it. With factories:

```typescript
export function makeUsersRepository(db: Database, tenantId: string) {
  return {
    findByEmail(email: string) {
      return db.query.users.findFirst({
        where: and(eq(users.tenantId, tenantId), eq(users.email, email)),
      });
    },
  };
}
```

Build the repo per-request (with `tenantId` from `req.user.tenantId`). Or: enable Postgres Row-Level Security and let the DB enforce.

## Schema-driven types in shared packages

If your frontend can use Node types, share the schema types:

```typescript
// in a shared package
export type { User, NewUser } from '@your-org/db-schema';
```

This gives the frontend exact ORM-derived types. Be careful: don't expose internal columns.

## Drizzle Studio

```bash
pnpm drizzle-kit studio
```

Browser UI for inspecting and editing rows. Useful in dev — never use against prod.
