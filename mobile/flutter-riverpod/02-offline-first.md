# Flutter Riverpod — Offline-First Architecture

> Local-first data with drift, optimistic UI updates, sync-on-network. The pattern for apps used in low-connectivity scenarios (field service, transit, mobile workers).

## The principle

**Local DB is the source of truth for the UI. Remote API is the source of truth for the data.** They eventually agree via sync.

This makes:
- UI instant (reads from local)
- Writes feel instant (write local first, sync in background)
- App usable offline (degraded but functional)
- Conflicts manageable (server reconciliation)

## Stack

| Concern | Pick |
|---------|------|
| **Local DB (relational)** | **drift** (SQLite, sound type-safe codegen) |
| **Local DB (NoSQL/embedded)** | **isar** (very fast, document-style) |
| **Connectivity detection** | `connectivity_plus` |
| **Background sync** | `workmanager` (true background) or simple periodic timer (foreground) |
| **State** | Riverpod (controllers expose local data + sync status) |
| **HTTP** | dio + retrofit |

## Drift schema

```dart
import 'package:drift/drift.dart';

class WorkOrders extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  TextColumn get title => text()();
  IntColumn get status => intEnum<WorkOrderStatus>()();
  DateTimeColumn get updatedAt => dateTime()();

  // sync metadata
  IntColumn get syncStatus => intEnum<SyncStatus>().withDefault(const Constant(0))();
  DateTimeColumn get lastSyncAttempt => dateTime().nullable()();
  TextColumn get serverVersion => text().nullable()();        // server-assigned ETag/version

  @override Set<Column> get primaryKey => {id};
}

enum SyncStatus { synced, dirty, conflicted }
enum WorkOrderStatus { pending, inProgress, completed, cancelled }

@DriftDatabase(tables: [WorkOrders, Photos, Signatures, SyncMeta])
class AppDb extends _$AppDb {
  AppDb() : super(_open());
  @override int get schemaVersion => 1;
}

LazyDatabase _open() => LazyDatabase(() async {
  final dir = await getApplicationDocumentsDirectory();
  return NativeDatabase.createInBackground(File(p.join(dir.path, 'app.db')));
});
```

## Repository — local-first

```dart
@riverpod
WorkOrderRepository workOrderRepository(WorkOrderRepositoryRef ref) {
  return WorkOrderRepository(
    db: ref.watch(appDbProvider),
    api: ref.watch(workOrderApiProvider),
  );
}

class WorkOrderRepository {
  WorkOrderRepository({required this.db, required this.api});
  final AppDb db;
  final WorkOrderApi api;

  // READ — always from local
  Stream<List<WorkOrder>> watchAll(String tenantId) {
    return (db.select(db.workOrders)
      ..where((t) => t.tenantId.equals(tenantId))
      ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
    ).watch().map((rows) => rows.map(_toEntity).toList());
  }

  // WRITE — local first, mark dirty, queue for sync
  Future<WorkOrder> updateStatus(String id, WorkOrderStatus status) async {
    await (db.update(db.workOrders)
      ..where((t) => t.id.equals(id))
    ).write(WorkOrdersCompanion(
      status: Value(status),
      updatedAt: Value(DateTime.now()),
      syncStatus: const Value(SyncStatus.dirty),
    ));

    // fire-and-forget sync
    unawaited(_syncOne(id));

    return await getById(id);
  }

  Future<void> _syncOne(String id) async {
    try {
      final local = await getById(id);
      final remote = await api.updateWorkOrder(id, local.toUpdateRequest());
      // server returned the canonical version — store it
      await (db.update(db.workOrders)..where((t) => t.id.equals(id)))
        .write(WorkOrdersCompanion(
          syncStatus: const Value(SyncStatus.synced),
          serverVersion: Value(remote.version),
        ));
    } catch (e) {
      // remain dirty; periodic sync will retry
      log.warning('sync failed for $id: $e');
    }
  }
}
```

## Sync controller (Riverpod)

```dart
@riverpod
class SyncController extends _$SyncController {
  Timer? _timer;

  @override
  Stream<SyncStatus> build() async* {
    // start periodic sync
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 5), (_) => unawaited(_syncAll()));
    ref.onDispose(() => _timer?.cancel());

    yield SyncStatus.idle;
  }

  Future<void> _syncAll() async {
    final connectivity = ref.read(connectivityProvider).valueOrNull;
    if (connectivity == ConnectivityResult.none) {
      log.info('skip sync — offline');
      return;
    }

    state = const AsyncData(SyncStatus.syncing);
    final repo = ref.read(workOrderRepositoryProvider);

    // 1. push local dirty changes
    final dirty = await repo.findDirty();
    for (final wo in dirty) {
      await repo._syncOne(wo.id);
    }

    // 2. pull remote changes since last sync
    final lastSync = await ref.read(syncMetaRepositoryProvider).lastSyncAt();
    final remote = await ref.read(workOrderApiProvider).sync(since: lastSync);
    await repo.applyServerChanges(remote);
    await ref.read(syncMetaRepositoryProvider).setLastSyncAt(DateTime.now());

    state = const AsyncData(SyncStatus.idle);
  }

  Future<void> syncNow() => _syncAll();
}
```

