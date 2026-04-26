# Testing FastAPI with pytest

> Fixture composition, factories, integration tests against a real database. No mocking what you can run for real.

## Test pyramid

| Type | Speed | Realism | Use for |
|------|-------|---------|---------|
| **Unit tests** (services, in isolation) | <10ms | Low | Pure logic: validators, calculations, state machines. Mock the repo. |
| **Integration tests** (route → service → repo → real DB) | 50–500ms | High | Most of your tests. Use a real Postgres in Docker. |
| **E2E tests** (full app, real services) | seconds | Highest | Critical user flows only |

Default to **integration tests against a real DB**. They're fast enough with the right fixtures, and they catch the bugs unit tests miss (SQL bugs, transaction bugs, JSON shape drift).

## Setup

```toml
# pyproject.toml
[dependency-groups]
dev = [
    "pytest>=8.3",
    "pytest-asyncio>=0.24",
    "pytest-cov>=6.0",
    "factory-boy>=3.3",
    "faker>=33",
    "httpx>=0.28",
    "asgi-lifespan>=2.1",
    "polyfactory>=2.18",   # alternative to factory-boy, plays nicer with pydantic
]

[tool.pytest.ini_options]
asyncio_mode = "auto"
testpaths = ["tests"]
addopts = "-ra --strict-markers --strict-config -p no:cacheprovider"
markers = [
    "slow: marks tests as slow (deselect with '-m \"not slow\"')",
    "integration: marks integration tests",
]
```

`asyncio_mode = "auto"` makes every `async def test_...` automatically work as an async test. Without it you have to decorate each one.

## Test database strategy

Three options, in increasing complexity:

| Strategy | Setup time per test | Isolation | When |
|----------|---------------------|-----------|------|
| **Drop & recreate schema once per session, transaction rollback per test** | ~5ms | Strong | Default. Fast and clean. |
| **One temp DB per test** (`pg_tmp` or per-test `CREATE DATABASE`) | ~200ms | Strongest | When tests need to commit (rare) |
| **Truncate tables between tests** | ~20ms | Strong | When you have schema-level state that breaks rollback |

Use the first one unless you have a specific reason not to.

## `tests/conftest.py`

```python
import pytest
import pytest_asyncio
from httpx import AsyncClient, ASGITransport
from asgi_lifespan import LifespanManager
from sqlalchemy.ext.asyncio import (
    AsyncSession,
    create_async_engine,
    async_sessionmaker,
)

from {{project-slug}}.main import create_app
from {{project-slug}}.config import get_settings
from {{project-slug}}.db.base import Base
from {{project-slug}}.deps import get_session


@pytest.fixture(scope="session")
def settings():
    s = get_settings()
    # rewrite db url to test db
    s.database_url = str(s.database_url).rsplit("/", 1)[0] + "/{{db-name}}_test"  # type: ignore
    return s


@pytest_asyncio.fixture(scope="session")
async def db_engine(settings):
    """Create schema once per session."""
    engine = create_async_engine(str(settings.database_url))
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)
    yield engine
    await engine.dispose()


@pytest_asyncio.fixture
async def db_session(db_engine):
    """Per-test session, wrapped in a transaction that rolls back."""
    async with db_engine.connect() as conn:
        trans = await conn.begin()
        Session = async_sessionmaker(bind=conn, expire_on_commit=False)
        async with Session() as session:
            try:
                yield session
            finally:
                await trans.rollback()


@pytest_asyncio.fixture
async def client(db_session):
    """Test client with the DB session overridden to the test transaction."""
    app = create_app()

    async def override_db():
        yield db_session

    app.dependency_overrides[get_session] = override_db

    async with LifespanManager(app):
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as ac:
            yield ac

    app.dependency_overrides.clear()
```

The trick: every test runs inside a transaction; the transaction is rolled back at teardown; the next test sees a clean DB. Schema is created once per pytest session.

### Run migrations vs `create_all` in tests

| Option | Pros | Cons |
|--------|------|------|
| `Base.metadata.create_all()` | Fast | Bypasses migrations — they could drift from models |
| `alembic upgrade head` | Tests the migrations themselves | Slower setup |

I use `create_all` for fast iteration + a separate CI job that runs `alembic upgrade head` against an empty DB and asserts no drift via `alembic check`.

## Factories

`factory-boy` for ORM-style factories:

```python
# tests/factories/user.py
import factory
from factory.alchemy import SQLAlchemyModelFactory
from {{project-slug}}.models.user import User
from {{project-slug}}.core.security import hash_password


class UserFactory(SQLAlchemyModelFactory):
    class Meta:
        model = User
        sqlalchemy_session_persistence = "flush"

    email = factory.Sequence(lambda n: f"user{n}@example.com")
    hashed_password = factory.LazyFunction(lambda: hash_password("hunter2"))
    is_active = True
```

Wire the session into factories via a fixture:

```python
@pytest_asyncio.fixture
async def factories(db_session):
    UserFactory._meta.sqlalchemy_session = db_session
    return type("F", (), {"user": UserFactory})
```

Use:

```python
async def test_login(client, factories, db_session):
    user = factories.user(email="alice@example.com")
    await db_session.flush()

    resp = await client.post("/api/v1/auth/login", data={
        "username": "alice@example.com",
        "password": "hunter2",
    })
    assert resp.status_code == 200
```

