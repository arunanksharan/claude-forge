# Pydantic v2 + Validation Patterns

> Settings, schemas, validators. Pydantic v2 only — v1 is EOL.

## Settings (`config.py`)

`pydantic-settings` is the canonical way to load env vars with type safety.

```python
from functools import lru_cache
from pydantic import Field, PostgresDsn, SecretStr, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",                    # don't crash on unknown env vars
        case_sensitive=False,
    )

    env: str = Field(default="development")
    debug: bool = False
    api_port: int = 8000

    database_url: PostgresDsn
    redis_url: str = "redis://localhost:6379/0"

    jwt_secret: SecretStr                  # SecretStr never logs raw value
    jwt_algorithm: str = "HS256"

    cors_origins: list[str] = Field(default_factory=list)

    @field_validator("cors_origins", mode="before")
    @classmethod
    def parse_cors(cls, v: str | list[str]) -> list[str]:
        if isinstance(v, str):
            return [o.strip() for o in v.split(",") if o.strip()]
        return v


@lru_cache
def get_settings() -> Settings:
    return Settings()  # type: ignore[call-arg]
```

### Tips

- **`SecretStr` for any secret.** Logs as `**********` automatically. Access raw via `.get_secret_value()`.
- **`@lru_cache` on `get_settings()`.** Single instance per process. Tests can `get_settings.cache_clear()` between cases.
- **`extra="ignore"` not `"forbid"`.** Forbid is too strict — you'll get crashes when ops adds an env var the app doesn't yet know about.
- **CORS as a list, parsed from comma-separated env.** Env vars are strings; the validator converts.

### Multiple environments

Don't have `Settings`, `DevSettings`, `ProdSettings`. Have one Settings class with smart defaults and environment-aware logic in code.

## Schema patterns

The `Create` / `Update` / `Response` triad per resource.

```python
from pydantic import BaseModel, ConfigDict, EmailStr, Field, model_validator


class UserBase(BaseModel):
    email: EmailStr


class UserCreate(UserBase):
    password: str = Field(min_length=8, max_length=128)
    password_confirm: str

    @model_validator(mode="after")
    def passwords_match(self):
        if self.password != self.password_confirm:
            raise ValueError("passwords do not match")
        return self


class UserUpdate(BaseModel):
    email: EmailStr | None = None
    is_active: bool | None = None


class UserResponse(UserBase):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    is_active: bool
    created_at: datetime


class UserListResponse(BaseModel):
    items: list[UserResponse]
    total: int
    page: int
    size: int
```

### Why the triad

| Schema | Purpose |
|--------|---------|
| `Create` | Required fields. Validators that only apply on creation. |
| `Update` | All fields optional — partial update (PATCH semantics). |
| `Response` | What the client sees. Excludes internals (hashed password, internal flags). `from_attributes=True` to build from ORM. |

Don't reuse `Create` for response. The fields you accept and the fields you return are different in subtle ways (timestamps, computed fields, IDs).

### `from_attributes=True` (was `orm_mode`)

Lets you `UserResponse.model_validate(user_orm_object)`. Required for ORM → schema conversion.

## Validators — when to use which

| Decorator | When | Example |
|-----------|------|---------|
| `@field_validator` `mode="before"` | Coerce input before parsing (e.g. comma-split) | parse CORS origins from string |
| `@field_validator` `mode="after"` | Validate parsed value against business rule | min length on a Trimmed string |
| `@model_validator` `mode="after"` | Cross-field validation | passwords match, end date > start date |

Avoid putting **business** validation in schemas. Schemas validate **shape and format**. "User has not exceeded plan limit" is business — that goes in the service.

## Common types