UI subscribes to `syncControllerProvider` to show "Syncing..." badges.

## API design — sync-friendly

The API needs to support delta sync:

```
POST /api/v1/sync
{
  "since": "2026-04-26T00:00:00Z",
  "client_changes": [
    {"id": "wo_123", "client_version": 5, "fields": {...}}
  ]
}

→ 200 OK
{
  "server_changes": [
    {"id": "wo_456", "version": "v3", "fields": {...}, "updated_at": "..."}
  ],
  "accepted": ["wo_123"],
  "conflicts": [
    {"id": "wo_789", "server_version": "v2", "client_version": "v1", "server_fields": {...}}
  ],
  "server_now": "2026-04-26T12:34:56Z"
}
```

Conflict resolution patterns:
- **Last-write-wins** (server timestamp): simple, sometimes loses work
- **Field-level merge**: server merges per-field; client retries
- **Surface to user**: server returns conflict; UI asks user to resolve

For most apps: last-write-wins per field, with audit log on the server. For high-stakes data (signed forms, payments): explicit conflict surfaces.

## Optimistic UI

```dart
@riverpod
class WorkOrderActions extends _$WorkOrderActions {
  @override
  void build() {}

  Future<void> markComplete(String id) async {
    final repo = ref.read(workOrderRepositoryProvider);

    // 1. instant local update — UI already reflects via stream
    await repo.updateStatus(id, WorkOrderStatus.completed);

    // (sync happens in repo's background task)

    // 2. optionally show success snackbar
    // ...
  }
}
```

Because the read-side is a `Stream` from drift, the UI re-renders instantly when the local DB changes. No "loading" state for the user.

## Connectivity provider

```dart
@riverpod
Stream<ConnectivityResult> connectivity(ConnectivityRef ref) {
  return Connectivity().onConnectivityChanged.map((results) => results.first);
}
```

Trigger immediate sync on connectivity restore:

```dart
class _MyAppState extends ConsumerState<MyApp> {
  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<ConnectivityResult>>(
      connectivityProvider,
      (prev, next) {
        if (prev?.value == ConnectivityResult.none && next.value != ConnectivityResult.none) {
          ref.read(syncControllerProvider.notifier).syncNow();
        }
      },
    );
    return ...;
  }
}
```

## Background sync (true background — workmanager)

```dart
import 'package:workmanager/workmanager.dart';

void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    // run sync from a separate isolate
    // requires re-initializing your dependency graph
    final container = ProviderContainer();
    await container.read(syncControllerProvider.notifier).syncNow();
    container.dispose();
    return true;
  });
}

// in main()
await Workmanager().initialize(callbackDispatcher);
await Workmanager().registerPeriodicTask(
  "sync-task",
  "sync",
  frequency: const Duration(minutes: 15),
  constraints: Constraints(networkType: NetworkType.connected),
);
```

iOS background execution is restrictive — relies on system scheduler. Don't promise users "syncs every X minutes."

## Photo / file uploads (large attachments)

Don't try to sync large files in the same flow as small data:

```dart
// Photo table
class Photos extends Table {
  TextColumn get id => text()();
  TextColumn get workOrderId => text()();
  TextColumn get localPath => text()();          // file path on device
  TextColumn get remoteUrl => text().nullable()(); // S3 URL after upload
  IntColumn get uploadStatus => intEnum<UploadStatus>()();
  IntColumn get bytesUploaded => integer().withDefault(const Constant(0))();
}

enum UploadStatus { pending, uploading, uploaded, failed }
```

Separate uploader queue. Multipart uploads with resume. Show per-photo progress in UI.

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| Sync runs while user is editing — overwrites local | Lock fields during edit; merge on save |
| Conflict resolution surfaces too often | Field-level merge; only surface user-facing conflicts |
| App slow on first launch (cold cache) | Pre-fetch + cache strategy; show shimmer / skeleton |
| Sync hammers API on connectivity restore | Backoff + jitter |
| Server clock skew breaks "since" queries | Use server-returned `server_now` for next sync's `since` |
| Local DB grows unbounded | TTL on synced data; archive completed work orders |
| Large list rebuilds on every drift change | Use `selectOnly` + key projections; or paginate |
| WorkManager constraint not honored | iOS limitations; design around them |
| Battery drain | Sync every 15min minimum; shorter only on user activity |
| Photo sync blocks important data sync | Separate queues with priority |
| Schema migration breaks existing user data | Drift migrations are linear; test on real data before release |
