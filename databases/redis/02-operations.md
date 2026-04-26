# Redis Operations

> Persistence, replication, Sentinel, Cluster, monitoring. The "now we're in production" cuts.

## Persistence — RDB vs AOF

| Mode | Behavior | When |
|------|----------|------|
| **None** | Memory only | Pure cache (regenerable) |
| **RDB** (snapshots) | Periodic dumps. Fast restart. May lose minutes of data. | Cache that benefits from warm restart |
| **AOF** (append-only file) | Every write logged. Slower, recoverable to ~1s ago. | Sessions, queues |
| **Both** | RDB for fast restart + AOF for durability | Important state you can't easily regen |

For pure cache: `save ""` (disable RDB) and `appendonly no`. For queue/session: `appendonly yes` with `appendfsync everysec`.

`appendfsync` choices:
- `always` — fsync on every write (safest, slowest)
- `everysec` — fsync once per second (recommended)
- `no` — let the OS decide (fastest, can lose writes)

## Replication

A Redis primary + N replicas. Replicas read-only by default; primary handles writes.

```
# replica config
replicaof <primary-host> 6379
masterauth ${REDIS_PASSWORD}
replica-read-only yes
```

Replicas useful for:
- Read scaling (route reads to replicas)
- Backups (snapshot from a replica without impacting primary)
- HA (with Sentinel or Cluster)

Replication is asynchronous — replicas can lag during heavy writes. For "must read your writes," go to the primary.

## Sentinel (HA without sharding)

Sentinel is a separate process that monitors Redis primaries + replicas. On primary failure, Sentinels elect a new primary from the replicas.

Standard topology: **3 Sentinels + 1 primary + 2 replicas**.

```
# sentinel.conf
port 26379
sentinel monitor mymaster <primary-host> 6379 2     # quorum=2 of 3 sentinels
sentinel auth-pass mymaster ${REDIS_PASSWORD}
sentinel down-after-milliseconds mymaster 5000
sentinel failover-timeout mymaster 60000
sentinel parallel-syncs mymaster 1
```

Clients connect via Sentinels (driver discovers current primary):

```python
from redis.sentinel import Sentinel
sentinel = Sentinel([("sentinel-1", 26379), ("sentinel-2", 26379), ("sentinel-3", 26379)],
                    socket_timeout=0.1, password=PASSWORD)
master = sentinel.master_for("mymaster", socket_timeout=0.1, password=PASSWORD)
```

Use Sentinel when you need HA but don't need to shard data across nodes (most apps).

## Cluster (sharding + HA)

Redis Cluster shards data across multiple nodes (each node owns a hash-slot range, 0–16383).

| Topology | Description |
|----------|-------------|
| Min | 3 primaries (no replicas — no HA) |
| Recommended | 3 primaries + 3 replicas |

```
# cluster mode
cluster-enabled yes
cluster-config-file nodes.conf
cluster-node-timeout 5000
cluster-require-full-coverage no
```

**Trade-off**: clients must be cluster-aware (`ioredis` clusterClient, `redis-py` `RedisCluster`). Multi-key commands only work if all keys are in the same hash slot — use **hash tags**: `{user:123}:profile` and `{user:123}:settings` go to the same slot.

Use Cluster when:
- Single-node memory limit reached
- Need >1 GB/sec network throughput
- Otherwise: stick with Sentinel — much simpler

## Managed alternatives (skip the ops)

| Provider | When |
|----------|------|
| **Upstash** | Serverless, REST API, free tier; great for edge functions |
| **Redis Cloud** | Official; full feature parity; enterprise tier with active-active |
| **AWS ElastiCache** | If on AWS |
| **GCP Memorystore** | If on GCP |
| **Azure Cache for Redis** | If on Azure |

For most teams: **managed**. Self-host only if compliance or cost demand it.

## Backups

For durable Redis (queues, sessions):

```bash
# RDB snapshot (also runs continuously per `save` config)
docker exec {{project-slug}}-redis redis-cli -a $REDIS_PASSWORD BGSAVE

# AOF rewrite (compacts the AOF)
docker exec {{project-slug}}-redis redis-cli -a $REDIS_PASSWORD BGREWRITEAOF

# copy the dump
docker cp {{project-slug}}-redis:/data/dump.rdb /var/backups/redis/dump-$(date -u +%FT%H%M%SZ).rdb
```

Restore: stop Redis, replace `/data/dump.rdb` and/or `appendonly.aof`, start.

For managed Redis: provider handles backups (Upstash, Redis Cloud, ElastiCache).

## Monitoring

### Built-in commands

