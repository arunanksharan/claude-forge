# FastAPI Project Layout & Layering

> Why the layered structure exists and what each layer is allowed to do. If you read one supporting file, read this one.

## The four layers

```
┌─────────────────────────────────────────────────────────────┐
│  api/  (routes)         ← HTTP shape only                   │
│      ▼                                                       │
│  services/              ← business logic, framework-free    │
│      ▼                                                       │
│  repositories/          ← data access only                  │
│      ▼                                                       │
│  models/  +  db/        ← SQLAlchemy schema                 │
└─────────────────────────────────────────────────────────────┘
```

Routes call services. Services call repositories. Repositories touch the DB. **Arrows only point downward.** A route never reaches into a repository directly. A service never imports a Pydantic schema.

## Why this matters

| Without layering | With layering |
|------------------|---------------|
| Logic spread across route handlers | Logic in services, callable from routes, Celery, CLI, tests |
| DB queries duplicated everywhere | One place per query — `repositories/{feature}.py` |
| Hard to test business logic without spinning HTTP | Services are plain async functions; mock the repo |
| Refactoring a column change touches 20 files | Touches the model + repo + maybe one service method |
| New developers can't find anything | New developers learn the layout in 10 minutes |

## Allowed imports per layer

| From | Can import | Cannot import |
|------|-----------|---------------|
| `api/v1/{feature}.py` | `services/{feature}`, `schemas/{feature}`, `deps`, `exceptions` | `repositories/`, `models/` directly |
| `services/{feature}.py` | `repositories/{feature}`, `models/{feature}`, `integrations/`, `core/` | `api/`, `schemas/` |
| `repositories/{feature}.py` | `models/{feature}`, `db/` | `services/`, `api/`, `schemas/` |
| `models/{feature}.py` | `models/base`, `db/base` | anything else |
| `schemas/{feature}.py` | `models/{feature}` (for `from_attributes=True`) | services, repositories |
| `workers/{feature}_tasks.py` | `services/{feature}`, `db/session` | `api/` |

Add a `# pyright: strict` or `mypy --strict` pass in CI to enforce some of this mechanically. For the rest, code review.

## What each layer looks like (one feature: `users`)

### `models/user.py`

```python
from datetime import datetime
from uuid import UUID, uuid4
from sqlalchemy import String
from sqlalchemy.orm import Mapped, mapped_column

from {{project-slug}}.models.base import Base, TimestampMixin


class User(Base, TimestampMixin):
    __tablename__ = "users"

    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    email: Mapped[str] = mapped_column(String(320), unique=True, index=True)
    hashed_password: Mapped[str] = mapped_column(String(255))
    is_active: Mapped[bool] = mapped_column(default=True)
```

Pure schema. No methods beyond what SQLAlchemy needs. No `def to_dict()`, no `def authenticate()`.

### `schemas/user.py`

```python
from datetime import datetime
from uuid import UUID
from pydantic import BaseModel, ConfigDict, EmailStr, Field


class UserCreate(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)


class UserUpdate(BaseModel):
    email: EmailStr | None = None
    is_active: bool | None = None


class UserResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    email: EmailStr
    is_active: bool
    created_at: datetime


class UserListResponse(BaseModel):
    items: list[UserResponse]
    total: int
```

The `Create` / `Update` / `Response` triad. `Update` fields are all optional. `Response` uses `from_attributes=True` so it can be built directly from a SQLAlchemy model.

### `repositories/user.py`

```python
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from {{project-slug}}.models.user import User
from {{project-slug}}.repositories.base import CRUDRepository


class UserRepository(CRUDRepository[User]):
    model = User

    def __init__(self, session: AsyncSession):
        super().__init__(session)

    async def get_by_email(self, email: str) -> User | None:
        stmt = select(User).where(User.email == email)
        result = await self.session.execute(stmt)
        return result.scalar_one_or_none()
```

Only data access. No password hashing here — that's logic. No "send welcome email" — that's logic. Just queries.

### `services/user.py`

