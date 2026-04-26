# Auth & Middleware

> JWT, OAuth2, dependencies vs middleware. When to roll your own and when to reach for a library.

## Decision: hand-rolled JWT vs fastapi-users vs Authlib

| Need | Pick |
|------|------|
| Email + password, JWTs, refresh tokens, RBAC — that's it | **Hand-roll** (~300 LOC). You'll understand and own it. |
| Plus social login (Google, GitHub, etc.) | **fastapi-users** + appropriate OAuth backends |
| Plus enterprise SSO (SAML, OIDC IdPs) | **Authlib** + likely a separate auth service or use Auth0/Clerk/WorkOS |
| Multi-tenant with tenant-scoped tokens | Hand-roll, with care |
| Anything involving "compliance" (SOC2, HIPAA) | Use a managed IdP (Auth0, Clerk, WorkOS, Cognito) — don't reinvent |

The patterns below cover the hand-rolled case. The library cases follow the same dependency-injection shape — only the token-issuing part changes.

## Password hashing

```python
# core/security.py
from passlib.context import CryptContext

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto", bcrypt__rounds=12)


def hash_password(plain: str) -> str:
    return pwd_context.hash(plain)


def verify_password(plain: str, hashed: str) -> bool:
    return pwd_context.verify(plain, hashed)
```

**Don't** use SHA-* directly. **Don't** use MD5. **Don't** roll your own KDF.
**Do** use bcrypt with rounds ≥12 (or argon2id if you want fancier). Adjust rounds so hashing takes ~250–500ms.

## JWT issue + verify

```python
# core/security.py (continued)
from datetime import datetime, timedelta, UTC
from typing import Literal
import jwt
from pydantic import BaseModel

from {{project-slug}}.config import get_settings

settings = get_settings()


class TokenPayload(BaseModel):
    sub: str                                # user id (string!)
    type: Literal["access", "refresh"]
    exp: datetime
    iat: datetime


def create_access_token(user_id: str) -> str:
    now = datetime.now(UTC)
    payload = TokenPayload(
        sub=user_id,
        type="access",
        iat=now,
        exp=now + timedelta(minutes=settings.jwt_access_expires_minutes),
    )
    return jwt.encode(
        payload.model_dump(mode="json"),
        settings.jwt_secret.get_secret_value(),
        algorithm=settings.jwt_algorithm,
    )


def create_refresh_token(user_id: str) -> str:
    now = datetime.now(UTC)
    payload = TokenPayload(
        sub=user_id,
        type="refresh",
        iat=now,
        exp=now + timedelta(days=settings.jwt_refresh_expires_days),
    )
    return jwt.encode(
        payload.model_dump(mode="json"),
        settings.jwt_secret.get_secret_value(),
        algorithm=settings.jwt_algorithm,
    )


def decode_token(token: str) -> TokenPayload:
    raw = jwt.decode(
        token,
        settings.jwt_secret.get_secret_value(),
        algorithms=[settings.jwt_algorithm],
    )
    return TokenPayload(**raw)
```

### Why two tokens

- **Access token (short-lived, ~15min):** sent on every request. If leaked, blast radius is bounded.
- **Refresh token (long-lived, ~30 days):** stored more carefully (httpOnly cookie ideally), used only to get new access tokens.

