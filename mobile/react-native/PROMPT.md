# React Native (Expo) — Master Scaffold Prompt

> **Modern React Native with Expo SDK 51+, expo-router file-based routing, TanStack Query for server state, Zustand for client state, Reanimated 3.**

---

## Context

You are scaffolding a new React Native app on Expo's managed workflow. File-based routing via expo-router, native auth/storage via Expo modules, no Java/Swift to write unless absolutely needed.

If something is ambiguous, **ask once, then proceed**.

## Project parameters

```
app_name:           {{app-name}}                # used as project + display
slug:               {{app-slug}}                # kebab-case
package_id:         {{com.example.app}}
description:        {{one-line-description}}
include_auth:       {{yes-or-no}}
api_base_url:       {{https://api.example.com}}
```

---

## Locked stack

| Concern | Pick | Why |
|---------|------|-----|
| Framework | **Expo SDK 51+** + React Native (latest) | Managed workflow — way less native pain |
| Routing | **expo-router** v3+ | File-based, types via TS, deep links free |
| State (server) | **@tanstack/react-query** v5 | |
| State (client) | **zustand** | |
| Forms | **react-hook-form** + **zod** + **@hookform/resolvers** | |
| Animation | **react-native-reanimated** 3 + **react-native-gesture-handler** | |
| Local storage | **react-native-mmkv** (key-value) + **expo-secure-store** (tokens) | MMKV is way faster than AsyncStorage |
| HTTP | **fetch** wrapper (or **ky**) | |
| Validation | **zod** | |
| UI components | **gluestack-ui** v2 or **tamagui** or roll your own | Tamagui is faster but heavier setup; gluestack is simpler |
| Icons | **@expo/vector-icons** | Lucide via `lucide-react-native` works too |
| Lint | **eslint** + **@react-native-community/eslint-config** | |
| Tests | `jest-expo` + `@testing-library/react-native` + `maestro` for E2E | |
| Build / OTA | EAS Build + EAS Update | |

## Rejected

| Library | Why not |
|---------|---------|
| Bare React Native | Expo's managed workflow + dev client gives you 95% of the power, 10% of the ops |
| **react-navigation** standalone | expo-router wraps it with a better DX |
| **redux** / **redux-toolkit** | Zustand + TanStack Query covers it with way less code |
| **mobx** | Same |
| **AsyncStorage** | Slow — use MMKV |
| **axios** | `fetch` is built-in; ky for niceties |
| **realm** | Heavy and weird; use MMKV / SQLite (expo-sqlite) |
| **NativeBase** | Maintenance is uncertain; use gluestack/tamagui |
| **lottie-react-native** unless you need Lottie | |
| **react-native-vector-icons** | `@expo/vector-icons` wraps it cleaner |
| **detox** | Maestro is much easier to set up + write |
| **fastlane** for builds | EAS handles it |

---

## Directory layout

```
{{app-name}}/
├── package.json
├── tsconfig.json
├── app.config.ts                       # dynamic Expo config
├── eas.json
├── babel.config.js
├── metro.config.js
├── .env
├── .env.example
├── README.md
├── app/                                # expo-router file-based routes
│   ├── _layout.tsx                     # root layout (providers)
│   ├── (auth)/
│   │   ├── _layout.tsx
│   │   ├── login.tsx
│   │   └── signup.tsx
│   ├── (app)/                          # authed routes
│   │   ├── _layout.tsx                 # tab nav
│   │   ├── index.tsx                   # home
│   │   ├── profile.tsx
│   │   └── settings.tsx
│   └── +not-found.tsx
├── src/
│   ├── api/
│   │   ├── client.ts                   # fetch wrapper
│   │   └── queries/
│   │       ├── use-users.ts
│   │       └── use-orders.ts
│   ├── stores/
│   │   ├── auth-store.ts               # zustand: tokens, current user
│   │   └── ui-store.ts
│   ├── lib/
│   │   ├── env.ts
│   │   ├── storage.ts                  # MMKV wrapper
│   │   └── secure-storage.ts           # expo-secure-store wrapper
│   ├── hooks/
│   │   └── use-debounce.ts
│   ├── components/
│   │   ├── ui/                         # primitives (Button, Input)
│   │   └── features/
│   │       └── {{feature}}/
│   ├── theme/
│   │   ├── colors.ts
│   │   └── tokens.ts
│   └── types/
│       └── api.ts
├── assets/
│   ├── images/
│   └── fonts/
└── __tests__/
    └── components/
```

## Layer rules

Same shape as the web Next.js guide:

