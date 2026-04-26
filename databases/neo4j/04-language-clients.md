# Neo4j Language Clients

> Python (`neo4j`), Node (`neo4j-driver`), Go, Java. Connection patterns + Graphiti for AI agent memory.

## Driver picks

| Language | Driver |
|----------|--------|
| **Python** | `neo4j` (official) — sync + async; `AsyncGraphDatabase` |
| **Python (high-level KG/agent)** | **Graphiti** — knowledge-graph framework on Neo4j with LLM extraction |
| **Node** | `neo4j-driver` (official) |
| **Go** | `github.com/neo4j/neo4j-go-driver/v5` |
| **Java** | `org.neo4j.driver:neo4j-java-driver` |
| **Rust** | `neo4rs` (community) |
| **HTTP API** | for non-driver languages — REST endpoint |

## Python — `neo4j`

```bash
uv add neo4j
```

```python
from neo4j import AsyncGraphDatabase

driver = AsyncGraphDatabase.driver(
    settings.neo4j_uri,                      # bolt://localhost:7687 or neo4j+s://...
    auth=(settings.neo4j_user, settings.neo4j_password),
    max_connection_pool_size=50,
    connection_timeout=30,
)

# health
await driver.verify_connectivity()

# auto-commit (single statement)
async def get_user(user_id: str):
    async with driver.session(database="neo4j") as session:
        result = await session.run("MATCH (u:User {id: $id}) RETURN u", id=user_id)
        record = await result.single()
        return dict(record["u"]) if record else None

# managed read with retry
async def list_friends(user_id: str):
    async with driver.session() as session:
        result = await session.execute_read(
            lambda tx: tx.run(
                "MATCH (u:User {id: $id})-[:FOLLOWS]->(f) RETURN f.id AS id, f.name AS name",
                id=user_id,
            ).data()
        )
    return result

# managed write with retry
async def follow_user(from_id: str, to_id: str):
    async with driver.session() as session:
        await session.execute_write(
            lambda tx: tx.run(
                """
                MATCH (a:User {id: $from_id}), (b:User {id: $to_id})
                MERGE (a)-[r:FOLLOWS]->(b)
                ON CREATE SET r.since = datetime()
                """,
                from_id=from_id, to_id=to_id,
            )
        )

# explicit transaction (multi-statement)
async def transfer_role(user_id, from_role, to_role):
    async with driver.session() as session:
        async with await session.begin_transaction() as tx:
            await tx.run(
                "MATCH (u:User {id: $id})-[r:HAS_ROLE]->(:Role {name: $from_role}) DELETE r",
                id=user_id, from_role=from_role,
            )
            await tx.run(
                """MATCH (u:User {id: $id}), (r:Role {name: $to_role})
                   MERGE (u)-[:HAS_ROLE {since: datetime()}]->(r)""",
                id=user_id, to_role=to_role,
            )
            # commit on exit, rollback on exception

# cleanup
await driver.close()
```

### Lifecycle (FastAPI)

```python
@asynccontextmanager
async def lifespan(app):
    await driver.verify_connectivity()
    yield
    await driver.close()
```

### Working with results

```python
async def get_user_full(user_id: str):
    async with driver.session() as session:
        result = await session.run(
            """
            MATCH (u:User {id: $id})
            OPTIONAL MATCH (u)-[:FOLLOWS]->(f)
            RETURN u, collect(f) AS following
            """,
            id=user_id,
        )
        record = await result.single()
        if not record:
            return None
        user = dict(record["u"])
        user["following"] = [dict(f) for f in record["following"]]
        return user
```

`Node` and `Relationship` objects can be `dict()`-converted to get properties. Use `record.get("key")` for safe access.

## Python — Graphiti (knowledge graph + LLM)

Graphiti turns Neo4j into a temporal knowledge graph with LLM-powered entity + relationship extraction. The brain behind the dual-memory architecture in [`memory-layer/`](../../memory-layer/).

