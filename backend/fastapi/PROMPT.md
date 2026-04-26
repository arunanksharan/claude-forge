# FastAPI Project — Master Scaffold Prompt

> **Copy this entire file into Claude Code (or any LLM). Replace `{{placeholders}}`. The model will scaffold a production-grade FastAPI project following the layered architecture below.**

---

## Context for the model

You are scaffolding a new FastAPI project. The project follows a strict layered architecture (routes → services → repositories → models). Your job is to generate the full scaffold according to the rules in this document. Do not invent extra layers. Do not skip layers. Do not add a "utils" dump folder. Do not pick libraries other than the ones listed.

If something is ambiguous (e.g. "do they want soft-delete?"), **ask once, then proceed**. Don't ask 10 questions in sequence.

## Project parameters (fill these in)

```
project_name:       {{project-name}}            # e.g. orderflow
project_slug:       {{project-slug}}            # e.g. orderflow (snake_case, used in package names)
description:        {{one-line-description}}
db_name:            {{db-name}}                 # e.g. orderflow_dev
api_port:           {{api-port}}                # e.g. 8000
python_version:     3.12
include_celery:     {{yes-or-no}}
include_auth:       {{yes-or-no}}               # JWT-based auth?
include_otel:       {{yes-or-no}}               # OpenTelemetry instrumentation?
```

---

## Locked stack

These are non-negotiable defaults. If the user pushes back on a specific one, override only that one.

| Concern | Pick | Why |
|---------|------|-----|
| Python | **3.12+** | Modern type system, faster, free-threaded coming |
| Package manager | **uv** | 10-100x faster than pip, lockfile, project management |
| Web framework | **FastAPI** (latest) | Async-first, Pydantic-native, OpenAPI free |
| ASGI server | **uvicorn** (dev) / **gunicorn + uvicorn workers** (prod) | Standard combo |
| ORM | **SQLAlchemy 2.0** async | The mature choice; SQLModel is fine but couples you to Pydantic in the model layer |
| DB driver | **asyncpg** (Postgres) | Fastest async Postgres driver |
| Migrations | **Alembic** | The only real option for SQLAlchemy |
| Validation | **Pydantic v2** | Already required by FastAPI |
| Settings | **pydantic-settings** | Type-safe env loading |
| Auth | **fastapi-users** *or* hand-rolled JWT (see `04-auth-and-middleware.md`) | Hand-roll if needs are simple; fastapi-users for full-featured |
| HTTP client | **httpx** (async) | Same author as Starlette/FastAPI |
| Background jobs | **Celery** + Redis broker (heavy) *or* **arq** (lighter, async-native) | See `05-async-and-celery.md` |
| Logging | **structlog** | Structured logs, JSON in prod, pretty in dev |
| Observability | **OpenTelemetry** | Vendor-neutral; ship to SigNoz/Tempo/Datadog |
| Testing | **pytest** + **pytest-asyncio** + **httpx.AsyncClient** | Standard |
| Linting/format | **ruff** (lint + format) | Replaces black/isort/flake8 |
| Type checking | **mypy** strict *or* **pyright** | Pick one; pyright is faster |

## Rejected (do not use unless explicitly asked)

| Library | Why not |
|---------|---------|
| Flask / Django | Different framework; not what we're building |
| Pydantic v1 | EOL — only Pydantic v2 |
| sync SQLAlchemy / Django ORM | Async path is mandatory in FastAPI |
| psycopg2 | Sync only; use asyncpg |
| Tortoise ORM | Smaller ecosystem, fewer migration tools |
| Beanie/Motor (unless MongoDB) | If using Mongo, see `databases/mongodb/` |
| poetry | uv is faster and is the new default in 2025+ |
| pip + requirements.txt | Use uv lockfile |
| black + isort + flake8 | Replaced by ruff |
| pylint | Slow; ruff covers 95% |
| python-dotenv (alone) | pydantic-settings handles it |
| FastAPI tutorial-style "everything in main.py" | Won't survive past 1000 LOC |
| `utils/` folder | Becomes a junk drawer |

---

## Directory layout (generate this exactly)