- `app/*.tsx` (routes) — thin, calls hooks
- `src/api/queries/*` — TanStack Query hooks; one file per resource
- `src/stores/*` — Zustand for client state only (UI flags, auth tokens)
- `src/components/features/*` — feature components
- `src/components/ui/*` — primitive components

---

## Key files

### `package.json`

```json
{
  "name": "{{app-slug}}",
  "main": "expo-router/entry",
  "version": "0.1.0",
  "scripts": {
    "start": "expo start",
    "android": "expo run:android",
    "ios": "expo run:ios",
    "web": "expo start --web",
    "lint": "eslint .",
    "typecheck": "tsc --noEmit",
    "test": "jest"
  },
  "dependencies": {
    "expo": "~52.0.0",
    "expo-router": "~4.0.0",
    "expo-status-bar": "~2.0.0",
    "expo-secure-store": "~14.0.0",
    "expo-constants": "~17.0.0",
    "expo-linking": "~7.0.0",
    "expo-splash-screen": "~0.29.0",
    "expo-system-ui": "~4.0.0",
    "expo-haptics": "~14.0.0",
    "react": "18.3.1",
    "react-native": "0.76.3",
    "react-native-reanimated": "~3.16.0",
    "react-native-gesture-handler": "~2.20.2",
    "react-native-screens": "~4.1.0",
    "react-native-safe-area-context": "~4.12.0",
    "react-native-mmkv": "~3.1.0",
    "@tanstack/react-query": "^5.59.0",
    "zustand": "^5.0.0",
    "react-hook-form": "^7.53.0",
    "@hookform/resolvers": "^3.9.0",
    "zod": "^3.23.8",
    "@expo/vector-icons": "~14.0.0"
  },
  "devDependencies": {
    "@babel/core": "^7.25.0",
    "@types/react": "~18.3.12",
    "typescript": "~5.6.0",
    "jest-expo": "~52.0.0",
    "jest": "^29.7.0",
    "@testing-library/react-native": "^12.7.0",
    "eslint": "^9.0.0",
    "eslint-config-expo": "~8.0.0"
  }
}
```

### `app.config.ts`

```typescript
import { ExpoConfig, ConfigContext } from 'expo/config';

export default ({ config }: ConfigContext): ExpoConfig => ({
  ...config,
  name: '{{app-name}}',
  slug: '{{app-slug}}',
  version: '0.1.0',
  orientation: 'portrait',
  icon: './assets/icon.png',
  scheme: '{{app-slug}}',
  userInterfaceStyle: 'automatic',
  newArchEnabled: true,
  ios: {
    supportsTablet: true,
    bundleIdentifier: '{{com.example.app}}',
  },
  android: {
    adaptiveIcon: { foregroundImage: './assets/adaptive-icon.png', backgroundColor: '#000000' },
    package: '{{com.example.app}}',
  },
  plugins: [
    'expo-router',
    'expo-secure-store',
    [
      'expo-splash-screen',
      { backgroundColor: '#000000', image: './assets/splash-icon.png', imageWidth: 200 },
    ],
  ],
  experiments: { typedRoutes: true },
  extra: {
    apiBaseUrl: process.env.EXPO_PUBLIC_API_URL,
    eas: { projectId: process.env.EAS_PROJECT_ID },
  },
});
```

### `app/_layout.tsx`

```tsx
import { Stack } from 'expo-router';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import { StatusBar } from 'expo-status-bar';
import { useState } from 'react';

export default function RootLayout() {
  const [queryClient] = useState(
    () =>
      new QueryClient({
        defaultOptions: {
          queries: { staleTime: 60_000, retry: 1, refetchOnWindowFocus: false },
        },
      }),
  );

  return (
    <GestureHandlerRootView style={{ flex: 1 }}>
      <QueryClientProvider client={queryClient}>
        <StatusBar style="auto" />
        <Stack screenOptions={{ headerShown: false }}>
          <Stack.Screen name="(auth)" />
          <Stack.Screen name="(app)" />
        </Stack>
      </QueryClientProvider>
    </GestureHandlerRootView>
  );
}
```

### `app/(app)/_layout.tsx`

```tsx
import { Tabs, Redirect } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { useAuthStore } from '@/src/stores/auth-store';

export default function AppLayout() {
  const isAuthenticated = useAuthStore((s) => !!s.accessToken);
  if (!isAuthenticated) return <Redirect href="/(auth)/login" />;

  return (
    <Tabs screenOptions={{ tabBarActiveTintColor: '#8b5cf6' }}>
      <Tabs.Screen name="index" options={{ title: 'Home', tabBarIcon: ({ color }) => <Ionicons name="home" size={22} color={color} /> }} />
      <Tabs.Screen name="profile" options={{ title: 'Profile', tabBarIcon: ({ color }) => <Ionicons name="person" size={22} color={color} /> }} />
      <Tabs.Screen name="settings" options={{ title: 'Settings', tabBarIcon: ({ color }) => <Ionicons name="settings" size={22} color={color} /> }} />
    </Tabs>
  );
}
```

