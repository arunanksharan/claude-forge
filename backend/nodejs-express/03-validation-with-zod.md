# Validation with zod

> Schema parsing in Express controllers, sharing schemas with the frontend, common patterns.

## Why zod (not joi, not class-validator)

| Option | Verdict |
|--------|---------|
| **zod** | Pick this. Type inference, composability, huge ecosystem (zod-to-openapi, drizzle-zod, etc.). |
| **valibot** | Smaller bundle, similar API. Worth considering for client-side use. |
| **yup** | Older, weaker types. |
| **joi** | Mature but no TS inference. |
| **class-validator** | Good *inside Nest*. Heavy decorators outside Nest. |
| **superstruct** | Niche. |

For Express + TypeScript: **zod**. For sharing schemas with React Native or web: **zod** is also great there.

## Where validation runs

In Express, no auto-pipes — you parse explicitly in the controller:

```typescript
import { Request, Response } from 'express';
import { createUserSchema } from './users.schemas';

export const createUser = asyncHandler(async (req: Request, res: Response) => {
  const dto = createUserSchema.parse(req.body);   // throws ZodError on bad input
  const user = await service.register(dto);
  res.status(201).json({ id: user.id, email: user.email });
});
```

The global error handler catches `ZodError` and returns 400.

For DRY:

```typescript
import { ZodSchema } from 'zod';
import { RequestHandler } from 'express';

export function validateBody<T>(schema: ZodSchema<T>): RequestHandler {
  return (req, _res, next) => {
    const result = schema.safeParse(req.body);
    if (!result.success) return next(result.error);
    req.body = result.data;
    next();
  };
}

// usage
router.post('/', validateBody(createUserSchema), controller.create);
```

The controller can then trust `req.body` is the parsed type. Cast it: `req.body as CreateUserInput`.

For type-safe `req.body` everywhere, use `express-validator` style with type augmentation, or use `tRPC` instead of Express if you're aggressively chasing this.

## Schemas

```typescript
import { z } from 'zod';

export const createUserSchema = z.object({
  email: z.string().email(),
  password: z.string().min(8).max(128),
  name: z.string().min(1).max(80).trim().optional(),
});

export const updateUserSchema = createUserSchema.partial().omit({ password: true });

export const userResponseSchema = z.object({
  id: z.string().uuid(),
  email: z.string().email(),
  isActive: z.boolean(),
  createdAt: z.coerce.date(),
});

export type CreateUserInput = z.infer<typeof createUserSchema>;
export type UpdateUserInput = z.infer<typeof updateUserSchema>;
export type UserResponse = z.infer<typeof userResponseSchema>;
```

`z.infer<>` gives you the TypeScript type from the schema. **One source of truth** — change the schema, the type follows.

## Common patterns

### Refinements (cross-field)

```typescript
export const registerSchema = z.object({
  password: z.string().min(8),
  passwordConfirm: z.string(),
}).refine((data) => data.password === data.passwordConfirm, {
  message: 'passwords do not match',
  path: ['passwordConfirm'],
});
```

### Discriminated unions

```typescript
export const eventSchema = z.discriminatedUnion('type', [
  z.object({ type: z.literal('signup'), userId: z.string().uuid() }),
  z.object({ type: z.literal('purchase'), orderId: z.string().uuid(), amountCents: z.number().int().positive() }),
  z.object({ type: z.literal('cancel'), reason: z.string() }),
]);

const event = eventSchema.parse(payload);
if (event.type === 'purchase') {
  // event.orderId, event.amountCents are typed
}
```

### Coerce primitives from query strings

```typescript
const querySchema = z.object({
  page: z.coerce.number().int().min(1).default(1),
  size: z.coerce.number().int().min(1).max(200).default(50),
  q: z.string().min(1).optional(),
});

const { page, size, q } = querySchema.parse(req.query);
```

`z.coerce.number()` converts strings to numbers — query strings always come as strings.

### Trimming + lowercasing

```typescript
z.string().trim().toLowerCase().email()
```

### Custom error messages

```typescript
z.string({ required_error: 'email is required', invalid_type_error: 'email must be a string' }).email('not a valid email')
```

For the global error response shape, prefer to format `ZodError` consistently in the error handler rather than per-field custom messages.

### Nested schemas

```typescript
const addressSchema = z.object({
  street: z.string().min(1),
  countryCode: z.string().length(2),
});

const userSchema = z.object({
  email: z.string().email(),
  address: addressSchema.optional(),
});
```

## Sharing schemas with the frontend

Two approaches:

### Option A — shared package (monorepo)

```
packages/
├── api-schemas/     ← zod schemas, types
├── frontend/        ← imports schemas
└── backend/         ← imports schemas
```

Both sides import the same `createUserSchema`. The frontend can validate the user's input *before* posting; the backend validates again at the boundary.

### Option B — generate OpenAPI from zod, generate client

`zod-to-openapi` generates an OpenAPI spec from your zod schemas. Then `openapi-typescript` (or similar) generates the client types.

Pros: works for any frontend (not just TS), produces real API docs.
Cons: more moving parts.

For monorepos: Option A. For polyglot or external API: Option B.

## drizzle-zod — schemas from DB schema

```bash
pnpm add drizzle-zod
```

```typescript
import { createInsertSchema, createSelectSchema } from 'drizzle-zod';
import { users } from './schema/users';

export const insertUserSchema = createInsertSchema(users, {
  email: (s) => s.email.email(),
  password: () => z.string().min(8),  // override
}).omit({ id: true, createdAt: true, updatedAt: true });
```

Generates a zod schema from your Drizzle table. Useful for trivial CRUD endpoints. Don't over-rely — your API shape and DB shape diverge over time.

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| `z.string().email()` is too lenient (accepts `foo@bar`) | Add custom regex or use `validator.js` for stricter parsing |
| `z.coerce.number()` accepts `'NaN'` | Add `.refine(Number.isFinite)` |
| `parse` throws synchronously, async parse needed | `await schema.parseAsync(value)` |
| `safeParse` not used → unhandled throws in catch-all | Use `safeParse` in non-controller code; route handlers can `parse` because the global handler catches |
| Discriminated union slow with many variants | Profile; usually fine but for >50 variants, separate parser |
| `z.date()` rejects ISO strings from JSON | Use `z.coerce.date()` |
| Optional vs nullable confusion | `.optional()` allows undefined; `.nullable()` allows null; `.nullish()` allows both |
| Schema explosion (50 schemas in one file) | Split per feature; one file per resource |
