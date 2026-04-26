# Flutter Riverpod — Providers & Architecture Deep Dive

> Provider types, code generation, dependency injection, and the layer rules. The patterns that make a Riverpod app stay maintainable.

## Provider types — when to use which

Riverpod 2 with code generation gives you these via `@riverpod`:

| Provider | Use case | Example |
|----------|----------|---------|
| **Provider** (function) | Pure values, computed from other providers | `theme`, `apiClient` |
| **FutureProvider** (async function) | One-shot async fetch | `currentUser`, `appConfig` |
| **StreamProvider** (stream function) | Continuous async stream | `connectivityStream`, `firestoreSnapshots` |
| **Notifier class** | Mutable state with methods | `cartController`, `authController` |
| **AsyncNotifier class** | Mutable state with async init/methods | `userListController` |

```dart
// Provider — sync, computed
@riverpod
Dio dio(DioRef ref) => Dio(BaseOptions(baseUrl: Env.apiBaseUrl))..interceptors.addAll([...]);

// FutureProvider — one-shot
@riverpod
Future<User?> currentUser(CurrentUserRef ref) async {
  final repo = ref.watch(authRepositoryProvider);
  return repo.currentUser();
}

// StreamProvider — continuous
@riverpod
Stream<ConnectivityResult> connectivity(ConnectivityRef ref) =>
    Connectivity().onConnectivityChanged;

// Notifier — mutable sync
@riverpod
class Counter extends _$Counter {
  @override int build() => 0;
  void increment() => state++;
  void reset() => state = 0;
}

// AsyncNotifier — mutable async
@riverpod
class AuthController extends _$AuthController {
  @override
  Future<AuthState> build() async {
    final user = await ref.read(authRepositoryProvider).currentUser();
    return user == null ? const AuthState.unauthenticated() : AuthState.authenticated(user);
  }

  Future<void> login(String email, String password) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final user = await ref.read(authRepositoryProvider).login(email, password);
      return AuthState.authenticated(user);
    });
  }
}
```

## Code generation (mandatory for new projects)

```bash
dart pub add riverpod_annotation flutter_riverpod
dart pub add --dev build_runner riverpod_generator riverpod_lint custom_lint

# regenerate after editing
dart run build_runner watch --delete-conflicting-outputs
```

Why codegen:
- Compile-time check that you read the right type
- Auto-generates Ref, dispose handling
- Linter (`riverpod_lint`) catches misuse

Without codegen, Riverpod becomes type-error-prone — use `@riverpod` always.

## Reading providers — `watch` vs `read` vs `listen`

```dart
class MyWidget extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);    // re-runs widget on changes
    final repo = ref.read(userRepositoryProvider);  // one-shot, doesn't subscribe

    ref.listen<AsyncValue<AuthState>>(
      authControllerProvider,
      (prev, next) {
        next.whenOrNull(
          data: (state) => state.maybeMap(
            authenticated: (_) => context.go('/home'),
            error: (e) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message))),
            orElse: () {},
          ),
        );
      },
    );

    return ...;
  }
}
```

| Method | Subscribes? | When |
|--------|-------------|------|
| `ref.watch(p)` | Yes — re-runs build on change | In build methods, render-affecting |
| `ref.read(p)` | No — single read | In callbacks, where you don't want to react |
| `ref.listen(p, callback)` | Yes — runs callback, doesn't rebuild | Side effects (navigation, snackbar) on changes |

**Use `watch` in `build`. Use `read` in callbacks. Use `listen` for side effects.**

## Family providers (parameterized)

```dart
@riverpod
Future<User?> userById(UserByIdRef ref, String id) async {
  final repo = ref.watch(userRepositoryProvider);
  return repo.findById(id);
}

// usage
final user = ref.watch(userByIdProvider('u1'));
```

Each unique parameter gets its own cached state. Auto-disposed when no longer watched.

## Auto-dispose vs keep-alive

By default, providers auto-dispose when no widget watches them:

```dart
@riverpod
Future<User?> currentUser(CurrentUserRef ref) async {
  // disposed when no widget reads
}

// keep alive forever
@Riverpod(keepAlive: true)
Future<User?> currentUserKeptAlive(CurrentUserKeptAliveRef ref) async { ... }

// dynamic keep-alive (e.g., during a critical operation)
@riverpod
Future<User?> currentUser(CurrentUserRef ref) async {
  final link = ref.keepAlive();
  // ... later: link.close() to release
}
```

For most state: auto-dispose is right. For session-wide state (current user, app config): `keepAlive: true`.

## Layer rules per feature

(Reinforced from PROMPT.md)

```
features/{feature}/
  data/                    -- repositories + APIs
  domain/                  -- freezed models, sealed states
  application/             -- @riverpod controllers (notifiers)
  presentation/            -- widgets / screens
```