```bash
uv add graphiti-core
```

```python
from graphiti_core import Graphiti
from graphiti_core.nodes import EntityNode, EpisodicNode

graphiti = Graphiti(
    uri="bolt://localhost:7687",
    user="neo4j",
    password=settings.neo4j_password,
    llm_client=...,                     # OpenAI / Anthropic
)

await graphiti.build_indices_and_constraints()

# add an episode (text → extracted entities + relationships)
await graphiti.add_episode(
    name="conversation_2026-04-26",
    episode_body="Alice mentioned she just moved from Tokyo to Berlin and started a job at Acme.",
    source_description="chat session",
    reference_time=datetime.now(UTC),
    group_id=tenant_id,                 # for multi-tenant
)

# search the graph
results = await graphiti.search(
    query="where does Alice live?",
    group_ids=[tenant_id],
    num_results=5,
)
for r in results:
    print(r.name, r.fact)

# bi-temporal: query state at a specific time
results = await graphiti.search(
    query="where did Alice live in 2025?",
    group_ids=[tenant_id],
    edge_types=["LIVES_IN"],
    valid_at=datetime(2025, 1, 1, tzinfo=UTC),
)
```

For the full pattern, see [`memory-layer/01-dual-memory-architecture.md`](../../memory-layer/01-dual-memory-architecture.md).

## Node — `neo4j-driver`

```bash
pnpm add neo4j-driver
```

```typescript
import neo4j, { Driver, Session } from 'neo4j-driver';

const driver: Driver = neo4j.driver(
  process.env.NEO4J_URI!,
  neo4j.auth.basic(process.env.NEO4J_USER!, process.env.NEO4J_PASSWORD!),
  {
    maxConnectionPoolSize: 50,
    connectionTimeout: 30_000,
  },
);

// health
await driver.verifyConnectivity();

// auto-commit
async function getUser(userId: string) {
  const session = driver.session({ database: 'neo4j' });
  try {
    const result = await session.run(
      'MATCH (u:User {id: $id}) RETURN u',
      { id: userId },
    );
    return result.records[0]?.get('u').properties;
  } finally {
    await session.close();
  }
}

// managed read
async function listFriends(userId: string) {
  const session = driver.session();
  try {
    const result = await session.executeRead(async (tx) => {
      const r = await tx.run(
        'MATCH (u:User {id: $id})-[:FOLLOWS]->(f) RETURN f.id AS id, f.name AS name',
        { id: userId },
      );
      return r.records.map((rec) => ({ id: rec.get('id'), name: rec.get('name') }));
    });
    return result;
  } finally {
    await session.close();
  }
}

// managed write
async function follow(fromId: string, toId: string) {
  const session = driver.session();
  try {
    await session.executeWrite(async (tx) => {
      await tx.run(
        `MATCH (a:User {id: $fromId}), (b:User {id: $toId})
         MERGE (a)-[r:FOLLOWS]->(b)
         ON CREATE SET r.since = datetime()`,
        { fromId, toId },
      );
    });
  } finally {
    await session.close();
  }
}

// shutdown
process.on('SIGTERM', async () => {
  await driver.close();
  process.exit(0);
});
```

### Type conversion

Neo4j integers are 64-bit; JS numbers are 53-bit safe. Use `int()`:

```typescript
import neo4j from 'neo4j-driver';

await tx.run('CREATE (u:User {id: $id, age: $age})', {
  id: userId,
  age: neo4j.int(35),
});

// reading
const record = result.records[0];
const age = record.get('age').toNumber();    // bigint → number (with care for overflow)
```

For BigInt values: `record.get('age').toBigInt()`.

## Go — `neo4j-go-driver`

