# Neo4j Graph Data Modeling

> Nodes, relationships, properties, labels, constraints. The decisions that determine whether your queries fly or crawl.

## The mental model

| RDBMS | Neo4j |
|-------|-------|
| Table | Label + Node |
| Row | Node |
| Column | Property (on node or relationship) |
| Foreign key | Relationship |
| Join | Traversal (cheap!) |
| Composite key | Constraint or property combination |

```cypher
// nodes
(:User {id: "u1", email: "alice@example.com", created_at: 1730000000})
(:Product {id: "p1", sku: "ABC", price_cents: 1000})

// relationship
(:User {id: "u1"})-[:PURCHASED {at: 1730000000, qty: 2}]->(:Product {id: "p1"})
```

## Naming conventions

| Element | Convention | Example |
|---------|-----------|---------|
| Label | `PascalCase` singular | `User`, `Product`, `Order` |
| Relationship type | `UPPER_SNAKE_CASE` | `FOLLOWS`, `PURCHASED`, `LIVES_IN` |
| Property | `snake_case` | `user_id`, `created_at` |
| Internal id (Neo4j-assigned) | Don't expose | Use `id` property as your stable id |

## Property types

| Type | Use |
|------|-----|
| String | identifiers, names, free text |
| Integer / Float | numbers |
| Boolean | flags |
| Date / DateTime / Duration | temporal (use temporal types, not strings!) |
| Point | spatial (2D / 3D, geographic / cartesian) |
| List of any of above | arrays |
| Map (limited) | nested structure (better: separate node) |

**No nested objects** beyond simple maps. If you need depth, model as separate nodes connected by relationships.

## Constraints + indexes

**Always define constraints + indexes upfront.** Without them, queries scan all nodes of a label.

```cypher
-- uniqueness constraint (auto-creates an index)
CREATE CONSTRAINT user_id_unique IF NOT EXISTS
  FOR (u:User) REQUIRE u.id IS UNIQUE;

-- existence constraint (Enterprise only)
CREATE CONSTRAINT user_email_required IF NOT EXISTS
  FOR (u:User) REQUIRE u.email IS NOT NULL;

-- node key (composite uniqueness, Enterprise)
CREATE CONSTRAINT user_tenant_email_key IF NOT EXISTS
  FOR (u:User) REQUIRE (u.tenant_id, u.email) IS NODE KEY;

-- range index (B-tree for equality + range)
CREATE INDEX user_tenant_idx IF NOT EXISTS
  FOR (u:User) ON (u.tenant_id);

-- composite range index
CREATE INDEX user_tenant_created_idx IF NOT EXISTS
  FOR (u:User) ON (u.tenant_id, u.created_at);

-- relationship index
CREATE INDEX follows_created_idx IF NOT EXISTS
  FOR ()-[r:FOLLOWS]-() ON (r.created_at);

-- full-text index (for CONTAINS searches)
CREATE FULLTEXT INDEX user_search IF NOT EXISTS
  FOR (u:User) ON EACH [u.name, u.bio];

-- text index (for STARTS WITH / ENDS WITH)
CREATE TEXT INDEX user_email_text_idx IF NOT EXISTS
  FOR (u:User) ON (u.email);

-- point index (for spatial)
CREATE POINT INDEX shop_location_idx IF NOT EXISTS
  FOR (s:Shop) ON (s.location);

-- vector index (Neo4j 5.13+)
CREATE VECTOR INDEX doc_embedding_idx IF NOT EXISTS
  FOR (d:Document) ON (d.embedding)
  OPTIONS { indexConfig: {
    `vector.dimensions`: 1536,
    `vector.similarity_function`: 'cosine'
  }};
```

Inspect:

```cypher
SHOW CONSTRAINTS;
SHOW INDEXES;
```

## Modeling patterns

### Direct relationship vs intermediate node

**Direct relationship** when:
- One predicate, no metadata about the relationship itself
- `(:User)-[:FOLLOWS]->(:User)`

**Intermediate node** when:
- Relationship has rich metadata
- Multiple relationships of the same kind between same pair (history)
- Time-evolving (e.g., subscription versions)

```cypher
// direct: simple
(:User)-[:LIKES {since: 1730000000}]->(:Post)

// intermediate node: rich relationship
(:User)-[:HAS_SUBSCRIPTION]->(:Subscription {plan: "pro", started_at: ...})-[:FOR]->(:Product)
```

The intermediate node lets you query subscriptions independently, version them, attach payment events, etc.

### Time-series (events)

For high-cardinality time-series, don't model each event as a node connected to the actor. It explodes.

```cypher
// BAD — millions of nodes per user
(:User {id})-[:VIEWED]->(:Page {id, viewed_at})

// BETTER — store events on the relationship and trim periodically
(:User {id})-[:VIEWED {at: ...}]->(:Page {id})

// EVEN BETTER — keep raw events out of Neo4j entirely
// store in Postgres / ClickHouse, only summary in Neo4j
```

Neo4j is great for the relationship layer; it's not optimized for billions of leaf events.

### Hierarchical / tree

```cypher
// adjacency list with relationship
(:Category {name: "electronics"})-[:HAS_CHILD]->(:Category {name: "computers"})
                                  -[:HAS_CHILD]->(:Category {name: "laptops"})

// query: all descendants
MATCH (root:Category {name: "electronics"})-[:HAS_CHILD*]->(d)
RETURN d;

// all ancestors
MATCH (leaf:Category {name: "thinkpad"})<-[:HAS_CHILD*]-(a)
RETURN a;
```

