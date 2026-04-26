# Flutter (Bloc) — Master Scaffold Prompt

> **Same architectural shape as `flutter-riverpod`, but using `flutter_bloc` for state management. Prefer Bloc when you want explicit event-driven state machines and the discipline that comes with them.**

---

## Context

You are scaffolding a new Flutter app using **flutter_bloc 8** with **freezed** events/states, **dio + retrofit**, **drift/isar** for local. Same feature-first folders + clean architecture as the Riverpod variant. Strict typing.

If something is ambiguous, **ask once, then proceed**.

## Project parameters

```
app_name:           {{app-name}}
package_id:         {{com.example.app}}
description:        {{one-line-description}}
flutter_version:    >=3.27.0
include_auth:       {{yes-or-no}}
include_local_db:   {{yes-or-no}}
api_base_url:       {{https://api.example.com}}
```

---

## Locked stack (differs from Riverpod where indicated)

| Concern | Pick |
|---------|------|
| State management | **flutter_bloc 8.x** + **bloc_concurrency** for transformer control |
| Models / events / states | **freezed** + **json_serializable** |
| HTTP | **dio** + **retrofit** |
| Local DB | **drift** or **isar** |
| Routing | **go_router** 14+ |
| Forms | **flutter_form_builder** + **form_builder_validators** |
| i18n | **intl** + **slang** |
| Logging | **bloc_logger** for transition logs + **logger** |
| Tests | `flutter_test` + `bloc_test` + `mocktail` |
| Lint | **very_good_analysis** + **bloc_lint_rules** |

Same rejected list as Riverpod variant.

---

## Directory layout

Same shape as Riverpod variant, but `application/` contains Blocs/Cubits instead of providers:

```
lib/features/auth/
├── data/
│   ├── auth_api.dart
│   └── auth_repository.dart
├── domain/
│   ├── auth_event.dart                  # freezed sealed events
│   ├── auth_state.dart                  # freezed sealed state
│   └── user.dart
├── application/
│   └── auth_bloc.dart
└── presentation/
    ├── login_screen.dart
    └── widgets/
```

## Layer rules

Same as Riverpod variant. Bloc replaces the controller/notifier role.

---

## Key files

### `pubspec.yaml` (deltas from Riverpod variant)

```yaml
dependencies:
  # ...
  flutter_bloc: ^8.1.6
  bloc_concurrency: ^0.3.0
  # NOT: flutter_riverpod, riverpod_annotation, hooks_riverpod, flutter_hooks

dev_dependencies:
  # ...
  bloc_test: ^9.1.7
  # NOT: riverpod_generator, riverpod_lint
```

### `lib/main.dart`

```dart
import 'package:flutter/material.dart';
import 'package:bloc/bloc.dart';
import 'package:{{app-name}}/app.dart';
import 'package:{{app-name}}/core/observers/app_bloc_observer.dart';

void main() {
  Bloc.observer = AppBlocObserver();          // log every transition in dev
  runApp(const MyApp());
}
```

### `lib/core/observers/app_bloc_observer.dart`

```dart
import 'package:bloc/bloc.dart';
import 'package:logger/logger.dart';

class AppBlocObserver extends BlocObserver {
  final _log = Logger();

  @override
  void onEvent(Bloc bloc, Object? event) {
    _log.d('${bloc.runtimeType} <- $event');
    super.onEvent(bloc, event);
  }

  @override
  void onTransition(Bloc bloc, Transition transition) {
    _log.d('${bloc.runtimeType}: ${transition.currentState.runtimeType} -> ${transition.nextState.runtimeType}');
    super.onTransition(bloc, transition);
  }

  @override
  void onError(BlocBase bloc, Object error, StackTrace stackTrace) {
    _log.e('${bloc.runtimeType} error', error: error, stackTrace: stackTrace);
    super.onError(bloc, error, stackTrace);
  }
}
```

### `lib/app.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:{{app-name}}/core/routing/app_router.dart';
import 'package:{{app-name}}/features/auth/application/auth_bloc.dart';
import 'package:{{app-name}}/features/auth/data/auth_repository.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // wire repositories at the top — depends on whether they hold state
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider(create: (_) => AuthRepository(/*...*/)),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(create: (ctx) => AuthBloc(authRepository: ctx.read())..add(const AuthEvent.appStarted())),
        ],
        child: MaterialApp.router(
          routerConfig: appRouter,
          // ...
        ),
      ),
    );
  }
}
```

### Feature: auth

```dart
// lib/features/auth/domain/user.dart  (same as Riverpod variant)
@freezed
class User with _$User {
  const factory User({
    required String id,
    required String email,
    required bool isActive,
  }) = _User;
  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);
}
```

```dart
// lib/features/auth/domain/auth_event.dart
import 'package:freezed_annotation/freezed_annotation.dart';
part 'auth_event.freezed.dart';

@freezed
class AuthEvent with _$AuthEvent {
  const factory AuthEvent.appStarted() = _AppStarted;
  const factory AuthEvent.loginRequested({required String email, required String password}) = _LoginRequested;
  const factory AuthEvent.logoutRequested() = _LogoutRequested;
}
```

```dart
// lib/features/auth/domain/auth_state.dart
import 'package:freezed_annotation/freezed_annotation.dart';
import 'user.dart';
part 'auth_state.freezed.dart';

