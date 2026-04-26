# Angular Testing — Vitest + Playwright

> Modern Angular tests with Vitest (replacing Karma) + Playwright for E2E. Component tests with the modern testing harness.

## The decision

| Tool | Replaces | Why |
|------|----------|-----|
| **Vitest** + **@analogjs/vitest-angular** | Karma + Jasmine | Faster, ESM-native, better TS support; Karma is being deprecated |
| **Jest** + **jest-preset-angular** | Karma + Jasmine | Mature alternative; pick if you prefer Jest ecosystem |
| **Playwright** | Cypress, Protractor | Multi-browser, better debugging, faster CI |
| **Cypress** | — | Still excellent; pick based on team preference |

Use Vitest unit/component tests + Playwright for E2E. Don't write E2E in the unit test runner.

## Setup — Vitest with Angular

```bash
pnpm add -D vitest @analogjs/vitest-angular @analogjs/platform jsdom @testing-library/angular @testing-library/jest-dom
```

`vitest.config.ts`:

```typescript
import { defineConfig } from 'vitest/config';
import angular from '@analogjs/vite-plugin-angular';

export default defineConfig({
  plugins: [angular()],
  test: {
    globals: true,
    environment: 'jsdom',
    setupFiles: ['./src/test-setup.ts'],
    include: ['src/**/*.spec.ts'],
  },
});
```

`src/test-setup.ts`:

```typescript
import '@testing-library/jest-dom/vitest';
import { TestBed } from '@angular/core/testing';
import { BrowserDynamicTestingModule, platformBrowserDynamicTesting } from '@angular/platform-browser-dynamic/testing';

TestBed.initTestEnvironment(BrowserDynamicTestingModule, platformBrowserDynamicTesting());
```

`package.json`:

```json
"scripts": {
  "test": "vitest run",
  "test:watch": "vitest",
  "test:cov": "vitest run --coverage"
}
```

## Service test (with HTTP)

```typescript
import { TestBed } from '@angular/core/testing';
import { provideHttpClient } from '@angular/common/http';
import { provideHttpClientTesting, HttpTestingController } from '@angular/common/http/testing';
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { AuthService } from './auth.service';
import { API_BASE_URL } from '../core/tokens/api-base-url.token';

describe('AuthService', () => {
  let service: AuthService;
  let httpMock: HttpTestingController;

  beforeEach(() => {
    TestBed.configureTestingModule({
      providers: [
        AuthService,
        provideHttpClient(),
        provideHttpClientTesting(),
        { provide: API_BASE_URL, useValue: 'http://api' },
      ],
    });
    service = TestBed.inject(AuthService);
    httpMock = TestBed.inject(HttpTestingController);
  });

  afterEach(() => httpMock.verify());

  it('logs in and stores tokens', async () => {
    const promise = service.login('alice@example.com', 'hunter22a');

    httpMock.expectOne('http://api/auth/login').flush({ accessToken: 'a', refreshToken: 'r' });
    httpMock.expectOne('http://api/users/me').flush({ id: 'u1', email: 'alice@example.com' });

    await promise;

    expect(service.accessToken()).toBe('a');
    expect(service.user()?.email).toBe('alice@example.com');
    expect(localStorage.getItem('access_token')).toBe('a');
  });

  it('clears tokens on signOut', () => {
    service.accessToken.set('x');
    service.signOut();
    expect(service.accessToken()).toBeNull();
  });
});
```

## Component test (Testing Library)

```typescript
import { render, screen, fireEvent } from '@testing-library/angular';
import { describe, it, expect } from 'vitest';
import { LoginComponent } from './login.component';
import { AuthService } from './auth.service';

describe('LoginComponent', () => {
  it('shows the form', async () => {
    await render(LoginComponent, {
      providers: [
        { provide: AuthService, useValue: { login: vi.fn() } },
      ],
    });

    expect(screen.getByPlaceholderText('Email')).toBeInTheDocument();
    expect(screen.getByPlaceholderText('Password')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /sign in/i })).toBeInTheDocument();
  });

  it('disables submit while submitting', async () => {
    const login = vi.fn().mockReturnValue(new Promise(() => {}));   // never resolves
    await render(LoginComponent, {
      providers: [{ provide: AuthService, useValue: { login } }],
    });

    fireEvent.input(screen.getByPlaceholderText('Email'), { target: { value: 'a@a.com' } });
    fireEvent.input(screen.getByPlaceholderText('Password'), { target: { value: 'hunter22a' } });
    fireEvent.click(screen.getByRole('button', { name: /sign in/i }));

    expect(await screen.findByText(/signing in/i)).toBeInTheDocument();
    expect(screen.getByRole('button')).toBeDisabled();
  });
});
```