Variable-length paths (`*`) are Cypher's superpower — natural in Neo4j, painful in SQL.

### Multi-tenancy

Add `tenant_id` property + index to every node:

```cypher
(:User {id, tenant_id, email})

// scope every query
MATCH (u:User {tenant_id: $tid})
WHERE ...
```

For strict isolation: use Neo4j Enterprise multi-database (one DB per tenant). Doesn't scale to many tenants.

For SaaS: shared DB + tenant_id property. Wrap your driver with tenant injection.

### Versioning relationships

```cypher
(:User)-[:HAS_ROLE {from: t1, to: t2}]->(:Role {name: "admin"})
(:User)-[:HAS_ROLE {from: t2, to: NULL}]->(:Role {name: "owner"})
```

Old roles preserved with `to`; current has `to: NULL` (or far future).

Query "user's role at time T":

```cypher
MATCH (u:User {id: $uid})-[r:HAS_ROLE]->(role)
WHERE r.from <= $t AND (r.to IS NULL OR r.to > $t)
RETURN role;
```

### Identity resolution (graph-natural)

Often the killer use case for Neo4j: "this email, this phone, and this device id all belong to the same person."

```cypher
(:User {id: u1})-[:HAS_EMAIL]->(:Email {address: "alice@..."})
(:User {id: u1})-[:HAS_PHONE]->(:Phone {number: "+1..."})
(:User {id: u2})-[:HAS_PHONE]->(:Phone {number: "+1..."})    // same phone

// merge — these two are the same person
MATCH (u1:User), (u2:User)-[:HAS_PHONE]->(p:Phone)<-[:HAS_PHONE]-(u1)
WHERE u1 <> u2
CALL apoc.refactor.mergeNodes([u1, u2]) YIELD node
RETURN node;
```

APOC's merge handles relationship deduping.

### Knowledge graph (Graphiti pattern)

For AI agent memory:

```cypher
(:Person {name: "Alice"})-[:LIVES_IN {since: t1, valid_to: NULL}]->(:City {name: "Tokyo"})
(:Person {name: "Alice"})-[:WORKS_AT]->(:Company {name: "Acme"})
(:Company {name: "Acme"})-[:HEADQUARTERED_IN]->(:City {name: "SF"})

// "Where does Alice live?"
MATCH (p:Person {name: "Alice"})-[r:LIVES_IN]->(c:City)
WHERE r.valid_to IS NULL
RETURN c.name;

// "When did Alice move to Tokyo?"
MATCH (p:Person {name: "Alice"})-[r:LIVES_IN]->(c:City {name: "Tokyo"})
RETURN r.since;
```

Graphiti automates this entity + relationship extraction from text using LLMs. See [`memory-layer/01-dual-memory-architecture.md`](../../memory-layer/01-dual-memory-architecture.md).

### Permissions (ReBAC, Google Zanzibar–style)

```cypher
(:User {id: alice})-[:MEMBER_OF]->(:Group {name: "engineering"})
(:Group {name: "engineering"})-[:CAN]->(:Permission {action: "read"})-[:ON]->(:Resource {id: doc_42})

// can alice read doc_42?
MATCH (alice:User {id: $uid})-[:MEMBER_OF*]->(g:Group)-[:CAN]->(p:Permission {action: "read"})-[:ON]->(r:Resource {id: $rid})
RETURN count(p) > 0 AS allowed;
```

Variable-length `MEMBER_OF*` handles nested groups.

For production permissions: consider OpenFGA / SpiceDB — they're purpose-built. Neo4j works but you're building a permissions service from scratch.

## When to embed properties vs split into another node

Embed when:
- Property is intrinsic to the entity (`User.email`, `Order.total_cents`)
- Cardinality is bounded
- Always retrieved together

Split when:
- Property has its own identity (a `Tag` referenced from many `Posts`)
- High cardinality (don't put 10K tags in a User node's array)
- You want to query "find all entities with this property value" — easier with separate nodes

```cypher
// embed
(:User {id, email, name, created_at})

// split — tags as nodes
(:User)-[:TAGGED]->(:Tag {name: "vip"})
(:User)-[:TAGGED]->(:Tag {name: "early-adopter"})

// query: all VIP users
MATCH (u:User)-[:TAGGED]->(t:Tag {name: "vip"})
RETURN u;
```

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| No constraints / indexes | Every query scans all nodes of a label — slow |
| Storing dates as strings | Use Neo4j's temporal types (`datetime()`, `date()`) |
| Internal `id()` exposed in API | Use a property `id` (UUID) — internal IDs change |
| Properties as JSON strings | Properties are first-class — use real types |
| One mega-label "Thing" | Use specific labels (`User`, `Order`); query via `MATCH (n:Thing)` rare |
| Bidirectional relationships duplicated | One direction; query both with `<-[:REL]-` or `[:REL]-` (no arrow) |
| Variable-length paths without bound | `*1..5` not `*` — unbounded explodes |
| Single hot node (super-node) | Re-model — distribute load via intermediate nodes |
| Trying to do RDBMS aggregations | Use APOC / GDS, or stream out + aggregate in app |
| Treating Neo4j as transactional system of record | Use it for graph, Postgres for the rest |