If you use only one long-lived token, you have to either accept long-blast-radius leaks or implement server-side blacklisting (defeats most of JWT's stateless appeal).

### Token storage on the client

| Storage | Pros | Cons |
|---------|------|------|
| **httpOnly cookie** (with SameSite=Lax/Strict + Secure) | XSS-safe; browser handles attachment | CSRF risk → mitigated by SameSite + token endpoints |
| **localStorage** | Easy, works everywhere | XSS = full token theft. Fine only if you 100% trust your CSP. |
| **memory only** | Most XSS-safe | Lost on refresh; need refresh-token roundtrip on each load |

For most web apps: refresh in httpOnly cookie, access in memory. Mobile: secure storage (Keychain / Keystore).

## The auth dependency

```python
# deps.py
from typing import Annotated
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer

from {{project-slug}}.core.security import decode_token
from {{project-slug}}.models.user import User
from {{project-slug}}.repositories.user import UserRepository
from {{project-slug}}.deps import DbSession

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/v1/auth/login", auto_error=False)


async def get_current_user(
    token: Annotated[str | None, Depends(oauth2_scheme)],
    session: DbSession,
) -> User:
    if token is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "missing token")
    try:
        payload = decode_token(token)
    except Exception as exc:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "invalid token") from exc

    if payload.type != "access":
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "wrong token type")

    repo = UserRepository(session)
    user = await repo.get(UUID(payload.sub))
    if user is None or not user.is_active:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "user not found or disabled")
    return user


CurrentUser = Annotated[User, Depends(get_current_user)]
```

Now any route that needs auth:

```python
@router.get("/me")
async def me(user: CurrentUser) -> UserResponse:
    return UserResponse.model_validate(user)
```

That's it. Add `CurrentUser` to a route → it's authed.

## Login route

```python
# api/v1/auth.py
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm

from {{project-slug}}.core.security import create_access_token, create_refresh_token
from {{project-slug}}.deps import get_user_service
from {{project-slug}}.exceptions import InvalidCredentials
from {{project-slug}}.schemas.auth import TokenPair

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/login", response_model=TokenPair)
async def login(
    form: Annotated[OAuth2PasswordRequestForm, Depends()],
    service: UserService = Depends(get_user_service),
):
    try:
        user = await service.authenticate(form.username, form.password)
    except InvalidCredentials:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "invalid credentials")

    return TokenPair(
        access_token=create_access_token(str(user.id)),
        refresh_token=create_refresh_token(str(user.id)),
        token_type="bearer",
    )
```

`OAuth2PasswordRequestForm` accepts `username` + `password` form data — Swagger UI plays nice with it.

## Authorization (RBAC)

Roles on the user model + a dependency factory:

```python
from enum import StrEnum
from typing import Iterable
from fastapi import Depends, HTTPException, status


class Role(StrEnum):
    USER = "user"
    ADMIN = "admin"


def require_role(*allowed: Role):
    async def checker(user: CurrentUser) -> User:
        if user.role not in allowed:
            raise HTTPException(status.HTTP_403_FORBIDDEN, "insufficient role")
        return user
    return checker


@router.delete("/users/{id}")
async def delete_user(
    id: UUID,
    user: Annotated[User, Depends(require_role(Role.ADMIN))],
    service: UserService = Depends(get_user_service),
):
    await service.delete(id)
```

For richer authorization (resource-level: "can edit this org's projects"), use a policy object inside the service rather than smearing checks across routes.

## Middleware vs dependencies

| Use middleware for | Use dependencies for |
|-------------------|---------------------|
| Cross-cutting concerns on every request: CORS, request ID injection, response headers, GZip | Per-route concerns: auth, role check, rate limit per user, DB session |
| Things that don't need access to route metadata | Things that need to know which route, what params, what user |
| Body-streaming behaviors (request size limit) | Anything with parameter dependencies |

Middleware in FastAPI:

```python
@app.middleware("http")
async def add_request_id(request: Request, call_next):
    request_id = request.headers.get("X-Request-ID") or str(uuid4())
    request.state.request_id = request_id
    response = await call_next(request)
    response.headers["X-Request-ID"] = request_id
    return response
```

Dependencies are stronger when you need: body parsing, the DB session, the current user, OpenAPI documentation. Middleware is right when you need: low-level body access, headers on all responses uniformly.

## Rate limiting

For most apps, **slowapi** is fine:

```python
from slowapi import Limiter
from slowapi.util import get_remote_address

limiter = Limiter(key_func=get_remote_address)
app.state.limiter = limiter

@router.post("/login")
@limiter.limit("5/minute")
async def login(request: Request, ...):
    ...
```

For real protection (per-user, distributed across instances), use Redis-backed rate limiting and a real WAF/CDN (Cloudflare).

## CSRF

If you store the access token in localStorage / Authorization header → CSRF doesn't apply (cross-origin reads are blocked).

If you store tokens in cookies → enable `SameSite=Lax` (default in modern browsers) and consider adding a double-submit token for state-changing endpoints.

## API keys (for service-to-service / 3rd-party)

Different concept from user JWTs. Pattern:

- Generate a key + display **once** to the user
- Store only the hash (`sha256` is fine here — not a password)
- Lookup by prefix (first 8 chars indexed) + verify the rest
- Scope keys to specific permissions

```python
class ApiKey(Base, TimestampMixin):
    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id"))
    prefix: Mapped[str] = mapped_column(String(8), index=True)
    key_hash: Mapped[str] = mapped_column(String(64))
    scopes: Mapped[list[str]] = mapped_column(JSONB, default=list)
    last_used_at: Mapped[datetime | None]
    expires_at: Mapped[datetime | None]
```

## OAuth2 / social login (when needed)

Don't roll it. Use `fastapi-users` with the social backend:

```python
from fastapi_users.authentication import JWTStrategy, BearerTransport, AuthenticationBackend
from httpx_oauth.clients.google import GoogleOAuth2

google_client = GoogleOAuth2(client_id, client_secret)
```

Or for simple cases, `Authlib` works well too. Either way: auth callback → match/create user → issue your own JWT (don't pass through provider tokens to the client).

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| `jwt.decode` accepts `algorithms=None` and you didn't notice | Always pass `algorithms=[settings.jwt_algorithm]` — never None |
| Using `algorithms=["HS256", "RS256"]` while accepting attacker's `alg` | Lock to exactly one algorithm |
| Long-lived access tokens | 15min max, refresh on demand |
| Storing JWTs in localStorage on a site with user-generated content | Just don't. Use cookies + SameSite. |
| Not invalidating refresh tokens on logout | Maintain a refresh-token table or use a quick deny-list in Redis |
| Hashed passwords with low rounds (<10) | Bcrypt cost 12+; argon2id is better |
| Returning `WWW-Authenticate` with sensitive info | Generic "invalid token" — never tell which check failed |
| Same-secret across environments | Each env has its own JWT secret. Rotate periodically. |