### `polyfactory` alternative

For Pydantic-first projects, `polyfactory` is cleaner — generates valid models from a schema with optional overrides.

## Test layout

```
tests/
├── conftest.py
├── factories/
│   ├── __init__.py
│   ├── user.py
│   └── order.py
├── unit/
│   └── services/
│       ├── test_user_service.py        # mock repo, test logic
│       └── test_order_pricing.py
└── integration/
    └── api/
        └── v1/
            ├── test_auth_endpoints.py
            ├── test_user_endpoints.py
            └── test_order_endpoints.py
```

## Unit test (service in isolation)

```python
# tests/unit/services/test_user_service.py
from unittest.mock import AsyncMock
import pytest
from {{project-slug}}.services.user import UserService
from {{project-slug}}.exceptions import EmailAlreadyExists


async def test_register_rejects_duplicate_email():
    repo = AsyncMock()
    existing_user = object()
    repo.get_by_email.return_value = existing_user

    service = UserService(repo)

    with pytest.raises(EmailAlreadyExists):
        await service.register(email="alice@example.com", password="hunter2")
```

Fast, focused, no DB. Useful for pure logic — pricing rules, state transitions, validators.

## Integration test (route → DB)

```python
# tests/integration/api/v1/test_user_endpoints.py
async def test_create_user_returns_201(client):
    resp = await client.post("/api/v1/users", json={
        "email": "alice@example.com",
        "password": "hunter22",
    })
    assert resp.status_code == 201
    body = resp.json()
    assert body["email"] == "alice@example.com"
    assert "id" in body
    assert "hashed_password" not in body  # never leak


async def test_create_user_rejects_duplicate(client, factories, db_session):
    factories.user(email="alice@example.com")
    await db_session.flush()

    resp = await client.post("/api/v1/users", json={
        "email": "alice@example.com",
        "password": "anything12",
    })
    assert resp.status_code == 409
    assert resp.json()["error"]["code"] == "email_already_exists"
```

The whole stack: HTTP serialization, route handler, service, repo, real Postgres queries. Catches bugs at every layer.

## Authenticated test client

A fixture that returns a client pre-authenticated as a user:

```python
@pytest_asyncio.fixture
async def auth_client(client, factories, db_session):
    user = factories.user()
    await db_session.flush()

    from {{project-slug}}.core.security import create_access_token
    token = create_access_token(str(user.id))

    client.headers["Authorization"] = f"Bearer {token}"
    return client, user


async def test_me(auth_client):
    client, user = auth_client
    resp = await client.get("/api/v1/users/me")
    assert resp.status_code == 200
    assert resp.json()["id"] == str(user.id)
```

## Mocking external services

Use **VCR-style cassettes** (`vcrpy` or `pytest-recording`) to record real HTTP interactions once and replay them:

```python
@pytest.mark.vcr
async def test_charge_card_succeeds(auth_client):
    resp = await auth_client.post("/api/v1/orders/123/pay")
    assert resp.status_code == 200
```

First run hits the real (sandbox) API and records to `cassettes/`. Subsequent runs replay. Fast, deterministic, real shapes.

For services without sandboxes, use `respx` (made by the httpx folks):

```python
import respx
import httpx

@respx.mock
async def test_external_call():
    route = respx.post("https://example.com/webhook").mock(
        return_value=httpx.Response(200, json={"ok": True})
    )
    # ... code that calls example.com ...
    assert route.called
```

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| Tests pass locally, fail in CI | DB state leaks. Check transaction rollback fixture. |
| `IntegrityError` on second test in same module | Sequence/uuid collision — use `factory.Sequence` or `factory.LazyFunction(uuid4)` |
| Slow test suite (>30s for 100 tests) | Move schema setup to session scope; use transaction rollback per test, not truncate |
| `RuntimeError: Event loop is closed` | Missing `asyncio_mode = "auto"`, or mixing sync and async fixtures |
| `DependencyOverrides` leaks between tests | Always `app.dependency_overrides.clear()` in teardown |
| Test reads stale data after a write | The test transaction wraps everything; verify both reads and writes use the same `db_session` |
| Coverage low because of `# pragma: no cover` everywhere | Don't suppress; refactor the uncovered branches into smaller functions and test them |
| Flaky tests | Almost always a real bug — timing, ordering, leaked state. Don't `pytest-rerunfailures` your way out. |

## Coverage

Aim for ~80%+ on services (where the logic lives), ~60%+ overall. Don't chase 100% — testing trivial getters wastes time.

```bash
uv run pytest --cov=src/{{project-slug}} --cov-report=term-missing --cov-report=html
```

Set a CI floor (e.g. `--cov-fail-under=70`) so coverage doesn't silently regress.

## Speed tricks

- `pytest -n auto` (`pytest-xdist`) parallelizes — but you'll need a per-worker DB, otherwise tests fight over the same rows
- Use `pytest -m "not slow"` for quick local runs; mark slow integration tests with `@pytest.mark.slow`
- Run only the test file you're working on: `uv run pytest tests/integration/api/v1/test_user_endpoints.py::test_create_user_returns_201 -x`
