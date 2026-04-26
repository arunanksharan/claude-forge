# Per-Framework Testing

> Conventional (CI-friendly) testing patterns per framework. Pairs with the agent-driven E2E guides one level up.

This folder is intentionally light — the framework-specific testing guides already live with their PROMPT.md files:

| Framework | Testing guide |
|-----------|--------------|
| Next.js | [`frontend/nextjs/06-testing-with-chrome-devtools-mcp.md`](../../frontend/nextjs/06-testing-with-chrome-devtools-mcp.md) |
| FastAPI | [`backend/fastapi/06-testing-pytest.md`](../../backend/fastapi/06-testing-pytest.md) |
| NestJS | [`backend/nestjs/06-testing-jest-supertest.md`](../../backend/nestjs/06-testing-jest-supertest.md) |
| Node + Express | [`backend/nodejs-express/06-testing-vitest-supertest.md`](../../backend/nodejs-express/06-testing-vitest-supertest.md) |
| Flutter (Riverpod / Bloc) | bloc_test patterns are in `mobile/flutter-bloc/PROMPT.md`; widget tests in both `mobile/flutter-*/PROMPT.md` |
| React Native | Maestro patterns are in `mobile/react-native/PROMPT.md` |
| Angular | Vitest + provideHttpClientTesting patterns are in `frontend/angular/PROMPT.md` |

## Quick philosophy

| Layer | Speed | What it catches |
|-------|-------|----------------|
| **Unit** (pure logic) | <10ms | calculations, validators, state machines |
| **Integration** (route → service → real DB) | 50–500ms | SQL bugs, transaction bugs, JSON shape drift |
| **E2E** (full app stack) | seconds | wiring bugs, regression of critical paths |
| **Agent-driven E2E** (Claude + MCP) | 30s–2min | exploratory, post-feature verification |
| **Synthetic** (production smoke) | continuous | "is prod up?" |

Default to integration tests against a real DB (the most bang per minute spent). Push critical user flows into a small Playwright suite. Use agent-driven E2E for "did Claude's recent work actually work?"

## Don't write these

- **Tests for getters/setters** — generated code, no value
- **Tests that mock the entire system under test** — you're testing your mocks
- **Snapshot tests for everything** — they break on every diff and nobody reads them
- **End-to-end tests for every edge case** — too slow; push edges into integration/unit
- **Tests that require manual setup** — if it can't run from `pnpm test` / `uv run pytest`, it'll bit-rot

## Common test smells

| Smell | Symptom |
|-------|---------|
| Tests that pass locally, fail in CI | DB / state leak; non-deterministic ordering |
| Tests that pass in isolation, fail in suite | Shared state between tests |
| Tests that take >5 minutes | Likely E2E too coarse — split |
| Test fixture bigger than the test | Push fixture setup to factory; assert one thing |
| Mocking what you don't own (third-party libs deeply) | Test through them; mock at the boundary you control |
| Asserting on UI strings that change | Use `data-testid` or accessibility roles |
