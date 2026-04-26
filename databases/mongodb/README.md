# MongoDB — claudeforge guide

> When MongoDB is the right choice (less often than people think), and how to use it well when it is.

## When to pick MongoDB over Postgres

| Pick MongoDB | Stay with Postgres |
|--------------|---------------------|
| Documents with deep nested structure that's queried as a unit (chat messages with embedded reactions and attachments) | Anything that decomposes into normalized rows |
| Schema-flexible / fast-evolving structure | Stable schema |
| Read-heavy with shape that fits BSON well | Write-heavy with relational integrity needs |
| You'll never need joins (or rarely) | Joins are a daily occurrence |
| Single-document atomicity is enough | Multi-row transactions are common |
| Geo + time-series + general docs in one DB | Specialized needs (use Postgres + extensions) |

If you're not sure → **use Postgres**. The most common MongoDB regret is "we wish we had used Postgres."

## Versions + hosting

- **MongoDB 7.0+** for new projects
- **MongoDB Atlas** for managed (free tier is generous)
- **Self-hosted** is fine but you become a DBA

## Drivers

| Lang | Driver |
|------|--------|
| Node/TS | **Official `mongodb` driver** (typed) — or **Mongoose** (ODM with schemas) |
| Python | **Motor** (async) on top of pymongo — or **Beanie** (ODM with Pydantic) |

For Python: **Beanie** if you like Pydantic models for documents. **Motor** if you want closer-to-raw control.
For Node: **Mongoose** if you want schemas and middleware. **mongodb driver** if you want Drizzle-like SQL-close minimalism.

## Schema design

### "Embed vs reference" — the core question