```python
from {{project-slug}}.core.security import hash_password, verify_password
from {{project-slug}}.models.user import User
from {{project-slug}}.repositories.user import UserRepository
from {{project-slug}}.exceptions import EmailAlreadyExists, InvalidCredentials


class UserService:
    def __init__(self, repo: UserRepository):
        self.repo = repo

    async def register(self, email: str, password: str) -> User:
        existing = await self.repo.get_by_email(email)
        if existing is not None:
            raise EmailAlreadyExists(email)

        user = User(email=email, hashed_password=hash_password(password))
        return await self.repo.create(user)

    async def authenticate(self, email: str, password: str) -> User:
        user = await self.repo.get_by_email(email)
        if user is None or not verify_password(password, user.hashed_password):
            raise InvalidCredentials()
        return user
```

Pure logic. Returns models, raises domain exceptions. **Does not know about HTTP.** Could be called from a Celery worker, a CLI command, or a test, with no changes.

### `api/v1/users.py`

```python
from fastapi import APIRouter, Depends, status

from {{project-slug}}.deps import get_user_service
from {{project-slug}}.schemas.user import UserCreate, UserResponse
from {{project-slug}}.services.user import UserService

router = APIRouter(prefix="/users", tags=["users"])


@router.post("", response_model=UserResponse, status_code=status.HTTP_201_CREATED)
async def create_user(
    payload: UserCreate,
    service: UserService = Depends(get_user_service),
) -> UserResponse:
    user = await service.register(email=payload.email, password=payload.password)
    return UserResponse.model_validate(user)
```

Thin. HTTP shape in (`UserCreate`), service call, HTTP shape out (`UserResponse`). No business logic. No queries.

### `deps.py` (the wiring)

```python
from typing import Annotated
from fastapi import Depends
from sqlalchemy.ext.asyncio import AsyncSession

from {{project-slug}}.db.session import get_session
from {{project-slug}}.repositories.user import UserRepository
from {{project-slug}}.services.user import UserService

DbSession = Annotated[AsyncSession, Depends(get_session)]


def get_user_repository(session: DbSession) -> UserRepository:
    return UserRepository(session)


def get_user_service(repo: UserRepository = Depends(get_user_repository)) -> UserService:
    return UserService(repo)
```

This is the only place the layers are wired together. To unit test the service, instantiate it directly with a fake repo — no FastAPI, no HTTP.

## Anti-patterns to reject

### "Just put it in utils/"

`utils/` becomes a junk drawer. Every function lives somewhere with a real reason. Date formatting → `core/dates.py`. Pagination → `core/pagination.py`. If you genuinely need a one-off helper, put it next to the code that uses it.

### "I'll add the logic in the route, just this once"

It's never just this once. The next route reaches in too. After 6 months you have 200 routes with copy-pasted business logic. Push it into a service from day one, even if the service has one method.

### "Fat models" / Active Record

`User.authenticate()` is the Django way. In a layered async FastAPI app, models are dumb. Logic lives in services. Yes this means more files. Yes it's worth it.

### "I'll use the schema in the service for type safety"

Then your service is coupled to HTTP. Workers can't reuse it without instantiating Pydantic models awkwardly. Use plain dicts, dataclasses, or domain types — not schemas — at service boundaries.

### Skipping the repository layer because "ORM is the repo"

Without an explicit repository, every service has its own ad-hoc query. You can't see the data access surface. You can't easily swap MongoDB in. You can't add a query cache uniformly. The repo layer is cheap insurance.

## When to bend the rules

- **Read-only "view" endpoints** that are basically `SELECT * FROM v` can skip the service layer. Route → repo → response. Be honest about it.
- **Health checks** don't need a service.
- **Simple CRUD admin tools** that just expose models can use a generic `CRUDRouter` factory. Don't over-engineer.
- **Tiny scripts / one-off jobs** can use the repository directly.

The layering is for the 80% of code that's actual product logic. Don't make pure-CRUD endpoints carry 4 files of ceremony.
