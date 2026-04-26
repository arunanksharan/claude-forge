# SQLAlchemy 2.0 (async) + Alembic

> Patterns for the data layer: engine setup, models, migrations, transactions, common pitfalls.

## Why SQLAlchemy 2.0 async (and not the alternatives)

| Option | Verdict |
|--------|---------|
| **SQLAlchemy 2.0 async** | **Pick this.** Mature, widely deployed, full async path with `asyncpg`. New 2.0 syntax (`Mapped[...]`, `mapped_column`) is much nicer than 1.x. |
| SQLModel | Fine for tiny apps. Couples you to Pydantic in the model layer (no clean separation). Doesn't add much over SA 2.0 + Pydantic. |
| Tortoise ORM | Smaller ecosystem, weaker migration story (aerich vs Alembic), fewer integrations. |
| Django ORM | Different framework. |
| Raw asyncpg | Use only if you have <5 tables and zero plans to grow. |
| Prisma (Python) | Generated client, sync-first, weak typing of joins. Skip. |

## Engine + session setup

The engine and session factory live in `db/session.py`. Singleton — created once at module import, disposed in app `lifespan`.

```python
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession

engine = create_async_engine(
    str(settings.database_url),         # postgresql+asyncpg://...
    pool_size=10,
    max_overflow=20,
    pool_pre_ping=True,                  # detect dropped connections
    pool_recycle=1800,                   # recycle connections every 30min
    echo=settings.database_echo,
)

SessionLocal = async_sessionmaker(
    engine,
    class_=AsyncSession,
    expire_on_commit=False,              # avoid lazy-load after commit
    autoflush=False,                     # explicit flushes only
)
```

**Why `expire_on_commit=False`:** after commit, SQLAlchemy normally expires all loaded objects so they re-fetch on next access. In async code you can't do an implicit re-fetch — so any access to a model attribute after commit raises `DetachedInstanceError`. Disabling expire makes models behave as snapshots after commit. You almost always want this.

**Why `autoflush=False`:** autoflush triggers DB writes on read queries when there's pending changes. In async code this can cause subtle ordering bugs. Be explicit: call `await session.flush()` when you need it.

## Session lifecycle

The dependency in `deps.py` opens a session, yields it, commits on success, rolls back on exception.

```python
async def get_session() -> AsyncIterator[AsyncSession]:
    async with SessionLocal() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise
        finally:
            await session.close()
```

**One session per request.** Don't open a new session inside a service. Inject the session via the repo via the service.

## Base model + mixins

```python
# models/base.py
from datetime import datetime, UTC
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, declared_attr
from sqlalchemy import DateTime, MetaData


class Base(DeclarativeBase):
    metadata = MetaData(
        naming_convention={
            "ix": "ix_%(column_0_label)s",
            "uq": "uq_%(table_name)s_%(column_0_name)s",
            "ck": "ck_%(table_name)s_%(constraint_name)s",
            "fk": "fk_%(table_name)s_%(column_0_name)s_%(referred_table_name)s",
            "pk": "pk_%(table_name)s",
        }
    )


class TimestampMixin:
    @declared_attr
    def created_at(cls) -> Mapped[datetime]:
        return mapped_column(DateTime(timezone=True), default=lambda: datetime.now(UTC), nullable=False)

    @declared_attr
    def updated_at(cls) -> Mapped[datetime]:
        return mapped_column(
            DateTime(timezone=True),
            default=lambda: datetime.now(UTC),
            onupdate=lambda: datetime.now(UTC),
            nullable=False,
        )


class SoftDeleteMixin:
    @declared_attr
    def deleted_at(cls) -> Mapped[datetime | None]:
        return mapped_column(DateTime(timezone=True), nullable=True, index=True)
```

**Why the `naming_convention`:** Alembic auto-names indexes/constraints. Without a convention, names drift between dev/prod (especially when a constraint is renamed). Locking the convention means your migration diffs are stable.

**Why explicit `lambda` defaults instead of `func.now()`:** keeps timestamp generation in Python, which is testable. `func.now()` is fine too — pick one and be consistent.

## Models — patterns

### Foreign keys + relationships

