---
name: wire-sentry
description: Use when the user wants to add Sentry for error tracking + performance to an existing app. Covers FastAPI, NestJS, Express, Next.js, React Native, Flutter. Includes scrubbing PII, sample rate decisions, source map upload in CI, release tracking. Triggers on "add sentry", "set up error tracking", "wire up sentry", "sentry integration".
---

# Wire Up Sentry (claudeforge)

Follow `observability/03-sentry.md`. Steps:

1. **Identify the stack**: which app(s) — FastAPI / NestJS / Express / Next.js / RN / Flutter?
2. **Confirm with user**: do they have a Sentry account + project + DSN? If not, ask them to create one and share the DSN.
3. **Install the SDK** for the target framework — see the relevant section of `03-sentry.md`:
   - Python (FastAPI): `sentry-sdk[fastapi]` + `setup_sentry()` in startup
   - Node (Nest/Express): `@sentry/node` + `@sentry/profiling-node`, import-first pattern
   - Next.js: `@sentry/nextjs` via `pnpx @sentry/wizard -i nextjs`
   - React Native: `@sentry/react-native` via `pnpx @sentry/wizard -i reactNative`
   - Flutter: `sentry_flutter` package + `SentryFlutter.init`
4. **Configure the SDK**:
   - `dsn`, `environment`, `release` (set via env)
   - Sample rates: `tracesSampleRate: 0.1`, `profilesSampleRate: 0.1` (start low, tune up if needed)
   - `sendDefaultPii: false` + a `before_send` / `beforeSend` scrubber for password/token/api_key fields
   - Integrations relevant to the framework (FastAPI, SQLAlchemy, Redis, Celery, etc.)
5. **Set up source maps** (web/RN frameworks):
   - In CI, after build: `npx @sentry/cli sourcemaps upload --release "{{slug}}@{{git-sha}}" ./dist`
6. **Set up release tracking**:
   - Set `SENTRY_RELEASE` env var to `{{slug}}@{{git-sha}}`
   - Confirm releases appear in Sentry UI
7. **Configure alerts in Sentry UI**: route critical errors to Slack/PagerDuty.
8. **Trigger a test error** to verify end-to-end: `sentry_sdk.capture_message("test")` or throw a test exception.

Don't crank `tracesSampleRate` to 1.0 in production — bill shock. Always scrub PII before sending.
