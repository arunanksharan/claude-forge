# Agent-Driven E2E with Puppeteer MCP

> Same idea as `e2e-with-chrome-devtools-mcp.md`, via the Puppeteer MCP server. When and why to pick this variant.

## When to use Puppeteer MCP

| Pick Puppeteer MCP | Pick Chrome DevTools MCP |
|---|---|
| Server / CI environment without a Chrome install | Local dev with full Chrome |
| You want headless by default | You want visible browser by default |
| Multi-tab orchestration needed | Single-page workflows |
| Familiar with Puppeteer's API | Don't care |
| Lower setup overhead | Want Lighthouse + accessibility tree |

For most local agent-driven E2E from inside Claude Code: **Chrome DevTools MCP**. For a remote runner or specific Puppeteer features: **Puppeteer MCP**.

## Setup

```json
// Claude Code MCP config
{
  "puppeteer": {
    "command": "npx",
    "args": ["-y", "@modelcontextprotocol/server-puppeteer"]
  }
}
```

Restart Claude Code. Tools `mcp__playwright__*` (yes — many "puppeteer" MCPs are actually backed by Playwright; check your installed version) become available.

> Note: a few different MCP servers exist ("puppeteer", "playwright", "browserbase"). They expose similar tools (`navigate`, `click`, `fill`, `screenshot`). The patterns below apply to all.

## Tools (typical)

- `browser_navigate(url)` — load a URL
- `browser_snapshot()` — get the DOM tree
- `browser_take_screenshot([path])` — image of current view
- `browser_click(element)` — click by accessibility selector
- `browser_fill_form(elements: [...])` — fill multiple fields at once
- `browser_evaluate(code)` — run JS in the page context
- `browser_console_messages()` — read console
- `browser_network_requests()` — list requests
- `browser_wait_for(text|condition)` — wait
- `browser_navigate_back()` — back button
- `browser_close()` — close
- `browser_tabs()` — list, switch tabs

## The same patterns

All the same flows as the Chrome DevTools MCP guide work here. The prompt patterns are identical:

```
Open http://localhost:3000/signup, fill in
qa+{{timestamp}}@example.com / hunter22a, click submit, verify we
land on /dashboard, screenshot the result.
```

Claude picks the right tools based on what's loaded.

## Differences in practice

### Multi-tab workflows

Puppeteer MCP makes multi-tab easier:

```
Open localhost:3000/admin in tab 1, login as admin.
In tab 2, open localhost:3000 and login as a regular user.
Verify the admin sees the new user's actions in tab 1's audit log.
```

Claude can use `browser_tabs()` + tab IDs to flip between them.

### Network interception

Some Puppeteer MCPs expose request interception:

```
Block all calls to https://analytics.example.com and verify the page
still works correctly.
```

Useful for testing third-party-script-down scenarios.

### Headless screenshots in CI-like environments

If you have a Claude Code run on a server (e.g. via `claude` CLI in a remote session), Puppeteer's headless mode just works without an X display.

## Pattern: parametric test runs

Because Claude is the runner, you can ask for parametric runs that would be tedious in a fixture file:

```
For each of these 10 user emails (paste list), sign in, go to /billing,
take a screenshot of the invoice. Generate a markdown table summarizing
each user's last invoice amount.
```

Claude loops, captures, reports. Won't beat Playwright in CI but for one-off ops investigations: very useful.

## Common pitfalls

Same as Chrome DevTools MCP. Plus:

| Pitfall | Fix |
|---------|-----|
| `Failed to launch browser` in CI | Pre-install chromium: `npx puppeteer browsers install chrome` |
| MCP server crashes on first call | Stale browser process — kill `chrome` / `chromium`, retry |
| Tool name mismatch (`browser_click` vs `mcp__puppeteer__click`) | Different MCP servers name tools differently — check your installed server's docs |
| Screenshots blank | Page didn't finish loading — `wait_for` first |
| Click finds wrong element | Use accessibility selectors (text, label) not CSS |

## See also

- [`e2e-with-chrome-devtools-mcp.md`](./e2e-with-chrome-devtools-mcp.md) — the more common variant
