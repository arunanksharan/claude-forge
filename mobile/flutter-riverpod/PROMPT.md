# Flutter (Riverpod) — Master Scaffold Prompt

> **Copy this file into Claude Code. Replace `{{placeholders}}`. The model scaffolds a Flutter 3 project with Riverpod 2 state management, feature-first folders, and a clean architecture.**

---

## Context

You are scaffolding a new Flutter app using **Riverpod 2** (with code generation), **freezed** for models, **dio + retrofit** for HTTP, and **drift** (or isar) for local storage. Feature-first folder layout. Strict typing. No Provider.legacy package, no GetX, no Bloc.

If something is ambiguous, **ask once, then proceed**.

## Project parameters

```
app_name:           {{app-name}}                # snake_case for project, "Title Case" for display
package_id:         {{com.example.app}}
description:        {{one-line-description}}
flutter_channel:    stable
flutter_version:    >=3.27.0                    # current as of 2026
include_auth:       {{yes-or-no}}
include_local_db:   {{yes-or-no}}
api_base_url:       {{https://api.example.com}}
```

---

## Locked stack

| Concern | Pick | Why |
|---------|------|-----|
| Framework | **Flutter 3.27+** on Dart 3.6+ | |
| State management | **flutter_riverpod 2.x** + **riverpod_generator** | Type-safe, code-gen-driven, no widget rebuilds you don't ask for |
| Models | **freezed** + **json_serializable** | Immutable models, `copyWith`, sealed unions |
| HTTP | **dio** + **retrofit** | Retrofit gives you typed clients from interfaces |
| JSON | **json_serializable** (with freezed) | |
| Local DB | **drift** (relational) or **isar** (NoSQL) | Drift for relational; isar for embedded NoSQL with great query API |
| Routing | **go_router** 14+ | Declarative, deep links, type-safe routes |
| Forms | **flutter_form_builder** + **form_builder_validators** | Or hand-rolled — both work |
| Localization | **flutter_localizations** + **intl** + **slang** | Slang gives you type-safe i18n |
| Animation | Built-in `AnimatedX` widgets + **flutter_animate** for declarative chains | |
| Logging | **logger** | |
| Tests | `flutter_test` (unit) + `integration_test` + `mocktail` | |
| Lint | **very_good_analysis** | Strictest reasonable lint config |
| Build runner | `build_runner` for codegen | |

## Rejected

| Library | Why not |
|---------|---------|
| **Provider** (the old package) | Riverpod is the successor by the same author |
| **GetX** | Anti-pattern soup — combines routing, state, DI in one package; bypasses Flutter conventions |
| **MobX** | Less idiomatic in Flutter; Riverpod's reactivity is better integrated |
| **flutter_bloc** | Great but a different style — see `mobile/flutter-bloc/` if you want it |
| **shared_preferences** standalone | Use only for tiny scalars; for app data, use isar/drift |
| **http** package | Use dio — interceptors, retries, multipart all built in |
| **chopper** | Use retrofit (more popular ecosystem) |
| **moor** | Renamed to drift years ago |
| **redux** / **flutter_redux** | Reactivity in Flutter has better options |
| **flame** unless making games | |
| **GestureDetector** for everything | Use semantic widgets (InkWell, IconButton) for accessibility |

---

## Directory layout (feature-first)

```
{{app-name}}/
├── pubspec.yaml
├── analysis_options.yaml
├── build.yaml                          # build_runner config
├── README.md
├── android/, ios/, web/, etc.
└── lib/
    ├── main.dart
    ├── app.dart                        # MaterialApp.router root
    ├── core/
    │   ├── env/
    │   │   ├── env.dart                # Env class (compile-time config via --dart-define)
    │   │   └── flavors.dart
    │   ├── theme/
    │   │   ├── app_theme.dart
    │   │   ├── colors.dart
    │   │   └── typography.dart
    │   ├── network/
    │   │   ├── dio_client.dart         # Dio instance + interceptors
    │   │   ├── auth_interceptor.dart
    │   │   ├── error_interceptor.dart
    │   │   └── api_exception.dart
    │   ├── routing/
    │   │   ├── app_router.dart         # go_router config
    │   │   └── routes.dart
    │   ├── storage/
    │   │   ├── secure_storage.dart     # for tokens
    │   │   └── local_db.dart           # drift/isar setup
    │   └── extensions/
    │       └── context_extensions.dart
    ├── features/                       # ONE FOLDER PER FEATURE
    │   ├── auth/
    │   │   ├── data/
    │   │   │   ├── auth_api.dart       # @RestApi retrofit interface
    │   │   │   └── auth_repository.dart
    │   │   ├── domain/
    │   │   │   ├── auth_state.dart     # freezed sealed state
    │   │   │   └── user.dart           # freezed model
    │   │   ├── application/
    │   │   │   └── auth_controller.dart # @riverpod
    │   │   └── presentation/
    │   │       ├── login_screen.dart
    │   │       └── widgets/
    │   ├── feed/
    │   │   └── (same shape)
    │   └── profile/
    │       └── (same shape)
    └── shared/
        ├── widgets/                    # cross-feature widgets
        │   ├── primary_button.dart
        │   ├── empty_state.dart
        │   └── loading_indicator.dart
        └── utils/
test/
├── helpers/
│   └── pump_app.dart                   # test harness
├── unit/
│   └── features/auth/auth_controller_test.dart
└── widget/
    └── features/auth/login_screen_test.dart
integration_test/
└── auth_flow_test.dart
```

