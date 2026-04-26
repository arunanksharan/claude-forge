# Flutter Bloc — bloc_test Patterns

> Test Blocs and Cubits with bloc_test. Event → state assertions, transformer testing, mocking dependencies.

## Setup

```bash
flutter pub add --dev bloc_test mocktail
```

## Basic Bloc test

```dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  late MockAuthRepository repo;

  setUp(() {
    repo = MockAuthRepository();
  });

  blocTest<AuthBloc, AuthState>(
    'emits [loading, authenticated] on successful login',
    build: () => AuthBloc(authRepository: repo),
    setUp: () {
      when(() => repo.login('alice@example.com', 'hunter22a')).thenAnswer(
        (_) async => const User(id: 'u1', email: 'alice@example.com', isActive: true),
      );
    },
    act: (bloc) => bloc.add(
      const AuthEvent.loginRequested(email: 'alice@example.com', password: 'hunter22a'),
    ),
    expect: () => [
      const AuthState.loading(),
      const AuthState.authenticated(User(id: 'u1', email: 'alice@example.com', isActive: true)),
    ],
    verify: (_) {
      verify(() => repo.login('alice@example.com', 'hunter22a')).called(1);
    },
  );
}
```

`blocTest` orchestrates: build the bloc → run setup → fire events via `act` → wait → assert states.

## Failure path

```dart
blocTest<AuthBloc, AuthState>(
  'emits [loading, error] on failed login',
  build: () => AuthBloc(authRepository: repo),
  setUp: () {
    when(() => repo.login(any(), any())).thenThrow(InvalidCredentials());
  },
  act: (bloc) => bloc.add(
    const AuthEvent.loginRequested(email: 'a@a.com', password: 'wrong'),
  ),
  expect: () => [
    const AuthState.loading(),
    isA<_Error>(),
  ],
);
```

Use `isA<>()` for state types you don't want to deeply assert. For more precise: pattern-match in `expect`.

## Initial state

```dart
blocTest<AuthBloc, AuthState>(
  'starts in initial state',
  build: () => AuthBloc(authRepository: repo),
  // no act — just check the initial state
  verify: (bloc) {
    expect(bloc.state, const AuthState.initial());
  },
);
```

## seed — start in a specific state

```dart
blocTest<AuthBloc, AuthState>(
  'logout transitions authenticated → unauthenticated',
  build: () => AuthBloc(authRepository: repo),
  seed: () => const AuthState.authenticated(User(id: 'u1', email: 'a@a.com', isActive: true)),
  setUp: () {
    when(() => repo.logout()).thenAnswer((_) async {});
  },
  act: (bloc) => bloc.add(const AuthEvent.logoutRequested()),
  expect: () => [const AuthState.unauthenticated()],
);
```

## skip — drop initial state(s) from assertion

```dart
blocTest<CounterBloc, int>(
  'increment after 3 emits 4',
  build: () => CounterBloc(),
  act: (bloc) {
    bloc.add(Increment());
    bloc.add(Increment());
    bloc.add(Increment());
    bloc.add(Increment());
  },
  skip: 3,                          // skip first 3 emissions
  expect: () => [4],
);
```

## Async setup

```dart
blocTest<UsersBloc, UsersState>(
  'loads users on init',
  setUp: () async {
    when(() => repo.list()).thenAnswer((_) async => [
      const User(id: 'u1', email: 'a@a.com'),
      const User(id: 'u2', email: 'b@b.com'),
    ]);
  },
  build: () => UsersBloc(usersRepository: repo)..add(const UsersEvent.loadRequested()),
  expect: () => [
    const UsersState.loading(),
    const UsersState.loaded([
      User(id: 'u1', email: 'a@a.com'),
      User(id: 'u2', email: 'b@b.com'),
    ]),
  ],
);
```

`.add(...)` after `..` constructor — fire an event right after creating the bloc.

## Cubit (simpler than Bloc)

```dart
class CounterCubit extends Cubit<int> {
  CounterCubit() : super(0);
  void increment() => emit(state + 1);
  void reset() => emit(0);
}

void main() {
  blocTest<CounterCubit, int>(
    'increment increments',
    build: () => CounterCubit(),
    act: (cubit) => cubit.increment(),
    expect: () => [1],
  );

  blocTest<CounterCubit, int>(
    'reset goes back to 0',
    build: () => CounterCubit(),
    seed: () => 5,
    act: (cubit) => cubit.reset(),
    expect: () => [0],
  );
}
```

Cubits use `emit` directly — no events. Use Cubit for trivial state, Bloc for event-driven.

## Testing event transformers

