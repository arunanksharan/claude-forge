# MongoDB Language Clients

> Motor / Beanie (Python), official `mongodb` driver / Mongoose (Node), with concrete connection patterns.

## Driver picks

| Language | Driver | Notes |
|----------|--------|-------|
| **Python (async)** | **Motor** (async PyMongo) — or **Beanie** (Pydantic ODM on Motor) | Beanie if you like Pydantic models |
| **Python (sync)** | PyMongo | rarely needed in 2026 |
| **Node** | Official **`mongodb`** driver — or **Mongoose** | Driver for typed minimalism; Mongoose for schemas + middleware |
| **Go** | Official `go.mongodb.org/mongo-driver` | |
| **Java** | Official `org.mongodb:mongodb-driver-sync` or `-reactivestreams` | |
| **Rust** | `mongodb` crate | |

## Python — Motor (async)

```python
from motor.motor_asyncio import AsyncIOMotorClient

client = AsyncIOMotorClient(
    settings.mongodb_url,
    maxPoolSize=50,
    minPoolSize=10,
    serverSelectionTimeoutMS=5_000,
    appName="{{project-slug}}",
)
db = client[settings.mongodb_database]

# basic operations
async def get_user(user_id: ObjectId):
    return await db.users.find_one({"_id": user_id})

async def list_orders(user_id: ObjectId, limit: int = 50):
    cursor = db.orders.find({"userId": user_id}).sort("_id", -1).limit(limit)
    return await cursor.to_list(length=limit)

async def stream_events():
    async for event in db.events.find({"processed": False}):
        await process(event)

# transaction (replica set required)
async def transfer(from_id, to_id, amount):
    async with await client.start_session() as session:
        async with session.start_transaction():
            await db.accounts.update_one(
                {"_id": from_id},
                {"$inc": {"balance": -amount}},
                session=session,
            )
            await db.accounts.update_one(
                {"_id": to_id},
                {"$inc": {"balance": amount}},
                session=session,
            )
```

### Lifecycle

```python
@asynccontextmanager
async def lifespan(app: FastAPI):
    yield
    client.close()       # await not needed — synchronous
```

## Python — Beanie (Pydantic ODM)

```python
from beanie import Document, init_beanie, Indexed
from pydantic import BaseModel, EmailStr
from datetime import datetime, UTC

class User(Document):
    email: Indexed(EmailStr, unique=True)
    hashed_password: str
    is_active: bool = True
    tenant_id: ObjectId
    created_at: datetime = Field(default_factory=lambda: datetime.now(UTC))
    updated_at: datetime = Field(default_factory=lambda: datetime.now(UTC))

    class Settings:
        name = "users"
        indexes = [
            [("tenant_id", 1), ("created_at", -1)],
        ]

# bootstrap
async def init():
    client = AsyncIOMotorClient(settings.mongodb_url)
    await init_beanie(database=client[settings.mongodb_database], document_models=[User, Order])

# usage
user = await User.find_one(User.email == "alice@example.com")
await User(email="bob@example.com", hashed_password="...", tenant_id=tid).insert()
await user.set({User.is_active: False})
users = await User.find(User.tenant_id == tid).sort(-User.created_at).limit(10).to_list()
```

Beanie gives you Pydantic-typed documents + a Django-ish query API. Built on Motor underneath.

## Node — official `mongodb` driver

```typescript
import { MongoClient, ObjectId } from 'mongodb';

const client = new MongoClient(process.env.MONGODB_URL!, {
  maxPoolSize: 50,
  minPoolSize: 10,
  serverSelectionTimeoutMS: 5_000,
  appName: '{{project-slug}}',
});

await client.connect();
export const db = client.db(process.env.MONGODB_DATABASE);

// typed collection
interface User {
  _id?: ObjectId;
  email: string;
  hashedPassword: string;
  isActive: boolean;
  tenantId: ObjectId;
  createdAt: Date;
  updatedAt: Date;
}

const users = db.collection<User>('users');

// query
const user = await users.findOne({ email: 'alice@example.com' });

const recent = await users.find({ tenantId, isActive: true })
  .sort({ createdAt: -1 })
  .limit(10)
  .toArray();

// insert
const result = await users.insertOne({
  email,
  hashedPassword,
  isActive: true,
  tenantId,
  createdAt: new Date(),
  updatedAt: new Date(),
} as User);
console.log(result.insertedId);

// update
await users.updateOne(
  { _id: userId },
  { $set: { isActive: false, updatedAt: new Date() } }
);

// transaction
const session = client.startSession();
try {
  await session.withTransaction(async () => {
    await accounts.updateOne({ _id: fromId }, { $inc: { balance: -amount } }, { session });
    await accounts.updateOne({ _id: toId }, { $inc: { balance: amount } }, { session });
  });
} finally {
  await session.endSession();
}

// graceful shutdown
process.on('SIGTERM', async () => {
  await client.close();
  process.exit(0);
});
```