```
{{project-slug}}/
├── pyproject.toml
├── uv.lock
├── README.md
├── .env.example
├── .python-version            # 3.12
├── .gitignore
├── ruff.toml
├── alembic.ini
├── docker-compose.dev.yml
├── Dockerfile
├── Makefile
├── alembic/
│   ├── env.py
│   ├── script.py.mako
│   └── versions/
└── src/
    └── {{project-slug}}/
        ├── __init__.py
        ├── main.py                   # FastAPI app factory + lifespan
        ├── config.py                 # pydantic-settings Settings class
        ├── deps.py                   # FastAPI dependencies (db session, current user, etc.)
        ├── exceptions.py             # custom exception classes + handlers
        ├── logging.py                # structlog setup
        ├── telemetry.py              # OpenTelemetry setup (if include_otel)
        ├── db/
        │   ├── __init__.py
        │   ├── base.py               # SQLAlchemy DeclarativeBase
        │   └── session.py            # async engine + session factory
        ├── api/
        │   ├── __init__.py
        │   ├── router.py             # aggregate APIRouter
        │   ├── v1/
        │   │   ├── __init__.py
        │   │   ├── health.py
        │   │   └── {{feature}}.py    # one file per feature/resource
        │   └── middleware.py
        ├── core/
        │   ├── __init__.py
        │   ├── security.py           # password hashing, JWT encode/decode
        │   └── pagination.py         # cursor + offset pagination helpers
        ├── models/                   # SQLAlchemy models
        │   ├── __init__.py
        │   ├── base.py               # Base + common columns (id, created_at, updated_at)
        │   └── {{feature}}.py
        ├── schemas/                  # Pydantic schemas (request/response)
        │   ├── __init__.py
        │   └── {{feature}}.py        # RequestCreate, RequestUpdate, Response, ListResponse
        ├── repositories/             # data access only — no business logic
        │   ├── __init__.py
        │   ├── base.py               # generic CRUDRepository[Model] base
        │   └── {{feature}}.py
        ├── services/                 # business logic — framework-agnostic
        │   ├── __init__.py
        │   └── {{feature}}.py
        ├── workers/                  # Celery / arq tasks (if include_celery)
        │   ├── __init__.py
        │   ├── celery_app.py
        │   └── {{feature}}_tasks.py
        └── integrations/             # external HTTP / SDK wrappers
            ├── __init__.py
            └── {{external-service}}.py

tests/
├── conftest.py                       # fixtures: db, client, factories
├── factories/                        # factory_boy factories
│   └── {{feature}}.py
├── unit/
│   └── services/
│       └── test_{{feature}}_service.py
└── integration/
    └── api/v1/
        └── test_{{feature}}_endpoints.py
```

## Layering rules (enforce strictly)

| Layer | Allowed to import from | Not allowed |
|-------|----------------------|-------------|
| `api/` (routes) | `services/`, `schemas/`, `deps`, `exceptions` | `repositories/`, `models/` directly |
| `services/` | `repositories/`, `models/`, `integrations/`, `core/` | `api/`, `schemas/` (use plain dicts or domain dataclasses) |
| `repositories/` | `models/`, `db/` | `services/`, `api/`, `schemas/` |
| `models/` | `db/base` | nothing else |
| `schemas/` | `models/` (only for `from_attributes=True`) | services / repos |
| `workers/` | `services/`, `repositories/`, `db/` | `api/` |

Why this matters: if a route imports a repository directly, business logic creeps into routes. If a service imports a schema, the service becomes coupled to HTTP shapes and you can't reuse it from a Celery worker. The discipline here is what makes the codebase still navigable at 50K LOC.

---

## Key files (generate these with real content, not stubs)

### `pyproject.toml`

