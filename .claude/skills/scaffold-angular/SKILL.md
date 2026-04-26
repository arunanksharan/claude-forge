---
name: scaffold-angular
description: Use when the user wants to scaffold a new Angular 18+ project with standalone components (no NgModules), signals for reactive state, NgRx Signal Store for shared state, RxJS for HTTP/WebSocket, typed reactive forms, lazy-loaded routes, Tailwind CSS, optional SSR via @angular/ssr, Vitest for tests, Playwright for E2E. Triggers on "new angular project", "scaffold angular", "angular 18 app".
---

# Scaffold Angular Project (claudeforge)

Follow the master prompt at `frontend/angular/PROMPT.md`. Steps:

1. **Confirm parameters**: `project_name`, `project_slug` (kebab-case), `description`, `api_base_url`, include SSR / auth, UI kit choice (default: tailwind+manual).
2. **Read** `frontend/angular/PROMPT.md` — directory tree, locked stack, key files (app.config.ts, app.routes.ts, auth interceptor, auth guard, AuthService with signals, LoginComponent with reactive forms).
3. **Generate**:
   - `npx -p @angular/cli@latest ng new {{project-slug}} --standalone --routing --style=css --strict --skip-tests`
   - `cd {{project-slug}} && pnpm install`
   - Add Tailwind: `pnpm add -D tailwindcss @tailwindcss/postcss postcss` + `tailwind.config.ts` + `@import "tailwindcss";` in `src/styles.css`
   - Add NgRx Signal Store: `pnpm add @ngrx/signals`
   - Generate the directory tree under `src/app/` (core/, features/, shared/)
   - Write `app.config.ts` with `provideRouter` + `provideHttpClient(withFetch(), withInterceptors([...]))`
   - Write `app.routes.ts` with lazy-loaded feature routes
   - Write `core/` interceptors (auth, error), guard (authGuard), token (API_BASE_URL)
   - Write one feature module end-to-end: AuthService (signal-based) + LoginComponent (standalone, reactive forms, signals)
4. **(Optional) SSR**: `ng add @angular/ssr` if `include_ssr=yes`.
5. **Verify**: `pnpm start` works, `pnpm lint && pnpm build` clean.
6. **Hand off**: next steps.

Do NOT use NgModules in new code. Do NOT install Angular Material or PrimeNG by default — keep Tailwind + CDK primitives unless user asks. Use signals for state, RxJS only for streams (HTTP, WebSocket).
