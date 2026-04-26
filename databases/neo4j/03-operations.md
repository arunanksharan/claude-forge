# Neo4j Operations

> Backup, monitoring, scaling, clustering. The "now we're in production" cuts.

## Backup strategy

| Edition | Backup tool |
|---------|-------------|
| **Community** | Offline only — stop DB, snapshot data dir |
| **Enterprise** | `neo4j-admin database backup` (online, hot backup) |
| **Aura** | Managed; automatic snapshots + PITR |

### Community offline backup

```bash
docker stop {{project-slug}}-neo4j
docker run --rm -v {{project-slug}}_neo4j_data:/data -v "$BACKUP_DIR:/backup" \
    neo4j:5.26-community \
    tar czf /backup/neo4j-$(date -u +%FT%H%M%SZ).tar.gz /data
docker start {{project-slug}}-neo4j
```

Schedule via cron — accept downtime window.

### Enterprise online backup

```bash
docker exec {{project-slug}}-neo4j neo4j-admin database backup \
    --to-path=/backups \
    --include-metadata=all \
    neo4j

# restore
docker exec {{project-slug}}-neo4j neo4j-admin database restore \
    --from-path=/backups/neo4j-2026-04-26 \
    --overwrite-destination \
    neo4j
```

Online — DB keeps serving requests during backup.

### Logical backup (any edition)

```bash
# export everything as Cypher
docker exec {{project-slug}}-neo4j cypher-shell -u neo4j -p $NEO4J_PASSWORD \
    "CALL apoc.export.cypher.all('/var/lib/neo4j/import/dump.cypher', {})"

# copy
docker cp {{project-slug}}-neo4j:/var/lib/neo4j/import/dump.cypher /var/backups/neo4j/dump-$(date -u +%FT%H%M%SZ).cypher
```

Slower but portable across versions / editions.

### Test restoring

Same rule as everywhere: test restore monthly. Otherwise it's hope, not backup.

## Aura (managed) — skip the ops

For production at any scale: **Aura** unless compliance demands self-hosting.

- AuraDB Free: 200K nodes / 400K relationships, hands-off
- AuraDB Professional: production tier with backups, monitoring, autoscaling
- AuraDS: includes Graph Data Science library

Connection: just an URI like `neo4j+s://abc123.databases.neo4j.io`. Your driver handles TLS + retries.

## Clustering (Enterprise + self-hosted)

For HA + read scaling: Neo4j Enterprise causal cluster.

Topology:
- 3 **core servers** (Raft consensus, write quorum)
- N **read replicas** (eventually consistent reads)

```yaml
# docker-compose.cluster.yml
services:
  core1:
    image: neo4j:5.26-enterprise
    environment:
      NEO4J_initial_dbms_default__primaries__count: 3
      NEO4J_initial_server_mode_constraint: PRIMARY
      NEO4J_dbms_cluster_discovery_endpoints: core1:5000,core2:5000,core3:5000
      NEO4J_server_default__advertised__address: core1
      NEO4J_ACCEPT_LICENSE_AGREEMENT: 'yes'
  core2:
    # ... same structure
  core3:
    # ... same structure
  read1:
    environment:
      NEO4J_initial_server_mode_constraint: SECONDARY
      # ... same config
```

Driver routes writes to a leader, reads to any replica:

```python
driver = AsyncGraphDatabase.driver("neo4j+s://my-cluster.example.com", auth=(user, pass))
# driver auto-discovers topology
```

## Monitoring

### Built-in metrics endpoint

Enterprise exposes JMX + Prometheus metrics. Community has limited metrics — query `:sysinfo` in browser.

```yaml
# enable Prometheus endpoint (Enterprise)
metrics.prometheus.enabled=true
metrics.prometheus.endpoint=0.0.0.0:2004
```

Scrape with Prometheus; visualize with Grafana dashboard ID 14258.

### Key metrics

- Heap usage, page cache hit rate (target > 99%)
- Active transactions, locks, deadlocks
- Bolt connections (open / waiting)
- Per-database read / write rate
- Checkpoint duration
- Replication lag (cluster)

### Slow query log

```
db.logs.query.enabled=INFO
db.logs.query.threshold=200ms
db.logs.query.parameter_logging_enabled=true
db.logs.query.runtime_logging_enabled=true
```

Then tail `logs/query.log`. For systematic analysis, ship to Loki.

## Memory tuning

Neo4j has three memory pools:

