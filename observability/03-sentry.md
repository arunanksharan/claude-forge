# Sentry — Error Tracking + Performance

> Frontend + backend, web + mobile. The "I just want to know when things break" tool. Pairs with Prom/Grafana/SigNoz; doesn't replace them.

## Why Sentry (and what it's not for)

Sentry's superpowers:

- **Errors with full context**: stack trace, browser/OS, breadcrumbs leading up, user, custom tags
- **Source maps** — readable stack traces from minified JS
- **Release tracking** — "this error appeared in v1.2.3"
- **User feedback widget** — "tell us what happened"
- **Performance/tracing** — request waterfalls, span analysis
- **Profiling** — flame graphs of slow code
- **Cross-platform**: Node, Python, browser JS, React, React Native, Flutter, Go, Rust, etc.

Sentry is **not** a replacement for:

- General APM (Prom/Grafana/Datadog) — Sentry's metrics are limited
- Log aggregation (Loki, CloudWatch) — Sentry shows logs around an error, not all logs
- Uptime monitoring — use Better Uptime, Uptime Robot, etc.

Use Sentry **for errors and as a complement to your APM stack**.

## Pricing

Generous free tier: 5K errors / 10K performance units / 1 user. Past that:

- Self-hosted is free but heavy ops (Docker compose with multiple services + ClickHouse)
- Hosted Team plan ~$26/mo, scales by volume
- Most teams: stay hosted unless privacy/compliance demands self-hosted

## Backend — Python (FastAPI)

```bash
uv add sentry-sdk[fastapi]
```

```python
# src/{{project-slug}}/telemetry.py (add at startup)
import sentry_sdk
from sentry_sdk.integrations.fastapi import FastApiIntegration
from sentry_sdk.integrations.starlette import StarletteIntegration
from sentry_sdk.integrations.sqlalchemy import SqlalchemyIntegration
from sentry_sdk.integrations.redis import RedisIntegration
from sentry_sdk.integrations.celery import CeleryIntegration

def setup_sentry(settings):
    if not settings.sentry_dsn:
        return
    sentry_sdk.init(
        dsn=settings.sentry_dsn,
        environment=settings.env,
        release=settings.release,                # e.g. "{{project-slug}}@1.2.3"
        traces_sample_rate=0.1,                  # 10% of requests get traced
        profiles_sample_rate=0.1,
        send_default_pii=False,                  # don't send IP, headers
        integrations=[
            FastApiIntegration(),
            StarletteIntegration(),
            SqlalchemyIntegration(),
            RedisIntegration(),
            CeleryIntegration(),
        ],
        before_send=lambda event, hint: scrub(event),
    )

def scrub(event):
    # remove sensitive fields before sending
    if "request" in event and "data" in event["request"]:
        for key in ("password", "token", "api_key"):
            event["request"]["data"].pop(key, None)
    return event
```

Call `setup_sentry(settings)` at app startup, before anything else.

### Capturing custom errors

```python
import sentry_sdk

# explicit
try:
    risky_thing()
except SomeException as e:
    sentry_sdk.capture_exception(e)
    raise

# with context
sentry_sdk.set_tag("feature", "billing")
sentry_sdk.set_user({"id": user.id, "email": user.email})

with sentry_sdk.start_transaction(name="process_order", op="task"):
    # ...
    pass

# breadcrumb (visible in error context)
sentry_sdk.add_breadcrumb(category="payment", message="charge initiated", data={"order_id": ...})
```

## Backend — Node (Nest / Express)

```bash
pnpm add @sentry/node @sentry/profiling-node
```

```typescript
// src/sentry.ts — import FIRST
import * as Sentry from '@sentry/node';
import { nodeProfilingIntegration } from '@sentry/profiling-node';

if (process.env.SENTRY_DSN) {
  Sentry.init({
    dsn: process.env.SENTRY_DSN,
    environment: process.env.NODE_ENV,
    release: process.env.SENTRY_RELEASE,
    tracesSampleRate: 0.1,
    profilesSampleRate: 0.1,
    sendDefaultPii: false,
    integrations: [nodeProfilingIntegration()],
  });
}
```

```typescript
// main.ts — import sentry first
import './sentry';
import { NestFactory } from '@nestjs/core';
// ...
```

### NestJS — global filter for unhandled exceptions

```typescript
import { ArgumentsHost, Catch, ExceptionFilter, HttpException } from '@nestjs/common';
import * as Sentry from '@sentry/node';

@Catch()
export class SentryExceptionFilter implements ExceptionFilter {
  catch(exception: unknown, host: ArgumentsHost) {
    if (!(exception instanceof HttpException) || (exception as HttpException).getStatus() >= 500) {
      Sentry.captureException(exception);
    }
    throw exception;   // re-throw so default handler still runs
  }
}

// in main.ts
app.useGlobalFilters(new SentryExceptionFilter());
```

For Express:

```typescript
import * as Sentry from '@sentry/node';

// must be after all routes
Sentry.setupExpressErrorHandler(app);
```

### BullMQ workers

```typescript
worker.on('failed', (job, err) => {
  Sentry.captureException(err, {
    tags: { queue: job?.queueName, job_name: job?.name },
    extra: { job_id: job?.id, attempts: job?.attemptsMade, data: job?.data },
  });
});
```

## Frontend — Next.js

```bash
pnpm add @sentry/nextjs
pnpx @sentry/wizard@latest -i nextjs
```

The wizard creates `sentry.client.config.ts`, `sentry.server.config.ts`, `sentry.edge.config.ts`, and updates `next.config.ts`. Customize:

```typescript
// sentry.client.config.ts
import * as Sentry from '@sentry/nextjs';

Sentry.init({
  dsn: process.env.NEXT_PUBLIC_SENTRY_DSN,
  environment: process.env.NEXT_PUBLIC_ENV,
  tracesSampleRate: 0.1,
  replaysSessionSampleRate: 0.0,
  replaysOnErrorSampleRate: 1.0,        // record 100% of error sessions
  integrations: [Sentry.replayIntegration({ maskAllText: false, blockAllMedia: true })],
});
```

Source maps upload automatically via the wizard's CI integration. Or:

```bash
SENTRY_AUTH_TOKEN=... pnpm sentry-cli sourcemaps upload --release {{release}} .next/
```

### React error boundaries

Wrap routes:

```tsx
'use client';
import * as Sentry from '@sentry/nextjs';

export default function ErrorBoundary({ error }: { error: Error }) {
  Sentry.captureException(error);
  return <div>Something went wrong.</div>;
}
```

Or `app/error.tsx` — Next handles auto-capture if `@sentry/nextjs` is configured.

## Frontend — Vue / SvelteKit / Vanilla

`@sentry/vue`, `@sentry/sveltekit`, `@sentry/browser`. All similar APIs. Wizard for each: `npx @sentry/wizard -i <framework>`.

## Mobile — React Native

```bash
pnpm add @sentry/react-native
pnpx @sentry/wizard -i reactNative
```

```typescript
// app/_layout.tsx (or wherever your root is)
import * as Sentry from '@sentry/react-native';

Sentry.init({
  dsn: process.env.EXPO_PUBLIC_SENTRY_DSN,
  environment: process.env.EXPO_PUBLIC_ENV,
  tracesSampleRate: 0.1,
  enableNative: true,
});

export default Sentry.wrap(RootLayout);    // wraps in error boundary
```

For Expo, install `@sentry/react-native` + the dev client. For pure Expo Go, you can use `@sentry/browser` only.

## Mobile — Flutter

```yaml
# pubspec.yaml
dependencies:
  sentry_flutter: ^8.10.0
```

```dart
// main.dart
import 'package:sentry_flutter/sentry_flutter.dart';

await SentryFlutter.init(
  (options) {
    options.dsn = const String.fromEnvironment('SENTRY_DSN');
    options.environment = const String.fromEnvironment('ENV', defaultValue: 'dev');
    options.tracesSampleRate = 0.1;
    options.profilesSampleRate = 0.1;
    options.attachScreenshot = true;
    options.attachViewHierarchy = true;
  },
  appRunner: () => runApp(const ProviderScope(child: MyApp())),
);
```

## Releases + source maps

Set `SENTRY_RELEASE` env var. Convention: `{{project-slug}}@<git-sha>` or `{{project-slug}}@<semver>`.

Upload source maps in CI:

```bash
SENTRY_AUTH_TOKEN=... \
  npx @sentry/cli releases new "{{project-slug}}@$(git rev-parse --short HEAD)"
SENTRY_AUTH_TOKEN=... \
  npx @sentry/cli sourcemaps upload \
  --release "{{project-slug}}@$(git rev-parse --short HEAD)" \
  ./dist
SENTRY_AUTH_TOKEN=... \
  npx @sentry/cli releases finalize "{{project-slug}}@$(git rev-parse --short HEAD)"
```

## What to scrub

By default Sentry collects:
- Request body (POST/PUT)
- Cookies
- Headers
- Local variables in stack frames

Aggressively scrub:
- Passwords (any field with "password" / "token" / "api_key" / "secret")
- PII per your jurisdiction
- Large bodies (set `max_request_body_size`)

```python
# Python
sentry_sdk.init(
    ...,
    before_send=scrub,
    request_bodies="never",         # don't capture request bodies at all
)
```

```typescript
// JS
Sentry.init({
  ...,
  beforeSend(event) {
    if (event.request?.data) {
      delete event.request.data.password;
    }
    return event;
  },
});
```

## Sample rate decisions

```
errors:    100% — always send all errors
traces:    10%  — sample for cost; bump for low-traffic services
profiles:  10%  — same
replays:   100% on error, 0% on success
```

Adjust by service criticality. For a critical API at low traffic: 100% traces. For a chatty service: 1%.

## Alert routing

In Sentry's UI:

- **Issue alerts**: "any new issue → Slack #alerts"
- **Threshold alerts**: "more than 100 events of type X in 5min → PagerDuty"
- **Integration**: Slack, PagerDuty, Discord, GitHub (auto-create issues)

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| `dsn` missing in prod | Sentry silently does nothing; verify in UI under "Stats" |
| Source maps wrong release | `SENTRY_RELEASE` must match between SDK init and upload |
| Source maps not uploading | CI step missing — `@sentry/cli` upload after build |
| Logged passwords / PII | Use `before_send` scrub; review filtered fields in UI |
| Sample rate too high → bill shock | Drop `tracesSampleRate` to 0.05 for high-traffic |
| Too many ignorable errors (network blips) | Use `ignoreErrors` / `ignoreTransactions` config |
| Replay is huge | Disable for non-error sessions; use `maskAllText: true` |
| Self-hosted Sentry maintenance burden | Migrate to hosted unless privacy-mandated |
| Errors don't include user | Set `setUser` in middleware after auth |
| 100% trace sample on free tier | You'll exceed quota fast — sample at 0.05–0.1 |

## Sentry vs other error trackers

| | **Sentry** | **Bugsnag** | **Rollbar** | **Honeybadger** |
|---|---|---|---|---|
| Frontend + backend coverage | best | good | good | good |
| Performance/tracing | yes | yes | basic | no |
| Self-hosting | yes | no | yes | no |
| Pricing | mid | low | mid | low |
| Open source | yes (BSL) | no | no | no |

For most teams: **Sentry**. Bugsnag is a fine second.
