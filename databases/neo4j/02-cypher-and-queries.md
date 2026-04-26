# Cypher & Query Patterns

> Cypher syntax, traversals, aggregations, EXPLAIN/PROFILE. The query language that makes graph queries readable.

## Cypher basics

```cypher
// CREATE
CREATE (u:User {id: "u1", email: "alice@example.com", created_at: datetime()})

// MATCH (read)
MATCH (u:User {id: "u1"})
RETURN u;

// MATCH with relationship
MATCH (u:User {id: "u1"})-[:FOLLOWS]->(f:User)
RETURN f.name;

// MERGE (upsert: match or create)
MERGE (u:User {id: "u1"})
ON CREATE SET u.email = "alice@...", u.created_at = datetime()
ON MATCH SET u.last_seen_at = datetime();

// SET (update)
MATCH (u:User {id: "u1"})
SET u.is_active = false, u.updated_at = datetime();

// DELETE
MATCH (u:User {id: "u1"})
DETACH DELETE u;     // DETACH = also delete connected relationships

// CREATE relationship
MATCH (a:User {id: "u1"}), (b:User {id: "u2"})
CREATE (a)-[:FOLLOWS {since: datetime()}]->(b);

// MERGE relationship (idempotent)
MATCH (a:User {id: "u1"}), (b:User {id: "u2"})
MERGE (a)-[r:FOLLOWS]->(b)
ON CREATE SET r.since = datetime();
```

## Traversals — the core feature

```cypher
// fixed depth
MATCH (u:User {id: "u1"})-[:FOLLOWS]->()-[:FOLLOWS]->(fof)
RETURN DISTINCT fof;

// variable depth (1 to 3 hops)
MATCH (u:User {id: "u1"})-[:FOLLOWS*1..3]->(reachable)
RETURN DISTINCT reachable;

// shortest path
MATCH path = shortestPath((a:User {id: "u1"})-[:FOLLOWS*]-(b:User {id: "u9"}))
RETURN path, length(path);

// all shortest paths
MATCH paths = allShortestPaths((a)-[*]-(b))
WHERE a.id = "u1" AND b.id = "u9"
RETURN paths;

// directed traversal — pay attention to arrows
//   ->  outgoing
//   <-  incoming
//   -   either direction (no arrow)
MATCH (u:User)-[:FOLLOWS]-(other)    // either follows or followed by
RETURN other;
```

**Always bound variable-length paths** (`*1..5`) — unbounded `*` can explode combinatorially.

## Filtering

```cypher
MATCH (u:User)
WHERE u.tenant_id = $tid
  AND u.created_at > datetime("2026-01-01")
  AND u.email CONTAINS "@example.com"
RETURN u
ORDER BY u.created_at DESC
LIMIT 50;

// pattern in WHERE — "users who follow at least one admin"
MATCH (u:User)
WHERE EXISTS {
  MATCH (u)-[:FOLLOWS]->(a:User {role: "admin"})
}
RETURN u;

// negation
MATCH (u:User)
WHERE NOT EXISTS {
  MATCH (u)-[:HAS_SESSION]->()
}
RETURN u;        // users with no sessions
```

## Aggregation

```cypher
// count
MATCH (u:User {tenant_id: $tid})
RETURN count(u);

// group + count
MATCH (u:User)-[:PURCHASED]->(p:Product)
RETURN p.category, count(*) AS purchases
ORDER BY purchases DESC;

// collect into list
MATCH (u:User {id: $uid})-[:FOLLOWS]->(f)
RETURN u, collect(f.name) AS following_names;

// sum, avg, min, max, percentileDisc, stDev
MATCH (o:Order {status: "paid"})
RETURN avg(o.total_cents) AS avg_total,
       percentileDisc(o.total_cents, 0.95) AS p95;

// distinct
MATCH (u:User)-[:VISITED]->(p:Page)
RETURN count(DISTINCT p) AS unique_pages_visited;
```

## Multiple statements (WITH chains)

