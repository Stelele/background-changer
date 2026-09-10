# Wallpaper Changer — Design Spec

**Date:** 2026-09-10
**Status:** Approved (brainstorm complete)
**Stack:** Flutter, Android only

## 1. Overview

A zero-taps Android app that changes the device wallpaper daily, pulling from the same
image sources as the KDE Plasma *Picture of the Day* plugin used on the author's Linux
desktop.

```
┌─ Goal ──────────────────────────────────────────────────────┐
│ Wake up → new wallpaper already set. App UI exists only     │
│ for configuration and enjoying the results.                 │
└─────────────────────────────────────────────────────────────┘
```

### Decisions (locked during brainstorm)

| Decision | Choice |
|---|---|
| Architecture | On-device standalone (no server, no desktop dependency) |
| Providers | Simon Stålenhag (scrape), Bing (API), NASA APOD (API), Wikimedia POTD (API) |
| Behavior | Auto daily rotation; manual "refresh now" on app open if stale |
| Screens | User-configurable: Home / Lock / Both (default Both) |
| Devices | Independent; no cross-device sync |
| Fit mode | **Center-crop** default on portrait phones; As-is default on tablets; Blur-pad available; per-device setting |
| UI | Single screen: hero preview, provider chips, target/fit dropdowns, recent strip |
| Workflow | Test-driven development throughout |
| CI | GitHub Actions: test+verify on push/PR; release on `v*` tags |

### Non-goals

- Desktop-parity (same image as the Linux box on the same day)
- Cross-device sync, accounts, cloud
- Live wallpapers, widgets
- iOS

## 2. Architecture

```
┌───────────────────────────── Flutter app ─────────────────────────────┐
│                                                                       │
│  UI                    Core logic                 Android (Kotlin)   │
│  ┌──────────────┐  ┌─────────────────────┐  ┌──────────────────────┐ │
│  │ HomeScreen   │  │ PotdService         │  │ MethodChannel:       │ │
│  │ hero + chips │─▶│  ├ PotdProvider (x4)│─▶│  "wallpaper/set"     │ │
│  │ + dropdowns  │  │  ├ ImageFitter      │  │  → WallpaperManager  │ │
│  │ + recents    │  │  └ WallpaperRepo    │  │ WorkManager bootstrap│ │
│  └──────────────┘  └─────────────────────┘  └──────────────────────┘ │
└───────────────────────────────────────────────────────────────────────┘
```

| Unit | Responsibility | Depends on |
|---|---|---|
| `PotdProvider` (interface) | Fetch today's `PotdItem {title, author, infoUrl, imageUrl, bytes}` | — |
| `StalenhagProvider` | Scrape static HTML for `4k/*_big.jpg` links; deterministic day-of-year rotation (desktop parity not required) | http |
| `BingProvider` | HPImageArchive endpoint; request portrait file when target device is portrait | http |
| `ApodProvider` | api.nasa.gov APOD (official API, DEMO_KEY with per-IP limits is fine for personal use) | http |
| `WikimediaProvider` | Commons "PotD" via MediaWiki API | http |
| `ImageFitter` | Transform bitmap per fit mode + screen aspect ratio | image |
| `WallpaperRepo` | Settings persistence; image+metadata cache; 14-item recent ring | filesystem |
| `WallpaperApi` (platform channel) | Kotlin: `WallpaperManager.setBitmap` with `FLAG_SYSTEM`/`FLAG_LOCK`; WorkManager registration | Kotlin |
| `PotdService` | Orchestrate fetch → validate → dedupe → fit → set → cache; stale alarm | all above |

## 3. Daily data flow

```
WorkManager periodic job (~24h, constraint: network)
  1. provider.fetch()              ──fail─▶ keep wallpaper, backoff retry (30m→1h→4h)
  2. validate item                 (non-empty bytes + title + imageUrl, else = fail)
  3. dedupe                        (imageUrl same as current? → done, idempotent)
  4. ImageFitter.transform()       (center-crop to screen AR; Bing native portrait skips crop)
  5. WallpaperApi.apply()          (home / lock / both per setting)
  6. Repo.save()                   (image + metadata; trim recent ring to 14)
  7. cache age > 3 days?           ─▶ notification: "Provider looks broken — pick another"
```

On app open: if current wallpaper is older than today, run the same pipeline immediately.

## 4. Settings

| Setting | Values | Default |
|---|---|---|
| Provider | Stålenhag / Bing / APOD / Wikimedia | Stålenhag |
| Screens | Home / Lock / Both | Both |
| Fit mode | Center-crop / As-is / Blur-pad | Center-crop (As-is when device is landscape/tablet) |
| Wi-Fi only | toggle | On |

Permissions: `SET_WALLPAPER` only (normal, auto-granted). `POST_NOTIFICATIONS` for the
stale alarm (ask lazily). No storage, no location, no internet permission surprises
(`INTERNET` obviously required).

## 5. Error handling

