# Testing Next.js with Chrome DevTools MCP

> Two complementary approaches: **traditional automated tests** (Vitest, Playwright) and **agent-driven E2E** via Chrome DevTools MCP / Puppeteer MCP.

## The pyramid + agent layer

```
                    ┌──────────────────────┐
                    │   Agent E2E (MCP)    │  ← exploratory, "did this flow work?"
                    └──────────────────────┘
                  ┌──────────────────────────┐
                  │  Playwright E2E (smoke)  │  ← critical user paths in CI
                  └──────────────────────────┘
            ┌────────────────────────────────────┐
            │  Vitest + RTL component tests       │  ← logic, edge cases
            └────────────────────────────────────┘
```

The bottom two run in CI on every PR. The top runs **on demand**, from inside Claude Code.

## Vitest + React Testing Library

`vitest.config.ts`:

```typescript
import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';
import { resolve } from 'path';

export default defineConfig({
  plugins: [react()],
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: ['./tests/setup.ts'],
    css: true,
  },
  resolve: {
    alias: { '@': resolve(__dirname, './src') },
  },
});
```

`tests/setup.ts`:

```typescript
import '@testing-library/jest-dom/vitest';
import { cleanup } from '@testing-library/react';
import { afterEach } from 'vitest';

afterEach(() => cleanup());
```

Component test:

```tsx
// src/components/features/users/users-list.test.tsx
import { render, screen } from '@testing-library/react';
import { UsersList } from './users-list';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';

const wrapper = ({ children }: { children: React.ReactNode }) => {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return <QueryClientProvider client={qc}>{children}</QueryClientProvider>;
};

it('renders the users heading', () => {
  render(<UsersList />, { wrapper });
  expect(screen.getByRole('heading', { name: /users/i })).toBeInTheDocument();
});
```

Mock fetch with `msw`:

```bash
pnpm add -D msw
```

```typescript
// tests/mocks/handlers.ts
import { http, HttpResponse } from 'msw';
import { env } from '@/lib/env';

export const handlers = [
  http.get(`${env.NEXT_PUBLIC_API_URL}/api/v1/users`, () =>
    HttpResponse.json([{ id: '1', email: 'alice@example.com' }]),
  ),
];
```

## Playwright (traditional E2E)

`playwright.config.ts`:

```typescript
import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './tests/e2e',
  timeout: 30_000,
  fullyParallel: true,
  retries: process.env.CI ? 2 : 0,
  use: {
    baseURL: 'http://localhost:3000',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
  },
  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
    { name: 'mobile', use: { ...devices['iPhone 14'] } },
  ],
  webServer: {
    command: 'pnpm dev',
    port: 3000,
    reuseExistingServer: !process.env.CI,
  },
});
```

Test:

```typescript
// tests/e2e/signup.spec.ts
import { test, expect } from '@playwright/test';

test('user can sign up and reach dashboard', async ({ page }) => {
  await page.goto('/');
  await page.getByRole('link', { name: /sign up/i }).click();
  await page.getByLabel(/email/i).fill(`alice+${Date.now()}@example.com`);
  await page.getByLabel(/password/i).fill('hunter22a');
  await page.getByRole('button', { name: /create account/i }).click();

  await expect(page.getByRole('heading', { name: /dashboard/i })).toBeVisible();
});
```

## Agent-driven E2E with Chrome DevTools MCP

The Chrome DevTools MCP server gives Claude Code direct control of a Chrome instance:

- Navigate pages
- Click, fill, hover
- Take screenshots
- Inspect DOM
- Read console messages
- Read network requests
- Run Lighthouse audits

This is **not a replacement for Playwright in CI**. It's an **interactive verification tool** that you run from inside Claude Code:

> "Open http://localhost:3000, sign up as a new user, click the dashboard, and tell me if there are any console errors or layout issues."

Claude actually does this — opens a browser, navigates, screenshots, reads console — and reports back.

### When agent-driven E2E wins

- **Exploratory testing** — "is this broken anywhere I haven't thought of?"
- **Visual regression** — Claude can screenshot and compare against an earlier image
- **Cross-browser smoke** — open in headed Chrome and look at it
- **Console error sweeps** — "any errors anywhere on these 5 pages?"
- **Validating a Claude-generated UI** — Claude built it, Claude verifies it