| Need | Use |
|------|-----|
| Email | `EmailStr` |
| URL | `HttpUrl`, `AnyUrl`, `PostgresDsn` |
| UUID | `UUID` (from `uuid`) |
| Decimal money | `Decimal` (and serialize to string in Response) |
| Datetime | `datetime` — Pydantic v2 parses ISO 8601 by default; always store/return UTC |
| Constrained int | `Annotated[int, Field(gt=0, le=100)]` |
| Constrained string | `Annotated[str, StringConstraints(min_length=1, max_length=80, strip_whitespace=True)]` |
| Enum | Python `StrEnum` works directly |
| File upload | `UploadFile` from `fastapi` |
| Optional | `Foo \| None = None` (don't use `Optional[Foo]` — verbose) |

### Money — never use floats

```python
from decimal import Decimal
from pydantic import BaseModel, Field
from typing import Annotated

Money = Annotated[Decimal, Field(decimal_places=2, max_digits=18)]

class Order(BaseModel):
    total: Money
```

In responses, serialize to string:

```python
class OrderResponse(BaseModel):
    model_config = ConfigDict(json_encoders={Decimal: str})
    total: Decimal
```

JS clients lose precision on Decimal — always send as string.

## Custom annotated types

Reuse common constraints:

```python
from typing import Annotated
from pydantic import StringConstraints, Field

NonEmptyStr = Annotated[str, StringConstraints(min_length=1, strip_whitespace=True)]
Slug = Annotated[str, StringConstraints(min_length=1, max_length=80, pattern=r"^[a-z0-9-]+$")]
PositiveInt = Annotated[int, Field(gt=0)]
PageSize = Annotated[int, Field(ge=1, le=200, default=50)]
```

Then `class FooCreate(BaseModel): name: NonEmptyStr; slug: Slug`. Cleaner than repeating constraints.

## Pagination schema

```python
from pydantic import BaseModel
from typing import Generic, TypeVar

ItemT = TypeVar("ItemT")


class Page(BaseModel, Generic[ItemT]):
    items: list[ItemT]
    total: int
    page: int
    size: int

    @property
    def pages(self) -> int:
        return (self.total + self.size - 1) // self.size if self.size else 0
```

Then `Page[UserResponse]` everywhere. Pydantic v2 supports generics natively.

## Error responses

Standardize error shape:

```python
class ErrorDetail(BaseModel):
    code: str                  # machine-readable: "email_already_exists"
    message: str               # human-readable
    field: str | None = None   # for validation errors


class ErrorResponse(BaseModel):
    error: ErrorDetail
```

Register a handler in `exceptions.py`:

```python
from fastapi import Request
from fastapi.responses import JSONResponse


class AppException(Exception):
    code = "internal_error"
    status_code = 500
    message = "internal error"


class EmailAlreadyExists(AppException):
    code = "email_already_exists"
    status_code = 409
    message = "email already in use"


def register_exception_handlers(app: FastAPI):
    @app.exception_handler(AppException)
    async def handle_app_exception(request: Request, exc: AppException):
        return JSONResponse(
            status_code=exc.status_code,
            content={"error": {"code": exc.code, "message": exc.message}},
        )
```

Now services raise `EmailAlreadyExists()` and the route never has to catch it.

## Common Pydantic v2 gotchas

| Gotcha | Fix |
|--------|-----|
| `Config` class is gone | Use `model_config = ConfigDict(...)` |
| `parse_obj` / `parse_raw` removed | Use `model_validate` / `model_validate_json` |
| `dict()` removed | Use `model_dump()` |
| `json()` removed | Use `model_dump_json()` |
| Validators must be `@classmethod` and need `mode=` | New API — pre/post replaced by `mode="before"` / `mode="after"` |
| `Optional[X]` works but is verbose | Use `X \| None` (Python 3.10+) |
| Strict mode by default for some types | Use `Field(..., strict=False)` if you need coercion |
| `populate_by_name` for aliases | `model_config = ConfigDict(populate_by_name=True, alias_generator=...)` |

## Validation in routes vs services

- **Schema (Pydantic) validation = at the boundary.** Format, types, ranges, regex, required fields.
- **Business validation = in the service.** Uniqueness across DB, plan limits, role permissions, state machine transitions.

Don't try to do business validation in Pydantic by injecting a session. Pydantic should be pure; services touch the world.
