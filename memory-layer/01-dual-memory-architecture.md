# Dual-Memory Architecture (Graphiti + Mem0)

> **Adapted from a production cross-channel AI memory system serving voice + chat channels in regulated markets. The Graphiti-as-truth + Mem0-as-cache pattern, identity resolution, query routing, and bi-temporal model are real and battle-tested.**
>
> Use this as a reference architecture for any AI agent that needs durable, cross-session, multi-channel memory. The compliance section uses APAC frameworks as examples — substitute GDPR/CCPA/HIPAA as needed.

## Executive Summary

The dual-memory architecture is an enterprise-grade, cross-channel memory system that combines **Graphiti** (temporal knowledge graph) as the source of truth with **Mem0** as the voice-optimized cache layer. This hybrid architecture enables:

- **<100ms retrieval** for voice channels (latency critical)
- **Bi-temporal queries** for text channels ("When did I...", "What was my...")
- **Cross-channel continuity** with unified user identity
- **Privacy compliance** (PDPA/APPI/GDPR/CCPA) — example uses APAC frameworks; same pattern applies for Western markets

---

## 1. System Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                              MEMORY SYSTEM                                   │
├─────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                      │
│  USER CHANNELS                                                                       │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐              │
│  │  VOICE   │  │ WEBSITE  │  │ WHATSAPP │  │  EMAIL   │  │   BSS    │              │
│  │(VoiceApp)│  │  (Chat)  │  │  (Bot)   │  │  (Bot)   │  │(Transact)│              │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘              │
│       │             │             │             │             │                      │
│       └─────────────┴─────────────┴─────────────┴─────────────┘                      │
│                                   │                                                  │
│                                   ▼                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────────┐    │
│  │                        IDENTITY RESOLUTION LAYER                             │    │
│  │   channel_identifier (phone, email, device_id) → unified_user_id             │    │
│  └─────────────────────────────────────────────────────────────────────────────┘    │
│                                   │                                                  │
│                                   ▼                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────────┐    │
│  │                         QUERY ROUTING LAYER                                  │    │
│  │                                                                              │    │
│  │   VOICE → MEM0_ONLY (latency critical, <200ms)                               │    │
│  │   TEMPORAL → GRAPHITI_PRIMARY ("When did I...")                              │    │
│  │   RELATIONSHIP → GRAPHITI_PRIMARY ("Who is connected to...")                 │    │
│  │   SIMPLE_FACT → MEM0_PRIMARY with Graphiti fallback                          │    │
│  └─────────────────────────────────────────────────────────────────────────────┘    │
│                          │                           │                               │
│                          ▼                           ▼                               │
│  ┌───────────────────────────────┐  ┌───────────────────────────────────────────┐  │
│  │      MEM0 INTEGRATION         │  │            GRAPHITI CORE                   │  │
│  │   (Voice-Optimized Cache)     │  │         (Source of Truth)                  │  │
│  │                               │  │                                            │  │
│  │  • <100ms retrieval           │  │  • Bi-temporal knowledge graph             │  │
│  │  • mentions (TTL=24h)         │  │  • Entity/relationship extraction          │  │
│  │  • validated_facts (no TTL)   │  │  • Conflict resolution                     │  │
│  │  • Vector similarity search   │  │  • Historical queries                      │  │
│  │                               │  │                                            │  │
│  │         ┌─────────┐           │  │         ┌─────────┐                        │  │
│  │         │ QDRANT  │           │  │         │  NEO4J  │                        │  │
│  │         └─────────┘           │  │         └─────────┘                        │  │
│  └───────────────────────────────┘  └───────────────────────────────────────────┘  │
│                          │                           │                               │
│                          └───────────┬───────────────┘                               │
│                                      ▼                                               │
│  ┌─────────────────────────────────────────────────────────────────────────────┐    │
│  │                          SYNC MECHANISM                                      │    │
│  │                                                                              │    │
│  │   WRITE: Conversation → Mem0 (immediate) → Queue → Graphiti (async)          │    │
│  │   READ:  Graphiti validates → Syncs to Mem0 → Cache invalidation             │    │
│  └─────────────────────────────────────────────────────────────────────────────┘    │
│                                                                                      │
│  ┌─────────────────────────────────────────────────────────────────────────────┐    │
│  │                          CACHING LAYER (REDIS)                               │    │
│  │                                                                              │    │
│  │   prefetch:context:{tenant}:{user} → PrefetchedContext (TTL: 5min)           │    │
│  │   graphiti:sync:queue → Job IDs (FIFO)                                       │    │
│  │   graphiti:sync:job:{job_id} → Job data (TTL: 7 days)                        │    │
│  └─────────────────────────────────────────────────────────────────────────────┘    │
│                                                                                      │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Why Two Systems? Mem0 + Graphiti