## Node — Mongoose

Schemas + middleware + plugins. More opinionated than the raw driver.

```typescript
import mongoose, { Schema, model } from 'mongoose';

const userSchema = new Schema({
  email: { type: String, required: true, unique: true, lowercase: true, trim: true },
  hashedPassword: { type: String, required: true },
  isActive: { type: Boolean, default: true },
  tenantId: { type: Schema.Types.ObjectId, ref: 'Tenant', required: true, index: true },
}, { timestamps: true });

userSchema.index({ tenantId: 1, createdAt: -1 });

userSchema.pre('save', function() {
  // example: lowercase email
  if (this.isModified('email')) this.email = this.email.toLowerCase();
});

export const User = model('User', userSchema);

// usage
await mongoose.connect(process.env.MONGODB_URL!);
const user = await User.findOne({ email: 'alice@example.com' }).lean();
const newUser = await User.create({ email, hashedPassword, tenantId });
```

`.lean()` returns plain objects (no Mongoose document overhead) — significantly faster for read-only queries.

### Mongoose vs raw driver — when to pick which

| Pick Mongoose | Pick raw driver |
|---------------|-----------------|
| You want schema enforcement at app level | You have collection validators |
| Middleware (pre-save hooks, post-find) | Don't need lifecycle hooks |
| Population (Mongoose's `$lookup` shortcut) | Comfortable writing aggregation |
| Plugin ecosystem (mongoose-paginate, etc.) | Don't need plugins |
| Performance is OK | Want every microsecond |

For Nest projects: `@nestjs/mongoose` is the idiomatic wrapper.

## Go — official driver

```go
import (
    "context"
    "go.mongodb.org/mongo-driver/v2/mongo"
    "go.mongodb.org/mongo-driver/v2/mongo/options"
)

client, err := mongo.Connect(options.Client().ApplyURI(os.Getenv("MONGODB_URL")))
if err != nil { log.Fatal(err) }
defer client.Disconnect(ctx)

db := client.Database("app")
users := db.Collection("users")

// find
var user User
err = users.FindOne(ctx, bson.M{"email": email}).Decode(&user)

// insert
res, err := users.InsertOne(ctx, bson.M{
    "email": email,
    "hashedPassword": hashed,
    "tenantId": tenantId,
    "createdAt": time.Now(),
})

// transaction
session, err := client.StartSession()
defer session.EndSession(ctx)
err = mongo.WithSession(ctx, session, func(sCtx mongo.SessionContext) error {
    if err := session.StartTransaction(); err != nil { return err }
    // ... ops ...
    return session.CommitTransaction(sCtx)
})
```

## Connection string forms

```
# basic
mongodb://user:pass@host:27017/dbname?authSource=admin

# replica set
mongodb://user:pass@host1:27017,host2:27017,host3:27017/dbname?replicaSet=rs0&authSource=admin

# Atlas SRV
mongodb+srv://user:pass@cluster0.abc12.mongodb.net/dbname?retryWrites=true&w=majority

# read preference
mongodb://...?readPreference=secondaryPreferred&maxStalenessSeconds=120

# write concern
mongodb://...?w=majority&journal=true
```

## Health check

```python
async def health() -> dict:
    try:
        await client.admin.command("ping")
        return {"status": "ok"}
    except Exception as e:
        return {"status": "degraded", "error": str(e)}
```

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| Forgot to `await` cursor `.to_list()` | Cursor has no data until iterated |
| Single client per request | Reuse one client globally; pool handles concurrency |
| `MongoClient` connection in module init blocks startup | Connect lazily in app `lifespan` / startup hook |
| Mongoose schema mismatch with collection | Use `strict: false` to ignore; or sync via `validate()` |
| `Decimal` precision loss in JS | Use `Decimal128` BSON type |
| Date deserialization in TS | `mongodb` driver returns `Date` objects automatically |
| `BigInt` doesn't `JSON.stringify` | Convert in DTO mapping |
| Slow first connection (DNS for SRV) | Cold-start cost; consider keeping connection alive |
| Aggregation `$lookup` slow | Index `foreignField`; or denormalize |
| Connection pool exhaustion under load | Increase `maxPoolSize`; check for held sessions |
| TLS errors with self-signed cert | `tlsAllowInvalidCertificates=true` (dev only); set CA in prod |
| `bsoncxx` / language-specific BSON gotchas | Read driver docs carefully; mismatched types are common |
