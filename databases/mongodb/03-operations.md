# MongoDB Operations

> Replica sets, sharding, backups, monitoring. The "in production" cuts.

## Replica sets — required for production

A replica set is a group of mongod processes that maintain the same data set. Standard topology: **3 nodes** (one primary, two secondaries). One can be an arbiter (no data, just votes) for cost savings, but I recommend full data replicas.

### Why required for production

- **HA**: primary fails → replica promoted in seconds
- **Backups**: take from a secondary without impacting primary
- **Read scaling**: route read queries to secondaries (with caveats — staleness)
- **Multi-doc transactions**: require a replica set

### Setup (self-hosted, 3 nodes)

```yaml
# docker-compose.replica-set.yml
services:
  mongo-1:
    image: mongo:8.0
    container_name: mongo-1
    command: ["--replSet", "rs0", "--bind_ip_all", "--keyFile", "/etc/mongo/keyfile"]
    ports: ["27017:27017"]
    volumes:
      - mongo-1-data:/data/db
      - ./keyfile:/etc/mongo/keyfile:ro

  mongo-2:
    image: mongo:8.0
    container_name: mongo-2
    command: ["--replSet", "rs0", "--bind_ip_all", "--keyFile", "/etc/mongo/keyfile"]
    ports: ["27018:27017"]
    volumes:
      - mongo-2-data:/data/db
      - ./keyfile:/etc/mongo/keyfile:ro

  mongo-3:
    image: mongo:8.0
    container_name: mongo-3
    command: ["--replSet", "rs0", "--bind_ip_all", "--keyFile", "/etc/mongo/keyfile"]
    ports: ["27019:27017"]
    volumes:
      - mongo-3-data:/data/db
      - ./keyfile:/etc/mongo/keyfile:ro

volumes:
  mongo-1-data:
  mongo-2-data:
  mongo-3-data:
```

Generate keyfile:

```bash
openssl rand -base64 756 > keyfile
chmod 400 keyfile
```

Initiate the set (one-time):

```javascript
docker exec -it mongo-1 mongosh --eval '
rs.initiate({
  _id: "rs0",
  members: [
    { _id: 0, host: "mongo-1:27017" },
    { _id: 1, host: "mongo-2:27017" },
    { _id: 2, host: "mongo-3:27017" }
  ]
})
'
```

Connection string:

```
mongodb://app:****@mongo-1:27017,mongo-2:27017,mongo-3:27017/{{db-name}}?replicaSet=rs0&authSource=admin
```

The driver discovers the topology and routes appropriately.

### Atlas — skip the operational burden

Atlas runs the replica set for you (free tier is 3-node M0). Connection strings, backups, monitoring all included. **Use Atlas unless compliance requires self-hosting.**

## Read preference

```javascript
db.collection.find().readPref("secondary");           // read from secondary
db.collection.find().readPref("secondaryPreferred");  // secondary if available
db.collection.find().readPref("nearest");             // lowest latency
```

| Preference | When |
|------------|------|
| `primary` (default) | Strongly consistent reads — your writes are immediately visible |
| `primaryPreferred` | Default with fallback to secondary |
| `secondary` | Reduce primary load; tolerate staleness |
| `secondaryPreferred` | Same with fallback |
| `nearest` | Lowest network latency (multi-region) |

For "read your writes", always `primary`. For analytics: `secondary` is fine.

### Replication lag

Secondaries are eventually consistent. Lag is usually <100ms but can spike during heavy writes.

```javascript
rs.printSecondaryReplicationInfo();
```

Monitor with `rs.status()` or Prometheus exporter.

## Sharding (only if you really need it)

Sharding splits data across multiple replica sets. Required only at huge scale (>1TB or >100K writes/sec).

A sharded cluster has:
- **Config servers** (replica set holding metadata)
- **Mongos routers** (clients connect here)
- **Shards** (each is a replica set holding part of the data)

Choose a **shard key** carefully — once chosen, hard to change. Should:
- Have high cardinality (many distinct values)
- Distribute writes evenly (avoid hot spots)
- Match common query patterns (so queries can be routed to one shard)

```javascript
sh.shardCollection("app.events", { tenantId: 1, _id: 1 });
```

If you're considering sharding, you're either at real scale or you've over-modeled. Be sure.

## Backups

### Atlas (managed)

Continuous backup with point-in-time restore. Configurable retention. Click-to-restore. Just enable.

### Self-hosted — `mongodump`

```bash
# logical backup
docker exec mongo-1 mongodump \
    --uri="mongodb://admin:****@localhost:27017/{{db-name}}?authSource=admin" \
    --gzip --archive=/tmp/{{db-name}}-$(date -u +%FT%H%M%SZ).archive.gz

docker cp mongo-1:/tmp/{{db-name}}-...archive.gz /var/backups/mongodb/

# restore
mongorestore --uri="..." --gzip --archive=/var/backups/.../...archive.gz
```