```go
import "github.com/neo4j/neo4j-go-driver/v5/neo4j"

driver, err := neo4j.NewDriverWithContext(
    "neo4j://localhost:7687",
    neo4j.BasicAuth(user, pass, ""),
)
defer driver.Close(ctx)

session := driver.NewSession(ctx, neo4j.SessionConfig{DatabaseName: "neo4j"})
defer session.Close(ctx)

result, err := session.ExecuteRead(ctx, func(tx neo4j.ManagedTransaction) (any, error) {
    res, err := tx.Run(ctx,
        "MATCH (u:User {id: $id}) RETURN u",
        map[string]any{"id": userId},
    )
    if err != nil { return nil, err }
    record, err := res.Single(ctx)
    if err != nil { return nil, err }
    return record.AsMap(), nil
})
```

## Connection URI forms

```
# bolt — single-node
bolt://localhost:7687

# routing — auto-discovers cluster topology (Aura, Enterprise cluster)
neo4j://my-cluster.example.com:7687

# secure
bolt+s://...
neo4j+s://my-cluster.databases.neo4j.io       # Aura

# self-signed cert (dev)
bolt+ssc://localhost:7687
```

| Scheme | Use |
|--------|-----|
| `bolt://` | Direct to a single instance |
| `neo4j://` | Routing — cluster-aware, sends reads to replicas |
| `+s` | TLS with cert verification |
| `+ssc` | TLS with self-signed cert (dev only) |

## Connection pooling

The driver maintains a pool. Tune:

```python
driver = AsyncGraphDatabase.driver(
    uri, auth=(user, pass),
    max_connection_pool_size=100,        # increase for high concurrency
    connection_acquisition_timeout=60,    # how long to wait for a free connection
    connection_timeout=30,                # initial connection
    keep_alive=True,
)
```

## Common patterns

### Tenant-scoped wrapper (Python)

```python
class TenantNeo4j:
    def __init__(self, driver, tenant_id: str):
        self.driver = driver
        self.tenant_id = tenant_id

    async def search_users(self, query: str):
        async with self.driver.session() as session:
            result = await session.execute_read(
                lambda tx: tx.run(
                    """MATCH (u:User {tenant_id: $tid})
                       WHERE u.name CONTAINS $q OR u.email CONTAINS $q
                       RETURN u LIMIT 50""",
                    tid=self.tenant_id, q=query,
                ).data()
            )
        return result
```

Inject tenant_id automatically; never trust the caller to pass it.

### Bulk import (UNWIND)

For inserting many nodes in one statement:

```python
await session.run(
    """
    UNWIND $rows AS row
    MERGE (u:User {id: row.id})
    SET u.email = row.email, u.created_at = datetime(row.created_at)
    """,
    rows=[
        {"id": "u1", "email": "alice@...", "created_at": "2026-04-26T12:00:00Z"},
        # ... 1000 rows
    ],
)
```

Much faster than 1000 individual MERGE statements.

### Streaming results (large queries)

```python
async with driver.session() as session:
    result = await session.run("MATCH (n:Document) RETURN n")
    async for record in result:
        process(record["n"])
    # don't accumulate to a list — stream
```

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| Forgot to close session | Use `async with` / try-finally |
| Cursor consumed twice | Re-run the query or buffer once |
| Datetime as string | Use `datetime()`, `date()` |
| Integer overflow in JS | Use `neo4j.int()` and `.toNumber()` / `.toBigInt()` |
| Connection refused | Check Bolt port (7687); driver uses 7687 not 7474 |
| TLS handshake error | Use `+s` scheme; verify cert validity |
| `Neo.ClientError.Schema.ConstraintValidationFailed` | MERGE matched on wrong property — verify uniqueness constraint |
| Slow Cypher | EXPLAIN/PROFILE; check for missing indexes |
| Memory error from big query | Stream results; use LIMIT |
| `executeWrite` retries forever | Make sure writes are idempotent; or set retry timeout |
| Driver hangs on shutdown | Close all sessions before `driver.close()` |
| `pool exhausted` errors | Increase pool size or check for held sessions |
