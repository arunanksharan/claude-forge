---
name: scaffold-react-native
description: Use when the user wants to scaffold a new React Native app with Expo SDK 52+, expo-router file-based routing, TanStack Query for server state, Zustand for client state, Reanimated 3, MMKV for storage, expo-secure-store for tokens, EAS Build/Update, Maestro for E2E. Triggers on "new react native project", "new expo project", "scaffold rn app".
---

# Scaffold React Native Project — Expo (claudeforge)

Follow the master prompt at `mobile/react-native/PROMPT.md`. Steps:

1. **Confirm parameters**: `app_name`, `slug` (kebab-case), `package_id` (com.x.y), `description`, include auth flag, `api_base_url`.
2. **Read** `mobile/react-native/PROMPT.md` — directory tree, locked stack (Expo SDK 52, expo-router 4, etc.), key files (package.json, app.config.ts, root layouts, API client, auth store, login screen).
3. **Generate**:
   - `npx create-expo-app@latest {{app-name}} --template blank-typescript`
   - `cd {{app-name}}` and replace `package.json` deps + scripts
   - `npx expo install expo-router expo-secure-store expo-status-bar expo-linking ...` for the Expo plugins (use `expo install` for those, `pnpm add` for the rest)
   - Replace `app.json` with `app.config.ts`
   - Create the `app/` (expo-router routes) and `src/` (api, stores, components, lib) directory tree
   - Write root layouts (`app/_layout.tsx`, `(auth)/_layout.tsx`, `(app)/_layout.tsx` with Tabs)
   - Write API client (with SecureStore-backed Bearer), Zustand auth-store, login + signup screens
4. **Verify**: `npx expo start`, smoke test on iOS Simulator + Android emulator.
5. **Set up EAS** if user is ready: `eas init`, `eas build:configure`, write `eas.json` with development / preview / production profiles.
6. **Hand off**: setup steps + how to run EAS Build.

Do NOT use AsyncStorage (use MMKV), axios (use fetch), redux (use Zustand+TanStack Query), or NativeBase. Use FlashList instead of FlatList for big lists.
