# Validation & DTOs

> class-validator + class-transformer patterns. When zod is the better choice.

## DTOs vs entities vs schema

| Layer | Type | Source of truth |
|-------|------|----------------|
| HTTP boundary | **DTO** (class with `class-validator` decorators) | What the API accepts/returns |
| Service layer | Plain TS interface or domain type | Internal vocabulary |
| ORM layer | **Entity** (Prisma type, TypeORM class) | DB schema |

The DTO and entity look similar but serve different purposes. The DTO is what crosses the wire — it has validation rules. The entity is what the ORM gives you back from the DB.

**Don't reuse entities as DTOs.** It leaks DB shape to clients (including columns that shouldn't be exposed) and couples your API to your schema (you can't refactor either freely).

## class-validator basics

```typescript
import { IsEmail, IsString, MinLength, MaxLength, IsOptional, ValidateNested, Type } from 'class-validator';

export class CreateUserDto {
  @IsEmail()
  email!: string;

  @IsString()
  @MinLength(8)
  @MaxLength(128)
  password!: string;

  @IsOptional()
  @ValidateNested()
  @Type(() => AddressDto)
  address?: AddressDto;
}

export class AddressDto {
  @IsString()
  @MinLength(1)
  street!: string;

  @IsString()
  @MinLength(2)
  @MaxLength(2)
  countryCode!: string;
}
```

### Wire it into Nest

In `main.ts`:

```typescript
app.useGlobalPipes(
  new ValidationPipe({
    whitelist: true,            // strip unknown properties
    forbidNonWhitelisted: true, // 400 if unknown property
    transform: true,            // coerce types (e.g. string → number)
    transformOptions: { enableImplicitConversion: true },
  }),
);
```

This means: every controller method that takes `@Body() dto: CreateUserDto` gets validated automatically. No `dto.validate()` calls anywhere.

### Common decorators

| Decorator | Use |
|-----------|-----|
| `@IsString()`, `@IsNumber()`, `@IsBoolean()`, `@IsDate()` | type checks |
| `@IsEmail()`, `@IsUUID()`, `@IsUrl()`, `@IsPhoneNumber()` | format validators |
| `@MinLength()`, `@MaxLength()` | string length |
| `@Min()`, `@Max()` | numeric range |
| `@IsArray()`, `@ArrayMinSize()`, `@ArrayMaxSize()` | arrays |
| `@IsEnum(MyEnum)` | enum |
| `@IsOptional()` | mark as optional (skip validation when absent) |
| `@ValidateNested()` + `@Type(() => Foo)` | nested DTOs (need both) |
| `@Transform(({ value }) => value.trim())` | transform input |

## Update DTOs — `PartialType`

```typescript
import { PartialType } from '@nestjs/mapped-types';

export class UpdateUserDto extends PartialType(CreateUserDto) {}
```

Now every field is optional. Good for PATCH endpoints. Don't forget to omit fields that shouldn't be updatable (use `OmitType`):

```typescript
export class UpdateUserDto extends PartialType(OmitType(CreateUserDto, ['email'] as const)) {}
```

## Response DTOs — never expose entities

```typescript
import { Expose, Type, plainToInstance } from 'class-transformer';

export class UserResponseDto {
  @Expose() id!: string;
  @Expose() email!: string;
  @Expose() isActive!: boolean;
  @Expose() createdAt!: Date;

  @Expose()
  @Type(() => OrderResponseDto)
  orders?: OrderResponseDto[];

  static from(user: User & { orders?: Order[] }): UserResponseDto {
    return plainToInstance(UserResponseDto, user, { excludeExtraneousValues: true });
  }
}
```

`excludeExtraneousValues: true` is critical — it strips anything not `@Expose()`d. So if your User entity has `hashedPassword`, it won't leak.

Add to your global config:

```typescript
// or via a ClassSerializerInterceptor
app.useGlobalInterceptors(new ClassSerializerInterceptor(app.get(Reflector)));
```

Then any `return userResponseDto` is auto-serialized correctly.

## Custom validators

```typescript
import { registerDecorator, ValidationOptions, ValidatorConstraint, ValidatorConstraintInterface } from 'class-validator';

@ValidatorConstraint({ name: 'isStrongPassword', async: false })
export class IsStrongPasswordConstraint implements ValidatorConstraintInterface {
  validate(value: any) {
    if (typeof value !== 'string') return false;
    return value.length >= 8 && /[A-Z]/.test(value) && /[0-9]/.test(value) && /[^A-Za-z0-9]/.test(value);
  }
  defaultMessage() {
    return 'password must be 8+ chars with upper, digit, and symbol';
  }
}

export function IsStrongPassword(options?: ValidationOptions) {
  return function (object: object, propertyName: string) {
    registerDecorator({
      target: object.constructor,
      propertyName,
      options,
      constraints: [],
      validator: IsStrongPasswordConstraint,
    });
  };
}
```

```typescript
export class CreateUserDto {
  @IsStrongPassword()
  password!: string;
}
```

## Async validators (DB-aware)

You *can* write async validators that hit the DB. But it's usually a bad idea — pushes business validation into the validation layer. Prefer:

- **Pydantic-style**: validate format/shape in the DTO
- **Service-side**: validate uniqueness, business rules in the service, throw `ConflictException` etc.

Reasons:
- Service-side validation is testable in isolation
- DB-aware DTO validators couple your DTOs to the data layer
- Race conditions: "is this email taken?" check at validation time can race with another request

## When to use zod instead

class-validator is great inside Nest controllers because of the decorator integration. But it has rough edges:

- Hard to share types between client and server (no JSON Schema export out of the box)
- Verbose for complex unions
- Can't easily compose like `userSchema.partial().pick(...)`

For:
- **Internal data validation** (queue messages, webhook payloads)
- **Sharing schemas with frontend** (or sharing a single source of truth)
- **Complex unions / discriminated types**

Use **zod**. You can use it inside a controller via a custom pipe:

```typescript
import { PipeTransform, BadRequestException } from '@nestjs/common';
import { ZodSchema } from 'zod';

export class ZodValidationPipe implements PipeTransform {
  constructor(private readonly schema: ZodSchema) {}

  transform(value: any) {
    const result = this.schema.safeParse(value);
    if (!result.success) {
      throw new BadRequestException(result.error.flatten());
    }
    return result.data;
  }
}
```

```typescript
@Post()
async create(@Body(new ZodValidationPipe(createUserSchema)) dto: CreateUserInput) {}
```

Or use **`nestjs-zod`** package which integrates more cleanly.

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| `transform: true` not set, body fields are still strings | Set in `ValidationPipe` config |
| Nested DTO not validated | Need both `@ValidateNested()` and `@Type(() => Foo)` |
| `@IsOptional()` allows `null` and `undefined` | If you want only `undefined`, add `@ValidateIf((o) => o.field !== undefined)` |
| Whitelist strips a field you wanted | The field is missing a decorator — add `@IsString()` etc. |
| Custom decorator not running | The decorator function must `registerDecorator` correctly + your DTO must be the target |
| Response leaks `hashedPassword` | `@Expose()` only what you want returned + `excludeExtraneousValues: true` |
| Big Int / Decimal serializes oddly | Add a custom transform in the DTO (`@Transform(({ value }) => value.toString())`) |
| `@nestjs/mapped-types` `PartialType` not preserving validators | Use `PartialType` from `@nestjs/swagger` if you have OpenAPI installed |
