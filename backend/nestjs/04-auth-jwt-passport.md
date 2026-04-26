# Auth — JWT + Passport + Guards

> Authentication and authorization in NestJS. JWT strategy, RBAC, custom decorators.

## The shape

```
┌──────────────────────────────────────────────────────┐
│  Request                                              │
│      ▼                                                │
│  JwtAuthGuard         ← validates token, sets req.user│
│      ▼                                                │
│  RolesGuard           ← checks role from req.user    │
│      ▼                                                │
│  Controller method    ← @CurrentUser() user          │
└──────────────────────────────────────────────────────┘
```

`@nestjs/passport` provides the wiring; `passport-jwt` provides the strategy.

## Install

```bash
pnpm add @nestjs/jwt @nestjs/passport passport passport-jwt bcrypt
pnpm add -D @types/passport-jwt @types/bcrypt
```

## AuthModule

```typescript
// src/auth/auth.module.ts
import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { PassportModule } from '@nestjs/passport';
import { ConfigService } from '@nestjs/config';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';
import { JwtStrategy } from './strategies/jwt.strategy';
import { UsersModule } from '../users/users.module';

@Module({
  imports: [
    UsersModule,
    PassportModule,
    JwtModule.registerAsync({
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        secret: config.get<string>('JWT_SECRET'),
        signOptions: { expiresIn: config.get<string>('JWT_ACCESS_EXPIRES') ?? '15m' },
      }),
    }),
  ],
  controllers: [AuthController],
  providers: [AuthService, JwtStrategy],
  exports: [AuthService, JwtModule],
})
export class AuthModule {}
```

## JwtStrategy

```typescript
// src/auth/strategies/jwt.strategy.ts
import { Injectable, UnauthorizedException } from '@nestjs/common';
import { PassportStrategy } from '@nestjs/passport';
import { ExtractJwt, Strategy } from 'passport-jwt';
import { ConfigService } from '@nestjs/config';
import { UsersService } from '../../users/users.service';

export interface JwtPayload {
  sub: string;       // user id
  type: 'access' | 'refresh';
  iat: number;
  exp: number;
}

@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy) {
  constructor(
    config: ConfigService,
    private readonly usersService: UsersService,
  ) {
    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      ignoreExpiration: false,
      secretOrKey: config.get<string>('JWT_SECRET')!,
    });
  }

  async validate(payload: JwtPayload) {
    if (payload.type !== 'access') throw new UnauthorizedException('wrong token type');
    const user = await this.usersService.findById(payload.sub);
    if (!user || !user.isActive) throw new UnauthorizedException();
    return { id: user.id, email: user.email, role: user.role };
  }
}
```

The return value of `validate()` becomes `request.user`.

## JwtAuthGuard

```typescript
// src/auth/jwt-auth.guard.ts
import { ExecutionContext, Injectable } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { AuthGuard } from '@nestjs/passport';
import { IS_PUBLIC_KEY } from '../common/decorators/public.decorator';

@Injectable()
export class JwtAuthGuard extends AuthGuard('jwt') {
  constructor(private reflector: Reflector) { super(); }

  canActivate(context: ExecutionContext) {
    const isPublic = this.reflector.getAllAndOverride<boolean>(IS_PUBLIC_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (isPublic) return true;
    return super.canActivate(context);
  }
}
```

Apply globally in `app.module.ts`:

```typescript
{ provide: APP_GUARD, useClass: JwtAuthGuard }
```

Now **every endpoint requires auth by default.** Endpoints opt out with `@Public()`:

```typescript
import { Public } from './common/decorators/public.decorator';

@Public()
@Post('login')
async login() { ... }
```

This is the right default. The opposite (auth-by-opt-in) is how endpoints accidentally ship un-authed.

## Public decorator

```typescript
// src/common/decorators/public.decorator.ts
import { SetMetadata } from '@nestjs/common';
export const IS_PUBLIC_KEY = 'isPublic';
export const Public = () => SetMetadata(IS_PUBLIC_KEY, true);
```

## CurrentUser decorator

```typescript
// src/common/decorators/current-user.decorator.ts
import { createParamDecorator, ExecutionContext } from '@nestjs/common';

export const CurrentUser = createParamDecorator(
  (_data: unknown, ctx: ExecutionContext) => {
    const req = ctx.switchToHttp().getRequest();
    return req.user;
  },
);
```

Usage:

```typescript
@Get('me')
async me(@CurrentUser() user: { id: string; email: string; role: Role }) {
  return user;
}
```

## RBAC — Roles + RolesGuard

```typescript
// src/common/decorators/roles.decorator.ts
import { SetMetadata } from '@nestjs/common';
import { Role } from '@prisma/client';
export const ROLES_KEY = 'roles';
export const Roles = (...roles: Role[]) => SetMetadata(ROLES_KEY, roles);
```

