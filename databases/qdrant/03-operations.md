# Qdrant Operations

> Snapshots, cluster mode, monitoring, on-disk + quantization, performance tuning.

## Snapshots — backups

```python
# create snapshot for one collection
snapshot = await client.create_snapshot(collection_name="docs")
print(snapshot.name)   # qdrant_snapshots/docs/{timestamp}.snapshot

# create snapshot of all collections (storage-level)
await client.create_full_snapshot()

# list
snapshots = await client.list_snapshots("docs")

# download for off-site backup
# in shell:
# docker exec qdrant tar czf /qdrant/snapshots/docs-$(date -u +%FT%H%M%SZ).tar.gz /qdrant/snapshots/docs/
# docker cp qdrant:/qdrant/snapshots/docs-...tar.gz /var/backups/qdrant/
# aws s3 cp /var/backups/qdrant/docs-...tar.gz s3://backups/

# restore: bring up new Qdrant, place snapshot in collection's snapshots dir, then:
await client.recover_snapshot(
    collection_name="docs",
    location="file:///qdrant/snapshots/docs/{timestamp}.snapshot",
)
```

Schedule snapshots via cron / systemd timer in production:

```bash
# /etc/cron.d/qdrant-backup
0 3 * * * docker exec {{project-slug}}-qdrant curl -X POST http://localhost:6333/collections/docs/snapshots -H "api-key: $QDRANT_API_KEY"
```

## Cluster mode (HA + sharding)

For >100M vectors or HA: enable cluster mode in `config.yaml`:

```yaml
cluster:
  enabled: true
  p2p:
    port: 6335
  consensus:
    tick_period_ms: 100
```

Topology: minimum **3 nodes** (Raft consensus needs majority).

Then create a sharded collection:

```python
await client.create_collection(
    collection_name="docs",
    vectors_config=VectorParams(size=1536, distance=Distance.COSINE),
    shard_number=6,                       # split data across 6 shards
    replication_factor=2,                 # each shard replicated to 2 nodes
)
```

Multi-tenancy with sharding — set tenant_id as the shard key for locality:

```python
await client.create_collection(
    ...,
    shard_number=6,
    sharding_method=ShardingMethod.CUSTOM,
)

# upsert with explicit shard key
await client.upsert(
    collection_name="docs",
    points=[PointStruct(id="...", vector=..., payload={"tenant_id": tid, ...})],
    shard_key_selector=tid,
)
```

For most workloads, single-node is enough. Cluster adds operational complexity.

## Qdrant Cloud (managed)

Skip the self-hosted ops:

- Free tier: 1 GB cluster
- Hybrid: deploy your own infra, Qdrant Cloud manages
- Fully managed: Qdrant Cloud runs everything (AWS/GCP/Azure regions)

For production at any scale: **Qdrant Cloud** unless you have specific compliance requirements.

## Monitoring

### Built-in metrics endpoint

Qdrant exposes Prometheus metrics at `/metrics`:

```yaml
# add to docker-compose.yml or expose with the API key
```

Scrape with Prometheus:

```yaml
scrape_configs:
  - job_name: 'qdrant'
    static_configs:
      - targets: ['qdrant:6333']
    metrics_path: /metrics
    scheme: http
    bearer_token: '${QDRANT_API_KEY}'
```

### Key metrics

- `qdrant_collections_size` — points per collection
- `qdrant_indexed_vectors_count` — vectors indexed (vs total)
- `qdrant_grpc_responses_total` / `qdrant_rest_responses_total` — request rate
- `qdrant_grpc_response_seconds_bucket` / `qdrant_rest_response_seconds_bucket` — latency
- Memory usage (host metric — 80%+ → tune quantization or scale up)
- Disk usage on `/qdrant/storage`

### Health endpoints

```
GET /healthz       # general health
GET /livez         # liveness
GET /readyz        # readiness
GET /telemetry     # detailed runtime stats (under api-key)
```

## Performance tuning

### When to use what

| Scale | Strategy |
|-------|----------|
| < 100K vectors | Defaults are fine; vectors in RAM |
| 100K – 1M | Defaults; consider on_disk for payload |
| 1M – 10M | `on_disk: true` for vectors, scalar quantization (INT8) |
| 10M – 100M | Binary quantization with rescore + sharding |
| > 100M | Cluster + binary quantization + careful tenant sharding |

