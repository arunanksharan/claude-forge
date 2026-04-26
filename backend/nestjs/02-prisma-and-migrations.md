# Prisma + Migrations

> Schema design, migrations, transactions, common queries, gotchas.

## Why Prisma (and the alternatives)

| Option | Verdict |
|--------|---------|
| **Prisma** | Best DX, type-safe queries, strong migration story, big community. The default. |
| **Drizzle** | Closer-to-SQL, smaller runtime, no codegen step. Pick if you want minimal magic. |
| **TypeORM** | Mature but messy. Use only for legacy projects. |
| **MikroORM** | Good design, smaller community. Fine, but Prisma is more discoverable. |
| **Sequelize** | Worse types, slower. Skip. |
| Raw SQL via **Kysely** | Type-safe SQL builder. Pair with raw migrations. Niche but excellent. |

For new Nest projects: **Prisma**. For minimal-magic preference: **Drizzle**. Don't mix.

## Prisma schema basics

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

  orders         Order[]
  sessions       Session[]

  @@map("users")
  @@index([isActive, createdAt])
}

model Order {
  id         String      @id @default(uuid()) @db.Uuid
  userId     String      @db.Uuid
  totalCents BigInt
  status     OrderStatus @default(PENDING)
  createdAt  DateTime    @default(now())
  updatedAt  DateTime    @updatedAt

  user       User        @relation(fields: [userId], references: [id], onDelete: Cascade)
  items      OrderItem[]

  @@map("orders")
  @@index([userId, createdAt(sort: Desc)])
  @@index([status])
}

enum Role { USER ADMIN }
enum OrderStatus { PENDING PAID SHIPPED CANCELLED }
```

### Conventions

- **`@@map("users")`** — table is `users`, model is `User`. Snake_case in DB, PascalCase in code.
- **`@@index`** — declare indexes you'll actually use. Don't index everything.
- **`onDelete: Cascade`** — explicit about what happens to children. Default is `NoAction` (DB will fail).
- **`@db.Uuid`** — actual Postgres `UUID` column, not `text`. Smaller, indexable.
- **`@updatedAt`** — Prisma updates this on writes; you don't have to.
- **`BigInt` for money** — store cents as `BigInt`. Never `Float`.

## Migrations

```bash
# during dev — interactive, applies to dev DB and creates migration file
pnpm prisma migrate dev --name "add orders table"

# in CI / staging / prod — non-interactive, only applies pending migrations
pnpm prisma migrate deploy

# inspect status
pnpm prisma migrate status
```

`prisma migrate dev` does:

1. Diffs your `schema.prisma` against the dev DB
2. Generates SQL into `prisma/migrations/<timestamp>_<name>/migration.sql`
3. Applies it

**You must read the generated SQL.** Prisma is good but:

- It can drop and recreate columns when it could ALTER
- It doesn't know about online-DDL concerns (index concurrently, etc.)
- It doesn't write data migrations — those are separate

### Editing generated migrations

Often necessary. To make an index concurrent on Postgres:

```sql
-- migration.sql
CREATE INDEX CONCURRENTLY "orders_user_id_created_at_idx" ON "orders"("userId", "createdAt" DESC);
```

For changes that aren't in `schema.prisma` (data backfills, raw SQL):

```bash
pnpm prisma migrate dev --create-only --name "backfill order totals"
# edit the generated SQL by hand
pnpm prisma migrate dev
```

### Migration discipline (same as the FastAPI guide)

| Rule | Why |
|------|-----|
| One migration per merged PR | Easier review/rebase/revert |
| Read the generated SQL | Prisma misses things |
| Never edit a merged migration | Create a new one |
| Backfill before constraint | nullable column → backfill → NOT NULL is three migrations |
| Test on prod-sized snapshot | 2s on dev can be 2hr on prod |
| Concurrent index creation | Use the SQL `CONCURRENTLY` keyword for big tables |

## Querying patterns

### Basic CRUD

```typescript
// findUnique on a unique field
const user = await prisma.user.findUnique({ where: { email } });

// findFirst with arbitrary filter
const recent = await prisma.order.findFirst({
  where: { userId, status: 'PAID' },
  orderBy: { createdAt: 'desc' },
});

// create
const user = await prisma.user.create({
  data: { email, hashedPassword },
});

// update
await prisma.user.update({
  where: { id: userId },
  data: { isActive: false },
});

// upsert
await prisma.user.upsert({
  where: { email },
  update: { lastSeenAt: new Date() },
  create: { email, hashedPassword },
});