```python
class Order(Base, TimestampMixin):
    __tablename__ = "orders"

    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    total_cents: Mapped[int]
    status: Mapped[OrderStatus] = mapped_column(SAEnum(OrderStatus), index=True)

    user: Mapped["User"] = relationship(back_populates="orders", lazy="raise")
    items: Mapped[list["OrderItem"]] = relationship(
        back_populates="order",
        cascade="all, delete-orphan",
        lazy="raise",
    )
```

**`lazy="raise"` is the magic.** It makes implicit lazy loads raise an error instead of silently issuing extra queries (and hanging in async code). You're forced to use `selectinload()` / `joinedload()` explicitly. This kills N+1 problems at compile time.

### Eager loading

```python
from sqlalchemy.orm import selectinload

stmt = (
    select(Order)
    .where(Order.user_id == user_id)
    .options(selectinload(Order.items))
    .order_by(Order.created_at.desc())
)
```

`selectinload` issues one extra query per relationship (good for has-many). `joinedload` issues one query with a JOIN (good for has-one or belongs-to). Default to `selectinload` for collections.

### Enums

```python
from enum import StrEnum

class OrderStatus(StrEnum):
    PENDING = "pending"
    PAID = "paid"
    SHIPPED = "shipped"
    CANCELLED = "cancelled"
```

`StrEnum` (Python 3.11+) serializes to JSON as the string value naturally. SQLAlchemy `SAEnum` will create a Postgres ENUM type — fine, but adding values requires a migration. If your enum values change frequently, store as `String` and validate in Pydantic instead.

### UUIDs vs auto-increment IDs

Default to **UUIDs** (specifically UUIDv7 if you can — sortable). Reasons: no leak of cardinality, safe to expose in URLs, easy to merge across shards, no auto-increment race conditions.

```python
from uuid_extensions import uuid7   # pip install uuid7

id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid7)
```

If you have legacy sync ID requirements (joins to existing systems with int IDs), use bigints — but rarely worth it for new tables.

## Querying patterns

### `select` everywhere — never `query()`

The 1.x `Session.query()` API is legacy. Use `select()` + `session.execute()`:

```python
from sqlalchemy import select, func

# scalar
user = (await session.execute(select(User).where(User.id == uid))).scalar_one_or_none()

# list
users = (await session.execute(select(User).limit(50))).scalars().all()

# count
total = (await session.execute(select(func.count()).select_from(User))).scalar_one()

# specific columns
rows = (await session.execute(select(User.id, User.email))).all()
```

### Pagination

Two flavors. Use **cursor pagination** for any list that grows unbounded (timelines, notifications, audit logs). Use **offset pagination** for small finite lists (admin tables) where total + page-jump matters.

```python
# cursor (better)
async def list_after(repo, cursor: UUID | None, limit: int = 50) -> list[Order]:
    stmt = select(Order).order_by(Order.id).limit(limit)
    if cursor is not None:
        stmt = stmt.where(Order.id > cursor)
    return list((await repo.session.execute(stmt)).scalars().all())

# offset (simple)
async def list_paginated(repo, page: int, size: int = 50):
    stmt = select(Order).order_by(Order.created_at.desc()).limit(size).offset((page - 1) * size)
    items = list((await repo.session.execute(stmt)).scalars().all())
    total = (await repo.session.execute(select(func.count()).select_from(Order))).scalar_one()
    return {"items": items, "total": total, "page": page, "size": size}
```

## Transactions

The session-per-request dependency commits at the end. Inside a request, you usually don't need explicit transactions — everything you do in the session is one logical unit.

If you need an explicit nested transaction (savepoint):

```python
async with session.begin_nested():
    await repo.create(user)
    await repo.create(audit_log)
    # if this block raises, only this savepoint rolls back
```

**Don't sprinkle `await session.commit()` inside services.** The lifecycle owns commits. Services flush if they need an ID back from an insert; commits are at the boundary.

## Alembic setup

`alembic.ini` — minimal, point it at the env.py:

```ini
[alembic]
script_location = alembic
prepend_sys_path = .
version_path_separator = os
sqlalchemy.url =                ; intentionally blank — env.py reads from settings
```

`alembic/env.py` — load metadata from your Base, use the async engine:

```python
import asyncio
from logging.config import fileConfig
from alembic import context
from sqlalchemy import pool
from sqlalchemy.ext.asyncio import async_engine_from_config

from {{project-slug}}.config import get_settings
from {{project-slug}}.db.base import Base
# IMPORTANT: import all models so they register on Base.metadata
from {{project-slug}} import models  # noqa: F401

config = context.config
config.set_main_option("sqlalchemy.url", str(get_settings().database_url))

if config.config_file_name is not None:
    fileConfig(config.config_file_name)

target_metadata = Base.metadata


def do_run_migrations(connection):
    context.configure(
        connection=connection,
        target_metadata=target_metadata,
        compare_type=True,                     # detect column type changes
        compare_server_default=True,
        render_as_batch=False,
    )
    with context.begin_transaction():
        context.run_migrations()


async def run_migrations_online():
    connectable = async_engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )
    async with connectable.connect() as connection:
        await connection.run_sync(do_run_migrations)
    await connectable.dispose()


def run_migrations_offline():
    context.configure(url=config.get_main_option("sqlalchemy.url"), target_metadata=target_metadata, literal_binds=True)
    with context.begin_transaction():
        context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    asyncio.run(run_migrations_online())
```

The critical line: **`from {{project-slug}} import models`**. Alembic only sees what's been imported. If you autogenerate without importing, your migration will be empty. Have an `__init__.py` in `models/` that imports every model, so this single line pulls them all in.

## Migration discipline

| Rule | Why |
|------|-----|
| **One migration per merged PR**, not one per commit | Easier to review, rebase, revert |
| **Always write the down-migration**, even if you'd never use it | Forces you to think about reversibility; helps when rebasing |
| **Inspect autogenerate output before committing** | It misses `server_default` changes, type narrowing on Postgres ENUMs, certain index changes |
| **Never edit a migration that's been merged** | Create a new one instead |
| **Use `op.execute()` for data migrations** | Schema migrations should be pure DDL; data migrations are often safer as separate scripts |
| **Concurrent index creation in Postgres** | Use `op.create_index(..., postgresql_concurrently=True)` and set `transactional_ddl = False` for that file |
| **Backfill before constraint** | Add nullable column → backfill → set NOT NULL. Three separate migrations. Never one. |
| **Test migrations on a prod-sized snapshot** before deploying | A 30-second migration on dev can be 6 hours on prod |

### Generating a migration

```bash
uv run alembic revision --autogenerate -m "add orders table"
```

Then **read the generated file**. Always. Common things to fix manually:

- Indexes that should be `CONCURRENTLY`
- ENUMs that need explicit `op.execute("ALTER TYPE ... ADD VALUE ...")`
- Default values that you want server-side, not Python-side
- Columns being dropped — verify nothing in older app versions reads them (zero-downtime!)

### Zero-downtime migrations

If you have any uptime requirement, follow the **expand → migrate → contract** pattern:

1. **Expand:** add new column/table/index. Old code keeps working.
2. **Migrate:** deploy new code that writes both old and new. Backfill in a separate job.
3. **Contract:** in a *later* migration, drop the old column once nothing reads it.

Never combine these in one migration — you'll hit a window where running app instances see a schema they don't understand.

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| `MissingGreenlet` error inside an async context | You called sync SQLAlchemy. Wrap in `await session.run_sync(...)` or rewrite. |
| `DetachedInstanceError` after commit | `expire_on_commit=False` (default in our setup) — make sure you set it. |
| N+1 queries on relationship access | `lazy="raise"` on relationships forces you to be explicit; use `selectinload`. |
| Slow autoincrement bottleneck | Switch to UUIDv7. |
| Migration autogen produces empty diff | Forgot to import models in `alembic/env.py`. |
| Postgres ENUM new value won't apply | Run `ALTER TYPE ... ADD VALUE ...` explicitly in a migration. |
| Connection pool exhaustion | Increase `pool_size`/`max_overflow`. Check for sessions held across `await` of slow external calls — extract those out of the session scope. |
| `prepared statement already exists` with PgBouncer (transaction mode) | Set `prepared_statement_cache_size=0` on the asyncpg connection or `statement_cache_size=0` in the URL query string. |

## Useful Makefile targets

```makefile
migrate:
	uv run alembic upgrade head

migration:
	uv run alembic revision --autogenerate -m "$(name)"

downgrade:
	uv run alembic downgrade -1

migrate-history:
	uv run alembic history --verbose

migrate-current:
	uv run alembic current
```

Then `make migration name="add orders table"` and `make migrate`.
