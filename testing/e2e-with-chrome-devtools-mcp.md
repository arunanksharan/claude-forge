# Agent-Driven E2E with Chrome DevTools MCP

> Let Claude Code drive a real Chrome instance — navigate, click, fill, screenshot, inspect console + network. Replace half your manual QA passes.

## What this is, what it isn't

**Is**:
- An interactive verification tool for use *inside Claude Code*
- Great for "did this user flow actually work?" right after building it
- Great for visual regression spot-checks
- Great for performance + console-error sweeps

**Isn't**:
- A replacement for Playwright in CI (too slow, non-deterministic, costs LLM tokens)
- A general-purpose browser automation framework (use Playwright/Puppeteer for that)
- A way to test mobile (use Maestro / native testing)

The pattern: keep your fast deterministic tests in CI, use agent-driven E2E for "did Claude's last 10 commits actually work end-to-end?"

## Setup

The Chrome DevTools MCP server gives Claude tools like `navigate_page`, `click`, `fill`, `take_screenshot`, `list_console_messages`, `list_network_requests`, `lighthouse_audit`.

```json
// in your Claude Code MCP config (via /mcp UI or settings)
{
  "chrome-devtools": {
    "command": "npx",
    "args": ["-y", "@modelcontextprotocol/server-chrome-devtools"]
  }
}
```

Restart Claude Code. Run `/mcp` to confirm it's loaded.

## The basic loop

```
You: "Open http://localhost:3000, navigate to /signup, sign up as
     qa+{{timestamp}}@example.com / hunter22a, verify we land on
     /dashboard, and report any console errors."

Claude:
  1. mcp__chrome-devtools__navigate_page(url="http://localhost:3000/signup")
  2. mcp__chrome-devtools__take_snapshot()           # learn the DOM
  3. mcp__chrome-devtools__fill(uid="...email...", text="qa+1730000000@example.com")
  4. mcp__chrome-devtools__fill(uid="...password...", text="hunter22a")
  5. mcp__chrome-devtools__click(uid="...submit...")
  6. mcp__chrome-devtools__wait_for(text="Welcome")
  7. mcp__chrome-devtools__take_screenshot()
  8. mcp__chrome-devtools__list_console_messages(level="error")
  9. → reports back with screenshot + any errors found
```

You see the screenshot inline + Claude's analysis. You review.

## Patterns

### 1. Smoke test after a UI change

```
Just refactored the checkout flow. Open http://localhost:3000/checkout,
walk through with a test card 4242 4242 4242 4242, verify we hit the
success page. Screenshot every step. Report any regressions.
```

Output: a sequence of screenshots + a verdict.

### 2. Console error sweep

```
Visit each of these pages and report any errors or warnings in the
console:
  /
  /products
  /products/123
  /cart
  /account
```

Claude opens each, reads `list_console_messages`, summarizes.

### 3. Visual regression vs a baseline

```
Take a screenshot of /pricing on the current branch. Then `git stash`
my changes, restart the dev server, and screenshot it again. Compare —
what visually changed?
```

Claude takes both screenshots, compares them visually, lists differences.

### 4. Network audit

```
Open /dashboard and monitor network requests. Tell me:
  - Are there any 4xx or 5xx responses?
  - What's the slowest API call?
  - Are we double-fetching anything?
```

Claude uses `list_network_requests` + `get_network_request` for details.

### 5. Performance audit

```
Run a Lighthouse audit on http://localhost:3000 for both mobile and
desktop. Report LCP, INP, CLS, TBT. Flag anything below threshold.
```

`mcp__chrome-devtools__lighthouse_audit` returns the full report.

### 6. Accessibility check

```
On /signup, take a snapshot of the DOM tree and verify:
  - All form inputs have labels (htmlFor matches id)
  - Submit button is keyboard-focusable
  - Color contrast meets WCAG AA on the form
Report violations.
```

### 7. After-deploy smoke

