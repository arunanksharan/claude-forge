# Mobile — claudeforge guides

> *Phase 3 — coming soon.*

## Decision matrix

| Pick | When |
|------|------|
| **Flutter (Riverpod)** | Greenfield, fewer footguns, code-generated providers, stronger types |
| **Flutter (Bloc)** | Larger team, prefer event-driven explicit state machines, want Bloc's testability story |
| **React Native** | Existing React/web team, want shared code with web, willing to fight occasional native module pain |

## Files

- [`flutter-riverpod/PROMPT.md`](./flutter-riverpod/PROMPT.md) — full project layout: features/ with each feature owning UI + providers + repos + models, freezed, dio + retrofit, drift/isar for local
- [`flutter-bloc/PROMPT.md`](./flutter-bloc/PROMPT.md) — same architectural shape with Bloc/Cubit replacing Riverpod providers, bloc_test patterns
- [`react-native/PROMPT.md`](./react-native/PROMPT.md) — Expo SDK 52, expo-router, TanStack Query + zustand, Reanimated 3, MMKV, EAS Build/Update, Maestro E2E
