# Angular Signals + State Management

> Signals (built-in), NgRx Signal Store (shared state), RxJS (async streams). When to use which, with patterns.

## The decision matrix

| State kind | Tool |
|-----------|------|
| Component-local | `signal()` |
| Cross-component (small app) | Service exposing `signal()` |
| Cross-component (medium app) | NgRx Signal Store |
| Cross-component (large app, event-sourced) | NgRx classic Store + Effects |
| HTTP responses, WebSocket, time-based | RxJS Observable |
| Forms | Reactive Forms (typed) |

**Default to signals.** Use RxJS only where it shines (HTTP, WebSocket, time, debounce).

## Signals — the basics

```typescript
import { Component, signal, computed, effect } from '@angular/core';

@Component({...})
export class CounterComponent {
  readonly count = signal(0);                          // writable signal
  readonly doubled = computed(() => this.count() * 2); // derived

  constructor() {
    // effect — runs when dependencies change
    effect(() => {
      console.log(`count is ${this.count()}, doubled is ${this.doubled()}`);
    });
  }

  increment() {
    this.count.update((c) => c + 1);   // or this.count.set(this.count() + 1)
  }
}
```

In templates:

```html
<p>Count: {{ count() }}</p>
<p>Doubled: {{ doubled() }}</p>
<button (click)="increment()">+</button>
```

Note the `()` — signals are functions when read.

## Signal updates — patterns

```typescript
// SET — replace value
state.set({ name: "alice", count: 1 });

// UPDATE — derive new from old
state.update((s) => ({ ...s, count: s.count + 1 }));

// MUTATE — DEPRECATED in newer Angular versions
// don't use; signals are designed for immutable updates

// ARRAYS
todos.update((arr) => [...arr, newTodo]);
todos.update((arr) => arr.filter((t) => t.id !== id));
```

**Always immutable.** Signals trigger re-renders by reference equality. Mutating an object in place won't trigger updates.

## Computed — derived state

```typescript
readonly total = computed(() => this.items().reduce((sum, item) => sum + item.price, 0));
readonly hasItems = computed(() => this.items().length > 0);

// computed depends on the signals it reads — automatic
```

Computed values are lazy + cached. Recomputed only when dependencies change.

## Effects — side effects

```typescript
constructor() {
  effect(() => {
    const id = this.userId();
    if (id) {
      this.loadProfile(id);     // side effect: fetch
    }
  });

  // cleanup on dependency change
  effect((onCleanup) => {
    const id = this.userId();
    const subscription = interval(1000).subscribe(() => console.log(id));
    onCleanup(() => subscription.unsubscribe());
  });
}
```

Effects run **after** the change detection cycle. For DOM-related side effects (focus, scroll), they're synchronous with the render.

**Don't use effects for state derivation** — use `computed` instead. Effects are for IO, not for "compute X from Y."

## Service-based shared state (signals)

```typescript
@Injectable({ providedIn: 'root' })
export class CartService {
  // private writable, public readonly
  private readonly _items = signal<CartItem[]>([]);
  readonly items = this._items.asReadonly();

  readonly total = computed(() => this._items().reduce((s, i) => s + i.priceCents * i.qty, 0));
  readonly count = computed(() => this._items().length);

  add(item: CartItem) {
    this._items.update((current) => [...current, item]);
  }

  remove(id: string) {
    this._items.update((current) => current.filter((i) => i.id !== id));
  }

  clear() {
    this._items.set([]);
  }
}
```

Components inject `CartService` and read `service.items()`. Templates auto-update.

## NgRx Signal Store

For larger apps where service-based state becomes unwieldy:

```bash
pnpm add @ngrx/signals
```