`WITH` is Cypher's pipeline operator — passes results to the next clause:

```cypher
MATCH (u:User)-[:PURCHASED]->(p:Product)
WHERE u.tenant_id = $tid
WITH u, count(p) AS purchase_count
WHERE purchase_count > 5
MATCH (u)-[:LIVES_IN]->(c:City)
RETURN u.email, c.name, purchase_count
ORDER BY purchase_count DESC
LIMIT 10;
```

Use `WITH` to:
- Filter aggregated results (like SQL HAVING)
- Limit intermediate results before further work
- Chain pattern matches

## CASE expressions

```cypher
MATCH (u:User)
RETURN u.email,
  CASE
    WHEN u.created_at > datetime() - duration("P30D") THEN "new"
    WHEN u.last_seen_at > datetime() - duration("P7D") THEN "active"
    ELSE "dormant"
  END AS status;
```

## UNION

```cypher
MATCH (u:User {role: "admin"}) RETURN u
UNION
MATCH (u:User {role: "owner"}) RETURN u;
```

`UNION` deduplicates; `UNION ALL` doesn't.

## CALL — procedures

```cypher
// APOC procedures — install required
CALL apoc.export.cypher.all("/var/lib/neo4j/import/dump.cypher", {});
CALL apoc.help("apoc.text");

// inline subqueries
CALL {
  MATCH (u:User)-[:PURCHASED]->(p:Product {category: "electronics"})
  RETURN u.id AS uid, count(p) AS n
}
WITH uid, n
WHERE n > 10
MATCH (u:User {id: uid})
RETURN u;
```

## Performance — EXPLAIN + PROFILE

```cypher
// EXPLAIN — show plan without executing
EXPLAIN MATCH (u:User {email: "alice@..."})-[:FOLLOWS]->(f) RETURN f;

// PROFILE — execute + show actual stats
PROFILE MATCH (u:User {email: "alice@..."})-[:FOLLOWS]->(f) RETURN f;
```

Look for:

| Operator | Meaning |
|----------|---------|
| `NodeIndexSeek` | Used an index — good |
| `NodeByLabelScan` | Scanned all nodes of a label — bad on big labels |
| `AllNodesScan` | Scanned everything — terrible |
| `Expand(All)` | Followed all relationships of a node |
| `Filter` | Post-scan filter — sometimes a missed index |
| `db hits` | Number of low-level operations |

If you see `NodeByLabelScan`, you're missing an index.

## Common query patterns

### Pagination

```cypher
MATCH (u:User {tenant_id: $tid})
RETURN u
ORDER BY u.created_at DESC, u.id    // tiebreaker for stability
SKIP $offset
LIMIT $limit;
```

For unbounded growth, **cursor pagination** is better:

```cypher
// page 1
MATCH (u:User {tenant_id: $tid})
RETURN u ORDER BY u.id LIMIT 50;

// page 2 — cursor = last id
MATCH (u:User {tenant_id: $tid})
WHERE u.id > $cursor
RETURN u ORDER BY u.id LIMIT 50;
```

### Recommendation: "people who bought X also bought Y"

```cypher
MATCH (target:User {id: $uid})-[:PURCHASED]->(p:Product)<-[:PURCHASED]-(other:User)
WHERE other <> target
MATCH (other)-[:PURCHASED]->(rec:Product)
WHERE NOT EXISTS { MATCH (target)-[:PURCHASED]->(rec) }
RETURN rec.id, count(*) AS strength
ORDER BY strength DESC
LIMIT 10;
```

Two-hop traversal — natural and fast in Neo4j; nightmare in SQL.

### Mutual follow

```cypher
MATCH (a:User {id: $aid})-[:FOLLOWS]->(b)-[:FOLLOWS]->(a)
RETURN b;
```

### Path of relationships

```cypher
MATCH path = (a:User {id: $a})-[:KNOWS*1..6]-(b:User {id: $b})
WITH path
ORDER BY length(path) ASC
LIMIT 1
RETURN [n IN nodes(path) | n.name] AS chain, length(path) AS hops;
```