**Embed** when:
- Child has no independent identity (an order's line items)
- You always read parent + child together
- Child cardinality is bounded (a comment with reactions, not a comment with millions of replies)
- 1-to-few or 1-to-many bounded

**Reference** when:
- Child has its own life (comments on a post — referenced from anywhere)
- Many-to-many
- Child can be very large (would blow past the 16MB doc limit)
- You frequently update the child without touching the parent

```javascript
// embedded — order with line items
{
  _id: ObjectId(),
  userId: ObjectId(),
  status: "paid",
  items: [
    { sku: "A1", quantity: 2, priceCents: 1000 },
    { sku: "B2", quantity: 1, priceCents: 5000 },
  ],
  totalCents: 7000,
  createdAt: ISODate(),
}

// referenced — chat messages reference user
{
  _id: ObjectId(),
  channelId: ObjectId(),
  userId: ObjectId(),     // reference; lookup user when needed
  text: "...",
  createdAt: ISODate(),
}
```

### IDs

Default `_id: ObjectId()`. ObjectIds are sortable by creation time, indexed by default.

For external compatibility, use UUIDs:

```javascript
{ _id: UUID("...") }
```

### Conventions

- **camelCase** field names (vs Postgres' snake_case) — JS-native
- Use `ObjectId` for `_id` unless you have a reason
- `createdAt`, `updatedAt` always
- Bounded growth: if an array might grow unbounded, reference instead of embed

## Common queries

### Find

```javascript
// one
await users.findOne({ email: "alice@example.com" });

// many with filter
await orders.find({
  userId: ObjectId(uid),
  status: "paid",
  createdAt: { $gte: since },
}).sort({ createdAt: -1 }).limit(10).toArray();

// projection
await users.find({}, { projection: { email: 1, name: 1 } }).toArray();
```

### Insert

```javascript
const result = await users.insertOne({ email, hashedPassword, createdAt: new Date() });
console.log(result.insertedId);

await users.insertMany([{ ... }, { ... }], { ordered: false });   // continue on error
```

### Update

```javascript
await users.updateOne({ _id }, { $set: { isActive: false } });

// upsert
await sessions.updateOne(
  { _id: sessionId },
  { $set: { lastSeenAt: new Date() }, $setOnInsert: { userId, createdAt: new Date() } },
  { upsert: true },
);

// atomic counter
await stats.updateOne({ _id: "global" }, { $inc: { activeUsers: 1 } });
```

### Aggregation pipeline

```javascript
await orders.aggregate([
  { $match: { status: "paid", createdAt: { $gte: lastMonth } } },
  { $group: {
    _id: "$userId",
    orderCount: { $sum: 1 },
    totalCents: { $sum: "$totalCents" },
  }},
  { $sort: { totalCents: -1 } },
  { $limit: 100 },
  { $lookup: {
    from: "users",
    localField: "_id",
    foreignField: "_id",
    as: "user",
  }},
]).toArray();
```

`$lookup` is MongoDB's join. Slow for big collections; design to avoid when you can.

### Transactions

```javascript
const session = client.startSession();
try {
  await session.withTransaction(async () => {
    await users.updateOne({ _id }, { $set: { ... } }, { session });
    await audit.insertOne({ ... }, { session });
  });
} finally {
  await session.endSession();
}
```

Multi-doc transactions work but are slower than single-doc updates. Use sparingly. Prefer schema design that makes operations atomic on a single doc.

## Indexes

```javascript
// single field
await users.createIndex({ email: 1 }, { unique: true });

// compound
await orders.createIndex({ userId: 1, createdAt: -1 });

// text search
await articles.createIndex({ title: "text", body: "text" });

// TTL — auto-delete docs after expiry
await sessions.createIndex({ expiresAt: 1 }, { expireAfterSeconds: 0 });

// partial — index only matching docs
await users.createIndex({ email: 1 }, { partialFilterExpression: { isActive: true } });

// 2dsphere for geo
await places.createIndex({ location: "2dsphere" });
```

Order matters in compound indexes. Use the **ESR rule**: Equality, Sort, Range. Put fields used with `$eq` first, then `sort` fields, then range filters.

```javascript
// query: find orders for user X paid in last week, sorted by createdAt desc
// good: { userId: 1, createdAt: -1 }    -- E (userId), S (createdAt)
// bad:  { createdAt: -1, userId: 1 }    -- can't use index for userId filter
```

Inspect with `explain()`:

```javascript
await orders.find({ userId, status }).explain("executionStats");
```

Look at `winningPlan.stage` — should be `IXSCAN`, not `COLLSCAN`.

## TTL collections

Auto-expire docs (sessions, ephemeral cache, raw events):

```javascript
await sessions.createIndex({ createdAt: 1 }, { expireAfterSeconds: 86400 });   // 24h
```

Or per-doc expiry:

```javascript
await sessions.insertOne({ ..., expiresAt: new Date(Date.now() + 3600_000) });
await sessions.createIndex({ expiresAt: 1 }, { expireAfterSeconds: 0 });
```

A background process scans every minute and deletes expired docs. **Not millisecond-precise**.

## Pagination — cursor over `_id`

```javascript
// first page
const page1 = await messages.find({ channelId }).sort({ _id: -1 }).limit(50).toArray();

// next page
const lastId = page1[page1.length - 1]._id;
const page2 = await messages.find({ channelId, _id: { $lt: lastId } }).sort({ _id: -1 }).limit(50).toArray();
```

ObjectId-based cursors give you stable pagination + sort by creation time for free.

## Schema validation (in MongoDB)

Even with a flexible schema, you can enforce shape:

```javascript
await db.createCollection("users", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["email", "createdAt"],
      properties: {
        email: { bsonType: "string", pattern: "^.+@.+$" },
        createdAt: { bsonType: "date" },
        isActive: { bsonType: "bool" },
      },
    },
  },
  validationAction: "error",
});
```

Useful as a safety net even when your app validates with Pydantic/zod. Catches direct DB writes (migration scripts, ops shell).

## Operations

### Backups

Atlas: automatic snapshots + PITR.

Self-hosted:

```bash
# logical backup
mongodump --uri="mongodb://..." --out=/var/backups/$(date +%F)

# restore
mongorestore --uri="mongodb://..." /var/backups/2026-04-26
```

For sharded / large clusters, use `mongodump` against a secondary, or filesystem snapshots.

### Replica set

Production should always be a 3-node replica set (one primary, two secondaries). Survives any single node loss.

### Sharding

Required only at huge scale (TB-level). If you're considering sharding, you're either at a real scale problem or you've over-modeled.

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| Embedded array growing unbounded | Switch to referenced collection; or cap with `$slice` |
| `find()` returning a cursor, not an array | Always `.toArray()` (with caution — large sets blow memory) |
| Missing index → COLLSCAN at scale | Profile with explain; add indexes |
| `$lookup` slow | Avoid joins — denormalize if hot read path |
| 16MB document limit hit | Embedded data too big — reference instead |
| `_id` collisions when generating client-side | Let MongoDB generate ObjectId by default |
| Unbounded `$or` arrays | Use `$in` for many equality checks |
| Slow aggregation | Use `$match` early, then `$project`, before `$lookup`/`$group` |
| Dates stored as strings | Use real `Date` (BSON date type) — sortable, indexable |
| Decimal precision lost | Use `Decimal128` for money |
| `$inc` on non-existent field | Auto-creates with the increment value — usually fine |
| Connection pool too small | Increase `maxPoolSize` (default 100) for high-concurrency apps |
| Slow startup of a long-running aggregation | Add an `allowDiskUse: true` option for big pipelines |

## When to migrate to Postgres

If you find yourself:
- Doing many `$lookup`s in your aggregations
- Wishing you had foreign keys
- Worrying about consistency across documents
- Reaching for transactions all the time
- Building a relational model in MongoDB

…you've outgrown MongoDB for this workload. Move to Postgres before the migration cost becomes painful.