// delete
await prisma.user.delete({ where: { id: userId } });
```

### Eager loading via `include`

```typescript
const user = await prisma.user.findUnique({
  where: { id },
  include: {
    orders: {
      where: { status: 'PAID' },
      orderBy: { createdAt: 'desc' },
      take: 10,
      include: { items: true },
    },
  },
});
```

Prisma issues efficient queries (one per relation, joined where possible). N+1 is structurally hard to write.

### Pagination

**Cursor pagination** for unbounded lists:

```typescript
const orders = await prisma.order.findMany({
  where: { userId },
  orderBy: { id: 'asc' },
  take: 50,
  ...(cursor && { skip: 1, cursor: { id: cursor } }),
});
```

**Offset pagination** for finite admin tables:

```typescript
const [items, total] = await Promise.all([
  prisma.order.findMany({ skip: (page - 1) * size, take: size }),
  prisma.order.count(),
]);
```

### Transactions

Two flavors.

**Sequential transaction** (when one query depends on another):

```typescript
const user = await prisma.$transaction(async (tx) => {
  const u = await tx.user.create({ data: { email, hashedPassword } });
  await tx.auditLog.create({ data: { userId: u.id, action: 'register' } });
  return u;
});
```

**Batched transaction** (when independent and you want them atomic):

```typescript
await prisma.$transaction([
  prisma.user.update({ where: { id }, data: { isActive: false } }),
  prisma.session.deleteMany({ where: { userId: id } }),
]);
```

Set isolation level when needed:

```typescript
await prisma.$transaction(async (tx) => { ... }, {
  isolationLevel: Prisma.TransactionIsolationLevel.Serializable,
  timeout: 10_000,
  maxWait: 5_000,
});
```

### Raw SQL

When Prisma's API isn't enough:

```typescript
// safe — parameterized
const rows = await prisma.$queryRaw<{ count: number }[]>`
  SELECT COUNT(*)::int as count
  FROM orders
  WHERE created_at > ${since}
`;

// when you need to interpolate identifiers (be very careful):
const tableName = Prisma.sql`"orders"`;
await prisma.$executeRaw`VACUUM ANALYZE ${tableName}`;
```

Never concatenate user input into raw SQL. Use the tagged template — it parameterizes.

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| `BigInt` doesn't `JSON.stringify` | Set up a serializer: `BigInt.prototype.toJSON = function() { return this.toString(); }` once at boot, or convert in the response DTO |
| `findUnique` returns `null` and you forget to handle it | Use `findUniqueOrThrow` when you genuinely expect it to exist |
| Decimal precision loss | Use `Decimal` from `@prisma/client/runtime/library`, not `number` |
| Slow on large `include` chains | Move to two queries; or use `select` to narrow what's loaded |
| Connection pool exhaustion | Set `connection_limit` in the URL: `?connection_limit=20`. Defaults to `num_cpus * 2 + 1`. |
| Prisma logs SQL but slow | `prisma.$on('query', ...)` is expensive — only enable in dev |
| Migration `db push` used in prod | `db push` skips migration history. Only for prototyping. Always `migrate dev` then `migrate deploy`. |
| Reset wipes the DB | `migrate reset` drops everything. Never run on prod. |

## PgBouncer / connection pooling

If you put a PgBouncer in front of Postgres in **transaction mode**, prepared statements break:

```
DATABASE_URL="postgresql://...?pgbouncer=true&connection_limit=1"
```

The `pgbouncer=true` flag tells Prisma to disable prepared statement caching.

For serverless (Vercel, Lambda), use:

- Prisma's **Accelerate** (managed pooler), or
- **Supabase Pooler / Neon Pooler** (PgBouncer in transaction mode), or
- A long-lived connection via Lambda extensions

## Soft delete

Prisma doesn't have built-in soft delete. Three options:

1. **Manual filter everywhere**: `where: { deletedAt: null }` — verbose, error-prone
2. **Prisma middleware** (`prisma.$use(...)`) that auto-injects the filter — global but easy to forget when needed
3. **Don't soft delete** — instead, have an explicit `archived` flag if business needs it, or move rows to an `archive` table

I lean toward "don't soft delete" — it's a common source of bugs (FK constraints, "why is this user appearing twice", reporting). Use real deletion + audit log if you need history.

## Multi-tenancy

For row-level multi-tenancy, every query needs a tenant filter. Either:

- **Discipline + code review** — `where: { tenantId, ... }` on every query
- **Custom Prisma client wrapper** that injects the tenant from request context
- **Postgres Row-Level Security (RLS)** — DB-level enforcement, harder to set up but airtight

For SaaS scale, RLS is worth the setup cost. For internal apps, discipline is fine.

## Seeds

```typescript
// prisma/seed.ts
import { PrismaClient } from '@prisma/client';
import * as bcrypt from 'bcrypt';

const prisma = new PrismaClient();

async function main() {
  await prisma.user.upsert({
    where: { email: 'admin@example.com' },
    update: {},
    create: {
      email: 'admin@example.com',
      hashedPassword: await bcrypt.hash('changeme', 12),
      role: 'ADMIN',
    },
  });
}

main()
  .catch((e) => { console.error(e); process.exit(1); })
  .finally(() => prisma.$disconnect());
```

```json
// package.json
"prisma": {
  "seed": "ts-node prisma/seed.ts"
}
```

```bash
pnpm prisma db seed
```
