# MongoDB Queries & Aggregation

> Find, aggregation pipelines, indexing (ESR rule), `$lookup`, transactions. The query patterns that scale.

## Find — basics

```javascript
// one
db.users.findOne({ email: "alice@example.com" });

// many with filter
db.orders.find({
  userId: ObjectId(uid),
  status: "paid",
  createdAt: { $gte: ISODate("2026-01-01") }
}).sort({ createdAt: -1 }).limit(10);

// projection (fetch only some fields)
db.users.find({}, { projection: { email: 1, name: 1, _id: 0 } });

// count
db.orders.countDocuments({ status: "paid" });
db.orders.estimatedDocumentCount();   // fast, uses metadata, less accurate
```

## Operators cheatsheet

| Op | Meaning |
|----|---------|
| `$eq`, `$ne`, `$gt`, `$gte`, `$lt`, `$lte` | comparison |
| `$in`, `$nin` | in array |
| `$and`, `$or`, `$not`, `$nor` | logical |
| `$exists` | field exists |
| `$type` | bson type check |
| `$regex` | pattern match (slow without index; use $text for FTS) |
| `$all` | array contains all |
| `$elemMatch` | array element matches (compound condition on one element) |
| `$size` | array length |
| `$expr` | use aggregation expression in find |

```javascript
// elemMatch — find orders where ANY item has sku="A1" AND quantity > 5
db.orders.find({
  items: { $elemMatch: { sku: "A1", quantity: { $gt: 5 } } }
});

// $expr — compare two fields
db.users.find({ $expr: { $gt: ["$lastSeen", "$createdAt"] } });
```

## Update operators

```javascript
// update single
db.users.updateOne(
  { _id: ObjectId(uid) },
  {
    $set: { isActive: false, deactivatedAt: new Date() },
    $unset: { sessionToken: "" },
    $inc: { updateCount: 1 }
  }
);

// upsert
db.sessions.updateOne(
  { _id: sessionId },
  {
    $set: { lastSeenAt: new Date() },
    $setOnInsert: { userId, createdAt: new Date() }
  },
  { upsert: true }
);

// array updates
db.posts.updateOne(
  { _id: postId },
  { $push: { reactions: { userId, emoji: "👍" } } }    // append
);

db.posts.updateOne(
  { _id: postId, "comments._id": commentId },
  { $set: { "comments.$.text": "edited" } }            // positional $
);

db.posts.updateOne(
  { _id: postId },
  { $pull: { comments: { _id: commentId } } }          // remove element
);

// bulk
db.orders.bulkWrite([
  { updateOne: { filter: { _id: id1 }, update: { $set: { status: "paid" } } } },
  { updateOne: { filter: { _id: id2 }, update: { $set: { status: "paid" } } } },
  { insertOne: { document: { ... } } }
]);
```

## Aggregation pipelines

The pipeline is a series of stages; each transforms the document stream.

```javascript
db.orders.aggregate([
  // 1. filter (always first when possible — use indexes)
  { $match: { status: "paid", createdAt: { $gte: lastMonth } } },

  // 2. group + aggregate
  { $group: {
      _id: "$userId",
      orderCount: { $sum: 1 },
      totalCents: { $sum: "$totalCents" },
      lastOrder: { $max: "$createdAt" }
  }},

  // 3. sort
  { $sort: { totalCents: -1 } },

  // 4. limit
  { $limit: 100 },

  // 5. join
  { $lookup: {
      from: "users",
      localField: "_id",
      foreignField: "_id",
      as: "user"
  }},

  // 6. shape output
  { $project: {
      userId: "$_id",
      _id: 0,
      orderCount: 1,
      totalCents: 1,
      lastOrder: 1,
      "user.email": 1
  }}
]);
```

### Common stages

| Stage | Purpose |
|-------|---------|
| `$match` | Filter (use first; uses indexes) |
| `$project` | Reshape; drop fields |
| `$group` | Aggregate by key |
| `$sort` | Sort (uses index if first stage and matches) |
| `$limit`, `$skip` | Pagination |
| `$lookup` | Join another collection |
| `$unwind` | Explode array into multiple docs |
| `$facet` | Multiple parallel sub-pipelines |
| `$out`, `$merge` | Write results to a collection |
| `$addFields` | Add computed fields |
| `$set`, `$unset` | Update documents in pipeline |

### `$lookup` — joins (with caution)

```javascript
{ $lookup: {
    from: "users",
    localField: "userId",
    foreignField: "_id",
    as: "user"
}}
```

Each input doc gets a `user` array (because `$lookup` returns an array — even for one match).