### 2.1 The Problem

| Requirement | Mem0 Alone | Graphiti Alone |
|-------------|------------|----------------|
| Voice latency (<100ms) | ✅ | ❌ (~300ms) |
| Temporal queries | ❌ | ✅ |
| Conflict resolution | ❌ | ✅ |
| Entity extraction | ❌ | ✅ |
| Vector similarity | ✅ | ⚠️ (basic) |
| Pipecat integration | ✅ Native | ❌ |

### 2.2 The Solution: Hybrid Architecture

```
MEM0 = Speed Layer (Cache)
├── Stores: mentions (ephemeral, 24h TTL)
├── Stores: validated_facts (from Graphiti, no TTL)
├── Optimized for: Voice calls, simple queries
└── Latency: <100ms

GRAPHITI = Truth Layer (Knowledge Graph)
├── Stores: All facts with bi-temporal metadata
├── Processes: Entity extraction, relationship mapping
├── Resolves: Conflicting facts (old → t_invalid = now)
└── Latency: ~300ms (acceptable for text channels)
```

### 2.3 The Single Source of Truth Invariant

**CRITICAL**: Mem0 stores MENTIONS (ephemeral), not FACTS (authoritative).

```
User says "I moved to Shibuya"
  ├── Mem0 stores: MENTION (TTL=24h, ephemeral)
  ├── Graphiti processes: Extracts (User)-[:LIVES_IN]->(Shibuya)
  ├── Graphiti resolves: Old location gets t_invalid=now
  └── Graphiti syncs: Validated fact → Mem0 (no TTL, authoritative)
```

---

## 3. Memory Flow

### 3.1 Write Path (Memory Insertion)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         MEMORY INSERTION FLOW                            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  STEP 1: IMMEDIATE (Voice Pipeline, <50ms)                              │
│  ─────────────────────────────────────────                              │
│  Mem0.add_memory(                                                        │
│      content="User mentioned moving to Shibuya",                         │
│      memory_type="mention",  // NOT "validated_fact"                     │
│      ttl_hours=24            // Ephemeral                                │
│  )                                                                       │
│                                                                          │
│  STEP 2: BACKGROUND (Async Queue, <5 min)                               │
│  ────────────────────────────────────────                               │
│  GraphitiSyncService.queue_sync(transcript)                              │
│  → Worker: graphiti.add_episode(transcript)                              │
│  → Extraction: User --LIVES_IN--> Shibuya (t_valid=now)                  │
│  → Conflict: Old location gets t_invalid=now                             │
│                                                                          │
│  STEP 3: SYNC BACK (Hourly or on-validation)                            │
│  ───────────────────────────────────────────                            │
│  Mem0.sync_validated_fact(fact, graphiti_edge_uuid)                      │
│  → Stored with memory_type="validated_fact", no TTL                      │
│  → Old invalidated facts removed from Mem0                               │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### 3.2 Read Path (Memory Retrieval)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         MEMORY RETRIEVAL FLOW                            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  PATH A: VOICE CHANNEL (Latency Critical, <200ms)                       │
│  ────────────────────────────────────────────────                       │
│  QueryRouter.route("What's my plan?", channel=VOICE)                     │
│  → Decision: MEM0_ONLY                                                   │
│  → Mem0.search(query) → Qdrant vector similarity                         │
│  → Return: Cached facts + recent mentions                                │
│  → Latency: ~80ms                                                        │
│                                                                          │
│  PATH B: TEXT CHANNEL (Temporal Query)                                  │
│  ─────────────────────────────────────                                  │
│  QueryRouter.route("When did I upgrade?", channel=WHATSAPP)              │
│  → Decision: GRAPHITI_PRIMARY                                            │
│  → Graphiti.search(query) → Neo4j traversal + bi-temporal filter         │
│  → Return: Facts with t_valid/t_invalid metadata                         │
│  → Latency: ~150ms                                                       │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### 3.3 Voice Prefetch Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         VOICE PREFETCH FLOW                              │
│              (Must complete within WebRTC handshake: ~500ms)             │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  T=0ms     User clicks "Call" button                                     │
│  T=50ms    Backend receives call initiation                              │
│  T=100ms   PARALLEL PREFETCH (asyncio.TaskGroup):                        │
│            ├── Task 1: Graphiti.get_current_facts()                      │
│            ├── Task 2: TelcoProvider.get_context()                       │
│            ├── Task 3: SupportService.get_state()                        │
│            └── Task 4: Redis.get(cached_context)                         │
│  T=350ms   Context Assembly (PrefetchedContext)                          │
│  T=400ms   Cache in Redis (TTL: 5min)                                    │
│  T=420ms   Warm Mem0 with Graphiti facts                                 │
│  T=500ms   BUDGET EXHAUSTED - Return whatever we have                    │
│  T=1000ms  WebRTC handshake complete, audio ready                        │
│            Context is READY before user speaks                           │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 4. Data Models