### When Playwright still wins

- **CI** — repeatable, parametric, fast
- **Critical paths that must never break** — the deterministic suite
- **Hundreds of cases** — agent E2E is too slow for breadth
- **Fixed budget** — agent calls cost LLM tokens

## Chrome DevTools MCP setup

Install the MCP server (in your Claude Code config):

```json
// ~/.claude/mcp_servers.json (or via /mcp UI)
{
  "chrome-devtools": {
    "command": "npx",
    "args": ["-y", "@modelcontextprotocol/server-chrome-devtools"]
  }
}
```

Restart Claude Code. The tools `mcp__chrome-devtools__*` become available.

### Common workflows

**Verify a page renders correctly:**

```
Open http://localhost:3000/dashboard, take a snapshot of the DOM and a screenshot,
and tell me if anything looks wrong (overlapping elements, missing data, console errors).
```

Claude:
1. Calls `mcp__chrome-devtools__navigate_page`
2. Calls `mcp__chrome-devtools__take_snapshot` (DOM tree with element IDs)
3. Calls `mcp__chrome-devtools__take_screenshot`
4. Calls `mcp__chrome-devtools__list_console_messages`
5. Reports

**Test a user flow:**

```
Sign up a new user via the form on /signup. Use email
"qa+{{timestamp}}@example.com" and password "hunter22a". After clicking submit,
verify we land on /dashboard and see "Welcome".
```

Claude uses `fill`, `click`, `wait_for` to drive the form.

**Profile performance:**

```
Run a Lighthouse audit on http://localhost:3000 and report the LCP, INP, CLS scores.
```

Claude uses `mcp__chrome-devtools__lighthouse_audit`.

**Debug a network issue:**

```
Open /products. While loading, monitor network requests for any 4xx/5xx responses
and report which endpoints failed.
```

Claude uses `list_network_requests` and `get_network_request` to inspect.

## Puppeteer MCP — alternative

`@modelcontextprotocol/server-puppeteer` provides a similar interface via Puppeteer instead of CDP. The Chrome DevTools MCP is more powerful (full CDP access, real Chrome). Use Puppeteer MCP if:

- You need headless control on a server without Chrome installed
- You're already familiar with Puppeteer's mental model
- You're scripting multi-page workflows that are easier in Puppeteer's API

## Patterns for agent-driven testing

### Idempotent test data

Use timestamps or UUIDs in test inputs:

```
email: qa+1730000000@example.com
```

So re-running doesn't hit "email already exists".

### Wait, don't sleep

Tell Claude to wait for a specific element/URL/text rather than a fixed timeout:

```
After clicking submit, wait for the URL to include "/dashboard" before screenshotting.
```

Claude uses `wait_for` with the right predicate.

### Capture proof

Always ask for screenshots + console snapshots so you can review even if Claude says "looks fine":

```
After each step, take a screenshot. At the end, list any console messages
of level warning or error.
```

### Don't trust the agent's "looks correct"

LLMs can confidently misread UIs. **Ask for the screenshot** and look yourself. The MCP returns the image into your conversation.

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| MCP server not loaded | Restart Claude Code; check `/mcp` shows it |
| Chrome flags differ between runs | Pin browser version in CI; agent-driven is for local |
| Slow agent runs (1 min per check) | Use Playwright for breadth; MCP for depth |
| Stale screenshots (cached page) | Force reload via `navigate_page` with cache disable |
| Form fills wrong field | Use accessible names (`getByLabel`-equivalent), not CSS selectors |
| Token budget blown on E2E | Each MCP call uses tokens — be intentional |
| Agent reads console but misses errors | Ask explicitly for level filter (`error` or `warn`) |

## CI integration

Chrome DevTools MCP is for local interactive use. In CI:

- Run **Vitest** for unit/component tests
- Run **Playwright** for traditional E2E
- Optionally: run **Lighthouse CI** for perf budgets

Don't try to run agent-driven tests in CI — the cost and non-determinism don't fit CI's needs.