`@testing-library/angular` removes most TestBed boilerplate. Use it.

## Signal Store test

```typescript
import { TestBed } from '@angular/core/testing';
import { describe, it, expect } from 'vitest';
import { provideHttpClient } from '@angular/common/http';
import { provideHttpClientTesting, HttpTestingController } from '@angular/common/http/testing';
import { UsersStore } from './users.store';

describe('UsersStore', () => {
  it('loads users', async () => {
    TestBed.configureTestingModule({
      providers: [provideHttpClient(), provideHttpClientTesting()],
    });
    const store = TestBed.inject(UsersStore);
    const httpMock = TestBed.inject(HttpTestingController);

    const promise = store.load();
    httpMock.expectOne('/api/v1/users').flush([{ id: 'u1', email: 'a@a.com' }]);
    await promise;

    expect(store.users()).toHaveLength(1);
    expect(store.count()).toBe(1);
    expect(store.loading()).toBe(false);
  });
});
```

## Playwright E2E

```bash
pnpm add -D @playwright/test
pnpx playwright install --with-deps chromium
```

`playwright.config.ts`:

```typescript
import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './e2e',
  timeout: 30_000,
  fullyParallel: true,
  retries: process.env.CI ? 2 : 0,
  use: {
    baseURL: 'http://localhost:4200',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
  },
  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
    { name: 'mobile-safari', use: { ...devices['iPhone 14'] } },
  ],
  webServer: {
    command: 'pnpm start',
    port: 4200,
    reuseExistingServer: !process.env.CI,
  },
});
```

`e2e/auth.spec.ts`:

```typescript
import { test, expect } from '@playwright/test';

test('user can sign in and reach dashboard', async ({ page }) => {
  await page.goto('/auth/login');
  await page.getByPlaceholder('Email').fill(`alice+${Date.now()}@example.com`);
  await page.getByPlaceholder('Password').fill('hunter22a');
  await page.getByRole('button', { name: /sign in/i }).click();

  await expect(page).toHaveURL(/\/dashboard/);
  await expect(page.getByRole('heading', { name: /welcome/i })).toBeVisible();
});
```

## Coverage

```bash
pnpm test:cov
# generates coverage/ — HTML + lcov
```

Target ~70% on services, ~50% overall. Don't chase 100% — diminishing returns.

```typescript
// in vitest.config.ts
test: {
  coverage: {
    provider: 'v8',
    reporter: ['text', 'html', 'lcov'],
    thresholds: {
      lines: 70,
      functions: 80,
      branches: 65,
      statements: 70,
    },
    exclude: ['**/*.spec.ts', '**/main.ts', '**/*.module.ts'],
  },
},
```

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| Karma config still around | Delete `karma.conf.js`, `test.ts`; remove from `angular.json` |
| `provideHttpClientTesting` not registering | Order matters — `provideHttpClient()` first, then `provideHttpClientTesting()` |
| Signal effects not running in test | Effects need a tick; use `TestBed.tick()` or wrap in `flushEffects()` |
| Component test fails in jsdom but works in browser | Some browser APIs missing in jsdom; use Playwright for those flows |
| Async tests timing out | Use `await firstValueFrom(...)` or `fakeAsync` + `tick()` |
| `ChangeDetectionStrategy.OnPush` doesn't update in test | Call `fixture.detectChanges()` |
| Memory leaks (open handles) | `httpMock.verify()` in `afterEach`; `TestBed.resetTestingModule()` if needed |
| Dependencies on `localStorage` polluting tests | `localStorage.clear()` in `beforeEach` |
| Tests pass locally fail in CI | Likely race in async setup; use `await` consistently |
| Playwright can't find element | Use `getByRole` / `getByText` (semantic) over CSS selectors; `await` for visibility |