### 4.1 Memory Types

| Type | TTL | Source | Use Case |
|------|-----|--------|----------|
| `mention` | 24h | Conversation | Ephemeral, unvalidated statements |
| `validated_fact` | None | Graphiti sync | Authoritative, from knowledge graph |
| `preference` | None | Explicit/inferred | User preferences |
| `context` | Session | Conversation | Current conversation context |

### 4.2 PrefetchedContext

```python
class PrefetchedContext:
    unified_user_id: str
    tenant_id: str
    account_id: str | None

    # From Graphiti (knowledge graph)
    facts: list[str]
    entities: list[dict]
    recent_changes: list[str]

    # From BSS/OSS (real-time, NOT stored)
    telco_context: TelcoContext | None
    telco_summary: str

    # From Support (shared across channels)
    support_state: SupportState | None
    support_summary: str

    # High-priority alerts
    alerts: list[str]

    # Metadata
    prefetch_time_ms: float
    source: str  # "graphiti" or "cache"
```

---

## 5. Key Design Principles

### 5.1 Channels Share Stabilized State, Not Conversations

- ✅ **Shared**: User facts (name, plan, location, preferences)
- ✅ **Shared**: Support state (open issues, SLA status)
- ❌ **Not Shared**: Conversation history (each channel has its own)

### 5.2 BSS/OSS Data is Authoritative

- Subscription, billing, usage data comes from BSS/OSS in real-time
- This data is NOT stored in memory (always fresh from source)
- Memory stores user-stated facts, not system-of-record data

### 5.3 Latency Budgets

| Operation | Budget | Strategy |
|-----------|--------|----------|
| Voice prefetch | 500ms | Parallel fetch, timeout with partial |
| Voice retrieval | 200ms | Mem0 only, no Graphiti |
| Text retrieval | 2000ms | Graphiti primary, Mem0 fallback |
| Sync to Graphiti | Async | Background queue |

---

## 6. Compliance

### 6.1 PDPA (Singapore) / APPI (Japan) / PDPL (Mongolia)

| Requirement | Implementation |
|-------------|----------------|
| Right to Access | Export all Graphiti edges + Mem0 memories |
| Right to Erasure | `Mem0.delete_user_memories()` + Graphiti node deletion |
| Data Minimization | TTL on mentions (24h), retention policies |
| Consent Tracking | Stored in user profile, checked before memory ops |

### 6.2 Tenant Isolation

