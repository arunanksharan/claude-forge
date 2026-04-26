# Testing — claudeforge guides

> *Phase 5 — coming soon.* End-to-end testing strategies, with a focus on **agent-driven testing via MCP** — letting Claude Code drive a real browser via Chrome DevTools MCP or Puppeteer MCP and verify what's actually rendering.

## Files

- `e2e-with-chrome-devtools-mcp.md` — *Phase 5* — using the Chrome DevTools MCP server to navigate, click, fill, screenshot, and inspect console messages from inside Claude Code
- `e2e-with-puppeteer-mcp.md` — *Phase 5* — same idea via Puppeteer MCP, when you need headless or specific Chromium control
- `per-framework/` — *Phase 5* — Vitest + RTL for React, pytest + httpx for FastAPI, Jest + Supertest for Nest/Express, Flutter integration tests

## Why agent-driven E2E

Traditional E2E tests are brittle (selectors break, timing flakes, you maintain a test suite of comparable size to your app). Agent-driven E2E flips the script: Claude can drive the browser, *see* the DOM, *read* console errors, and reason about whether the feature actually works — much closer to a human QA pass. You still want unit and integration tests for fast feedback, but for "did this user flow break?" agent-driven E2E is faster to write and more resilient.