### `src/api/client.ts`

```typescript
import * as SecureStore from 'expo-secure-store';
import Constants from 'expo-constants';

const baseUrl = Constants.expoConfig?.extra?.apiBaseUrl as string;

export class ApiError extends Error {
  constructor(public status: number, public body: unknown, message: string) {
    super(message);
  }
}

export async function api<T>(path: string, init?: RequestInit): Promise<T> {
  const token = await SecureStore.getItemAsync('access_token');
  const res = await fetch(`${baseUrl}${path}`, {
    ...init,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...(init?.headers || {}),
    },
  });

  if (!res.ok) {
    const body = await res.json().catch(() => null);
    throw new ApiError(res.status, body, body?.error?.message ?? res.statusText);
  }

  if (res.status === 204) return undefined as T;
  return res.json() as Promise<T>;
}
```

### `src/stores/auth-store.ts`

```typescript
import { create } from 'zustand';
import * as SecureStore from 'expo-secure-store';

interface User { id: string; email: string; }
interface AuthState {
  accessToken: string | null;
  refreshToken: string | null;
  user: User | null;
  bootstrap: () => Promise<void>;
  setSession: (tokens: { accessToken: string; refreshToken: string }, user: User) => Promise<void>;
  signOut: () => Promise<void>;
}

export const useAuthStore = create<AuthState>((set) => ({
  accessToken: null,
  refreshToken: null,
  user: null,
  async bootstrap() {
    const access = await SecureStore.getItemAsync('access_token');
    const refresh = await SecureStore.getItemAsync('refresh_token');
    set({ accessToken: access, refreshToken: refresh });
  },
  async setSession(tokens, user) {
    await SecureStore.setItemAsync('access_token', tokens.accessToken);
    await SecureStore.setItemAsync('refresh_token', tokens.refreshToken);
    set({ accessToken: tokens.accessToken, refreshToken: tokens.refreshToken, user });
  },
  async signOut() {
    await SecureStore.deleteItemAsync('access_token');
    await SecureStore.deleteItemAsync('refresh_token');
    set({ accessToken: null, refreshToken: null, user: null });
  },
}));
```

### `app/(auth)/login.tsx`

```tsx
import { View, Text, TextInput, Pressable, Alert, ActivityIndicator } from 'react-native';
import { useForm, Controller } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import { useRouter } from 'expo-router';
import { api } from '@/src/api/client';
import { useAuthStore } from '@/src/stores/auth-store';
import { useState } from 'react';

const schema = z.object({
  email: z.string().email(),
  password: z.string().min(8),
});
type FormValues = z.infer<typeof schema>;

export default function Login() {
  const router = useRouter();
  const setSession = useAuthStore((s) => s.setSession);
  const [submitting, setSubmitting] = useState(false);
  const { control, handleSubmit, formState: { errors } } = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: { email: '', password: '' },
  });

  const onSubmit = async (values: FormValues) => {
    setSubmitting(true);
    try {
      const { accessToken, refreshToken } = await api<{ accessToken: string; refreshToken: string }>(
        '/api/v1/auth/login', { method: 'POST', body: JSON.stringify(values) },
      );
      const user = await api<{ id: string; email: string }>('/api/v1/users/me');
      await setSession({ accessToken, refreshToken }, user);
      router.replace('/(app)');
    } catch (err) {
      Alert.alert('Sign in failed', err instanceof Error ? err.message : 'unknown error');
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <View style={{ flex: 1, padding: 24, justifyContent: 'center' }}>
      <Text style={{ fontSize: 24, fontWeight: '600', marginBottom: 24 }}>Sign in</Text>

      <Controller control={control} name="email" render={({ field: { onChange, value } }) => (
        <TextInput
          placeholder="Email"
          autoCapitalize="none"
          keyboardType="email-address"
          autoComplete="email"
          onChangeText={onChange}
          value={value}
          style={{ borderWidth: 1, borderColor: '#ccc', padding: 12, borderRadius: 8, marginBottom: 8 }}
        />
      )} />
      {errors.email && <Text style={{ color: 'red', marginBottom: 8 }}>{errors.email.message}</Text>}

      <Controller control={control} name="password" render={({ field: { onChange, value } }) => (
        <TextInput
          placeholder="Password"
          secureTextEntry
          autoComplete="current-password"
          onChangeText={onChange}
          value={value}
          style={{ borderWidth: 1, borderColor: '#ccc', padding: 12, borderRadius: 8, marginBottom: 8 }}
        />
      )} />
      {errors.password && <Text style={{ color: 'red', marginBottom: 8 }}>{errors.password.message}</Text>}

      <Pressable
        onPress={handleSubmit(onSubmit)}
        disabled={submitting}
        style={{ backgroundColor: '#8b5cf6', padding: 14, borderRadius: 8, marginTop: 16, alignItems: 'center' }}
      >
        {submitting ? <ActivityIndicator color="white" /> : <Text style={{ color: 'white', fontWeight: '600' }}>Sign in</Text>}
      </Pressable>
    </View>
  );
}
```

