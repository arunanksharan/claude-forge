# React Native — EAS Build + EAS Update

> Building, signing, and shipping React Native apps via Expo Application Services. Plus over-the-air updates for JS-only changes.

## EAS Build — what it does

Builds your iOS + Android app in the cloud, signed and ready for the App Store / Play Console / Internal Distribution. No Mac needed for iOS. No Android Studio needed.

For most projects: **EAS Build is the right answer**. The alternative (self-hosted GitHub Actions with macOS runners) costs more money than EAS for typical usage.

## Setup

```bash
npm install -g eas-cli
eas login
cd your-app
eas init
```

Creates `eas.json` and links to an EAS project.

## `eas.json`

```json
{
  "cli": { "version": ">= 13.0.0" },
  "build": {
    "development": {
      "developmentClient": true,
      "distribution": "internal",
      "ios": { "simulator": true },
      "channel": "development"
    },
    "preview": {
      "distribution": "internal",
      "ios": { "simulator": false },
      "channel": "preview"
    },
    "production": {
      "channel": "production",
      "autoIncrement": true,
      "ios": { "resourceClass": "m-medium" },
      "android": { "buildType": "app-bundle" }
    }
  },
  "submit": {
    "production": {
      "ios": {
        "appleId": "you@example.com",
        "ascAppId": "1234567890",
        "appleTeamId": "ABCDEF1234"
      },
      "android": {
        "serviceAccountKeyPath": "./service-account.json",
        "track": "production",
        "releaseStatus": "completed"
      }
    }
  }
}
```

| Profile | When |
|---------|------|
| `development` | For dev clients (custom binaries with Expo dev tools) |
| `preview` | Internal testing (TestFlight, Firebase App Distribution) |
| `production` | Store-ready binaries |

## Build commands

```bash
# build for both platforms
eas build --profile production --platform all

# iOS only
eas build --profile production --platform ios

# wait for the build to finish (otherwise async)
eas build --profile production --platform ios --wait

# local build (skip cloud — requires Mac for iOS)
eas build --profile production --platform ios --local
```

The build runs in the cloud. You get a link to the binary when it's done. Time: ~10-15 min per platform per build.

## Credentials management

EAS handles signing credentials for you:

```bash
# iOS — generates / fetches certs + provisioning profiles
eas credentials -p ios

# Android — generates upload keystore
eas credentials -p android
```

Stored on Expo's servers, encrypted. You don't need to manage `.p12` / `.jks` files yourself.

For sensitive accounts: you can BYO credentials and EAS uses them.

## EAS Submit — auto-publish to stores

```bash
eas submit --profile production --platform all --latest
```

Uploads the latest production build to App Store Connect (review pending) and Play Console (your configured track).

For App Store: requires App Store Connect API key.
For Play Store: requires service account JSON.

## EAS Update — OTA for JS-only changes

For **JavaScript / asset changes** (no native code change), ship updates without re-publishing to stores:

```bash
# publish an update
eas update --branch production --message "Fix login button color"
```

Existing app users on this build's runtime get the update on next launch (or via `Updates.checkForUpdateAsync()` in your code).

### Branches + channels

- A **branch** is a stream of updates (e.g., `production`, `staging`, `feature/checkout-flow`)
- A **channel** is what binaries listen to (configured in `eas.json` `channel:`)
- A binary built with `channel: "production"` receives updates from the branch you pointed `production` channel at

```bash
# point a channel at a branch
eas channel:edit production --branch production

# send an update only to the production channel
eas update --branch production --message "..."
```

### When OTA works (and doesn't)

| Change | OTA works |
|--------|-----------|
| JS code changes | Yes |
| Asset changes (images, fonts in JS bundle) | Yes |
| `react-native-reanimated` worklets | Yes |
| Adding a new npm package | Usually yes (if pure JS) |
| Native module added/removed | NO — needs new build |
| `app.json` / `app.config.ts` change | Sometimes — depends what changed |
| `Info.plist` / `AndroidManifest.xml` change | NO |
| Expo SDK upgrade | NO — needs new build |

OTA is for "fix a bug, change copy, tweak UI." Not for "add Bluetooth support."

## Runtime version

Critical: every binary has a **runtime version**. Updates are only delivered to binaries with matching runtime version.

```javascript
// app.config.ts
export default {
  ...,
  runtimeVersion: { policy: "appVersion" },    // or "sdkVersion", or hardcoded
};
```

| Policy | Update compat |
|--------|---------------|
| `"sdkVersion"` | Updates target a specific Expo SDK version |
| `"appVersion"` | Updates target a specific app version (1.2.3) |
| `"nativeVersion"` | Combines version + native build |
| Hardcoded `"1.0.0"` | Manual control |

Bump runtime version when you change native code. Mismatched runtime = update silently ignored.

## Auto-update in app

```javascript
import * as Updates from 'expo-updates';

async function checkForUpdate() {
  if (__DEV__) return;          // skip in dev

  try {
    const update = await Updates.checkForUpdateAsync();
    if (update.isAvailable) {
      await Updates.fetchUpdateAsync();
      // optionally show "restart to update" banner
      Updates.reloadAsync();
    }
  } catch (e) {
    // network error etc. — fail silently
  }
}
```

Default behavior (configurable in `app.config.ts`): update check on launch, apply on next launch. Tune via `updates.checkAutomatically` and `updates.fallbackToCacheTimeout`.

## CI integration

GitHub Actions for builds + updates:

```yaml
# .github/workflows/eas-update.yml
name: EAS Update

on:
  push:
    branches: [main]
    paths:
      - 'src/**'
      - 'app.config.ts'

jobs:
  update:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v4
        with: { version: 9 }
      - uses: actions/setup-node@v4
        with: { node-version: 22, cache: 'pnpm' }
      - run: pnpm install --frozen-lockfile
      - uses: expo/expo-github-action@v8
        with:
          eas-version: latest
          token: ${{ secrets.EXPO_TOKEN }}
      - run: eas update --branch production --message "${{ github.event.head_commit.message }}" --non-interactive
```

For builds (less frequent — only on native changes):

```yaml
# .github/workflows/eas-build.yml
on:
  push:
    tags: ['v*']
jobs:
  build:
    # ... same setup ...
    - run: eas build --profile production --platform all --non-interactive
    - run: eas submit --profile production --platform all --latest --non-interactive
```

## Build optimization

- **Cache**: EAS auto-caches `node_modules`, Pods. Faster subsequent builds.
- **Resource class**: pick `m-medium` (default) or `m-large` for faster builds (more $).
- **Build artifacts**: configurable retention; keep last 10 typically.

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| First iOS build asks 20 questions | Run `eas credentials` interactively first; subsequent builds non-interactive |
| Build times out | Resource class too small; switch to `m-large` |
| OTA update not received | Verify runtime version matches; verify channel pointed at right branch |
| `expo-updates` not installed | Required for OTA; `npx expo install expo-updates` |
| App store rejection for "remote code" | OTA must update only JS, not download native code; check Expo's compliance docs |
| Build fails on iOS — provisioning profile | Re-run `eas credentials -p ios`; let EAS regenerate |
| Android build fails — keystore | EAS auto-generates; if you provided one, verify password |
| Native module conflict | Eject from managed workflow only if absolutely needed |
| `app.json` and `app.config.ts` both exist | Use only one (config.ts is preferred) |
| Forgot to bump version before submit | Stores reject duplicate version; bump and rebuild |
| OTA breaks existing users | Test on internal channel first; can roll back via `eas update --republish --group <id>` |
| Slow OTA update download | Check size; use code splitting; lazy-load big features |