```toml
[project]
name = "{{project-slug}}"
version = "0.1.0"
description = "{{one-line-description}}"
requires-python = ">=3.12"
dependencies = [
    "fastapi>=0.115",
    "uvicorn[standard]>=0.32",
    "gunicorn>=23",
    "sqlalchemy[asyncio]>=2.0.36",
    "asyncpg>=0.30",
    "alembic>=1.14",
    "pydantic>=2.10",
    "pydantic-settings>=2.7",
    "httpx>=0.28",
    "structlog>=24.4",
    "python-multipart>=0.0.20",
    # auth (if include_auth)
    "passlib[bcrypt]>=1.7.4",
    "pyjwt>=2.10",
    # otel (if include_otel)
    "opentelemetry-api>=1.29",
    "opentelemetry-sdk>=1.29",
    "opentelemetry-instrumentation-fastapi>=0.50b0",
    "opentelemetry-instrumentation-sqlalchemy>=0.50b0",
    "opentelemetry-instrumentation-httpx>=0.50b0",
    "opentelemetry-exporter-otlp>=1.29",
    # celery (if include_celery)
    "celery[redis]>=5.4",
    "redis>=5.2",
]

[dependency-groups]
dev = [
    "ruff>=0.8",
    "mypy>=1.13",
    "pytest>=8.3",
    "pytest-asyncio>=0.24",
    "pytest-cov>=6.0",
    "factory-boy>=3.3",
    "faker>=33",
    "httpx>=0.28",
    "asgi-lifespan>=2.1",
]

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[tool.pytest.ini_options]
asyncio_mode = "auto"
testpaths = ["tests"]
addopts = "-ra --strict-markers --strict-config"

[tool.mypy]
python_version = "3.12"
strict = true
plugins = ["pydantic.mypy"]
```

### `ruff.toml`

```toml
target-version = "py312"
line-length = 100

[lint]
select = [
    "E", "F", "W",          # pycodestyle + pyflakes
    "I",                    # isort
    "B",                    # bugbear
    "UP",                   # pyupgrade
    "N",                    # pep8-naming
    "S",                    # bandit
    "ASYNC",                # async pitfalls
    "RUF",                  # ruff-specific
]
ignore = ["S101"]           # allow asserts in tests

[lint.per-file-ignores]
"tests/**/*.py" = ["S105", "S106"]  # hardcoded passwords ok in tests
```

### `src/{{project-slug}}/config.py`

```python
from functools import lru_cache
from pydantic import Field, PostgresDsn
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
        case_sensitive=False,
    )

    env: str = Field(default="development")
    debug: bool = Field(default=False)
    api_port: int = Field(default={{api-port}})
    api_host: str = Field(default="0.0.0.0")

    database_url: PostgresDsn
    database_pool_size: int = Field(default=10)
    database_max_overflow: int = Field(default=20)
    database_echo: bool = Field(default=False)

    redis_url: str = Field(default="redis://localhost:6379/0")

    jwt_secret: str = Field(default="changeme")
    jwt_algorithm: str = Field(default="HS256")
    jwt_access_expires_minutes: int = Field(default=15)
    jwt_refresh_expires_days: int = Field(default=30)

    otel_enabled: bool = Field(default=False)
    otel_endpoint: str = Field(default="http://localhost:4317")
    otel_service_name: str = Field(default="{{project-slug}}")

    log_level: str = Field(default="INFO")
    log_format: str = Field(default="json")  # json | console


@lru_cache
def get_settings() -> Settings:
    return Settings()
```

### `src/{{project-slug}}/main.py`

```python
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from {{project-slug}}.config import get_settings
from {{project-slug}}.api.router import api_router
from {{project-slug}}.exceptions import register_exception_handlers
from {{project-slug}}.logging import configure_logging
from {{project-slug}}.db.session import engine


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings = get_settings()
    configure_logging(settings)

    if settings.otel_enabled:
        from {{project-slug}}.telemetry import setup_telemetry
        setup_telemetry(app, settings)

    yield

    await engine.dispose()


def create_app() -> FastAPI:
    settings = get_settings()
    app = FastAPI(
        title="{{project-name}}",
        version="0.1.0",
        debug=settings.debug,
        lifespan=lifespan,
    )

    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"] if settings.debug else [],
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    register_exception_handlers(app)
    app.include_router(api_router, prefix="/api")
    return app


app = create_app()
```

### `src/{{project-slug}}/db/session.py`

```python
from typing import AsyncIterator
from sqlalchemy.ext.asyncio import (
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)

from {{project-slug}}.config import get_settings

settings = get_settings()

engine = create_async_engine(
    str(settings.database_url),
    pool_size=settings.database_pool_size,
    max_overflow=settings.database_max_overflow,
    echo=settings.database_echo,
    pool_pre_ping=True,
)

SessionLocal = async_sessionmaker(
    engine,
    class_=AsyncSession,
    expire_on_commit=False,
    autoflush=False,
)


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

### `src/{{project-slug}}/repositories/base.py`

```python
from typing import Generic, TypeVar
from uuid import UUID
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from {{project-slug}}.models.base import Base

