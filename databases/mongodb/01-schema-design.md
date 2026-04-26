# MongoDB Schema Design

> Embed-vs-reference, validators, naming, common patterns. The decisions that determine whether MongoDB feels right or fights you.

## The core question — embed or reference?

**Embed** when:
- Child has no independent identity (an order's line items)
- You always read parent + child together
- Child cardinality is **bounded** (a comment with reactions, not a comment with millions of replies)
- 1-to-few or 1-to-many bounded
- Embedded data won't push you near the 16MB doc limit

**Reference** when:
- Child has its own life cycle (comments on a post — referenced from anywhere)
- Many-to-many
- Child can be very large
- You frequently update the child without touching the parent
- Need transactional updates across multiple parents

```javascript
// embedded — order with line items (bounded, always read together)
{
  _id: ObjectId(),
  userId: ObjectId(),
  status: "paid",
  items: [
    { sku: "A1", quantity: 2, priceCents: 1000, name: "Widget" },
    { sku: "B2", quantity: 1, priceCents: 5000, name: "Gadget" }
  ],
  totalCents: 7000,
  shippingAddress: { street: "...", city: "...", zip: "..." },
  createdAt: ISODate(),
  updatedAt: ISODate()
}

// referenced — chat messages reference user + channel
{
  _id: ObjectId(),
  channelId: ObjectId(),       // reference
  userId: ObjectId(),          // reference
  text: "...",
  reactions: [                 // bounded embed (max ~20 reactions per msg)
    { userId: ObjectId(), emoji: "👍" }
  ],
  createdAt: ISODate()
}
```

## Naming conventions

| Object | Convention | Example |
|--------|-----------|---------|
| Collection | `camelCase` (or snake_case if your team prefers) | `users`, `orderItems` |
| Field | `camelCase` | `email`, `createdAt` |
| `_id` | `ObjectId` (default) or `UUID` | both indexed by default |
| References | `<entity>Id` | `userId`, `channelId` |
| Timestamps | `createdAt`, `updatedAt` | always ISODate |

Many languages auto-map (Mongoose, Beanie). Be consistent.

## `_id` — ObjectId vs UUID

| Type | Pros | Cons |
|------|------|------|
| **ObjectId** (default) | 12 bytes, sortable by creation, indexed by default, Mongo-native | Specific to Mongo; harder to use in URLs |
| **UUID v7** | URL-safe, sortable, portable across systems | 16 bytes, must opt in |
| **Custom string** | Domain-meaningful (e.g., slug) | Risk of collision; ensure unique |

For most apps: **ObjectId** unless you have a reason. For systems that share IDs across services: **UUID v7**.

```javascript
// UUID v7 in Node
import { v7 as uuidv7 } from 'uuid';
db.users.insertOne({ _id: uuidv7(), email: '...' });
```

## Standard fields

```javascript
{
  _id: ObjectId(),
  tenantId: ObjectId(),         // multi-tenant filter
  createdAt: ISODate(),
  updatedAt: ISODate(),
  // ... data ...
  schemaVersion: 1               // bump when shape changes
}
```

`schemaVersion` lets you migrate documents lazily — read code handles each version.

## JSON Schema validators

MongoDB allows JSON Schema enforcement at the collection level:

```javascript
db.createCollection("users", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["email", "tenantId", "createdAt"],
      properties: {
        email: {
          bsonType: "string",
          pattern: "^[^@]+@[^@]+\\..+$",
          maxLength: 320
        },
        hashedPassword: {
          bsonType: "string",
          minLength: 60                // bcrypt outputs 60 chars
        },
        tenantId: { bsonType: "objectId" },
        isActive: { bsonType: "bool" },
        roles: {
          bsonType: "array",
          items: { bsonType: "string", enum: ["user", "admin"] }
        },
        createdAt: { bsonType: "date" },
        updatedAt: { bsonType: "date" }
      },
      additionalProperties: false      // strict
    }
  },
  validationAction: "error",          // reject invalid writes
  validationLevel: "strict"            // validate all documents
});
```

Even with app-level validation (Pydantic / Mongoose), collection validators catch direct writes from migration scripts, ops shells, malformed data. **Always add them.**

## Indexes

```javascript
// single field, unique
db.users.createIndex({ email: 1 }, { unique: true });

// compound — order matters (Equality, Sort, Range = ESR)
db.orders.createIndex({ userId: 1, createdAt: -1 });

// partial — index only matching docs (smaller, faster)
db.users.createIndex(
  { email: 1 },
  { partialFilterExpression: { isActive: true }, unique: true }
);

// text search
db.articles.createIndex({ title: "text", body: "text" });

// TTL — auto-delete after expiry
db.sessions.createIndex({ expiresAt: 1 }, { expireAfterSeconds: 0 });

// 2dsphere for geo
db.places.createIndex({ location: "2dsphere" });

// wildcard — index all fields under a path
db.events.createIndex({ "payload.$**": 1 });
```

### ESR rule (Equality, Sort, Range)

For compound indexes:
1. Equality fields first (`status: 'paid'`)
2. Sort fields next (`createdAt: -1`)
3. Range fields last (`amount: { $gt: 100 }`)

```javascript
// query: find user X's paid orders, sorted by created date, with amount > 100
// good index: { userId: 1, status: 1, createdAt: -1, amount: 1 }
//             E         E           S                   R
```

Inspect with `explain()`:

```javascript
db.orders.find({ userId, status: "paid" }).sort({ createdAt: -1 }).explain("executionStats")
// look at: winningPlan.stage = IXSCAN (good) or COLLSCAN (bad)
```

## Common patterns

### Multi-tenancy

Filter every query by `tenantId`. Wrap your data access:

```typescript
class TenantScopedRepo {
  constructor(private db: Db, private tenantId: ObjectId) {}

  async findUsers(filter = {}) {
    return this.db.collection('users').find({ ...filter, tenantId: this.tenantId }).toArray();
  }
  // ...
}
```

For stricter isolation, use one collection per tenant (named like `users_${tenantId}`) — adds operational complexity, only worth it for compliance.

### Audit log

Append-only collection:

```javascript
{
  _id: ObjectId(),
  tenantId: ObjectId(),
  actorId: ObjectId(),               // who did it
  action: "user.created",
  entityType: "user",
  entityId: ObjectId(),
  beforeState: { ... },              // null for create
  afterState: { ... },               // null for delete
  metadata: { ip: "...", requestId: "..." },
  createdAt: ISODate()
}
```

Index by `entityType + entityId + createdAt` for entity history; by `actorId + createdAt` for "what did this user do."

### Soft delete

```javascript
{ ..., deletedAt: ISODate() }
```

Plus a partial index that excludes deleted:

```javascript
db.users.createIndex(
  { email: 1 },
  { partialFilterExpression: { deletedAt: { $exists: false } }, unique: true }
);
```

Same caveats as Postgres — soft delete causes more bugs than it solves. Prefer real delete + audit log.

### Versioned documents

```javascript
{
  _id: ObjectId(),
  schemaVersion: 2,
  // v1 fields no longer used
  // v2 fields current
  ...
}
```

Read code handles both versions; write code only writes v2. Migrate lazily (rewrite v1 → v2 on next write) or batch (background script).

### Polymorphic with discriminator

```javascript
db.notifications.insertOne({
  type: "email",
  recipient: "user@example.com",
  subject: "...",
  body: "..."
});

db.notifications.insertOne({
  type: "sms",
  phone: "+1...",
  message: "..."
});
```

Index `{ type: 1, ... }`. Validate per-type via `oneOf` in JSON Schema.

### Bucketing time-series

For high-volume time-series, pre-bucket per hour/day:

```javascript
{
  _id: ObjectId(),
  metric: "page_view",
  dimensions: { url: "/", country: "US" },
  hour: ISODate("2026-04-26T14:00:00Z"),
  count: 1342,
  samples: [...]                       // optional sample events
}
```

Or use **MongoDB Time Series Collections** (built-in, 5.0+):

```javascript
db.createCollection("metrics", {
  timeseries: {
    timeField: "ts",
    metaField: "tags",
    granularity: "hours"
  }
});
```

## Anti-patterns

| Pattern | Why bad | Use instead |
|---------|---------|-------------|
| Unbounded array embedded | Hits 16MB; slow updates | Reference collection |
| `$lookup` everywhere | Slow joins; defeats Mongo's denormalization | Denormalize; or move to Postgres |
| Missing indexes on filter fields | COLLSCAN at scale | Always profile + index |
| Unique constraint via app code | Race conditions | Use unique index |
| Embedding documents that will be updated frequently | Whole doc rewritten on each update | Reference |
| 100K-element arrays | Slow `$push`, `$pull`, `$slice` | Cap arrays, paginate |
| Strings as `_id` from user input | Collisions, control chars | Use ObjectId / UUID |
| Storing large binaries (images) | Bloats docs; replication slow | GridFS for files; better, S3 |

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| Embedded array growing forever | Cap at insert time (`$slice` in `$push`) or reference |
| Schema drift across documents | Add JSON Schema validator early |
| Slow `$lookup` | Index the foreign key; or denormalize the joined fields |
| `find({ a: 1, b: 1 })` not using compound index | Order matters — query fields must align with leading index columns |
| Decimal precision lost | Use `Decimal128`, not `double` |
| `_id` collisions when generating client-side | Let Mongo generate `ObjectId` by default |
| Document hits 16MB limit | Either reference, or split into multiple docs |
| Long-running aggregation runs out of memory | `allowDiskUse: true` |
| Wrong compound index — only first column query works | Add the right one or use `IndexHint` to force |
| Validators rejected migration scripts | Use `validationAction: "warn"` during migrations, switch back after |