```dart
class SearchBloc extends Bloc<SearchEvent, SearchState> {
  SearchBloc({required this.repo}) : super(const SearchState.initial()) {
    on<_QueryChanged>(
      _onQueryChanged,
      transformer: (events, mapper) => events
        .debounceTime(const Duration(milliseconds: 300))
        .switchMap(mapper),
    );
  }
  // ...
}

blocTest<SearchBloc, SearchState>(
  'debounces queries — only last fires after delay',
  build: () => SearchBloc(repo: repo),
  setUp: () {
    when(() => repo.search('foo bar baz')).thenAnswer((_) async => [Result(...)]);
  },
  act: (bloc) async {
    bloc.add(const SearchEvent.queryChanged('foo'));
    bloc.add(const SearchEvent.queryChanged('foo bar'));
    bloc.add(const SearchEvent.queryChanged('foo bar baz'));
    await Future.delayed(const Duration(milliseconds: 400));
  },
  wait: const Duration(milliseconds: 500),
  expect: () => [
    const SearchState.loading(),
    SearchState.loaded([Result(...)]),
  ],
  verify: (_) {
    verify(() => repo.search('foo bar baz')).called(1);
    verifyNever(() => repo.search('foo'));
    verifyNever(() => repo.search('foo bar'));
  },
);
```

`wait:` lets you simulate time passing — needed for debounce / throttle testing.

## bloc_concurrency transformers

| Transformer | Behavior |
|-------------|----------|
| `sequential()` | Process events one at a time, in order |
| `concurrent()` (default) | Process all events in parallel |
| `droppable()` | Drop events while one is in progress |
| `restartable()` | Cancel in-progress and start new (good for search) |

```dart
import 'package:bloc_concurrency/bloc_concurrency.dart';

on<AuthEvent>(
  _onAuthEvent,
  transformer: sequential(),
);
```

Test by ensuring expected serialization:

```dart
blocTest<AuthBloc, AuthState>(
  'login then logout serializes correctly',
  build: () => AuthBloc(authRepository: repo),
  setUp: () {
    when(() => repo.login(any(), any())).thenAnswer((_) async {
      await Future.delayed(const Duration(milliseconds: 100));
      return User(id: 'u1', email: 'a@a.com', isActive: true);
    });
    when(() => repo.logout()).thenAnswer((_) async {});
  },
  act: (bloc) {
    bloc.add(const AuthEvent.loginRequested(email: 'a@a.com', password: 'p'));
    bloc.add(const AuthEvent.logoutRequested());
  },
  expect: () => [
    const AuthState.loading(),
    isA<_Authenticated>(),
    const AuthState.unauthenticated(),
  ],
);
```

## BlocObserver — global event/state logging

```dart
class TestBlocObserver extends BlocObserver {
  final events = <Object?>[];
  final transitions = <Transition>[];

  @override
  void onEvent(Bloc bloc, Object? event) {
    events.add(event);
    super.onEvent(bloc, event);
  }

  @override
  void onTransition(Bloc bloc, Transition transition) {
    transitions.add(transition);
    super.onTransition(bloc, transition);
  }
}

void main() {
  late TestBlocObserver observer;
  setUp(() {
    observer = TestBlocObserver();
    Bloc.observer = observer;
  });
  tearDown(() {
    Bloc.observer = const BlocObserver();
  });

  // tests can inspect observer.events and observer.transitions
}
```

## Widget testing with Bloc

For widget tests, mock the bloc via `BlocProvider.value`:

```dart
testWidgets('shows loading indicator when bloc is loading', (tester) async {
  final mockBloc = MockAuthBloc();
  when(() => mockBloc.state).thenReturn(const AuthState.loading());
  whenListen(mockBloc, Stream.fromIterable([const AuthState.loading()]));

  await tester.pumpWidget(
    MaterialApp(
      home: BlocProvider.value(
        value: mockBloc,
        child: const LoginScreen(),
      ),
    ),
  );

  expect(find.byType(CircularProgressIndicator), findsOneWidget);
});
```

`whenListen` from `bloc_test` mocks the stream-of-states.

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| Test runs synchronously, async work doesn't complete | Use `wait:` parameter or `tester.pumpAndSettle()` |
| Mock not registered for `any()` matchers | `registerFallbackValue<T>(...)` for custom types |
| Multiple events firing in wrong order | Use `transformer: sequential()` if order matters |
| State equality fails despite same values | Use freezed for value equality |
| `bloc_test` expecting more / fewer states | Verify: are intermediate states emitted? Use `skip` to drop initials |
| Bloc not disposed in test | `bloc_test` auto-closes; manual: `await bloc.close()` |
| `emit was called after the event handler completed` | Async work outside handler — make sure work is awaited within the handler |
| Transformer test depends on real time | Use fake_async or trigger events manually |
| Verifying mock interactions | `verify(() => mock.method())` — must be in `verify:` block, not `expect:` |
| Tests slow due to bcrypt/heavy logic in repo | Mock the repo entirely; don't run real crypto |
