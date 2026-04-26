---
name: scaffold-flutter-riverpod
description: Use when the user wants to scaffold a new Flutter app with Riverpod 2 (with code generation), freezed for immutable models, dio + retrofit for typed HTTP clients, drift or isar for local storage, go_router 14 for routing, feature-first folder structure, very_good_analysis lint. Triggers on "new flutter project with riverpod", "flutter riverpod scaffold", "flutter app".
---

# Scaffold Flutter Project — Riverpod (claudeforge)

Follow the master prompt at `mobile/flutter-riverpod/PROMPT.md`. Steps:

1. **Confirm parameters**: `app_name` (snake_case), `package_id` (com.x.y), `description`, include auth / local DB flags, `api_base_url`.
2. **Read** `mobile/flutter-riverpod/PROMPT.md` — full directory tree, locked stack, layer rules, key files (pubspec.yaml, analysis_options.yaml, main.dart, app.dart, dio_client, auth feature end-to-end).
3. **Generate**:
   - `flutter create --org {{com.example}} --project-name {{app-name}} {{app-name}}`
   - Replace `pubspec.yaml` with locked stack
   - `flutter pub get`
   - Create directory tree under `lib/` per the prompt
   - Write `core/` files: env, theme, network (dio + interceptors), routing (go_router), storage
   - Write one feature module (auth/) end-to-end: model (freezed) → repository → @riverpod controller → screen
   - Run `dart run build_runner build --delete-conflicting-outputs` to generate freezed/riverpod/retrofit code
4. **Verify**: `flutter analyze` clean, `flutter test` passes, `flutter run` works on simulator.
5. **Hand off**: setup steps.

Do NOT use the legacy `provider` package, GetX, MobX, or Bloc (point to `mobile/flutter-bloc/` if user wants Bloc). Strict feature-first folders with the data/domain/application/presentation split.