## Layer rules per feature

| Layer | Imports from | Cannot import |
|-------|------------|---------------|
| `presentation/` | `application/` (Riverpod providers), `shared/widgets/` | `data/` directly, `domain/` for non-display types |
| `application/` (controllers/notifiers) | `data/` (repositories), `domain/` | `presentation/` |
| `data/` (repositories, APIs) | `domain/` (models), `core/network/`, `core/storage/` | `application/`, `presentation/` |
| `domain/` (models, state) | nothing else | application, data, presentation |
| `core/` | utility-only deps | features |

Same shape as the backend guides. The discipline is what keeps the codebase navigable past 50 screens.

---

## Key files

### `pubspec.yaml`

```yaml
name: {{app-name}}
description: {{one-line-description}}
publish_to: 'none'
version: 0.1.0+1

environment:
  sdk: ^3.6.0
  flutter: ">=3.27.0"

dependencies:
  flutter:
    sdk: flutter
  flutter_localizations:
    sdk: flutter

  # state
  flutter_riverpod: ^2.6.0
  riverpod_annotation: ^2.6.0
  hooks_riverpod: ^2.6.0
  flutter_hooks: ^0.21.0

  # models
  freezed_annotation: ^2.4.4
  json_annotation: ^4.9.0

  # http
  dio: ^5.7.0
  retrofit: ^4.4.0
  pretty_dio_logger: ^1.4.0

  # routing
  go_router: ^14.6.0

  # storage
  flutter_secure_storage: ^9.2.0
  drift: ^2.21.0
  sqlite3_flutter_libs: ^0.5.24
  path_provider: ^2.1.4
  path: ^1.9.0

  # ui
  google_fonts: ^6.2.1
  flutter_animate: ^4.5.0
  cached_network_image: ^3.4.1
  flutter_form_builder: ^9.5.0
  form_builder_validators: ^11.0.0

  # i18n
  intl: ^0.19.0

  # logs
  logger: ^2.4.0

  cupertino_icons: ^1.0.8

dev_dependencies:
  flutter_test:
    sdk: flutter
  integration_test:
    sdk: flutter
  build_runner: ^2.4.13
  freezed: ^2.5.7
  json_serializable: ^6.8.0
  riverpod_generator: ^2.6.0
  retrofit_generator: ^9.1.0
  drift_dev: ^2.21.0
  custom_lint: ^0.7.0
  riverpod_lint: ^2.6.0
  very_good_analysis: ^6.0.0
  mocktail: ^1.0.4

flutter:
  uses-material-design: true
```

### `analysis_options.yaml`

```yaml
include: package:very_good_analysis/analysis_options.yaml

analyzer:
  language:
    strict-casts: true
    strict-inference: true
    strict-raw-types: true
  exclude:
    - "**/*.g.dart"
    - "**/*.freezed.dart"
    - "**/*.gen.dart"

linter:
  rules:
    avoid_print: true
    require_trailing_commas: true
    sort_constructors_first: true
    use_super_parameters: true
```

### `lib/main.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:{{app-name}}/app.dart';

void main() {
  // any pre-runApp init (Sentry, Firebase, etc.) goes here
  runApp(const ProviderScope(child: MyApp()));
}
```

### `lib/app.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:{{app-name}}/core/routing/app_router.dart';
import 'package:{{app-name}}/core/theme/app_theme.dart';

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: '{{app-name}}',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
```

### `lib/core/network/dio_client.dart`

```dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:{{app-name}}/core/env/env.dart';
import 'package:{{app-name}}/core/network/auth_interceptor.dart';
import 'package:{{app-name}}/core/network/error_interceptor.dart';

part 'dio_client.g.dart';

