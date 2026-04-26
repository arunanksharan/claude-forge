# End-to-End: Mobile App + API + Shared Pipeline

> Hypothetical: a Flutter app + FastAPI backend deployed together, shared CI/CD, real auth. Walks through the prompt chain.

## The hypothetical product

**FieldNote** — a field-service mobile app:
- Flutter app for technicians (offline-first, syncs when online)
- FastAPI backend for the data + auth
- Web admin for managers (Next.js)
- One Postgres, one Redis, one Sentry account, one CI pipeline

A common pattern: backend serves both web and mobile.

---

## Phase 0 — Decisions (half day)

| Decision | Reference | Pick |
|----------|-----------|------|
| Backend | [`backend/fastapi/README.md`](../backend/fastapi/README.md) | FastAPI |
| Mobile state | [`mobile/README.md`](../mobile/README.md) | Flutter Riverpod (offline-first; clean async ergonomics) |
| Web | [`frontend/nextjs/README.md`](../frontend/nextjs/README.md) | Next.js |
| Database | [`databases/postgres/README.md`](../databases/postgres/README.md) | Postgres + Redis |
| Auth | [`backend/fastapi/04-auth-and-middleware.md`](../backend/fastapi/04-auth-and-middleware.md) | JWT (access + refresh); refresh in Flutter SecureStore, web cookie |
| Deploy | [`deployment/README.md`](../deployment/README.md) | Backend on VPS; mobile via Firebase App Distribution / TestFlight |
| Observability | [`observability/03-sentry.md`](../observability/03-sentry.md) | Sentry for backend + mobile + web (one project per) |

---

## Phase 1 — Backend (1 day)

Same as `examples/end-to-end-saas-app.md` Phases 1-2:

1. `/skill scaffold-fastapi` for the backend
2. Models: `User`, `Tenant`, `WorkOrder`, `Photo`, `Signature`
3. Auth with refresh tokens
4. `/api/v1/work-orders` CRUD endpoints
5. `/api/v1/sync` endpoint that returns delta since last sync (timestamp-based)
6. Tests

The mobile app needs **offline-first**, so the API design matters:

- **Cursor-based sync**: `/api/v1/sync?since={timestamp}` returns changes since last sync
- **Idempotent uploads**: each work-order update has a client-generated UUID; backend dedupes
- **Conflict resolution**: explicit (last-write-wins, or return both versions for app to merge)

---

## Phase 2 — Mobile app (3 days)

### Step 1: scaffold

```
/skill scaffold-flutter-riverpod
app_name: fieldnote
include_auth: yes
include_local_db: yes
api_base_url: https://api.fieldnote.example.com
```

Or paste [`mobile/flutter-riverpod/PROMPT.md`](../mobile/flutter-riverpod/PROMPT.md).

### Step 2: drift schema mirroring API

In `lib/core/storage/local_db.dart`, define drift tables that mirror the API models:

```dart
@DriftDatabase(tables: [WorkOrders, Photos, Signatures, SyncMeta])
class AppDb extends _$AppDb { ... }

class WorkOrders extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  TextColumn get title => text()();
  TextColumn get status => textEnum<WorkOrderStatus>()();
  DateTimeColumn get updatedAt => dateTime()();
  IntColumn get syncStatus => intEnum<SyncStatus>().withDefault(const Constant(0))();   // pending|synced|conflict
}
```

Local is source of truth. UI reads only from drift. Sync runs in background.

### Step 3: sync logic

```dart
@riverpod
class SyncController extends _$SyncController {
  @override
  Stream<SyncStatus> build() async* {
    while (true) {
      yield SyncStatus.syncing;
      await _pull();      // pull deltas from server
      await _push();      // push local changes
      yield SyncStatus.idle;
      await Future.delayed(const Duration(minutes: 5));
    }
  }
  // ...
}
```

Use `connectivity_plus` to skip sync when offline. Use a Riverpod `StreamProvider` to expose sync state to the UI.

### Step 4: features

For each domain object: feature folder per the [scaffold layout](../mobile/flutter-riverpod/PROMPT.md):

```
lib/features/work_orders/
├── data/work_orders_repository.dart       # reads from drift, writes to drift, queues sync
├── application/work_orders_controller.dart  # @riverpod
├── domain/work_order.dart                 # freezed (mirrors drift table)
└── presentation/
    ├── work_orders_list_screen.dart
    └── work_order_detail_screen.dart
```

