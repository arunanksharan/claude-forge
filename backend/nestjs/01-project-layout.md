# NestJS Project Layout

> Modules, providers, dependency injection. The Nest mental model.

## The unit is the module

Everything in Nest belongs to a module. A module declares: providers (services, repositories), controllers, imports (other modules), exports (what other modules can use).

```typescript
@Module({
  imports: [PrismaModule],
  controllers: [UsersController],
  providers: [UsersService],
  exports: [UsersService],   // makes UsersService injectable into other modules
})
export class UsersModule {}
```

**Rule of thumb**: one module per *bounded context*. `UsersModule`, `OrdersModule`, `BillingModule`, `AuthModule`. Not `ServicesModule`, `ControllersModule` — that's the `utils/` anti-pattern in module form.

## Folder structure per feature

```
src/users/
├── users.module.ts
├── users.controller.ts          # HTTP layer
├── users.service.ts             # business logic
├── users.repository.ts          # (optional, Prisma users often skip this)
├── dto/
│   ├── create-user.dto.ts
│   ├── update-user.dto.ts
│   └── user-response.dto.ts
└── entities/                    # ORM types if not using Prisma's generated types
    └── user.entity.ts
```

## Layer rules

| From | Can import | Cannot import |
|------|-----------|---------------|
| Controller | Service of *this* module, DTOs, common/ | Repositories directly, entities directly |
| Service | Repository of *this* module, services of *imported* modules, integrations | DTOs (use plain typed objects), controllers |
| Repository | ORM client, entities | Services, controllers, DTOs |
| DTO | nothing else | services, repositories |

Same rules as the FastAPI guide — different framework, same logic.

## Repository pattern with Prisma — when?

Prisma's client is already a thin DB abstraction with great types. You can argue the service should call `prisma.user.findUnique(...)` directly with no separate repo file.

| Skip the repo | Add a repo |
|---------------|------------|
| Simple CRUD per feature | Complex queries (joins, raw SQL, aggregations) |
| Single ORM forever | Possibility of swapping ORM (rare) |
| Small team, easy to grep across services | Want to mock data access cleanly in unit tests |
| <50 LOC of DB access per feature | >150 LOC of DB access (refactor needed) |

**Be consistent within a project.** Don't have repos in some features and not others — pick one rule and stick to it. My default: **skip the repo for Prisma, add it when complexity justifies it.**

If you do add a repo:

```typescript
// users.repository.ts
@Injectable()
export class UsersRepository {
  constructor(private readonly prisma: PrismaService) {}

  async findByEmail(email: string): Promise<User | null> {
    return this.prisma.user.findUnique({ where: { email } });
  }

  async create(data: { email: string; hashedPassword: string }): Promise<User> {
    return this.prisma.user.create({ data });
  }
}
```

```typescript
// users.module.ts
@Module({
  imports: [PrismaModule],
  controllers: [UsersController],
  providers: [UsersService, UsersRepository],
})
export class UsersModule {}
```

## Dependency injection — what to know

Nest's DI container resolves the constructor parameters:

```typescript
@Injectable()
export class UsersService {
  constructor(
    private readonly usersRepo: UsersRepository,  // resolved by class type
    private readonly mailer: MailerService,
    @Inject('CONFIG') private readonly config: AppConfig,  // when not a class
  ) {}
}
```

### Provider scopes

Default scope is **singleton** — one instance per app. You almost always want this.

| Scope | When | Cost |
|-------|------|------|
| `DEFAULT` (singleton) | 99% of cases | None |
| `REQUEST` | Per-request state, `current user` propagated through call chain | High — instantiated per request |
| `TRANSIENT` | A new instance per consumer | Medium |

Avoid `REQUEST` scope unless you really need it — it cascades through the dependency graph. Better to pass the user via method parameter.

### Forward refs (circular deps)

If `AuthModule` imports `UsersModule` and `UsersModule` imports `AuthModule`, use `forwardRef()`:

```typescript
imports: [forwardRef(() => UsersModule)]
constructor(@Inject(forwardRef(() => UsersService)) private users: UsersService)
```

But: **circular deps usually mean a missing module**. Extract the shared piece into a third module (e.g. `AuthCoreModule`) and have both depend on it. `forwardRef()` is a code smell.

## Common module composition patterns

### Global module (singleton, available everywhere without import)

```typescript
@Global()
@Module({
  providers: [PrismaService],
  exports: [PrismaService],
})
export class PrismaModule {}
```

Use sparingly — only for truly cross-cutting things (Prisma client, config). Otherwise be explicit about imports.

### Dynamic module (configured at import time)

```typescript
@Module({})
export class CacheModule {
  static forRoot(options: CacheOptions): DynamicModule {
    return {
      module: CacheModule,
      providers: [
        { provide: CACHE_OPTIONS, useValue: options },
        CacheService,
      ],
      exports: [CacheService],
    };
  }
}

// usage
@Module({
  imports: [CacheModule.forRoot({ ttl: 60 })],
})
```

Prefer this over reading config inside the service — the module API is explicit.

### `useFactory` for async config

```typescript
{
  provide: 'KAFKA_CLIENT',
  useFactory: async (config: ConfigService) => {
    const client = new KafkaClient(config.get('KAFKA_BROKERS'));
    await client.connect();
    return client;
  },
  inject: [ConfigService],
}
```

## Common providers (`common/`)

Cross-cutting things that aren't a feature module:

- **Decorators**: `@CurrentUser()`, `@Public()`, `@Roles()`
- **Filters**: global exception filter (turns `AppException` into the right HTTP shape)
- **Guards**: `JwtAuthGuard`, `RolesGuard`
- **Interceptors**: logging, response transform, timeout
- **Pipes**: custom validators
- **Middleware**: request id injection (better as middleware than interceptor for low-level access)

Don't make a `CommonModule` that exports everything. Group related items into smaller modules:

- `LoggingModule` — interceptor + middleware
- `ExceptionsModule` — filter + base classes
- `AuthModule` — guards + strategies + decorators

Or just put them in `src/common/` as standalone files and `@Global()` provide what's needed.

## Versioning

Use URI versioning (Nest supports header and media-type too, but URI is the most explorable):

```typescript
app.enableVersioning({ type: VersioningType.URI, defaultVersion: '1' });
```

```typescript
@Controller({ path: 'users', version: '1' })
export class UsersControllerV1 {}

@Controller({ path: 'users', version: '2' })
export class UsersControllerV2 {}
```

Both live under `/api/v1/users` and `/api/v2/users`.

## Anti-patterns

### "Service-only modules"

```typescript
// services.module.ts — DON'T
@Module({
  providers: [UsersService, OrdersService, BillingService],
  exports: [UsersService, OrdersService, BillingService],
})
```

This defeats the module system. Each service belongs in its feature module.

### Static helpers calling other services

```typescript
// DON'T
export class OrderUtils {
  static async total(order: Order) {
    const tax = await TaxService.calculate(...);  // can't DI from a static
  }
}
```

If it needs DI, make it a service. If it's pure, make it a `function` and `import` it.

### One controller, ten methods, ten services

```typescript
// the controller becomes a giant orchestrator
class CheckoutController {
  constructor(
    private a: ServiceA, private b: ServiceB, private c: ServiceC,
    private d: ServiceD, private e: ServiceE, private f: ServiceF,
  ) {}
}
```

Push the orchestration into a `CheckoutService`. Controller has one dep (the service), one method per route.

### Exporting services that should be private

If `UsersModule` doesn't export `PasswordHasherService`, no other module can use it. Good — it stays internal. Only export what's part of your module's public API.