@riverpod
Dio dio(DioRef ref) {
  final dio = Dio(BaseOptions(
    baseUrl: Env.apiBaseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30),
    sendTimeout: const Duration(seconds: 30),
    headers: {'Accept': 'application/json'},
  ))
    ..interceptors.addAll([
      ref.watch(authInterceptorProvider),
      ErrorInterceptor(),
      if (Env.isDev) PrettyDioLogger(requestHeader: true, requestBody: true),
    ]);
  return dio;
}
```

### Feature: auth (riverpod-generated controller)

```dart
// lib/features/auth/domain/user.dart
import 'package:freezed_annotation/freezed_annotation.dart';
part 'user.freezed.dart';
part 'user.g.dart';

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
// lib/features/auth/data/auth_api.dart
import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';
import 'package:{{app-name}}/features/auth/domain/user.dart';
part 'auth_api.g.dart';

@RestApi()
abstract class AuthApi {
  factory AuthApi(Dio dio) = _AuthApi;

  @POST('/auth/login')
  Future<TokenResponse> login(@Body() LoginRequest body);

  @POST('/users')
  Future<User> register(@Body() RegisterRequest body);

  @GET('/users/me')
  Future<User> me();
}
```

```dart
// lib/features/auth/data/auth_repository.dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:{{app-name}}/features/auth/data/auth_api.dart';
import 'package:{{app-name}}/features/auth/domain/user.dart';
part 'auth_repository.g.dart';

@riverpod
AuthRepository authRepository(AuthRepositoryRef ref) {
  return AuthRepository(
    api: AuthApi(ref.watch(dioProvider)),
    storage: const FlutterSecureStorage(),
  );
}

class AuthRepository {
  AuthRepository({required this.api, required this.storage});
  final AuthApi api;
  final FlutterSecureStorage storage;

  Future<User> login(String email, String password) async {
    final tokens = await api.login(LoginRequest(email: email, password: password));
    await storage.write(key: 'access_token', value: tokens.accessToken);
    await storage.write(key: 'refresh_token', value: tokens.refreshToken);
    return api.me();
  }

  Future<void> logout() async {
    await storage.deleteAll();
  }

  Future<User?> currentUser() async {
    final token = await storage.read(key: 'access_token');
    if (token == null) return null;
    return api.me();
  }
}
```

```dart
// lib/features/auth/application/auth_controller.dart
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:{{app-name}}/features/auth/data/auth_repository.dart';
import 'package:{{app-name}}/features/auth/domain/auth_state.dart';
part 'auth_controller.g.dart';

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

  Future<void> logout() async {
    await ref.read(authRepositoryProvider).logout();
    state = const AsyncValue.data(AuthState.unauthenticated());
  }
}
```

```dart
// lib/features/auth/presentation/login_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:{{app-name}}/features/auth/application/auth_controller.dart';

class LoginScreen extends HookConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final emailCtrl = useTextEditingController();
    final passwordCtrl = useTextEditingController();
    final auth = ref.watch(authControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            TextField(controller: emailCtrl, decoration: const InputDecoration(labelText: 'Email')),
            const SizedBox(height: 16),
            TextField(controller: passwordCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: auth.isLoading
                  ? null
                  : () => ref.read(authControllerProvider.notifier).login(emailCtrl.text, passwordCtrl.text),
              child: auth.isLoading ? const CircularProgressIndicator() : const Text('Sign in'),
            ),
            if (auth.hasError) Text(auth.error.toString(), style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ),
      ),
    );
  }
}
```

---

## Generation steps

1. **Confirm parameters.**
2. **Run `flutter create --org {{com.example}} --project-name {{app-name}} {{app-name}}`.**
3. **Replace `pubspec.yaml`** with the locked stack.
4. **`flutter pub get`.**
5. **Add `analysis_options.yaml` and `build.yaml`.**
6. **Generate the directory tree** under `lib/`.
7. **Write `core/`** files: env, theme, network, routing, storage.
8. **Write one feature module (`auth/`)** end-to-end: model → repo → controller → screen.
9. **Run `dart run build_runner build --delete-conflicting-outputs`** — generates freezed/riverpod/retrofit code.
10. **Run `flutter analyze`** — should be clean.
11. **Write one widget test + one integration test.**
12. **Run `flutter test` and `flutter test integration_test`.**

---

## Companion deep-dives

- *Coming in future iterations* — for now this scaffold + the inline patterns are enough to ship a real app. Follow the layer rules.

## Why Riverpod over Bloc

| | **Riverpod** | **Bloc** |
|---|---|---|
| Boilerplate | Low (with codegen) | Medium-high (events + states + bloc) |
| Async ergonomics | `AsyncValue` is the model — explicit loading/data/error | Manual states for each |
| Testing | Override providers in test | Mock dependencies |
| Mental model | "Reactive providers" | "Event-driven state machine" |
| Flutter integration | Native widget refresh via `ref.watch` | StreamBuilder / BlocBuilder |
| Curve | Gentler | Steeper but explicit |

For greenfield + small team: **Riverpod**. For larger teams that want explicit event flows: **Bloc** (see `mobile/flutter-bloc/`).