- All queries filtered by `tenant_id`
- Mem0 user_id format: `{tenant_id}::{unified_user_id}`
- Graphiti `group_ids` include tenant_id

---

## 7. Service Roles & Responsibilities

### 7.1 Service Overview

The memory system consists of three distinct services, each with specific responsibilities:

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                              SERVICE ARCHITECTURE                                     │
├─────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                      │
│  ┌───────────────────────────────────────────────────────────────────────────────┐  │
│  │                    memory-service (Port 9000)                          │  │
│  │                         API Gateway & Orchestrator                             │  │
│  │                                                                                │  │
│  │  Responsibilities:                                                             │  │
│  │  • REST API for all memory operations                                         │  │
│  │  • Identity resolution (channel → unified user)                               │  │
│  │  • Query routing (Mem0 vs Graphiti based on channel/query type)               │  │
│  │  • Mem0 integration (self-hosted with Qdrant)                                 │  │
│  │  • Voice prefetch & caching (Redis)                                           │  │
│  │  • Compliance endpoints (PDPA/APPI deletion, export)                          │  │
│  │  • BSS/OSS integration for telco context                                      │  │
│  │  • Support state tracking                                                      │  │
│  │  • OpenTelemetry metrics & tracing                                            │  │
│  │                                                                                │  │
│  │  Databases Managed:                                                           │  │
│  │  • MongoDB: User profiles, episodes, channel identities                       │  │
│  │  • Qdrant: Vector embeddings for Mem0                                         │  │
│  │  • Redis: Caching, prefetch data, sync queues                                 │  │
│  └───────────────────────────────────────────────────────────────────────────────┘  │
│                                      │                                               │
│                                      │ HTTP (library or HTTP mode)                   │
│                                      ▼                                               │
│  ┌───────────────────────────────────────────────────────────────────────────────┐  │
│  │                      graphiti-service (Port 9011)                              │  │
│  │                    Knowledge Graph Microservice                                │  │
│  │                                                                                │  │
│  │  Responsibilities:                                                             │  │
│  │  • Wraps graphiti-core library                                                │  │
│  │  • Episode ingestion with LLM entity extraction                               │  │
│  │  • Relationship mapping using custom edge types                               │  │
│  │  • Bi-temporal fact management (valid_at, invalid_at)                         │  │
│  │  • Conflict resolution (superseded facts marked invalid)                      │  │
│  │  • Semantic search over knowledge graph                                       │  │
│  │  • Historical queries ("What was true at time T?")                            │  │
│  │                                                                                │  │
│  │  Custom Types (31 Entity + 31 Edge types):                                    │  │
│  │  • Entity: AppUser, MobilePlan, Device, Location, Preference, etc.        │  │
│  │  • Edge: Subscribes, LivesIn, TravelsTo, InterestedIn, Trusts, etc.           │  │
│  │                                                                                │  │
│  │  Databases Managed:                                                           │  │
│  │  • Neo4j: Knowledge graph nodes and edges                                     │  │
│  └───────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                      │
│  ┌───────────────────────────────────────────────────────────────────────────────┐  │
│  │                      sync-worker (Background)                         │  │
│  │                       Async Processing Worker                                  │  │
│  │                                                                                │  │
│  │  Responsibilities:                                                             │  │
│  │  • Polls Redis queue for sync jobs (every 30s)                                │  │
│  │  • Sends conversation transcripts to graphiti-service                         │  │
│  │  • Syncs validated facts to Mem0 after extraction                             │  │
│  │  • Invalidates Redis voice context cache                                      │  │
│  │  • Handles retries for failed jobs (up to 3 attempts)                         │  │
│  │  • Cleanup of old job records (daily at 4 AM)                                 │  │
│  │                                                                                │  │
│  │  Technology: ARQ (async Redis queue) worker                                   │  │
│  └───────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                      │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

### 7.2 Why Separate Services?