Followed by `{ $unwind: "$user" }` if you want a single object.

**Performance**: `$lookup` is slow on big collections without an index on `foreignField`. If you `$lookup` constantly, you're doing relational queries — consider Postgres.

### `$facet` — multiple aggregations in one pass

```javascript
db.orders.aggregate([
  { $match: { status: "paid" } },
  { $facet: {
      byMonth: [
        { $group: { _id: { $month: "$createdAt" }, total: { $sum: "$totalCents" } } }
      ],
      byUser: [
        { $group: { _id: "$userId", count: { $sum: 1 } } },
        { $sort: { count: -1 } },
        { $limit: 10 }
      ],
      total: [
        { $count: "value" }
      ]
  }}
]);
```

Returns one doc with all three results — useful for dashboards.

## Pagination

### Cursor over `_id` (preferred)

```javascript
// page 1
const page1 = await db.messages.find({ channelId })
  .sort({ _id: -1 })
  .limit(50).toArray();

// page 2 — cursor = last _id of page 1
const lastId = page1[page1.length - 1]._id;
const page2 = await db.messages.find({ channelId, _id: { $lt: lastId } })
  .sort({ _id: -1 })
  .limit(50).toArray();
```

ObjectIds are sortable by creation time → stable cursor pagination + chronological sort for free.

### Skip+limit (only for small data sets)

```javascript
db.users.find({}).sort({ createdAt: -1 }).skip(page * 50).limit(50);
```

`skip` is O(N) — slow at high offsets. Don't use for unbounded lists.

## Transactions

MongoDB 4.0+ supports multi-document ACID transactions on replica sets.

```javascript
const session = client.startSession();
try {
  await session.withTransaction(async () => {
    await users.updateOne({ _id }, { $inc: { credits: -100 } }, { session });
    await ledger.insertOne({ userId: _id, change: -100, reason: "purchase" }, { session });
  }, {
    readPreference: "primary",
    readConcern: { level: "majority" },
    writeConcern: { w: "majority", j: true }
  });
} finally {
  await session.endSession();
}
```

**Multi-doc transactions are slower than single-doc updates.** Design schema (embedding) to avoid them when possible. Prefer schema such that every operation is atomic on a single doc.

## Indexes — when used

```javascript
db.orders.find({ userId, status }).explain("executionStats");
```

Look at `winningPlan.stage`:
- `IXSCAN` — index used (good)
- `COLLSCAN` — full scan (bad on big data)
- `FETCH + IXSCAN` — index found doc IDs, then fetched docs

`executionStats.totalKeysExamined` vs `nReturned` — should be close. If `examined >> returned`, the index isn't selective enough.

## Text search (built-in)

```javascript
db.articles.createIndex({ title: "text", body: "text" });

db.articles.find(
  { $text: { $search: "postgresql vector" } },
  { score: { $meta: "textScore" } }
).sort({ score: { $meta: "textScore" } });
```

Decent for simple search. For production search at scale, use Atlas Search (MongoDB's wrapped Elasticsearch) — much better.

## Atlas Search (Atlas-only)

If you're on Atlas, use Atlas Search for production text/vector search:

```javascript
db.articles.aggregate([
  {
    $search: {
      index: "default",
      compound: {
        must: [{ text: { query: "postgresql", path: "title", score: { boost: { value: 3 } } } }],
        should: [{ text: { query: "vector", path: "body" } }]
      }
    }
  },
  { $limit: 20 }
]);
```

Atlas Search supports vector embeddings (`knnBeta` operator), facets, autocomplete, and more.

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| `find().toArray()` on huge collection | Use cursor (`for await`) for streaming |
| `$where: "this.field == ..."` | Slow JS evaluation — use proper operators |
| Regex without prefix anchor (`/^foo/`) | Can't use index — anchor or use `$text` |
| Slow aggregation | `$match` first, then `$project`, then `$group`/`$lookup` |
| `$lookup` without index | Always index `foreignField` |
| TTL not deleting | TTL has minute-scale precision; large backlog gets cleared in batches |
| `$inc` on non-existent field | Auto-creates with the increment value (usually fine) |
| `$set` overwrites instead of merging | Use dot notation: `$set: { "address.city": "..." }` |
| Dates stored as strings | Always BSON `Date` — sortable, indexable |
| 16MB doc limit hit | Reference instead of embed; or use GridFS for files |
| `connection refused` from Docker | Use container hostname not localhost; check network |
| Stale reads after write | Use `readConcern: "majority"` + `writeConcern: { w: "majority" }` |