For larger DBs, run `mongodump` against a **secondary** to avoid loading the primary:

```bash
mongodump --uri="mongodb://...secondary..." --readPreference=secondary
```

### Filesystem snapshot (fastest)

If your storage supports snapshots (LVM, ZFS, EBS):

1. `db.fsyncLock()` on a secondary to flush + lock writes
2. Take filesystem snapshot
3. `db.fsyncUnlock()`
4. Mount snapshot, copy data files

Faster than `mongodump` for big DBs. Requires snapshot-capable storage.

### Test restoring

Same rule as Postgres: backups never tested = hope, not backup. **Restore monthly to a sandbox.**

## Monitoring

### Atlas

Built-in dashboards for queries, replication lag, disk, connections, alerting.

### Self-hosted — Prometheus exporter

```yaml
mongodb-exporter:
  image: percona/mongodb_exporter:latest
  command:
    - "--mongodb.uri=mongodb://exporter:****@mongo-1:27017,mongo-2:27017,mongo-3:27017/?authSource=admin&replicaSet=rs0"
  ports: ["9216:9216"]
```

Grafana dashboard ID 7353 (MongoDB exporter).

### Key metrics + alerts

- **Replication lag** > 10s
- **Connection count** > 80% of limit
- **Disk free** < 20%
- **Lock wait time** spikes
- **Page faults / queries per sec** ratio (working set fits in RAM?)
- **Slow queries** (`db.system.profile` if profiling enabled)

### Slow query profiler

```javascript
db.setProfilingLevel(1, { slowms: 100 });   // log queries > 100ms
db.system.profile.find().sort({ ts: -1 }).limit(20);
```

Don't leave at level 2 (all queries) in production — overhead.

## Connection pool sizing

```typescript
// Node driver
new MongoClient(url, {
  maxPoolSize: 50,           // per process
  minPoolSize: 10,
  maxIdleTimeMS: 60_000,
  serverSelectionTimeoutMS: 5_000,
});
```

```python
# Motor / Beanie
client = motor_asyncio.AsyncIOMotorClient(url, maxPoolSize=50, minPoolSize=10)
```

Default pool is often too small for production. Increase, but watch the server's connection limit (usually 1024 for Atlas M0+).

## TLS

Atlas: TLS by default, no config needed.

Self-hosted:

```yaml
# mongod.conf
net:
  tls:
    mode: requireTLS
    certificateKeyFile: /etc/ssl/mongo.pem
    CAFile: /etc/ssl/ca.pem
```

Connection string:

```
mongodb://...?tls=true&tlsCertificateKeyFile=...
```

For Internet-exposed: required. For VPC-internal: nice-to-have, often skipped for simplicity.

## Migrations

MongoDB has no formal migration framework (no schema!). Patterns:

### Lazy migration (preferred)

Read code handles all schema versions:

```typescript
function normalizeUser(doc: any): User {
  if (doc.schemaVersion === 1) return migrateV1ToV2(doc);
  if (doc.schemaVersion === 2) return doc;
  throw new Error(`unknown version: ${doc.schemaVersion}`);
}
```

Write code only writes the latest. Old docs migrate as they're read.

Pros: zero downtime, no big batch job. Cons: cleanup never finishes — old code stays forever.

### Bulk migration script

```javascript
db.users.find({ schemaVersion: 1 }).forEach(doc => {
  const v2 = migrateV1ToV2(doc);
  db.users.updateOne({ _id: doc._id }, { $set: v2 });
});
```

Run as a one-off script. For big collections, paginate + run in batches with `bulkWrite`.

### Validators as enforcement

Update collection validator after migration to reject old shape:

```javascript
db.runCommand({
  collMod: "users",
  validator: { $jsonSchema: { required: ["..."], ... } },
  validationAction: "error"
});
```

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| Single-node prod | Always replica set |
| Backups never tested | Test restore monthly |
| Slow `$lookup` | Index foreign field; or denormalize |
| Connections exhausted | Increase `maxPoolSize`; Atlas has hard limits |
| Replication lag growing | Network or secondary overloaded; investigate |
| `setProfilingLevel(2)` in prod | Heavy overhead; only for debugging |
| Memory pressure (working set > RAM) | Add RAM, or shard, or shrink data (TTL, archive) |
| Long-running aggregation | `allowDiskUse: true`; or split into smaller stages |
| Failover lost writes | Use `writeConcern: { w: "majority", j: true }` for critical writes |
| Slow startup after restart | Index rebuild; consider `--noIndexBuildRetry` if intentional |
| Validator blocks needed migration | Use `validationAction: "warn"` during migration window |
| Disk fills (oplog grows) | Tune `oplogSizeMB`; check for stuck secondaries |
