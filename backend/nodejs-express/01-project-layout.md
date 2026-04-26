# Express Project Layout — Factory Functions Without DI

> Without Nest's IoC container, layering needs explicit wiring. Factory functions are the cheapest, clearest way.

## Why no DI container

You *can* use `tsyringe` or `inversify`. Don't. Reasons:

- They add bundle weight, decorator complexity, and a learning curve
- The bug they prevent (constructor wiring drift) doesn't really exist when you have factory functions
- If you genuinely need DI badly enough to install one of these, you should be using NestJS

Factory functions are 5 lines of explicit wiring per feature. That's the right cost.

## The pattern

Each layer is a function that takes its dependencies and returns an object of methods.

```typescript
// repository
export function makeUsersRepository(db: Database) {
  return {
    findByEmail(email: string) { return db.query.users.findFirst({ where: eq(users.email, email) }); },
    create(data: NewUser) { return db.insert(users).values(data).returning().then(rows => rows[0]); },
  };
}
export type UsersRepository = ReturnType<typeof makeUsersRepository>;

// service
export function makeUsersService(repo: UsersRepository) {
  return {
    async register(input: CreateUserInput) {
      if (await repo.findByEmail(input.email)) throw new Conflict('email taken');
      return repo.create({ email: input.email, hashedPassword: await bcrypt.hash(input.password, 12) });
    },
  };
}
export type UsersService = ReturnType<typeof makeUsersService>;

// controller
export function makeUsersController(service: UsersService) {
  return {
    create: asyncHandler(async (req, res) => {
      const dto = createUserSchema.parse(req.body);
      res.status(201).json(await service.register(dto));
    }),
  };
}

// module
export function createUsersModule() {
  const repo = makeUsersRepository(db);
  const service = makeUsersService(repo);
  const controller = makeUsersController(service);
  const router = makeUsersRouter(controller);
  return { service, router };
}
```

This gives you:

- **Explicit dependency graph** — read top-to-bottom in `index.ts`
- **Easy testing** — pass fakes to the factory
- **No magic** — no decorator metadata, no global container
- **No singletons unless you want them** — call `create*Module()` once at boot

## Why not classes?

You can use classes:

```typescript
class UsersService {
  constructor(private repo: UsersRepository) {}
  async register(...) {}
}
```

That works fine. But:

- TypeScript's `private` is enforced only at compile time
- Classes drag in `this` and the constraint that everything is async-arrow or bound
- Factories return plain objects — they auto-narrow types better in TS

Both styles are valid. Pick one and stick with it. **Don't mix.**

## Module structure

```
src/modules/{feature}/
├── index.ts             # createModule() factory + exports
├── {feature}.routes.ts  # Router factory
├── {feature}.controller.ts
├── {feature}.service.ts
├── {feature}.repository.ts
├── {feature}.schemas.ts # zod input + output types
└── {feature}.types.ts   # shared types (optional)
```

`index.ts` is the public face. Other modules import only what's exported.

## Cross-module dependencies

The Auth module needs the Users service. Don't reach in — wire it explicitly:

```typescript
// modules/auth/index.ts
export function createAuthModule(deps: { usersService: UsersService }) {
  const service = makeAuthService(deps.usersService);
  const controller = makeAuthController(service);
  const router = makeAuthRouter(controller);
  return { service, router };
}

// routes.ts
const users = createUsersModule();
const auth = createAuthModule({ usersService: users.service });
```

Now the dependency between modules is a function argument — visible in code review.

## What goes in `lib/`

Cross-cutting helpers with **no business logic**:

- `errors.ts` — `AppError` + subclasses
- `logger.ts` — pino instance
- `jwt.ts` — `signAccess`, `verify`
- `password.ts` — `hash`, `verify` (around bcrypt)
- `pagination.ts` — cursor + offset helpers
- `async-handler.ts` — wraps async route handlers

If something needs DB access or service calls, it doesn't go in `lib/`. It goes in a module.

## What goes in `middleware/`

Cross-cutting Express middlewares:

- `request-id.ts` — assign or accept `X-Request-ID`
- `logging.ts` — `pino-http` config
- `auth.ts` — verify JWT → `req.user`
- `error-handler.ts` — `errorHandler`, `notFoundHandler`
- `rate-limit.ts` — global rate limit (e.g. `express-rate-limit`)

## Anti-patterns

### Singletons via top-level `new`

```typescript
// DON'T
export const usersService = new UsersService();  // wired at import time
```

This makes testing painful (can't sub in fakes per test) and binds initialization order to import order. Use factories called from `routes.ts`.

### Globals in `lib/`

```typescript
// DON'T
// lib/db.ts
export const db = drizzle(...);   // initialized at import
```

If you mock the env in tests, this already ran. Either:

- Lazy-init via a getter
- Or pass `db` explicitly to every factory (cleanest)

The example scaffold uses a top-level `db` for brevity, but in real life prefer passing it.

### `utils/` folder

Same anti-pattern as in the FastAPI guide. Every helper has a real home.

### "Module" that exports 20 things

A module's job is to handle one feature. If it exports many internal types and helpers, you're using it as a namespace, not a module. Split it.

## When to outgrow this pattern

If your codebase gets large enough that:

- Factory wiring becomes unwieldy (circular dependencies)
- You need request-scoped instances
- You want decorator-driven config
- You have 50+ feature modules

…you should be on **NestJS**, not Express. Migrate before the wiring becomes a bigger pain than the migration.

The factory pattern is great up to ~30 modules / 30K LOC. Past that, the friction starts to win.
