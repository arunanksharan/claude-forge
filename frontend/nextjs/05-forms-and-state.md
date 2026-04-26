# Forms & State Management

> react-hook-form + zod for forms; TanStack Query for server state; Zustand for client state. When to pick which, with patterns.

## State, classified

| Kind | Example | Tool |
|------|---------|------|
| **Server state** (cached, refetched, mutated) | user list, current user, posts | **TanStack Query** |
| **Form state** (controlled, validated) | sign-up form, profile editor | **react-hook-form** |
| **UI state** (ephemeral, page-local) | "is dropdown open" | **`useState`** |
| **Cross-component UI state** | sidebar collapsed, theme | **Zustand** |
| **URL state** (shareable, restorable) | filters, search, pagination | **`useSearchParams`** |

When in doubt, **prefer URL state**. It's free, restorable, shareable, and survives refresh.

## Server state with TanStack Query

### Query client setup (already in `PROMPT.md` providers)

```tsx
const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 60_000,           // data is fresh for 1min
      refetchOnWindowFocus: false,  // don't be annoying
      retry: 1,
    },
  },
});
```

### Fetch wrapper

```typescript
// src/lib/api-client.ts
import { env } from './env';

export class ApiError extends Error {
  constructor(public status: number, public body: unknown, message: string) {
    super(message);
  }
}

export async function api<T>(path: string, init?: RequestInit): Promise<T> {
  const res = await fetch(`${env.NEXT_PUBLIC_API_URL}${path}`, {
    ...init,
    headers: {
      'Content-Type': 'application/json',
      ...(init?.headers || {}),
    },
    credentials: 'include',
  });

  if (!res.ok) {
    const body = await res.json().catch(() => null);
    throw new ApiError(res.status, body, body?.error?.message ?? res.statusText);
  }

  if (res.status === 204) return undefined as T;
  return res.json() as Promise<T>;
}
```

### Queries

```tsx
'use client';

import { useQuery } from '@tanstack/react-query';
import { api } from '@/lib/api-client';
import type { User } from '@/types/api';

function useUsers() {
  return useQuery({
    queryKey: ['users'],
    queryFn: () => api<User[]>('/api/v1/users'),
  });
}

export function UsersList() {
  const { data, isPending, error } = useUsers();
  if (isPending) return <div>Loading...</div>;
  if (error) return <div>Error: {error.message}</div>;
  return <ul>{data.map((u) => <li key={u.id}>{u.email}</li>)}</ul>;
}
```

### Mutations

```tsx
function useCreateUser() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (input: { email: string; password: string }) =>
      api<User>('/api/v1/users', { method: 'POST', body: JSON.stringify(input) }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['users'] });
    },
  });
}
```

### Server Components + TanStack Query

In Next.js App Router, prefer **fetching in Server Components** when the data isn't going to mutate from the client. TanStack Query is for client-side fetching/mutations.

```tsx
// app/(app)/users/page.tsx — Server Component
import { api } from '@/lib/api-client';

export default async function UsersPage() {
  const users = await api<User[]>('/api/v1/users');
  return <UsersListClient initialUsers={users} />;
}
```

For mutations and re-fetches, the client component takes over with TanStack Query. Hydrate the cache:

```tsx
// app/(app)/users/page.tsx
import { dehydrate, HydrationBoundary, QueryClient } from '@tanstack/react-query';

export default async function UsersPage() {
  const qc = new QueryClient();
  await qc.prefetchQuery({ queryKey: ['users'], queryFn: () => api<User[]>('/api/v1/users') });

  return (
    <HydrationBoundary state={dehydrate(qc)}>
      <UsersListClient />
    </HydrationBoundary>
  );
}
```

The client component `useQuery({queryKey: ['users']})` finds it in cache — no second fetch.

### Query key conventions

```typescript
['users']                            // list
['users', userId]                    // detail
['users', { search, page }]          // filtered list
['orders', userId, 'invoices']       // nested resource
```