```
INFO                  # everything
INFO memory          # memory stats
INFO replication     # replication state
INFO clients         # client connections
INFO commandstats    # per-command statistics
INFO persistence     # RDB/AOF state
SLOWLOG GET 20       # 20 slowest commands recently
LATENCY DOCTOR       # latency analysis
CLIENT LIST          # connected clients
DBSIZE               # number of keys
MEMORY USAGE key     # bytes for a specific key
```

### Prometheus exporter

```yaml
redis-exporter:
  image: oliver006/redis_exporter:latest
  environment:
    REDIS_ADDR: redis://redis:6379
    REDIS_PASSWORD: ${REDIS_PASSWORD}
  ports: ["9121:9121"]
```

Grafana dashboard ID 763 (Redis Dashboard for Prometheus Redis Exporter).

### Key metrics + alerts

- `redis_memory_used_bytes / redis_memory_max_bytes > 0.8` — memory pressure
- `redis_commands_processed_total` rate — sudden drop = something wrong
- `redis_connected_clients` near max
- `redis_replication_lag` (replicas)
- `redis_keyspace_misses / redis_keyspace_hits` ratio (cache hit rate)
- `redis_slowlog_length` growing — slow queries piling up
- `redis_aof_last_write_status` — AOF errors

### Cache hit rate

```
INFO stats
# keyspace_hits, keyspace_misses
hit_rate = hits / (hits + misses)
```

For cache, aim > 80%. Lower means TTL too short or wrong cache key strategy.

## Tuning

For dedicated Redis on a 4 CPU / 16 GB RAM box:

```
maxmemory 12gb                                # 75% RAM
maxmemory-policy allkeys-lru                  # for cache
io-threads 4                                  # use all cores for I/O
io-threads-do-reads yes
hz 100                                        # default; raise for low latency
tcp-keepalive 300

# disable transparent huge pages on host (echo never > /sys/kernel/mm/transparent_hugepage/enabled)
```

For low-latency requirements, adjust:
- Use `noeviction` if writes must succeed (fail rather than evict)
- Use `volatile-lru` to evict only TTL-bearing keys (preserve persistent data)
- Pin Redis to specific cores (CPU affinity)

## Security

### Password (always)

```
requirepass <strong-random-32+-char-password>
```

In docker compose, pass via env: `--requirepass ${REDIS_PASSWORD}`.

### ACLs (Redis 6+)

For multi-app shared Redis, use ACLs to scope per-app:

```
ACL SETUSER app_a on >password ~app_a:* +@read +@write +@string +@hash +@sortedset
ACL SETUSER app_b on >password ~app_b:* +@read +@write +@string +@hash
```

`~app_a:*` — only keys matching this pattern.

### TLS

```
# redis.conf
tls-port 6380
port 0                          # disable plain TCP
tls-cert-file /etc/redis/tls/cert.pem
tls-key-file /etc/redis/tls/key.pem
tls-ca-cert-file /etc/redis/tls/ca.pem
tls-auth-clients yes            # require client certs (mTLS)
```

For internet-exposed: TLS required. For VPC-internal: optional.

### Disable dangerous commands

```
rename-command FLUSHALL ""
rename-command FLUSHDB ""
rename-command CONFIG ""
rename-command DEBUG ""
rename-command KEYS ""
rename-command SHUTDOWN ""
```

Or rename to a hard-to-guess string for ops use.

## Tools

- **`redis-cli`** — CLI; standard
- **RedisInsight** — official GUI from Redis Labs
- **redis-commander** — web UI
- **MEMORY DOCTOR** — built-in diagnostics
- **SLOWLOG GET** — slow query inspection
- **CLIENT LIST** — see who's connected
- **MONITOR** — live command stream (impacts performance — debug only)

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| Out of memory + `noeviction` policy | Writes start failing; switch to LRU or scale up |
| Long-running BLPOP / SUBSCRIBE on shared connection | Use a separate connection (`redis.duplicate()`) |
| Master + replica with mismatched configs | Replicas inherit some config; verify both |
| Sentinel topology < quorum during partition | Failover doesn't happen — use majority quorum |
| Cluster multi-key ops fail (CROSSSLOT) | Use hash tags `{...}` to colocate keys |
| AOF growing unbounded | Trigger `BGREWRITEAOF`; set `auto-aof-rewrite-percentage` |
| Replication broken after upgrade | Check version compat; usually rolling upgrade works |
| TLS handshake slow | OK in normal use; cache connections |
| Persistence on cache | Wastes IO; disable for pure cache (`save ""`) |
| Backup never tested | Restore monthly to verify |
| Passwords in connection logs | Sanitize logs; use env vars only |
| Connection pool too small under load | Increase driver-level pool; check `connected_clients` |