### HNSW parameters

| Param | Effect |
|-------|--------|
| `m` (default 16) | Higher = better recall, more memory; 32 for very large |
| `ef_construct` (default 100) | Higher = better quality, slower indexing; 200 for max |
| `full_scan_threshold` (default 10K) | Below this, use brute force (no HNSW) |
| `max_indexing_threads` | Parallelism during index build |
| `on_disk` | Memory-mapped index instead of in RAM |

Search-time:

| Param | Effect |
|-------|--------|
| `hnsw_ef` (default 100) | Search depth; higher = better recall, slower |
| `exact` | Brute force (perfect recall, slow) — use only for small collections or eval |
| `quantization.rescore` | Re-rank quantized results with original vectors |

Tune by measuring recall + p95 on your real workload. Don't over-tune defaults blindly.

### Indexing thresholds

Bulk-load **first**, then build the HNSW index:

```python
# disable indexing during bulk load
await client.update_collection(
    collection_name="docs",
    optimizers_config=OptimizersConfigDiff(indexing_threshold=0),    # 0 = disable
)

# bulk upsert
for batch in batches(points, size=1000):
    await client.upsert("docs", points=batch, wait=False)

# re-enable
await client.update_collection(
    collection_name="docs",
    optimizers_config=OptimizersConfigDiff(indexing_threshold=10000),
)

# wait for indexing
while True:
    info = await client.get_collection("docs")
    if info.indexed_vectors_count == info.points_count:
        break
    await asyncio.sleep(5)
```

## TLS

For production:

```yaml
service:
  enable_tls: true
  tls_cert: /qdrant/tls/cert.pem
  tls_key: /qdrant/tls/key.pem
```

Or front Qdrant with nginx for TLS termination + auth header injection.

## Authentication

```yaml
service:
  api_key: "<32+ char random string>"
  read_only_api_key: "<separate read-only key>"      # for read-only consumers
```

Pass in client:

```python
client = AsyncQdrantClient(url=url, api_key=API_KEY)
```

For multi-tenant with finer ACL: rely on app-level filter scoping (Qdrant doesn't have row-level ACLs).

## Resource sizing

Estimate per 1M vectors:

| Component | Size |
|-----------|------|
| Vectors (1536 dim float32) | 6 GB |
| HNSW graph | ~25% of vector size = 1.5 GB |
| Payload (varies) | ~1-3 GB depending on text length |
| Total RAM (defaults) | ~10 GB per 1M vectors |
| With `on_disk=True` | ~2-3 GB RAM (vectors mmap'd) |
| With INT8 quantization in RAM | ~2 GB RAM (quantized) |
| With binary quantization in RAM | ~200 MB RAM (binary) |

Plan for 2x headroom. Provision RAM accordingly.

## Operations checklist (production)

- [ ] API key set + rotated quarterly
- [ ] TLS enabled (or behind TLS proxy)
- [ ] Daily snapshots → S3 / B2
- [ ] Tested restore at least monthly
- [ ] Monitored: memory, disk, request latency, error rate
- [ ] Alerted: < 20% disk, > 80% memory, p99 > target latency, error rate > 1%
- [ ] Quantization configured for collections > 1M vectors
- [ ] `on_disk: true` for collections > 5M vectors
- [ ] Telemetry disabled (`telemetry_disabled: true`)
- [ ] Backup retention policy documented

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| Slow inserts | Batch (1000 per request); `wait=False` for fire-and-forget |
| OOM during bulk load | Disable indexing during load; add quantization |
| HNSW unused on filtered query | Filter too selective — Qdrant falls back to scan; sometimes desired |
| Recall too low | Bump `hnsw_ef` (search-time) and/or `ef_construct` (index-time) |
| Slow snapshot | Snapshot is fast for small collections; large = slow; consider incremental backups |
| Cold start latency after restart | First search loads HNSW from disk; pre-warm |
| Cluster split-brain | Configure consensus carefully; min 3 nodes |
| Auth bypassed | Verify `api_key` is set; check no `--no-api-key` flag in startup |
| Telemetry calls to Qdrant servers | `telemetry_disabled: true` in config |
| Wrong client version vs server | Pin both; check changelogs for breaking changes |
| Missing payload index → unexpected slow filter | Always index every filtered field |