| Concern | memory-service | graphiti-service |
|---------|------------------------|------------------|
| **Scaling** | Scale for API traffic | Scale for LLM/Neo4j load |
| **Failure Isolation** | API stays up if Graphiti slow | Neo4j issues don't break API |
| **Deployment** | Frequent (API changes) | Rare (stable graph logic) |
| **Resource Profile** | Low latency, many connections | High compute (LLM calls) |
| **Technology** | FastAPI + multiple DBs | graphiti-core + Neo4j |

### 7.3 Communication Modes

The `memory-service` can communicate with Graphiti in two modes:

1. **Library Mode** (default for development):
   - Imports `graphiti-core` directly
   - No network overhead
   - Configuration: `GRAPHITI_USE_HTTP=false`

2. **HTTP Mode** (recommended for production):
   - Calls `graphiti-service` via HTTP
   - Better fault isolation
   - Configuration: `GRAPHITI_USE_HTTP=true`, `GRAPHITI_HTTP_URL=http://localhost:9011`

```python
# app/services/graphiti_factory.py determines which mode to use
client = await get_graphiti_client()  # Returns library client or HTTP client
```

### 7.4 Data Flow Between Services

```
VOICE CALL ENDS → /voice/sync API
                        │
                        ▼
               GraphitiSyncService.queue_sync()
                        │
                        ▼ (Redis Queue)
               graphiti:sync:queue
                        │
                        ▼ (every 30s)
               sync-worker
                        │
                        ▼ (HTTP or Library)
               graphiti-service.add_episode()
                        │
                        ├──► Neo4j: Store entities/edges
                        │
                        ▼
               sync_facts_to_mem0()
                        │
                        ├──► Mem0/Qdrant: Validated facts
                        │
                        ▼
               Redis: Invalidate voice cache
```

---

## 8. Custom Entity & Edge Types

### 8.1 Entity Types (31 total)

The system uses 31 custom Pydantic entity types for telecom domain extraction:

| Category | Entity Types |
|----------|-------------|
| **User** | AppUser, Person, Organization |
| **Telecom** | MobilePlan, AddOn, Device, SupportTicket, NetworkIssue |
| **Location** | Location |
| **Preference** | Preference, CommunicationStyle |
| **Personal** | Family, LifeEvent, Milestone, Goal, Memory, Hobby |
| **Financial** | PaymentMethod, BillingIssue, Promotion, Loyalty |
| **Temporal** | ScheduledEvent, SeasonalPattern |
| **AI Relationship** | ConversationTopic, EmotionalState, TrustLevel, ServiceInteraction, Feedback, Complaint, Resolution |

### 8.2 Edge Types (31 total)

| Category | Edge Types |
|----------|-----------|
| **Subscription** | Subscribes, UpgradedFrom, HasAddOn, InterestedIn, Purchased |
| **Location** | LivesIn, WorksIn, TravelsTo, VisitedLocation |
| **Support** | ReportedIssue, ResolvedIssue, ExperiencedOutage |
| **Preference** | Prefers, Dislikes |
| **Device** | Uses |
| **Personal** | Knows, RelatedTo, HasFamily, ExperiencedLifeEvent, AchievedMilestone, HasGoal, Remembers, EnjoysMentioned, BelongsToOrganization |
| **Financial** | UsesPaymentMethod, HasBillingIssue, ReceivedPromotion, HasLoyalty |
| **AI Relationship** | DiscussedTopic, FeltEmotion, HasTrustLevel, HadInteraction, GaveFeedback, FiledComplaint, ReceivedResolution |

### 8.3 Memory Scope by Avatar

| Memory Type | Scope | Description |
|-------------|-------|-------------|
| **identity** | GLOBAL | Shared across all avatars (name, phone, email) |
| **subscription** | GLOBAL | Current plan, billing status |
| **location** | GLOBAL | Home, work, travel destinations |
| **device** | GLOBAL | Phone model, IMEI |
| **preference** | AVATAR | Communication style per avatar |
| **topic_interest** | AVATAR | What they discussed with specific avatar |
| **emotional_state** | AVATAR | Trust level with specific avatar |
| **conversation_context** | AVATAR | Current conversation context |