### Step 5: media (photos, signatures)

Use `image_picker`, `signature` packages. Store the file locally (path in drift), upload in background. Show "uploading" badge in UI.

### Step 6: tests

`bloc_test`-equivalent for Riverpod (`riverpod_test`) for controllers. Widget tests for screens. One integration test for full sync flow against a mock API.

---

## Phase 3 — Web admin (1.5 days)

Per `examples/end-to-end-saas-app.md` Phase 2. Skip the mobile-responsive concerns — admin is desktop-only.

---

## Phase 4 — Shared deployment (1 day)

### Backend

Per [`deployment/per-framework/deploy-fastapi.md`](../deployment/per-framework/deploy-fastapi.md). Hosted on `api.fieldnote.example.com`.

### Web admin

Per [`deployment/per-framework/deploy-nextjs.md`](../deployment/per-framework/deploy-nextjs.md). Hosted on `admin.fieldnote.example.com` (same VPS, different nginx server block).

### Mobile

Outside the VPS. Use Firebase App Distribution (testers) → TestFlight + Play Console (production).

For Flutter: `flutter build apk --release` and `flutter build ipa --release`. Set up Codemagic / Bitrise / GitHub Actions Android+iOS workflows for automated builds.

---

## Phase 5 — Shared CI (1 day)

```
{{repo}}/
├── backend/             # FastAPI
├── web/                 # Next.js
├── mobile/              # Flutter
└── .github/workflows/
    ├── backend-ci.yml
    ├── backend-deploy.yml
    ├── web-ci.yml
    ├── web-deploy.yml
    ├── mobile-ci.yml
    └── mobile-build.yml   # builds APK + IPA, uploads to App Distribution
```

Per-app workflows trigger on path filters:

```yaml
on:
  pull_request:
    paths: ['backend/**']

jobs:
  test:
    runs-on: ubuntu-latest
    defaults: { run: { working-directory: backend } }
    # ...
```

So a mobile-only PR doesn't trigger backend CI. See [`cicd/github-actions-fastapi.md`](../cicd/github-actions-fastapi.md) for the backend pipeline; same shape for the others.

---

## Phase 6 — Observability + auth on three surfaces (half day)

Sentry: separate projects per surface.

```
/skill wire-sentry
target: backend → @sentry/python (FastAPI integration)
target: web → @sentry/nextjs
target: mobile → sentry_flutter
```

Per [`observability/03-sentry.md`](../observability/03-sentry.md). Each surface has its own DSN.

Auth coordination:
- Backend issues access + refresh
- Web stores access in memory, refresh in httpOnly cookie
- Mobile stores access in memory (Riverpod state), refresh in `flutter_secure_storage` (Keychain / Keystore)
- Refresh endpoint identical for both — backend doesn't care which client called

---

## Phase 7 — Security review (half day)

Per [`security/security-review-checklist.md`](../security/security-review-checklist.md). Add mobile-specific items:

- ✅ Tokens in secure storage (not shared_prefs)
- ✅ Certificate pinning if you decide it's worth the operational cost
- ✅ Deep link validation
- ✅ Code obfuscation for release builds (R8 / Hermes)
- ✅ Build/sign keys in CI secrets (not committed to repo)

---

## Time budget

| Phase | Duration |
|-------|----------|
| 0 — Decisions | 0.5 day |
| 1 — Backend | 1 day |
| 2 — Mobile (offline-first) | 3 days |
| 3 — Web admin | 1.5 days |
| 4 — Deployment | 1 day |
| 5 — CI/CD | 1 day |
| 6 — Observability + auth | 0.5 day |
| 7 — Security | 0.5 day |
| **Total** | **~9 days** |

Three surfaces in 9 days because the prompts handle the boilerplate. Without the prompts, expect 3-4 weeks.

---

## What this walkthrough emphasizes

- **API design that supports offline-first** — sync endpoints, idempotent uploads, conflict shape
- **One backend, multiple clients** — auth that works for web (cookie) + mobile (token in secure storage)
- **Per-app CI** with path filters
- **Per-surface observability** with separate Sentry projects
- **Mobile-specific security** beyond the base checklist

The prompts referenced are independent — you compose them per project's needs.