| Failure | Behavior |
|---|---|
| No network at job time | WorkManager waits for constraint; backoff retries |
| Provider parse yields nothing (site redesign) | Treated as fetch failure; wallpaper stays; stale alarm at 3 days |
| `setBitmap` fails | Retry on next backoff; cache preserved |
| Reboot / app swiped away | WorkManager persists jobs across reboots and process death |
| Duplicate image for the day | Dedupe by URL; job exits successfully |

## 6. Development workflow — TDD

Strict red-green-refactor per unit, inside-out (models → providers → fitter → repo → service → UI):

```
1. RED    write a failing test for the next smallest behavior
2. GREEN  minimal code to pass
3. REFACTOR clean up, keep tests green
```

- Provider tests run against **fixture files** (saved HTML/JSON from the real sources),
  never live network — deterministic and offline-friendly.
- Platform channel (`WallpaperApi`) is behind an interface; tests use a fake. The Kotlin
  side is exercised manually on device/emulator (manual QA checklist below).
- UI test: one widget test verifying the home screen renders provider chips + preview
  from a faked repo/service.

## 7. CI/CD — GitHub Actions

```
push / PR ──▶ [verify]  flutter analyze + flutter test
                        (ubuntu, stable channel, flutter-action)
tag v*    ──▶ [release] verify → flutter build apk --release
                        → sign (keystore from secrets)
                        → attach APK to GitHub Release
```

| Job | Trigger | Steps |
|---|---|---|
| `verify` | push to `main`, PRs | checkout → setup Flutter (stable) → `flutter pub get` → `flutter analyze` → `flutter test` |
| `release` | tag push `v*` | same as verify → `flutter build apk --release` → decode keystore from `SECRETS` (`KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`) → sign → create GitHub Release with APK artifact |

- Keystore is generated once locally (documented in README), stored as base64 secret.
  CI fails fast with a clear message if secrets are missing.
- Version for the release is taken from the git tag; `pubspec.yaml` version bumped in
  the same commit as the tag.

## 8. Project layout

```
lib/
  main.dart
  models/potd_item.dart
  providers/provider.dart              ← PotdProvider interface
  providers/{stalenhag,bing,apod,wikimedia}.dart
  services/potd_service.dart
  services/image_fitter.dart
  services/wallpaper_repo.dart
  platform/wallpaper_api.dart          ← MethodChannel client (interface + impl)
  ui/home_screen.dart
android/app/src/main/…/MainActivity.kt ← channel handler + WallpaperManager + WorkManager
test/
  providers/{stalenhag,bing,apod,wikimedia}_test.dart   (+ fixtures/ dir)
  services/{image_fitter,potd_service,wallpaper_repo}_test.dart
  ui/home_screen_test.dart
.github/workflows/
  verify.yml
  release.yml
```

## 9. Testing strategy

| Layer | Test type | Key cases |
|---|---|---|
| Providers | unit + fixtures | parse success, parse-empty → failure, metadata extraction, day rotation determinism |
| ImageFitter | unit | crop rect math (landscape→portrait, square→wide), as-is passthrough, blur-pad compositing dimensions |
| WallpaperRepo | unit (temp dirs) | save/load roundtrip, ring trim at 14, settings defaults, stale detection |
| PotdService | unit (fake provider/api) | happy path, fetch-fail keeps wallpaper, dedupe, stale alarm fires at >3d |
| HomeScreen | widget | renders chips + today's item from faked service |
| End-to-end | emulator + adb (agentic) | set home/lock/both; reboot; overnight doze; airplane mode recovery; Wi-Fi-only respected; stale notification |

## 10. Emulator QA via adb (pre-release)

End-to-end scenarios unit/widget tests can't reach are verified **agentically** on an
Android emulator (`emulator` + `adb`) — the agent drives install, input, and device
state, then asserts outcomes. Complex scenarios (doze, clock shifts) use adb device
controls:

| Control | adb mechanism |
|---|---|
| Install / launch | `adb install`, `adb shell am start` |
| Reboot | `adb reboot` (then wait-for-device) |
| Network kill/restore | `adb shell svc wifi disable/enable`, `svc data` or emulator console `network speed 0` |
| Clock shift (stale test) | `adb root && adb shell date @<epoch>` (Google APIs emulator image) |
| Doze | `adb shell dumpsys deviceidle force-idle` / `step` |
| Assert wallpaper changed | `adb shell dumpsys wallpaper` bitmap dims changed + app cache/logcat markers |

```
□ fresh install → first run sets today's wallpaper without interaction beyond launch
□ home + lock + both modes each apply correctly
□ reboot: next day's change still happens
□ airplane mode at job time: wallpaper preserved, applies when back online
□ provider switch takes effect next refresh
□ stale provider (point at bad URL) triggers notification after 3 days (clock-shifted via adb)
□ APK from CI installs over previous release version (signature check)
```

These scenarios run as scripted agent sessions before each tagged release; outcomes are
recorded in the release notes commit.