Object keys auto-serialize. Use them for filters / pagination.

### Optimistic updates

```typescript
const qc = useQueryClient();

const mutation = useMutation({
  mutationFn: (newUser: NewUser) => api('/api/v1/users', { method: 'POST', body: JSON.stringify(newUser) }),
  onMutate: async (newUser) => {
    await qc.cancelQueries({ queryKey: ['users'] });
    const previous = qc.getQueryData<User[]>(['users']);
    qc.setQueryData<User[]>(['users'], (old = []) => [...old, { ...newUser, id: 'temp', createdAt: new Date() }]);
    return { previous };
  },
  onError: (_err, _newUser, ctx) => {
    qc.setQueryData(['users'], ctx?.previous);
  },
  onSettled: () => qc.invalidateQueries({ queryKey: ['users'] }),
});
```

## Forms with react-hook-form + zod

### Why this combo

| | rhf + zod | Formik | TanStack Form |
|---|---|---|---|
| Re-renders | Minimal (uncontrolled) | Every keystroke | Minimal |
| Validation | Zod schema | Yup | Zod (or others) |
| Schema sharable with API | Yes | Awkward | Yes |
| Maturity | Mature | Dead | Newer |

### Setup

```tsx
'use client';

import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { toast } from 'sonner';

const schema = z.object({
  email: z.string().email(),
  password: z.string().min(8, 'min 8 characters'),
});

type FormValues = z.infer<typeof schema>;

export function SignupForm() {
  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting },
  } = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: { email: '', password: '' },
  });

  const onSubmit = async (values: FormValues) => {
    try {
      await api('/api/v1/auth/signup', { method: 'POST', body: JSON.stringify(values) });
      toast.success('Account created');
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Failed');
    }
  };

  return (
    <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
      <div className="space-y-2">
        <Label htmlFor="email">Email</Label>
        <Input id="email" type="email" autoComplete="email" {...register('email')} aria-invalid={!!errors.email} />
        {errors.email && <p className="text-sm text-red-500">{errors.email.message}</p>}
      </div>

      <div className="space-y-2">
        <Label htmlFor="password">Password</Label>
        <Input id="password" type="password" autoComplete="new-password" {...register('password')} aria-invalid={!!errors.password} />
        {errors.password && <p className="text-sm text-red-500">{errors.password.message}</p>}
      </div>

      <Button type="submit" disabled={isSubmitting}>
        {isSubmitting ? 'Creating...' : 'Create account'}
      </Button>
    </form>
  );
}
```

### Controlled inputs (Radix select, custom components)

```tsx
import { Controller } from 'react-hook-form';

<Controller
  control={control}
  name="role"
  render={({ field }) => (
    <Select value={field.value} onValueChange={field.onChange}>
      <SelectTrigger><SelectValue /></SelectTrigger>
      <SelectContent>
        <SelectItem value="user">User</SelectItem>
        <SelectItem value="admin">Admin</SelectItem>
      </SelectContent>
    </Select>
  )}
/>
```

### Server-side validation errors

When the API rejects (e.g. "email already in use"), surface to the field:

```typescript
const onSubmit = async (values: FormValues) => {
  try {
    await api(...);
  } catch (err) {
    if (err instanceof ApiError && err.body && typeof err.body === 'object') {
      const fieldErrors = (err.body as any).fieldErrors as Record<string, string[]>;
      if (fieldErrors) {
        Object.entries(fieldErrors).forEach(([field, msgs]) => {
          setError(field as keyof FormValues, { message: msgs[0] });
        });
      }
    }
    toast.error(err.message);
  }
};
```

### Form composition (multi-step, dynamic fields)

For multi-step wizards, lift form state into a Zustand store or use a shared `FormProvider`:

```tsx
import { FormProvider, useFormContext } from 'react-hook-form';

const methods = useForm({ resolver: zodResolver(fullSchema) });

<FormProvider {...methods}>
  <Step1 />
  <Step2 />
  <Step3 />
</FormProvider>
```

Each step uses `useFormContext()` to register fields against the shared form.

## Zustand for client state

### When to use Zustand

UI state that's **shared across components** (sidebar collapsed, theme, current modal). Don't use it for server data — TanStack Query owns that.

### Store

```typescript
// src/stores/ui-store.ts
import { create } from 'zustand';

interface UiState {
  sidebarOpen: boolean;
  theme: 'dark' | 'light';
  toggleSidebar: () => void;
  setTheme: (theme: 'dark' | 'light') => void;
}

export const useUiStore = create<UiState>((set) => ({
  sidebarOpen: true,
  theme: 'dark',
  toggleSidebar: () => set((s) => ({ sidebarOpen: !s.sidebarOpen })),
  setTheme: (theme) => set({ theme }),
}));
```

### Selective subscription

To avoid re-rendering on unrelated state changes:

```tsx
const sidebarOpen = useUiStore((s) => s.sidebarOpen);
const toggleSidebar = useUiStore((s) => s.toggleSidebar);
```

Or with shallow:

```tsx
import { useShallow } from 'zustand/react/shallow';
const { sidebarOpen, toggleSidebar } = useUiStore(
  useShallow((s) => ({ sidebarOpen: s.sidebarOpen, toggleSidebar: s.toggleSidebar })),
);
```

### Persist

```typescript
import { persist } from 'zustand/middleware';

export const useUiStore = create<UiState>()(
  persist(
    (set) => ({ ... }),
    { name: 'ui-store', partialize: (state) => ({ theme: state.theme }) },
  ),
);
```

`partialize` chooses which fields to persist. Don't persist server data (it'll go stale).

## URL state with `useSearchParams`

For filters, pagination, search — anything you'd want to share via URL or restore on refresh:

```tsx
'use client';

import { usePathname, useRouter, useSearchParams } from 'next/navigation';

function useQueryState<T extends string>(key: string, defaultValue: T) {
  const params = useSearchParams();
  const router = useRouter();
  const pathname = usePathname();

  const value = (params.get(key) as T) ?? defaultValue;

  const setValue = (next: T | null) => {
    const sp = new URLSearchParams(params);
    if (next == null || next === defaultValue) sp.delete(key);
    else sp.set(key, next);
    router.replace(`${pathname}?${sp.toString()}`, { scroll: false });
  };

  return [value, setValue] as const;
}

// usage
const [search, setSearch] = useQueryState('q', '');
const [page, setPage] = useQueryState('page', '1');
```

For a more featureful version, use `nuqs`:

```bash
pnpm add nuqs
```

```tsx
import { useQueryState, parseAsString, parseAsInteger } from 'nuqs';

const [search, setSearch] = useQueryState('q', parseAsString.withDefault(''));
const [page, setPage] = useQueryState('page', parseAsInteger.withDefault(1));
```

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| Re-fetching on every keystroke (search) | Debounce with `useDebounce` (400ms is the sweet spot) |
| Cascading re-renders from Zustand | Use selectors (single field per `useStore`) |
| Form submits empty values | `defaultValues` matters — set them in `useForm` |
| Server-rendered form values lost on hydration | Pass `defaultValues` from props; don't fetch in client form |
| Optimistic update orphaned on error | `onError` handler restores `previous` state from context |
| TanStack Query refetches everything | Tune `staleTime`; default-zero fetches on every mount |
| `setError` doesn't clear on re-submit | rhf clears errors automatically when the field is re-validated |
| Multiple mutations race | Use `mutation.mutate` not `mutation.mutateAsync` if you don't await |
| Form state lost on route change | Lift to URL state, or persist in Zustand |
| Number inputs return strings | `register('age', { valueAsNumber: true })` or use `z.coerce.number()` |
