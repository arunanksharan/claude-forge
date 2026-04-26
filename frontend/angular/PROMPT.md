# Angular — Master Scaffold Prompt

> **Modern Angular (18+) with standalone components, signals, RxJS where it shines, server-side rendering optional. No NgModules unless absolutely required.**

---

## Context

You are scaffolding a new Angular 18+ app using **standalone components**, **signals** for reactive state, **RxJS** for async streams (HTTP, websockets), and **NgRx Signal Store** if needed for shared state. Strict template type checking.

If something is ambiguous, **ask once, then proceed**.

## Project parameters

```
project_name:       {{project-name}}
project_slug:       {{project-slug}}            # kebab-case
description:        {{one-line-description}}
api_base_url:       {{https://api.example.com}}
include_ssr:        {{yes-or-no}}
include_auth:       {{yes-or-no}}
ui_kit:             {{angular-material|tailwind+manual|primeng}}    # default: tailwind+manual
```

---

## Locked stack

| Concern | Pick | Why |
|---------|------|-----|
| Framework | **Angular 18+** | Signals + standalone APIs are stable |
| Components | **Standalone components** (no NgModule) | Less boilerplate, better tree-shaking |
| State (local) | **Signals** built-in | The new way; reactive without RxJS overhead |
| State (shared, complex) | **NgRx Signal Store** | Lighter than NgRx classic Store |
| State (simple shared) | **Service with signals** | Often enough |
| Async streams | **RxJS** | Still the right tool for HTTP + websocket |
| Forms | **Reactive forms** with typed FormGroup/FormBuilder | Strongly typed since v14 |
| HTTP | **HttpClient** + **provideHttpClient(withFetch())** | Built-in |
| Routing | **provideRouter** + lazy-loaded routes | Standalone-style routing |
| Styling | **Tailwind CSS** + Angular CDK primitives | UI kits are heavy |
| i18n | **@angular/localize** | Built-in |
| Tests | **Vitest + @analogjs/vitest-angular** (modern) or **Jest** | Karma is being deprecated |
| E2E | **Playwright** | |
| Linting | **ESLint** + **angular-eslint** + Prettier | |
| SSR | **Angular Universal** (now first-class via `provideServerRendering`) | |

## Rejected

| Library | Why not |
|---------|---------|
| **NgModules** for new projects | Standalone is the future and the default |
| **Karma** | Deprecated; use Vitest or Jest |
| **TestBed**-heavy unit tests | Prefer service unit tests with no TestBed |
| **NGRX classic Store** | Powerful but heavy; signal-based stores are simpler |
| **AngularFire / @angular/fire** | If using Firebase, fine; but assess vs direct SDKs |
| **PrimeNG / Material** _by default_ | Pick deliberately — they couple your app to their themes |
| **Bootstrap** | Tailwind is more flexible |
| **MomentJS** | Use date-fns or built-in `Intl.DateTimeFormat` |
| **lodash** | Modern TS / ES has most of it; selectively import if needed |
| **Yarn classic / Lerna** | Use pnpm + Nx for monorepos |

---

## Directory layout

```
{{project-slug}}/
├── package.json
├── tsconfig.json
├── tsconfig.app.json
├── angular.json
├── eslint.config.js
├── tailwind.config.ts
├── postcss.config.js
├── .prettierrc
├── README.md
├── src/
│   ├── main.ts
│   ├── main.server.ts                  # if SSR
│   ├── styles.css
│   ├── app/
│   │   ├── app.config.ts               # standalone-style providers
│   │   ├── app.config.server.ts        # SSR-specific providers
│   │   ├── app.routes.ts               # routes
│   │   ├── app.component.ts            # root component
│   │   ├── core/
│   │   │   ├── interceptors/
│   │   │   │   ├── auth.interceptor.ts
│   │   │   │   └── error.interceptor.ts
│   │   │   ├── guards/
│   │   │   │   └── auth.guard.ts
│   │   │   ├── services/
│   │   │   │   └── api.service.ts      # base HTTP wrapper
│   │   │   └── tokens/
│   │   │       └── api-base-url.token.ts
│   │   ├── features/
│   │   │   ├── auth/
│   │   │   │   ├── auth.routes.ts      # lazy-loaded child routes
│   │   │   │   ├── login.component.ts
│   │   │   │   ├── auth.service.ts     # signal-based
│   │   │   │   └── auth.types.ts
│   │   │   └── dashboard/
│   │   │       ├── dashboard.routes.ts
│   │   │       ├── dashboard.component.ts
│   │   │       ├── dashboard.service.ts
│   │   │       └── widgets/
│   │   ├── shared/
│   │   │   ├── components/
│   │   │   │   ├── button.component.ts
│   │   │   │   └── card.component.ts
│   │   │   └── directives/
│   │   └── stores/
│   │       └── ui.store.ts             # NgRx Signal Store
│   └── environments/
│       ├── environment.ts
│       └── environment.prod.ts
└── e2e/
    └── playwright.config.ts
```

