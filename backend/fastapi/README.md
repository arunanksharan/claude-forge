# FastAPI — claudeforge guides

Production-grade FastAPI scaffolding with strict layered architecture.

## Files

| File | What it is | Read when |
|------|-----------|-----------|
| [`PROMPT.md`](./PROMPT.md) | The master scaffold prompt — paste into Claude Code to generate a full project | Starting a new FastAPI project |
| [`01-project-layout.md`](./01-project-layout.md) | Layering rationale + import rules + per-layer code examples | Understanding the architecture; onboarding |
| [`02-sqlalchemy-and-alembic.md`](./02-sqlalchemy-and-alembic.md) | Async engine, model patterns, query patterns, migration discipline | Working with the data layer |
| [`03-pydantic-and-validation.md`](./03-pydantic-and-validation.md) | Settings, schemas, validators, common Pydantic v2 gotchas | Designing API request/response shapes |
| [`04-auth-and-middleware.md`](./04-auth-and-middleware.md) | JWT, OAuth2, dependencies vs middleware, RBAC | Adding authentication |
| [`05-async-and-celery.md`](./05-async-and-celery.md) | BackgroundTasks vs Celery vs arq decision matrix; Celery setup | Adding background work |
| [`06-testing-pytest.md`](./06-testing-pytest.md) | pytest-asyncio, factories, integration tests against real DB | Writing tests |

## Quick decision summary

- **Python 3.12+** with **uv** package manager
- **SQLAlchemy 2.0 async** + **asyncpg** + **Alembic** for the data layer
- **Pydantic v2** with **pydantic-settings** for config
- **structlog** for logging, **OpenTelemetry** for tracing/metrics
- **pytest** + **pytest-asyncio** + **factory-boy** for tests, real Postgres in Docker
- **Celery** for serious background work, **BackgroundTasks** for fire-and-forget
- **ruff** for lint+format (not black/isort/flake8)
- **mypy strict** or **pyright** for type checking

## Anti-patterns rejected

- Pydantic v1, sync SQLAlchemy, psycopg2, Tortoise ORM
- Flask / Django for greenfield
- poetry (use uv), pip + requirements.txt
- "Everything in main.py" — use the layered scaffold
- `utils/` junk drawer
- Active Record fat models — services own logic, models are dumb
