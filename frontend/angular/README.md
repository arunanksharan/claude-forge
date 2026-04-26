# Angular — claudeforge guides

Modern Angular (18+) with standalone components, signals, lazy-loaded routes, and SSR optional.

## Files

- [`PROMPT.md`](./PROMPT.md) — master scaffold: standalone components, signals, NgRx Signal Store, reactive forms, Tailwind, SSR-ready

## Quick decision summary

- **Angular 18+** with **standalone components** (no NgModules in new code)
- **Signals** for local state, **NgRx Signal Store** for shared
- **RxJS** only for HTTP / WebSocket / time-based async
- **Reactive Forms** (typed)
- **Tailwind** for styling (avoid Material/PrimeNG by default)
- **Vitest** + **Playwright** for tests (Karma is being deprecated)
- Standalone APIs: `provideRouter`, `provideHttpClient`, `withFetch()`