```typescript
import { signalStore, withState, withMethods, withComputed, patchState } from '@ngrx/signals';
import { computed, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';

interface UsersState {
  users: User[];
  loading: boolean;
  filter: string;
}

const initialState: UsersState = { users: [], loading: false, filter: '' };

export const UsersStore = signalStore(
  { providedIn: 'root' },
  withState(initialState),
  withComputed((store) => ({
    filteredUsers: computed(() =>
      store.users().filter((u) =>
        u.email.toLowerCase().includes(store.filter().toLowerCase())
      )
    ),
    count: computed(() => store.users().length),
  })),
  withMethods((store, http = inject(HttpClient)) => ({
    async load() {
      patchState(store, { loading: true });
      try {
        const users = await firstValueFrom(http.get<User[]>('/api/v1/users'));
        patchState(store, { users, loading: false });
      } catch {
        patchState(store, { loading: false });
      }
    },
    setFilter(filter: string) {
      patchState(store, { filter });
    },
    addUser(user: User) {
      patchState(store, (s) => ({ users: [...s.users, user] }));
    },
  })),
);
```

Use:

```typescript
@Component({...})
export class UsersListComponent {
  readonly store = inject(UsersStore);
  // store.users(), store.filteredUsers(), store.count()
  // store.load(), store.setFilter('foo')
}
```

Pros over service: clean state slice + reactive computeds + methods all colocated. Pros over classic NgRx: way less boilerplate, no actions/reducers/selectors/effects ceremony.

## RxJS — when to use it

Reach for RxJS when you have:

- **HTTP** — `HttpClient` returns Observables; `firstValueFrom()` to await
- **WebSocket / SSE** — natural Observable shape
- **Debounce / throttle** — `debounceTime`, `throttleTime` operators
- **Combine multiple async sources** — `combineLatest`, `forkJoin`, `merge`
- **Polling** — `interval(5000).pipe(switchMap(() => http.get(...)))`

```typescript
@Injectable()
export class SearchService {
  search(query$: Observable<string>): Observable<Result[]> {
    return query$.pipe(
      debounceTime(300),
      distinctUntilChanged(),
      switchMap((q) => this.http.get<Result[]>(`/api/search?q=${q}`)),
    );
  }
}
```

## Bridging RxJS ↔ Signals

```typescript
import { toSignal, toObservable } from '@angular/core/rxjs-interop';

// Observable → Signal (for templates)
class FooComponent {
  private route = inject(ActivatedRoute);
  readonly id = toSignal(this.route.params.pipe(map((p) => p['id'])));
  readonly profile = toSignal(this.fetchProfile(), { initialValue: null });
}

// Signal → Observable (for RxJS pipelines)
class BarComponent {
  readonly query = signal('');
  readonly results = toSignal(
    toObservable(this.query).pipe(
      debounceTime(300),
      switchMap((q) => this.http.get<Result[]>(`/api/search?q=${q}`)),
    ),
    { initialValue: [] },
  );
}
```

`toSignal` and `toObservable` are first-class. Use them; don't shoehorn one paradigm where the other is natural.

## Anti-patterns

| Pattern | Why bad | Use instead |
|---------|---------|-------------|
| `BehaviorSubject` for state | Pre-signal era | `signal()` |
| Mutating signal value in place | Doesn't trigger update | `update((s) => ({...s, x: 1}))` |
| `effect()` for derived state | Wrong tool | `computed()` |
| `Subject<void>` for "trigger" events | Verbose | Direct method call on service |
| Wrapping signals in Observables for `async` pipe | Pointless | Read signal directly in template |
| Big monolithic `AppState` signal | Hard to update granularly | Multiple smaller signals or Signal Store |
| `effect()` that writes back to a signal | Infinite loop | Use computed; or `allowSignalWrites: true` (sparingly) |
| `switchMap` inside service constructor | Subscription leak | Use proper lifecycle |

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| Signal value not updating | Mutating object in place — use immutable update |
| Template doesn't re-render | OnPush + signal works fine; verify signal is being read in template |
| `Cannot read property of undefined` in `computed` | Add a default value when creating signal |
| Effect runs in infinite loop | Check what the effect writes to — if it writes a signal it depends on, loop |
| `toSignal` without `initialValue` | First read returns `undefined`; provide `initialValue` |
| `inject()` outside injection context | Only call `inject` in constructor or factory function |
| Memory leak from `interval()` | Unsubscribe in `onCleanup` of effect, or use `takeUntilDestroyed()` |
| Async/await with signals | Fine — but signals don't auto-await; use computed for derived |
