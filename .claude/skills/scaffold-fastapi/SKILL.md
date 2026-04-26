---
name: scaffold-fastapi
description: Use when the user wants to scaffold a new FastAPI project with the layered claudeforge architecture (routes/services/repositories/models), SQLAlchemy 2.0 async + asyncpg + Alembic, Pydantic v2 settings, JWT auth, pytest with real-DB integration, structlog, OpenTelemetry, Docker dev setup, and uv. Triggers on phrases like "new fastapi project", "scaffold fastapi", "fastapi backend", "fastapi with postgres".
---

# Scaffold FastAPI Project (claudeforge)

Follow the master prompt at `backend/fastapi/PROMPT.md` for the complete spec. Steps:

1. **Confirm project parameters** with the user — ask only for ones you don't already have:
   - `project_name`, `project_slug` (snake_case), `db_name`, `api_port`
   - whether to include: Celery, JWT auth, OpenTelemetry
2. **Read the master prompt**: `backend/fastapi/PROMPT.md`. It contains the full directory tree, dependencies, key files (pyproject.toml, ruff.toml, config.py, main.py, db/session.py, repositories/base.py, tests/conftest.py), and generation steps.
3. **Read the deep-dive guides as needed** when generating each layer:
   - `backend/fastapi/01-project-layout.md` — layer rules
   - `backend/fastapi/02-sqlalchemy-and-alembic.md` — model + migration patterns
   - `backend/fastapi/03-pydantic-and-validation.md` — schema patterns
   - `backend/fastapi/04-auth-and-middleware.md` (if include_auth)
   - `backend/fastapi/05-async-and-celery.md` (if include_celery)
   - `backend/fastapi/06-testing-pytest.md` — test setup
4. **Generate the scaffold** following the prompt's step-by-step section: create dirs, write files, scaffold one example feature (users) end-to-end as a working pattern.
5. **Verify**: `uv sync`, `uv run pytest`, `uv run ruff check .` — all clean.
6. **Hand off**: tell the user the next steps (set up Postgres, run migrations, start dev server).

Do not skip the layered architecture. Do not collapse into "everything in main.py". The discipline is the value.