The "Six degrees of Kevin Bacon" query.

### Vector similarity (Neo4j 5.13+)

```cypher
// after creating a vector index
CALL db.index.vector.queryNodes('doc_embedding_idx', 10, $query_embedding)
YIELD node, score
WHERE node.tenant_id = $tid
RETURN node.text, score;
```

Combines well with relationship traversal:

```cypher
CALL db.index.vector.queryNodes('doc_embedding_idx', 10, $query_embedding)
YIELD node AS doc
MATCH (doc)<-[:WROTE]-(author:User)
RETURN doc.text, author.name, score;
```

## Transactions

In the driver:

```python
async with driver.session() as session:
    # auto-commit (single statement)
    result = await session.run("MATCH (u:User {id: $id}) RETURN u", id=uid)

    # explicit transaction (multi-statement)
    async with await session.begin_transaction() as tx:
        await tx.run("MATCH (u:User {id: $id}) SET u.balance = u.balance - $amt", id=from_id, amt=amount)
        await tx.run("MATCH (u:User {id: $id}) SET u.balance = u.balance + $amt", id=to_id, amt=amount)
        # auto-commit on exit, rollback on exception

    # managed transaction with retry
    result = await session.execute_write(lambda tx: tx.run("...", ...))
```

`execute_write` / `execute_read` retry on transient failures (e.g., deadlock).

## Bulk import

For initial data load (millions of rows):

```cypher
// LOAD CSV — small to medium
LOAD CSV WITH HEADERS FROM 'file:///users.csv' AS row
MERGE (u:User {id: row.id})
SET u.email = row.email, u.created_at = datetime(row.created_at);
```

For massive loads (10M+ rows):

```bash
# offline import — much faster, but requires DB stopped
docker exec {{project-slug}}-neo4j neo4j-admin database import full \
    --nodes=User=/var/lib/neo4j/import/users.csv \
    --relationships=FOLLOWS=/var/lib/neo4j/import/follows.csv \
    neo4j
```

## APOC procedures (worth knowing)

```cypher
// merge nodes (deduplicate)
CALL apoc.refactor.mergeNodes([n1, n2]) YIELD node;

// run periodically batched updates
CALL apoc.periodic.iterate(
  "MATCH (u:User) WHERE u.needs_update = true RETURN u",
  "SET u.processed = true",
  {batchSize: 500, parallel: false}
);

// virtual nodes / paths (for visualization)
CALL apoc.create.vNode(['Synthetic'], {name: 'X'}) YIELD node;

// JSON load
CALL apoc.load.json('https://api.example.com/data.json') YIELD value;

// trigger on data changes
CALL apoc.trigger.add('audit_user_changes',
  'UNWIND $createdNodes AS n WHERE "User" IN labels(n)
   CREATE (a:Audit {action: "user.created", user_id: n.id, at: datetime()})',
  {phase: 'after'});
```

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| Missing constraint → duplicate nodes from MERGE | Always create constraints first |
| `MATCH (n {prop: $val})` slow without index | Add index on label + property |
| Variable-length path explodes | Bound it: `*1..5`, not `*` |
| `count(*)` slow on large MATCH | Pre-aggregate; or store counters in nodes |
| `MERGE` matches partially | `MERGE` matches all properties given; specify uniqueness via constraint |
| Cartesian product | Two disjoint MATCH clauses without WITH or relation = N×M rows |
| Hot relationship type | "All users HAS_VIEWED all pages" — model differently or shard |
| Mixing label and property filters | Push specific labels into MATCH, not WHERE |
| `OPTIONAL MATCH` slow | Returns nulls for non-matches; sometimes restructure as separate query |
| Datetime stored as string | Use `datetime()`, `date()`, etc. |
| Returning huge graphs | Add `LIMIT` always; use pagination |
| Profile says `AllNodesScan` | Add a label predicate; create an index |
