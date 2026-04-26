# Mobile — claudeforge guides

> *Phase 3 — coming soon.*

## Decision matrix

| Pick | When |
|------|------|
| **Flutter (Riverpod)** | Greenfield, fewer footguns, code-generated providers, stronger types |
| **Flutter (Bloc)** | Larger team, prefer event-driven explicit state machines, want Bloc's testability story |
| **React Native** | Existing React/web team, want shared code with web, willing to fight occasional native module pain |

## Files

- `flutter-riverpod/PROMPT.md` — *Phase 3* — full project layout: features/ with each feature owning UI + providers + repos + models, freezed for models, dio + retrofit for HTTP, isar/drift for local
- `flutter-bloc/PROMPT.md` — *Phase 3* — same architectural shape, with Bloc/Cubit replacing Riverpod providers
- `react-native/PROMPT.md` — *Phase 3* — Expo SDK 51+, expo-router file-based routing, react-query for server state, zustand for client state, Reanimated 3 for animation, MMKV for local storage