| Pool | Purpose | Sizing |
|------|---------|--------|
| **Heap** | Java objects, query execution | 1-4 GB typically; max 31 GB (compressed oops) |
| **Page cache** | DB file caching | RAM minus heap minus OS overhead |
| **OS** | Filesystem cache | Leave at least 1 GB for the OS |

For a 16 GB host:

```
server.memory.heap.initial_size=4g
server.memory.heap.max_size=4g       # heap = initial = max for stability
server.memory.pagecache.size=10g
```

Use `neo4j-admin server memory-recommendation --memory=16g` for guidance.

## Scaling

| Bottleneck | Solution |
|------------|----------|
| Read throughput | Read replicas (cluster) — route reads to replicas |
| Write throughput | Vertical scale (Neo4j writes are single-leader) |
| Storage | Vertical disk; Enterprise supports multi-TB |
| Memory pressure on big graph | Bigger box; or model differently (split graph) |
| Multi-region | Aura multi-region; or app-level sharding |

Neo4j doesn't shard automatically (writes are single-leader). For massive graphs, consider:
- Vertical scaling first (Neo4j scales well to ~hundreds of GB)
- Application-level sharding (per tenant, per region)
- Move to a different DB if the data really doesn't fit (Janus, Dgraph)

## Indexes — operational care

Indexes are stored separately from data. Lifecycle:

```cypher
// list
SHOW INDEXES;

// drop
DROP INDEX user_email_unique IF EXISTS;

// rebuild (auto on startup)
```

Check index usage:

```cypher
// approximate stats
SHOW INDEXES YIELD name, state, populationPercent, lastRead;
```

Unused indexes: drop them — they cost write performance + disk.

## Security

### Auth

Always set a strong password on first login (browser prompts). Disable defaults.

```cypher
ALTER USER neo4j SET PASSWORD 'new-strong-password';
```

### Roles + ACL (Enterprise)

```cypher
CREATE ROLE app_reader;
GRANT TRAVERSE ON GRAPH * TO app_reader;
GRANT READ {*} ON GRAPH * TO app_reader;
DENY READ {hashed_password} ON GRAPH * NODES User TO app_reader;

CREATE USER app WITH PASSWORD '...' CHANGE NOT REQUIRED;
GRANT ROLE app_reader TO app;
```

Property-level deny is powerful — use to hide sensitive fields.

### TLS

```
server.bolt.tls_level=REQUIRED
server.bolt.advertised_address=neo4j.example.com:7687

dbms.ssl.policy.bolt.enabled=true
dbms.ssl.policy.bolt.base_directory=certificates/bolt
dbms.ssl.policy.bolt.private_key=private.key
dbms.ssl.policy.bolt.public_certificate=public.crt
```

For internet-exposed Neo4j: **always TLS**. For VPC-internal: optional.

## Health endpoints

```
GET /db/neo4j/cluster/available     # Enterprise cluster
GET /db/neo4j/cluster/writable
GET /                               # browser endpoint (returns 200 if alive)
```

```python
async def health() -> dict:
    try:
        async with driver.session() as session:
            r = await session.run("RETURN 1 AS ok")
            await r.single()
        return {"status": "ok"}
    except Exception as e:
        return {"status": "degraded", "error": str(e)}
```

## Maintenance

### Compaction

Neo4j auto-compacts; usually no manual intervention.

### Disk reclamation after deletes

Deleted nodes leave gaps in store files. To reclaim:

```bash
# offline rebuild
neo4j-admin database copy --to-database=neo4j_compact neo4j
# then swap
```

For most workloads, this isn't needed.

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| Default password unchanged | Change on first login |
| Heap and page cache mis-sized | Use `neo4j-admin server memory-recommendation` |
| Page cache hit rate < 95% | Add RAM; reduce graph; partition |
| Single-node prod (community) | Aura or Enterprise cluster |
| Backups never tested | Restore monthly |
| Long-running write blocks reads | Investigate with `:queries` (Enterprise) |
| Bolt connection pool too small | Driver-level pool — increase |
| TLS misconfigured | Cert issues — verify hostname matches |
| Disk fills (transaction logs) | `db.tx_log.rotation.retention_policy` controls retention |
| GC pauses blocking queries | Heap too big or wrong GC flag — try ZGC |
| Shutdown taking forever | Active checkpoints; tune `db.checkpoint` settings |
| Cluster split-brain | Quorum requires majority — never run 2-node cluster |
