# Auth with JWT (no Passport)

> Hand-rolled JWT auth in Express. Without Passport's middleware, just a clear flow.

## Why no Passport

Passport is a strategy registry built for the days of "support 50 OAuth providers." For a simple email + password + JWT setup it adds:

- A learning curve
- Decorator-style strategy classes
- An extra abstraction over the actual JWT logic

If you only need JWT (and maybe one OAuth provider), hand-roll. ~150 LOC.

If you need 5+ social providers + SAML + magic links + multi-factor, switch to:

- **better-auth** (newer, full-featured)
- **lucia-auth** (more focused, library-style)
- **next-auth / Auth.js** (if you're on Next anyway)
- **WorkOS / Clerk / Auth0** (managed)

## The shape

```
Request → authMiddleware → req.user → controller → service
```

## Tokens

`src/lib/jwt.ts`:

```typescript
import jwt, { type JwtPayload as Jwt } from 'jsonwebtoken';
import { env } from '../config/env';

export type TokenType = 'access' | 'refresh';

export interface Payload extends Jwt {
  sub: string;         // user id
  type: TokenType;
}

export function signAccessToken(userId: string): string {
  return jwt.sign({ sub: userId, type: 'access' }, env.JWT_SECRET, {
    expiresIn: env.JWT_ACCESS_EXPIRES,
    algorithm: 'HS256',
  });
}

export function signRefreshToken(userId: string): string {
  return jwt.sign({ sub: userId, type: 'refresh' }, env.JWT_SECRET, {
    expiresIn: env.JWT_REFRESH_EXPIRES,
    algorithm: 'HS256',
  });
}

export function verify(token: string): Payload {
  return jwt.verify(token, env.JWT_SECRET, { algorithms: ['HS256'] }) as Payload;
}
```

**Always pass `algorithms: ['HS256']` to verify.** Otherwise an attacker can supply `alg: 'none'` and bypass the signature.

## Password hashing

`src/lib/password.ts`:

```typescript
import bcrypt from 'bcrypt';

const ROUNDS = process.env.NODE_ENV === 'test' ? 4 : 12;

export const hashPassword = (plain: string) => bcrypt.hash(plain, ROUNDS);
export const verifyPassword = (plain: string, hash: string) => bcrypt.compare(plain, hash);
```

Lower rounds in tests so the suite isn't dominated by bcrypt. 12 in prod (~250ms).

## Auth middleware

`src/middleware/auth.ts`:

```typescript
import type { RequestHandler } from 'express';
import { Unauthorized } from '../lib/errors';
import { verify } from '../lib/jwt';

declare global {
  namespace Express {
    interface Request {
      user?: { id: string; role?: string };
    }
  }
}

export const authMiddleware: RequestHandler = (req, _res, next) => {
  const auth = req.header('authorization');
  if (!auth?.startsWith('Bearer ')) return next(new Unauthorized('missing bearer token'));
  const token = auth.slice(7);

  try {
    const payload = verify(token);
    if (payload.type !== 'access') return next(new Unauthorized('wrong token type'));
    req.user = { id: payload.sub };
    next();
  } catch (err) {
    next(new Unauthorized('invalid token'));
  }
};
```

The `declare global` augmentation gives you `req.user` typed everywhere it's read.

For the `req.user` to include richer info (email, role), you can either:

1. **Encode in the JWT** — pros: no DB lookup per request. Cons: stale on role change until token refresh.
2. **Look up from DB** — pros: always current. Cons: DB hit per request (cache it for 60s).

For most apps: encode `sub` only, look up other fields on demand in services. For high-traffic + RBAC: encode role and accept staleness.

## Auth service

`src/modules/auth/auth.service.ts`:

```typescript
import { Unauthorized } from '../../lib/errors';
import { signAccessToken, signRefreshToken, verify } from '../../lib/jwt';
import { verifyPassword } from '../../lib/password';
import type { UsersService } from '../users/users.service';

export function makeAuthService(users: UsersService) {
  return {
    async login(email: string, password: string) {
      const user = await users.findByEmail(email);
      if (!user || !(await verifyPassword(password, user.hashedPassword))) {
        throw new Unauthorized('invalid credentials');
      }
      return tokens(user.id);
    },

    async refresh(refreshToken: string) {
      let payload;
      try { payload = verify(refreshToken); }
      catch { throw new Unauthorized('invalid refresh token'); }
      if (payload.type !== 'refresh') throw new Unauthorized('wrong token type');

      const user = await users.findById(payload.sub);
      if (!user || !user.isActive) throw new Unauthorized();

      return tokens(user.id);
    },
  };
}

function tokens(userId: string) {
  return {
    accessToken: signAccessToken(userId),
    refreshToken: signRefreshToken(userId),
    tokenType: 'Bearer' as const,
  };
}
```

## Auth controller + routes

```typescript
import { Router } from 'express';
import { z } from 'zod';
import { asyncHandler } from '../../lib/async-handler';
import { validateBody } from '../../middleware/validate';

const loginSchema = z.object({ email: z.string().email(), password: z.string() });
const refreshSchema = z.object({ refreshToken: z.string() });

export function makeAuthController(service: ReturnType<typeof makeAuthService>) {
  return {
    login: asyncHandler(async (req, res) => {
      const { email, password } = loginSchema.parse(req.body);
      res.json(await service.login(email, password));
    }),
    refresh: asyncHandler(async (req, res) => {
      const { refreshToken } = refreshSchema.parse(req.body);
      res.json(await service.refresh(refreshToken));
    }),
  };
}

export function makeAuthRouter(controller: ReturnType<typeof makeAuthController>) {
  const router = Router();
  router.post('/login', controller.login);
  router.post('/refresh', controller.refresh);
  return router;
}
```

## RBAC

Add `role` to the JWT (or look up):

```typescript
export const requireRole = (...roles: string[]): RequestHandler => (req, _res, next) => {
  if (!req.user) return next(new Unauthorized());
  if (!req.user.role || !roles.includes(req.user.role)) return next(new Forbidden());
  next();
};

router.delete('/users/:id', authMiddleware, requireRole('admin'), controller.delete);
```

For richer policies (resource-level: "can edit this org's projects"), check inside the service:

```typescript
async function deleteProject(actingUserId: string, projectId: string) {
  const project = await repo.findById(projectId);
  if (!project) throw new NotFound();
  if (project.ownerId !== actingUserId) throw new Forbidden();
  await repo.delete(projectId);
}
```

The middleware enforces "is admin". The service enforces "is owner". Different concerns.

## Cookies vs headers

Bearer header in `Authorization` is the simplest. For SPAs, consider:

- **Access token** in memory (lost on refresh — small price)
- **Refresh token** in `httpOnly` + `Secure` + `SameSite=Strict` cookie

Set the refresh cookie:

```typescript
res.cookie('refresh_token', refreshToken, {
  httpOnly: true,
  secure: env.NODE_ENV === 'production',
  sameSite: 'strict',
  maxAge: 30 * 24 * 60 * 60 * 1000,
  path: '/api/v1/auth',
});
```

The `path: '/api/v1/auth'` scope means the cookie is only sent to auth endpoints — minimizes exposure.

For mobile clients: secure storage (Keychain / Keystore), no cookies.

## Refresh token rotation

For higher security, rotate refresh tokens on every use:

1. Refresh endpoint takes the old refresh token
2. Verifies it
3. Marks it as used in a Redis set / DB table
4. Issues a *new* refresh token
5. Returns both new tokens

If a used refresh token is presented again, treat it as compromised and invalidate all tokens for that user.

This is more work but standard for security-conscious apps.

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| `jwt.verify` without `algorithms: [...]` | Always pass; otherwise `alg: none` attack |
| Refresh token in URL | Always in body or httpOnly cookie |
| Long-lived access tokens | 15min; rely on refresh |
| `sub` in JWT is a number | Always string — JWT `sub` is conventionally string |
| Same JWT secret across envs | Each env unique; rotate periodically |
| `bcrypt` is slow in tests | Lower rounds in `NODE_ENV === 'test'` |
| Logging the request body of login | Redact `password` in pino config (`redact: ['req.body.password']`) |
| `req.user` typed as `any` | Use the `declare global { namespace Express { interface Request } }` augmentation |
| 401 vs 403 confusion | 401 = "you're not authenticated"; 403 = "authenticated but not allowed" |