```typescript
// src/common/guards/roles.guard.ts
import { CanActivate, ExecutionContext, Injectable } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { Role } from '@prisma/client';
import { ROLES_KEY } from '../decorators/roles.decorator';

@Injectable()
export class RolesGuard implements CanActivate {
  constructor(private reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    const required = this.reflector.getAllAndOverride<Role[]>(ROLES_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (!required || required.length === 0) return true;

    const { user } = context.switchToHttp().getRequest();
    return required.includes(user?.role);
  }
}
```

Apply globally too (after JwtAuthGuard):

```typescript
{ provide: APP_GUARD, useClass: RolesGuard }
```

Usage:

```typescript
@Roles(Role.ADMIN)
@Delete(':id')
async delete(@Param('id') id: string) { ... }
```

## AuthService — login/refresh

```typescript
// src/auth/auth.service.ts
import { Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { ConfigService } from '@nestjs/config';
import * as bcrypt from 'bcrypt';
import { UsersService } from '../users/users.service';

@Injectable()
export class AuthService {
  constructor(
    private readonly users: UsersService,
    private readonly jwt: JwtService,
    private readonly config: ConfigService,
  ) {}

  async login(email: string, password: string) {
    const user = await this.users.findByEmail(email);
    if (!user) throw new UnauthorizedException('invalid credentials');

    const ok = await bcrypt.compare(password, user.hashedPassword);
    if (!ok) throw new UnauthorizedException('invalid credentials');

    return this.issueTokens(user.id);
  }

  async refresh(refreshToken: string) {
    let payload: any;
    try {
      payload = await this.jwt.verifyAsync(refreshToken, {
        secret: this.config.get<string>('JWT_SECRET'),
      });
    } catch {
      throw new UnauthorizedException('invalid refresh token');
    }

    if (payload.type !== 'refresh') throw new UnauthorizedException();
    return this.issueTokens(payload.sub);
  }

  private issueTokens(userId: string) {
    const accessToken = this.jwt.sign(
      { sub: userId, type: 'access' },
      { expiresIn: this.config.get<string>('JWT_ACCESS_EXPIRES') ?? '15m' },
    );
    const refreshToken = this.jwt.sign(
      { sub: userId, type: 'refresh' },
      { expiresIn: this.config.get<string>('JWT_REFRESH_EXPIRES') ?? '30d' },
    );
    return { accessToken, refreshToken, tokenType: 'Bearer' };
  }
}
```

## AuthController

```typescript
// src/auth/auth.controller.ts
import { Body, Controller, Post } from '@nestjs/common';
import { Public } from '../common/decorators/public.decorator';
import { AuthService } from './auth.service';
import { LoginDto } from './dto/login.dto';
import { RefreshDto } from './dto/refresh.dto';

@Controller({ path: 'auth', version: '1' })
export class AuthController {
  constructor(private readonly auth: AuthService) {}

  @Public()
  @Post('login')
  login(@Body() dto: LoginDto) {
    return this.auth.login(dto.email, dto.password);
  }

  @Public()
  @Post('refresh')
  refresh(@Body() dto: RefreshDto) {
    return this.auth.refresh(dto.refreshToken);
  }
}
```

## API keys

For service-to-service or third-party API access. Use a separate guard.

```typescript
@Injectable()
export class ApiKeyGuard implements CanActivate {
  constructor(private readonly apiKeys: ApiKeysService) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const req = context.switchToHttp().getRequest();
    const key = req.header('x-api-key');
    if (!key) return false;
    const record = await this.apiKeys.verify(key);
    if (!record) return false;
    req.apiKey = record;
    return true;
  }
}
```

Use as alternative to JWT on specific endpoints:

```typescript
@UseGuards(ApiKeyGuard)
@Post('webhook')
async webhook(@Body() payload: any) {}
```

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| Forgot to make global guard, endpoints unauthed | `{ provide: APP_GUARD, useClass: JwtAuthGuard }` in `app.module.ts` |
| `@Public()` not working | The guard must check the metadata. Use `getAllAndOverride` so method-level `@Public` overrides class-level |
| Refresh token sent in URL | Always in body or httpOnly cookie. URLs leak via logs/referrer. |
| Rotating JWT secret invalidates all tokens | Plan for it — accept multiple secrets briefly during rotation |
| `validate()` called every request — DB hit per request | Cache user lookups (60s TTL) or include enough in the JWT to avoid the lookup |
| Bcrypt rounds too low | Use 12+. Adjust so hashing takes 250–500ms. |
| Returning user with `hashedPassword` from `validate()` | Pick only what you need in `validate()` — don't return the full user |
| Passport throws unclear errors | Wrap in your guard's `handleRequest` for custom error shape |