ModelT = TypeVar("ModelT", bound=Base)


class CRUDRepository(Generic[ModelT]):
    model: type[ModelT]

    def __init__(self, session: AsyncSession):
        self.session = session

    async def get(self, id_: UUID) -> ModelT | None:
        return await self.session.get(self.model, id_)

    async def list(self, *, limit: int = 50, offset: int = 0) -> list[ModelT]:
        stmt = select(self.model).limit(limit).offset(offset)
        result = await self.session.execute(stmt)
        return list(result.scalars().all())

    async def create(self, obj: ModelT) -> ModelT:
        self.session.add(obj)
        await self.session.flush()
        return obj

    async def delete(self, obj: ModelT) -> None:
        await self.session.delete(obj)
        await self.session.flush()
```

### `tests/conftest.py`

```python
import pytest
import pytest_asyncio
from httpx import AsyncClient, ASGITransport
from asgi_lifespan import LifespanManager
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine, async_sessionmaker

from {{project-slug}}.main import create_app
from {{project-slug}}.config import get_settings
from {{project-slug}}.db.base import Base
from {{project-slug}}.deps import get_db_session


@pytest.fixture(scope="session")
def settings():
    s = get_settings()
    s.database_url = s.database_url.replace("/{{db-name}}", "/{{db-name}}_test")  # type: ignore
    return s


@pytest_asyncio.fixture
async def db_engine(settings):
    engine = create_async_engine(str(settings.database_url))
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)
    yield engine
    await engine.dispose()


@pytest_asyncio.fixture
async def db_session(db_engine) -> AsyncSession:
    async with db_engine.connect() as conn:
        trans = await conn.begin()
        Session = async_sessionmaker(bind=conn, expire_on_commit=False)
        async with Session() as session:
            yield session
        await trans.rollback()


@pytest_asyncio.fixture
async def client(db_session):
    app = create_app()

    async def override_db():
        yield db_session

    app.dependency_overrides[get_db_session] = override_db

    async with LifespanManager(app):
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
            yield ac
```

---

## Generation steps (model: do these in order)

1. **Confirm parameters** with the user — list them back, ask for any you don't have.
2. **Create the directory tree** exactly as shown above.
3. **Write `pyproject.toml` and `ruff.toml`** — include only the optional deps the user opted into.
4. **Write `config.py`, `main.py`, `db/session.py`, `db/base.py`** — these are foundational.
5. **Write the layered scaffold for ONE example feature** (e.g. "users") — model, schema, repository, service, route. This shows the pattern.
6. **Write `tests/conftest.py` and one example test file** — shows the test layout.
7. **Write `alembic/env.py`** wired to the async engine, plus `alembic.ini`. Run `uv run alembic init alembic` first if needed, then customize.
8. **Write `Dockerfile`, `docker-compose.dev.yml`, `Makefile`** with common targets (`dev`, `test`, `lint`, `migrate`, `migration name=...`).
9. **Write `README.md`** with: setup, running locally, running tests, creating migrations.
10. **Run `uv sync`** to materialize the venv. **Run `uv run pytest`** — should pass with zero tests collected (or with the one example test passing).
11. **Run `uv run ruff check . && uv run ruff format --check .`** — should be clean.

If any step fails, **fix it before moving on** rather than soldiering through.

---

## Companion deep-dive files

After the scaffold is up, refer to these for the patterns within each layer:

- [`01-project-layout.md`](./01-project-layout.md) — layering rationale + import rules in detail
- [`02-sqlalchemy-and-alembic.md`](./02-sqlalchemy-and-alembic.md) — async engine, model patterns, migration discipline
- [`03-pydantic-and-validation.md`](./03-pydantic-and-validation.md) — settings, schema patterns, validators, common pitfalls
- [`04-auth-and-middleware.md`](./04-auth-and-middleware.md) — JWT, OAuth2, dependencies vs middleware
- [`05-async-and-celery.md`](./05-async-and-celery.md) — when to use FastAPI background tasks vs Celery vs arq
- [`06-testing-pytest.md`](./06-testing-pytest.md) — fixture composition, factories, integration tests
