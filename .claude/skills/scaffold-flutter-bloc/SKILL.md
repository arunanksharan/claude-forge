---
name: scaffold-flutter-bloc
description: Use when the user wants to scaffold a new Flutter app with flutter_bloc 8 + bloc_concurrency, freezed events/states, dio + retrofit, drift/isar, go_router, feature-first folders. Triggers on "new flutter project with bloc", "flutter bloc scaffold", "flutter cubit".
---

# Scaffold Flutter Project — Bloc (claudeforge)

Follow the master prompt at `mobile/flutter-bloc/PROMPT.md`. Steps:

1. **Confirm parameters**: `app_name`, `package_id`, `description`, include auth / local DB flags, `api_base_url`.
2. **Read** `mobile/flutter-bloc/PROMPT.md` — directory tree, locked stack (Bloc-specific deltas from Riverpod variant), layer rules, key files (pubspec, AppBlocObserver, auth feature with freezed events/states + Bloc + BlocConsumer screen).
3. **Generate**:
   - `flutter create --org {{com.example}} --project-name {{app-name}} {{app-name}}`
   - Replace `pubspec.yaml` with locked stack (flutter_bloc 8, bloc_concurrency, bloc_test in dev deps)
   - `flutter pub get`
   - Create directory tree under `lib/`
   - Write `core/` files
   - Add AppBlocObserver in `core/observers/`
   - Write one feature module (auth/) with freezed events + freezed states + Bloc with `transformer: sequential()` + BlocConsumer-based screen
   - Run `dart run build_runner build --delete-conflicting-outputs`
4. **Verify**: `flutter analyze` clean, `flutter test` passes (write one bloc_test).
5. **Hand off**: setup steps.

Use Cubit (not Bloc) for trivial state without events. Use `transformer: sequential()` to serialize events that need ordering. Same feature-first folder layout as the Riverpod variant.