@freezed
class AuthState with _$AuthState {
  const factory AuthState.initial() = _Initial;
  const factory AuthState.loading() = _Loading;
  const factory AuthState.authenticated(User user) = _Authenticated;
  const factory AuthState.unauthenticated() = _Unauthenticated;
  const factory AuthState.error(String message) = _Error;
}
```

```dart
// lib/features/auth/application/auth_bloc.dart
import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:{{app-name}}/features/auth/data/auth_repository.dart';
import 'package:{{app-name}}/features/auth/domain/auth_event.dart';
import 'package:{{app-name}}/features/auth/domain/auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc({required this.authRepository}) : super(const AuthState.initial()) {
    on<AuthEvent>(
      (event, emit) => event.map(
        appStarted: (e) => _onAppStarted(e, emit),
        loginRequested: (e) => _onLoginRequested(e, emit),
        logoutRequested: (e) => _onLogoutRequested(e, emit),
      ),
      transformer: sequential(),                        // serialize events
    );
  }

  final AuthRepository authRepository;

  Future<void> _onAppStarted(_AppStarted event, Emitter<AuthState> emit) async {
    final user = await authRepository.currentUser();
    emit(user == null ? const AuthState.unauthenticated() : AuthState.authenticated(user));
  }

  Future<void> _onLoginRequested(_LoginRequested event, Emitter<AuthState> emit) async {
    emit(const AuthState.loading());
    try {
      final user = await authRepository.login(event.email, event.password);
      emit(AuthState.authenticated(user));
    } catch (e) {
      emit(AuthState.error(e.toString()));
    }
  }

  Future<void> _onLogoutRequested(_LogoutRequested event, Emitter<AuthState> emit) async {
    await authRepository.logout();
    emit(const AuthState.unauthenticated());
  }
}
```

### `lib/features/auth/presentation/login_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:{{app-name}}/features/auth/application/auth_bloc.dart';
import 'package:{{app-name}}/features/auth/domain/auth_event.dart';
import 'package:{{app-name}}/features/auth/domain/auth_state.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailCtrl = TextEditingController();
  final passwordCtrl = TextEditingController();

  @override
  void dispose() {
    emailCtrl.dispose();
    passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: BlocConsumer<AuthBloc, AuthState>(
        listener: (ctx, state) {
          state.maybeMap(
            authenticated: (_) => ctx.go('/home'),
            error: (e) => ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(e.message))),
            orElse: () {},
          );
        },
        builder: (ctx, state) {
          final loading = state is _Loading;
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                TextField(controller: emailCtrl, decoration: const InputDecoration(labelText: 'Email')),
                const SizedBox(height: 16),
                TextField(controller: passwordCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: loading
                      ? null
                      : () => ctx.read<AuthBloc>().add(AuthEvent.loginRequested(
                            email: emailCtrl.text,
                            password: passwordCtrl.text,
                          )),
                  child: loading ? const CircularProgressIndicator() : const Text('Sign in'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
```

## Why Bloc

| Pro | Con |
|-----|-----|
| Explicit event → state transitions; auditable | More files per feature |
| Event transformers (sequential, droppable, restartable) | Verbose for simple state |
| `bloc_test` makes testing transitions clean | Codegen lighter than Riverpod |
| Easy to onboard developers familiar with redux/elm | Slight overhead for trivial UI state — use Cubit for those |

**Use Cubit (not Bloc) when** there are no events worth modeling — it's just `Cubit<State>` with `emit(...)` methods. The boilerplate goes way down.

## Cubit example (simpler than Bloc)

```dart
class CounterCubit extends Cubit<int> {
  CounterCubit() : super(0);
  void increment() => emit(state + 1);
  void reset() => emit(0);
}
```

For pure state mutation without an event audit trail, Cubit is enough.

## Testing with bloc_test

```dart
import 'package:bloc_test/bloc_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  late AuthRepository repo;
  setUp(() => repo = MockAuthRepository());

  blocTest<AuthBloc, AuthState>(
    'emits [loading, authenticated] on successful login',
    build: () => AuthBloc(authRepository: repo),
    setUp: () {
      when(() => repo.login(any(), any())).thenAnswer((_) async => const User(id: 'u1', email: 'a@a.com', isActive: true));
    },
    act: (bloc) => bloc.add(const AuthEvent.loginRequested(email: 'a@a.com', password: 'hunter22')),
    expect: () => [
      const AuthState.loading(),
      const AuthState.authenticated(User(id: 'u1', email: 'a@a.com', isActive: true)),
    ],
  );

  blocTest<AuthBloc, AuthState>(
    'emits [loading, error] on failed login',
    build: () => AuthBloc(authRepository: repo),
    setUp: () {
      when(() => repo.login(any(), any())).thenThrow(Exception('invalid credentials'));
    },
    act: (bloc) => bloc.add(const AuthEvent.loginRequested(email: 'a@a.com', password: 'wrong')),
    expect: () => [
      const AuthState.loading(),
      isA<_Error>(),
    ],
  );
}
```

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| `emit` after dispose | Check `if (!emit.isDone)` or use `try/catch` |
| Multiple events overlapping | Use `transformer: sequential()` to serialize, or `droppable()` to ignore in-flight |
| Bloc not provided in tree | `BlocProvider` must wrap the consumer — check tree |
| Mutation in state | freezed states are immutable — `copyWith` to update |
| Heavy work in event handler blocks UI | Offload to isolate or async — Bloc handlers should be quick |
| Bloc holds `BuildContext` | Never — context belongs to widgets |
| Repositories created in BlocProvider | They're recreated on rebuild — use `RepositoryProvider` higher up |
| Forgot `..add(StartEvent)` after creating bloc | Initial state never transitions — bootstrap with an event |

## See also

- The Riverpod variant in `../flutter-riverpod/` — same shape, different state lib
- React Native: `../react-native/`