## Layer rules

- **Routes** (`*.routes.ts`) — wire components, guards, lazy loading
- **Components** (`*.component.ts`) — UI + signals + injecting services
- **Services** — business logic; signal-based for state, RxJS for streams
- **Stores** (`stores/`) — for cross-feature state (NgRx Signal Store)
- **Core** — singletons (interceptors, guards, base HTTP)
- **Shared** — reusable presentational components

---

## Key files

### `package.json`

```json
{
  "name": "{{project-slug}}",
  "version": "0.1.0",
  "scripts": {
    "ng": "ng",
    "start": "ng serve",
    "build": "ng build",
    "build:ssr": "ng build && ng run {{project-slug}}:server",
    "watch": "ng build --watch --configuration development",
    "test": "vitest run",
    "test:watch": "vitest",
    "lint": "eslint .",
    "format": "prettier --write \"src/**/*.{ts,html,css}\"",
    "e2e": "playwright test"
  },
  "dependencies": {
    "@angular/animations": "^18.2.0",
    "@angular/common": "^18.2.0",
    "@angular/compiler": "^18.2.0",
    "@angular/core": "^18.2.0",
    "@angular/forms": "^18.2.0",
    "@angular/platform-browser": "^18.2.0",
    "@angular/platform-browser-dynamic": "^18.2.0",
    "@angular/platform-server": "^18.2.0",
    "@angular/router": "^18.2.0",
    "@angular/ssr": "^18.2.0",
    "@angular/cdk": "^18.2.0",
    "@ngrx/signals": "^18.0.0",
    "rxjs": "~7.8.0",
    "tslib": "^2.7.0",
    "zone.js": "~0.14.0"
  },
  "devDependencies": {
    "@angular-devkit/build-angular": "^18.2.0",
    "@angular/cli": "^18.2.0",
    "@angular/compiler-cli": "^18.2.0",
    "typescript": "~5.5.0",
    "tailwindcss": "^4.0.0",
    "@tailwindcss/postcss": "^4.0.0",
    "postcss": "^8.4.0",
    "eslint": "^9.0.0",
    "@typescript-eslint/eslint-plugin": "^8.0.0",
    "@typescript-eslint/parser": "^8.0.0",
    "angular-eslint": "^18.0.0",
    "prettier": "^3.0.0",
    "vitest": "^2.0.0",
    "@analogjs/vitest-angular": "^1.10.0",
    "@playwright/test": "^1.48.0"
  }
}
```

### `src/main.ts`

```typescript
import { bootstrapApplication } from '@angular/platform-browser';
import { AppComponent } from './app/app.component';
import { appConfig } from './app/app.config';

bootstrapApplication(AppComponent, appConfig).catch((err) => console.error(err));
```

### `src/app/app.config.ts`

```typescript
import { ApplicationConfig, provideZoneChangeDetection } from '@angular/core';
import { provideRouter } from '@angular/router';
import { provideHttpClient, withFetch, withInterceptors } from '@angular/common/http';
import { routes } from './app.routes';
import { authInterceptor } from './core/interceptors/auth.interceptor';
import { errorInterceptor } from './core/interceptors/error.interceptor';
import { API_BASE_URL } from './core/tokens/api-base-url.token';
import { environment } from '../environments/environment';

export const appConfig: ApplicationConfig = {
  providers: [
    provideZoneChangeDetection({ eventCoalescing: true }),
    provideRouter(routes),
    provideHttpClient(withFetch(), withInterceptors([authInterceptor, errorInterceptor])),
    { provide: API_BASE_URL, useValue: environment.apiBaseUrl },
  ],
};
```

### `src/app/app.routes.ts`