---

## Generation steps

1. **Confirm parameters.**
2. **Run `npx create-expo-app@latest {{app-name}} --template blank-typescript`.**
3. **`cd {{app-name}} && npx expo install expo-router expo-secure-store ...`** (one `expo install` for all the Expo plugins; `pnpm add` for the rest).
4. **Replace `package.json` deps + scripts.**
5. **Add `app.config.ts`** (delete `app.json`).
6. **Generate the directory tree**: `app/`, `src/`, `assets/`.
7. **Write root files**: `app/_layout.tsx`, `(auth)/_layout.tsx`, `(app)/_layout.tsx`.
8. **Write API client + auth store + login screen** as shown.
9. **Run `npx expo start`** — verify the auth flow on iOS Simulator + Android emulator.
10. **Set up EAS:** `eas init`, `eas build:configure`. Write `eas.json` with `development`, `preview`, `production` profiles.
11. **Test: `pnpm test` (Jest), and a Maestro flow (`maestro/login.yaml`) for E2E.**

---

## EAS Build + Update

```bash
# install
npm install -g eas-cli
eas login

# configure
eas build:configure

# build a development client (with Expo dev tools)
eas build --profile development --platform ios

# production build
eas build --profile production --platform all

# OTA update (no rebuild needed for JS-only changes)
eas update --branch production --message "Fix login button"
```

`eas.json`:

```json
{
  "cli": { "version": ">= 13.0.0" },
  "build": {
    "development": {
      "developmentClient": true,
      "distribution": "internal"
    },
    "preview": {
      "distribution": "internal"
    },
    "production": {}
  },
  "submit": {
    "production": {}
  }
}
```

## Performance notes

- **Use Reanimated 3 worklets**, not the JS thread for animations
- **Avoid `console.log` in prod** — Reactotron / Sentry breadcrumbs instead
- **Use FlashList** (Shopify) instead of FlatList for big lists — much faster scroll
- **Memoize list rows** (`memo`, stable keys)
- **`require('./img.png')` static**, not dynamic (Metro can't bundle dynamic paths)
- **MMKV for any local state read >5 times/screen** — synchronous, no JSON parse

## E2E with Maestro

```bash
brew install maestro

# maestro/login.yaml
appId: {{com.example.app}}
---
- launchApp
- tapOn: "Email"
- inputText: "alice@example.com"
- tapOn: "Password"
- inputText: "hunter22a"
- tapOn: "Sign in"
- assertVisible: "Home"

# run
maestro test maestro/login.yaml
```

Maestro is dramatically simpler than Detox. Use it.

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| `process.env.X` undefined | Use `EXPO_PUBLIC_*` prefix; access via `process.env.EXPO_PUBLIC_X` (build-time only) |
| Reanimated worklet error | Make sure `react-native-reanimated/plugin` is the LAST plugin in `babel.config.js` |
| TypedRoutes types missing | Run `npx expo customize tsconfig.json` once + `experiments: { typedRoutes: true }` |
| MMKV crashes on iOS Simulator | Reset Simulator (Erase All Content). Or use AsyncStorage in dev. |
| `Network request failed` on Android | Localhost is `10.0.2.2` from Android emulator; configure for emulator vs device |
| Hot reload eats state | That's normal — reload twice for clean state |
| Dev client vs Expo Go confusion | Use Expo Go for first weeks; switch to dev client when you add custom native modules |
| `expo-secure-store` size limit | iOS Keychain ~4KB per item; for big secrets, encrypt + store in MMKV |
| Animations laggy on debug build | Always profile on release builds |
| Bundle splitting / size | Use `expo-router` lazy routes + `react-native-bundle-visualizer` |