```
Production was just deployed. Visit https://example.com:
  1. Home page loads, no console errors
  2. Click 'Sign in' link, verify modal opens
  3. Try an invalid login, verify error appears
  4. Check the API health endpoint /api/v1/health returns 200
Report green/red per check.
```

## Hardening tips

### Use timestamps, not fixed strings

```
qa+{{timestamp}}@example.com
```

Re-runnable without "email already in use" failures.

### Use accessible names, not CSS selectors

```
"click the button labeled Sign in"     ✓  (Claude finds via accessibility tree)
"click button.btn-primary.submit-btn"  ✗  (brittle; CSS selectors break easily)
```

The MCP exposes the accessibility tree, which is closer to how a user perceives the page. More resilient to design changes.

### Wait for state, not time

```
"after clicking submit, wait for /dashboard to appear in the URL"   ✓
"after clicking submit, wait 5 seconds"                              ✗
```

The first is deterministic; the second is brittle and slow.

### Demand evidence

```
After each step, take a screenshot. At the end, list any console
messages of level warning or error.
```

Don't trust "looks fine" — demand artifacts.

### Bound the work

```
Run this check in under 5 steps. If it takes more, stop and report.
```

Otherwise an LLM might spend 30 calls exploring before reporting.

## Token budget reality

Each MCP call uses tokens (the screenshot or DOM snapshot is sent back to the model). A 10-step E2E run might cost $0.10–$1 depending on the model. **Use selectively.** Don't put it in CI.

A typical session:
- Build a feature with Claude
- Run **one** agent E2E to verify
- Fix issues found
- Move on

That's the right cadence.

## Combining with Playwright

The relationship:

| Layer | Tool | Cadence |
|-------|------|---------|
| Unit tests (logic) | Vitest / Jest | every CI run, fast |
| Component tests (rendering) | RTL / Vue Test Utils | every CI run, fast |
| E2E (deterministic, critical paths) | Playwright | every CI run, slower |
| E2E (exploratory, recent changes) | Chrome DevTools MCP | manually, after a feature |
| Production smoke | Synthetic monitoring (Checkly, etc.) | continuous |

The MCP layer fills the gap between "I shipped a feature" and "I have time to write a full Playwright test for it."

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| MCP server not loaded | `/mcp` to verify; restart Claude Code |
| Slow runs (60s+) | Limit step count; use Playwright for breadth |
| Stale page state across runs | Force `navigate_page` with cache disable; or restart browser |
| Wrong field filled | Use `take_snapshot` first; use accessible names |
| Token cost mounting | Cap per-session step count; use parallel Playwright for breadth |
| Console errors missed | Always `list_console_messages(level="error")` explicitly |
| Form submits with stale CSRF | Refresh cookie / restart browser between flows |
| Test pollution (shared user) | Always use timestamped/UUID inputs |
| Agent confidently misreports | Demand screenshots; verify visually |

## Alternative: Puppeteer MCP

There's also `@modelcontextprotocol/server-puppeteer`. Differences:

| | Chrome DevTools MCP | Puppeteer MCP |
|---|---|---|
| Backend | Real Chrome via CDP | Puppeteer (which also uses CDP) |
| Headless option | yes | yes |
| Lighthouse | built-in | manual via Puppeteer |
| DOM snapshot | rich (accessibility tree) | DOM serialization |
| Node deps | none on host | needs chromium |

For most cases: **Chrome DevTools MCP**. Puppeteer MCP is fine if you specifically want headless control on a server without an X server.

## See also

- [`e2e-with-puppeteer-mcp.md`](./e2e-with-puppeteer-mcp.md) — Puppeteer MCP variant
- [`per-framework/e2e-playwright-nextjs.md`](./per-framework/e2e-playwright-nextjs.md) — traditional E2E in CI
- `frontend/nextjs/06-testing-with-chrome-devtools-mcp.md` — Next.js-specific patterns