```typescript
import { Routes } from '@angular/router';
import { authGuard } from './core/guards/auth.guard';

export const routes: Routes = [
  {
    path: 'auth',
    loadChildren: () => import('./features/auth/auth.routes').then((m) => m.AUTH_ROUTES),
  },
  {
    path: '',
    canActivate: [authGuard],
    loadChildren: () => import('./features/dashboard/dashboard.routes').then((m) => m.DASHBOARD_ROUTES),
  },
  { path: '**', redirectTo: '' },
];
```

### `src/app/core/interceptors/auth.interceptor.ts`

```typescript
import { HttpInterceptorFn } from '@angular/common/http';
import { inject } from '@angular/core';
import { AuthService } from '../../features/auth/auth.service';

export const authInterceptor: HttpInterceptorFn = (req, next) => {
  const auth = inject(AuthService);
  const token = auth.accessToken();
  if (!token) return next(req);
  return next(req.clone({ setHeaders: { Authorization: `Bearer ${token}` } }));
};
```

### `src/app/core/guards/auth.guard.ts`

```typescript
import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { AuthService } from '../../features/auth/auth.service';

export const authGuard: CanActivateFn = (_route, state) => {
  const auth = inject(AuthService);
  const router = inject(Router);
  if (auth.isAuthenticated()) return true;
  return router.createUrlTree(['/auth/login'], { queryParams: { redirect: state.url } });
};
```

### `src/app/features/auth/auth.service.ts`

```typescript
import { inject, Injectable, signal, computed } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Router } from '@angular/router';
import { firstValueFrom } from 'rxjs';
import { API_BASE_URL } from '../../core/tokens/api-base-url.token';

interface User { id: string; email: string; }
interface TokenResponse { accessToken: string; refreshToken: string; }

@Injectable({ providedIn: 'root' })
export class AuthService {
  private http = inject(HttpClient);
  private router = inject(Router);
  private apiBaseUrl = inject(API_BASE_URL);

  // signals
  readonly accessToken = signal<string | null>(localStorage.getItem('access_token'));
  readonly refreshToken = signal<string | null>(localStorage.getItem('refresh_token'));
  readonly user = signal<User | null>(null);
  readonly isAuthenticated = computed(() => this.accessToken() !== null);

  async login(email: string, password: string): Promise<void> {
    const tokens = await firstValueFrom(
      this.http.post<TokenResponse>(`${this.apiBaseUrl}/auth/login`, { email, password }),
    );
    this.setTokens(tokens);
    const me = await firstValueFrom(this.http.get<User>(`${this.apiBaseUrl}/users/me`));
    this.user.set(me);
  }

  signOut(): void {
    this.accessToken.set(null);
    this.refreshToken.set(null);
    this.user.set(null);
    localStorage.removeItem('access_token');
    localStorage.removeItem('refresh_token');
    this.router.navigateByUrl('/auth/login');
  }

  private setTokens(t: TokenResponse): void {
    this.accessToken.set(t.accessToken);
    this.refreshToken.set(t.refreshToken);
    localStorage.setItem('access_token', t.accessToken);
    localStorage.setItem('refresh_token', t.refreshToken);
  }
}
```

### `src/app/features/auth/login.component.ts`

```typescript
import { Component, inject, signal } from '@angular/core';
import { FormBuilder, ReactiveFormsModule, Validators } from '@angular/forms';
import { Router } from '@angular/router';
import { AuthService } from './auth.service';

@Component({
  selector: 'app-login',
  standalone: true,
  imports: [ReactiveFormsModule],
  template: `
    <div class="mx-auto max-w-sm p-6">
      <h1 class="mb-6 text-2xl font-semibold">Sign in</h1>
      <form [formGroup]="form" (ngSubmit)="submit()" class="space-y-4">
        <input
          formControlName="email"
          type="email"
          placeholder="Email"
          autocomplete="email"
          class="w-full rounded border px-3 py-2"
        />
        <input
          formControlName="password"
          type="password"
          placeholder="Password"
          autocomplete="current-password"
          class="w-full rounded border px-3 py-2"
        />
        @if (error()) {
          <p class="text-sm text-red-600">{{ error() }}</p>
        }
        <button
          type="submit"
          [disabled]="form.invalid || submitting()"
          class="w-full rounded bg-violet-600 py-2 text-white disabled:opacity-50"
        >
          {{ submitting() ? 'Signing in...' : 'Sign in' }}
        </button>
      </form>
    </div>
  `,
})
export class LoginComponent {
  private fb = inject(FormBuilder);
  private auth = inject(AuthService);
  private router = inject(Router);

  readonly submitting = signal(false);
  readonly error = signal<string | null>(null);

  readonly form = this.fb.nonNullable.group({
    email: ['', [Validators.required, Validators.email]],
    password: ['', [Validators.required, Validators.minLength(8)]],
  });

  async submit(): Promise<void> {
    if (this.form.invalid) return;
    this.submitting.set(true);
    this.error.set(null);
    try {
      const { email, password } = this.form.getRawValue();
      await this.auth.login(email, password);
      await this.router.navigateByUrl('/');
    } catch (err) {
      this.error.set(err instanceof Error ? err.message : 'Sign in failed');
    } finally {
      this.submitting.set(false);
    }
  }
}
```