| Layer | Imports from | Forbidden |
|-------|------------|-----------|
| `presentation/` | `application/` (controllers), shared widgets | `data/` directly, internal types |
| `application/` | `data/` (repos), `domain/` | `presentation/` |
| `data/` | `domain/`, `core/network`, `core/storage` | `application/`, `presentation/` |
| `domain/` | nothing else | everything |

This separation is what makes Riverpod scalable past 50+ screens. Without it, providers tangle.

## Cross-feature dependencies

When feature B needs feature A's data:

```dart
// in feature B's controller
@riverpod
class BController extends _$BController {
  @override
  Future<BState> build() async {
    final user = await ref.watch(currentUserProvider.future);   // depend on A
    if (user == null) throw Unauthenticated();
    final data = await ref.watch(aServiceProvider).getDataFor(user.id);
    return BState(data: data);
  }
}
```

`ref.watch` on another provider creates a reactive dependency — when `currentUser` changes, `BController` rebuilds.

For one-time reads that don't react: `ref.read(currentUserProvider)`.

## Testing providers

Override providers in `ProviderContainer` for tests:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthRepo extends Mock implements AuthRepository {}

void main() {
  test('AuthController.login emits authenticated on success', () async {
    final repo = MockAuthRepo();
    when(() => repo.currentUser()).thenAnswer((_) async => null);
    when(() => repo.login(any(), any())).thenAnswer(
      (_) async => const User(id: 'u1', email: 'a@a.com', isActive: true),
    );

    final container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);

    final notifier = container.read(authControllerProvider.notifier);
    await notifier.login('a@a.com', 'hunter22');

    final state = container.read(authControllerProvider);
    expect(state.value, isA<_Authenticated>());
  });
}
```

## Common patterns

### Loading-aware UI

```dart
final auth = ref.watch(authControllerProvider);

return auth.when(
  data: (state) => state.map(
    initial: (_) => const SizedBox(),
    loading: (_) => const CircularProgressIndicator(),
    authenticated: (s) => HomeScreen(user: s.user),
    unauthenticated: (_) => const LoginScreen(),
    error: (e) => ErrorScreen(message: e.message),
  ),
  loading: () => const CircularProgressIndicator(),
  error: (err, _) => ErrorScreen(message: err.toString()),
);
```

`AsyncValue<T>` makes loading/error states explicit — never forget to handle them.

### Form state (with hooks)

```dart
class LoginScreen extends HookConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final emailCtrl = useTextEditingController();
    final passwordCtrl = useTextEditingController();
    final auth = ref.watch(authControllerProvider);

    return Scaffold(
      body: Column(children: [
        TextField(controller: emailCtrl, ...),
        TextField(controller: passwordCtrl, ...),
        FilledButton(
          onPressed: auth.isLoading
              ? null
              : () => ref.read(authControllerProvider.notifier).login(emailCtrl.text, passwordCtrl.text),
          child: auth.isLoading ? const CircularProgressIndicator() : const Text('Sign in'),
        ),
      ]),
    );
  }
}
```

`flutter_hooks` + `HookConsumerWidget` gives you `useTextEditingController`, `useState`, `useEffect` — clean local state without StatefulWidget.

## Anti-patterns

| Pattern | Why bad |
|---------|---------|
| `ref.watch` in callbacks | Doesn't reactively rebuild outside `build` |
| `ref.read` in `build` | Misses updates |
| Storing widgets in providers | Providers are state, not UI |
| Long methods inside `Notifier.build` | Side effect during init — extract |
| Mutating `state` directly without assignment | Riverpod uses `==` to detect changes; mutation in place doesn't trigger update |
| Provider dependencies forming cycles | Re-architect; usually means a missing layer |
| Heavy computation inside providers without memoization | Use `select` to narrow what's watched |
| Writing tests against `ConsumerWidget` directly | Test the provider in isolation; widget test covers UI separately |

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| `Bad state: Cannot use ref.watch outside of build` | Don't call inside callbacks; use `ref.read` instead |
| Provider rebuilds too often | Use `select`: `ref.watch(authProvider.select((s) => s.user.id))` |
| Codegen errors after schema change | `dart run build_runner build --delete-conflicting-outputs` |
| `ProviderContainer` not disposed in test | Always `addTearDown(container.dispose)` |
| Auto-dispose drops state too eagerly | `keepAlive: true` or `ref.keepAlive()` link |
| Cross-isolate providers | Riverpod is single-isolate; for compute use `compute()` directly |
| Stream provider doesn't emit | Verify the underlying stream is hot; not a Future |
| `family` provider not unique per param | Verify the param has proper `==` (use freezed for complex params) |