---

## Generation steps

1. **Confirm parameters.**
2. **Run `npx -p @angular/cli@latest ng new {{project-slug}} --standalone --routing --style=css --strict --skip-tests`.**
3. **`cd {{project-slug}} && pnpm install`.**
4. **Add Tailwind:** `pnpm add -D tailwindcss @tailwindcss/postcss postcss` + create `tailwind.config.ts` + add `@import "tailwindcss";` to `src/styles.css`.
5. **Add NgRx Signal Store:** `pnpm add @ngrx/signals`.
6. **Generate the directory tree** under `src/app/`.
7. **Write `app.config.ts`, `app.routes.ts`, `app.component.ts`.**
8. **Write `core/`** interceptors, guards, tokens.
9. **Write one feature module (`auth/`)** end-to-end.
10. **(Optional) Add SSR:** `ng add @angular/ssr`.
11. **Run `pnpm start`** — verify dev server.
12. **Run `pnpm lint && pnpm build`** — clean.

## SSR setup

```bash
ng add @angular/ssr
```

This adds `main.server.ts`, `server.ts`, and updates `angular.json`. Build with `pnpm build:ssr`, run with `node dist/{{project-slug}}/server/server.mjs`.

For deployment, treat it like the Next.js standalone output (see `deployment/per-framework/deploy-nextjs.md`) — Node behind nginx.

## Testing

```typescript
// auth.service.spec.ts
import { TestBed } from '@angular/core/testing';
import { provideHttpClientTesting, HttpTestingController } from '@angular/common/http/testing';
import { provideHttpClient } from '@angular/common/http';
import { AuthService } from './auth.service';
import { API_BASE_URL } from '../../core/tokens/api-base-url.token';

describe('AuthService', () => {
  let service: AuthService;
  let httpMock: HttpTestingController;

  beforeEach(() => {
    TestBed.configureTestingModule({
      providers: [
        provideHttpClient(),
        provideHttpClientTesting(),
        { provide: API_BASE_URL, useValue: 'http://api' },
      ],
    });
    service = TestBed.inject(AuthService);
    httpMock = TestBed.inject(HttpTestingController);
  });

  afterEach(() => httpMock.verify());

  it('logs in', async () => {
    const promise = service.login('a@a.com', 'hunter22');

    httpMock.expectOne('http://api/auth/login').flush({ accessToken: 'a', refreshToken: 'r' });
    httpMock.expectOne('http://api/users/me').flush({ id: 'u', email: 'a@a.com' });

    await promise;
    expect(service.accessToken()).toBe('a');
    expect(service.user()?.email).toBe('a@a.com');
  });
});
```

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| Mixing NgModules and standalone | Pick one; standalone for new code |
| Forgot to add `imports: [...]` on standalone component | Compile error — list every directive/pipe/component |
| `signal()` with object — mutation doesn't trigger update | Always assign a new object: `s.set({ ...s(), x: 1 })` |
| RxJS `Subject` for state | Use signals; reserve RxJS for HTTP, websocket, time-based |
| Forgetting `provideHttpClient()` | All HTTP calls error — must register in providers |
| Routes not lazy-loaded | Use `loadChildren: () => import(...)` for big features |
| Strict template type checking errors | Update `tsconfig.json` `strictTemplates: true` once + fix |
| OnPush + signal | Signals work with OnPush — that's the point — change detection runs only when signals read |
| Karma-based tests still in `angular.json` | Migrate to Vitest via `@analogjs/vitest-angular` |
| `ChangeDetectorRef.detectChanges()` everywhere | If you need this, you're fighting Angular — use signals |
| `async` pipe + signal | `async` pipe is for Observables; signals don't need it (just call `count()` in template) |
| SSR errors on `localStorage` | Wrap in `if (isPlatformBrowser(this.platformId))` |
