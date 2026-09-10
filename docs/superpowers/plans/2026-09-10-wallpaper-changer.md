# Wallpaper Changer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Flutter Android app that automatically changes the device wallpaper daily from four KDE-POTD-style sources (Simon Stålenhag, Bing, NASA APOD, Wikimedia POTD).

**Architecture:** On-device only. A `PotdService` orchestrates provider fetch → image fit → platform-channel wallpaper set → cache. A WorkManager periodic job drives it daily; the single-screen UI exists for configuration and preview. Providers are fixture-tested; orchestration is fake-tested; end-to-end runs on an emulator via adb.

**Tech Stack:** Flutter 3.47 (stable) at `~/flutter/flutter`, Android SDK at `~/Android/Sdk` (AVD `test_device`), pub packages `http`, `image`, `path_provider`, `workmanager`, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-10-wallpaper-changer-design.md`

**Environment note:** Flutter/adb/emulator are installed but not on PATH. Task 0 fixes this once; all later tasks assume `flutter`, `adb`, `emulator` resolve.

---

## File structure map

```
lib/
  models/potd_item.dart        ← PotdMeta, PotdItem                    (Task 3)
  models/settings.dart         ← Settings, ScreenTarget, FitMode       (Task 4)
  providers/provider.dart      ← ProviderId, PotdProvider, PotdException (Task 3)
  providers/stalenhag.dart     ← StalenhagProvider                     (Task 6)
  providers/bing.dart          ← BingProvider                          (Task 7)
  providers/apod.dart          ← ApodProvider                          (Task 8)
  providers/wikimedia.dart     ← WikimediaProvider                     (Task 9)
  providers/provider_factory.dart ← defaultProviderFor                (Task 6)
  services/wallpaper_repo.dart ← WallpaperRepo, HistoryEntry           (Tasks 4-5)
  services/image_fitter.dart   ← ImageFitter                           (Task 10)
  services/potd_service.dart   ← PotdService, RunOutcome               (Task 12)
  platform/wallpaper_api.dart  ← WallpaperApi + MethodChannel impl     (Task 11)
  ui/home_screen.dart          ← HomeScreen                            (Task 14)
  background.dart              ← WorkManager callbackDispatcher        (Task 14)
  main.dart                    ← app entry, task registration          (Task 14)
android/app/src/main/kotlin/dev/gift/wallpaper_changer/MainActivity.kt  (Task 13)
android/app/src/main/AndroidManifest.xml                                (Task 13)
android/app/build.gradle.kts                                           (Task 15)
.github/workflows/verify.yml                                           (Task 2)
.github/workflows/release.yml                                          (Task 15)
test/                                                                  (per task)
test/fixtures/                                                         (Tasks 6-9)
```

---

### Task 0: Toolchain PATH

**Files:**
- Modify: `~/.bashrc` (append export line)

- [ ] **Step 1: Add SDK paths to ~/.bashrc if missing**

```bash
grep -q 'flutter/flutter/bin' ~/.bashrc || cat >> ~/.bashrc <<'EOF'
export PATH="$HOME/flutter/flutter/bin:$HOME/Android/Sdk/platform-tools:$HOME/Android/Sdk/emulator:$PATH"
EOF
```

- [ ] **Step 2: Verify in a fresh shell**

Run: `bash -lc 'flutter --version && adb version | head -1 && emulator -list-avds'`
Expected: Flutter 3.47.2, adb 1.0.41, `test_device`

---

### Task 1: Scaffold Flutter project

**Files:**
- Create: Flutter template (`lib/main.dart`, `android/`, `pubspec.yaml`, `test/widget_test.dart`)

- [ ] **Step 1: Create project (android only)**

Run: `flutter create --org dev.gift --project-name wallpaper_changer --platforms android .`
Expected: `...Created project wallpaper_changer...`

- [ ] **Step 2: Add dependencies**

Run: `flutter pub add http image path_provider workmanager`
Expected: version numbers printed, exit 0

- [ ] **Step 3: Verify analyze + tests pass on template**

Run: `flutter analyze && flutter test`
Expected: `No issues found!` / `All tests passed!`

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "chore: scaffold flutter app with core deps"
```

---

### Task 2: CI verify workflow

**Files:**
- Create: `.github/workflows/verify.yml`

- [ ] **Step 1: Write workflow**

```yaml
name: verify
on:
  push:
    branches: [main]
  pull_request:
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
      - run: flutter pub get
      - run: flutter analyze
      - run: flutter test
```

- [ ] **Step 2: Validate YAML locally**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/verify.yml'))" && echo OK`
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add .github && git commit -m "ci: verify workflow (analyze + test)"
```

---

### Task 3: PotdItem model + provider interface

**Files:**
- Create: `lib/models/potd_item.dart`
- Create: `lib/providers/provider.dart`
- Test: `test/providers/provider_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wallpaper_changer/models/potd_item.dart';
import 'package:wallpaper_changer/providers/provider.dart';

void main() {
  test('PotdMeta and PotdItem hold their values', () {
    final meta = PotdMeta(
      title: 'T', author: 'A', infoUrl: 'https://i', imageUrl: 'https://img',
    );
    final item = PotdItem(meta: meta, bytes: [1, 2, 3]);
    expect(item.meta.title, 'T');
    expect(item.bytes, [1, 2, 3]);
  });

  test('PotdException exposes reason', () {
    expect(const PotdException('no images').toString(), contains('no images'));
  });

  test('ProviderId covers all four sources', () {
    expect(ProviderId.values.map((e) => e.name),
        ['stalenhag', 'bing', 'apod', 'wikimedia']);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/providers/provider_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'wallpaper_changer'`

- [ ] **Step 3: Write lib/models/potd_item.dart**

```dart
import 'dart:typed_data';

class PotdMeta {
  final String title;
  final String author;
  final String infoUrl;
  final String imageUrl;

  const PotdMeta({
    required this.title,
    required this.author,
    required this.infoUrl,
    required this.imageUrl,
  });
}

class PotdItem {
  final PotdMeta meta;
  final Uint8List bytes;

  const PotdItem({required this.meta, required this.bytes});
}
```

- [ ] **Step 4: Write lib/providers/provider.dart**

```dart
import '../models/potd_item.dart';

enum ProviderId { stalenhag, bing, apod, wikimedia }

abstract class PotdProvider {
  String get id;
  String get label;
  Future<PotdItem> fetch();
}

class PotdException implements Exception {
  final String reason;
  const PotdException(this.reason);

  @override
  String toString() => 'PotdException: $reason';
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/providers/provider_test.dart`
Expected: PASS (3 tests)

- [ ] **Step 6: Commit**

```bash
git add lib/models lib/providers test/providers && git commit -m "feat: potd item model and provider interface"
```

---

### Task 4: Settings model + repo persistence

**Files:**
- Create: `lib/models/settings.dart`
- Create: `lib/services/wallpaper_repo.dart` (settings part only)
- Test: `test/services/wallpaper_repo_test.dart`

- [ ] **Step 1: Write the failing test (settings defaults + roundtrip)**

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallpaper_changer/models/settings.dart';
import 'package:wallpaper_changer/providers/provider.dart';
import 'package:wallpaper_changer/services/wallpaper_repo.dart';

void main() {
  late Directory tmp;
  late WallpaperRepo repo;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('repo_test');
    repo = WallpaperRepo(tmp);
  });
  tearDown(() async => tmp.deleteSync(recursive: true));

  test('defaults when no settings file exists', () {
    final s = repo.loadSettings();
    expect(s.providerId, ProviderId.stalenhag);
    expect(s.screens, {ScreenTarget.home, ScreenTarget.lock});
    expect(s.fitMode, FitMode.centerCrop);
    expect(s.wifiOnly, isTrue);
  });

  test('settings roundtrip survives reload', () async {
    final s = Settings(
      providerId: ProviderId.apod,
      screens: {ScreenTarget.lock},
      fitMode: FitMode.asIs,
      wifiOnly: false,
    );
    await repo.saveSettings(s);
    expect(repo.loadSettings(), s);
  });

  test('missing keys fall back to defaults (forward compatibility)', () {
    File('${tmp.path}/settings.json').writeAsString('{}');
    expect(repo.loadSettings().providerId, ProviderId.stalenhag);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/wallpaper_repo_test.dart`
Expected: FAIL — package `settings.dart` not found

- [ ] **Step 3: Write lib/models/settings.dart**

```dart
import '../providers/provider.dart';

enum ScreenTarget { home, lock }

enum FitMode { centerCrop, asIs, blurPad }

class Settings {
  final ProviderId providerId;
  final Set<ScreenTarget> screens;
  final FitMode fitMode;
  final bool wifiOnly;

  const Settings({
    this.providerId = ProviderId.stalenhag,
    this.screens = const {ScreenTarget.home, ScreenTarget.lock},
    this.fitMode = FitMode.centerCrop,
    this.wifiOnly = true,
  });

  Settings copyWith({
    ProviderId? providerId,
    Set<ScreenTarget>? screens,
    FitMode? fitMode,
    bool? wifiOnly,
  }) =>
      Settings(
        providerId: providerId ?? this.providerId,
        screens: screens ?? this.screens,
        fitMode: fitMode ?? this.fitMode,
        wifiOnly: wifiOnly ?? this.wifiOnly,
      );

  Map<String, dynamic> toJson() => {
        'providerId': providerId.name,
        'screens': screens.map((s) => s.name).toList(),
        'fitMode': fitMode.name,
        'wifiOnly': wifiOnly,
      };

  factory Settings.fromJson(Map<String, dynamic> json) {
    ProviderId? pid;
    for (final p in ProviderId.values) {
      if (p.name == json['providerId']) pid = p;
    }
    final screens = <ScreenTarget>{
      for (final name in (json['screens'] as List<String>? ?? const []))
        for (final s in ScreenTarget.values)
          if (s.name == name) s,
    };
    FitMode? fit;
    for (final f in FitMode.values) {
      if (f.name == json['fitMode']) fit = f;
    }
    return Settings(
      providerId: pid ?? ProviderId.stalenhag,
      screens: screens.isEmpty ? const {ScreenTarget.home, ScreenTarget.lock} : screens,
      fitMode: fit ?? FitMode.centerCrop,
      wifiOnly: json['wifiOnly'] as bool? ?? true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Settings &&
      other.providerId == providerId &&
      other.screens.length == screens.length &&
      other.screens.containsAll(screens) &&
      other.fitMode == fitMode &&
      other.wifiOnly == wifiOnly;

  @override
  int get hashCode =>
      Object.hash(providerId, screens.length, fitMode, wifiOnly);
}
```

- [ ] **Step 4: Write lib/services/wallpaper_repo.dart (settings part)**

```dart
import 'dart:convert';
import 'dart:io';

import '../models/settings.dart';

class WallpaperRepo {
  final Directory baseDir;

  WallpaperRepo(this.baseDir);

  File get _settingsFile => File('${baseDir.path}/settings.json');

  Settings loadSettings() {
    if (!_settingsFile.existsSync()) return const Settings();
    try {
      final json =
          jsonDecode(_settingsFile.readAsStringSync()) as Map<String, dynamic>;
      return Settings.fromJson(json);
    } catch (_) {
      return const Settings();
    }
  }

  Future<void> saveSettings(Settings settings) async {
    await _settingsFile.writeAsString(jsonEncode(settings.toJson()));
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/services/wallpaper_repo_test.dart`
Expected: PASS (3 tests)

- [ ] **Step 6: Commit**

```bash
git add lib/models/settings.dart lib/services/wallpaper_repo.dart test/services && git commit -m "feat: settings model with json persistence"
```

---

### Task 5: Repo current item, history ring, staleness

**Files:**
- Modify: `lib/services/wallpaper_repo.dart`
- Test: `test/services/wallpaper_repo_test.dart` (append)

- [ ] **Step 1: Append failing tests**

```dart
// append inside main() — new group + needed import at top of file:
// import 'package:wallpaper_changer/models/potd_item.dart';
  group('current + history', () {
    PotdItem item(String url) => PotdItem(
          meta: PotdMeta(
              title: 'T', author: 'A', infoUrl: 'https://i', imageUrl: url),
          bytes: [1, 2, 3],
        );

    test('saveCurrent persists meta + appliedAt + image, load roundtrips', () async {
      final at = DateTime(2026, 9, 10, 6, 30);
      await repo.saveCurrent(item: item('https://img/1.jpg'), appliedAt: at);
      expect(repo.loadCurrentMeta()?.imageUrl, 'https://img/1.jpg');
      expect(repo.currentAppliedAt(), at);
      expect(repo.loadHistory().length, 1);
      expect(repo.loadHistory().first.imageFile.existsSync(), isTrue);
    });

    test('history ring trims to 14 newest', () async {
      for (var i = 0; i < 16; i++) {
        await repo.saveCurrent(
          item: item('https://img/$i.jpg'),
          appliedAt: DateTime(2026, 9, 1).add(Duration(minutes: i)),
        );
      }
      final h = repo.loadHistory();
      expect(h.length, 14);
      expect(h.first.meta.imageUrl, 'https://img/15.jpg'); // newest first
      expect(h.last.meta.imageUrl, 'https://img/2.jpg');
    });

    test('isStale true only after 3 days', () async {
      final at = DateTime(2026, 9, 1);
      await repo.saveCurrent(item: item('https://img/1.jpg'), appliedAt: at);
      expect(repo.isStale(DateTime(2026, 9, 3, 23)), isFalse);
      expect(repo.isStale(DateTime(2026, 9, 5)), isTrue);
    });

    test('isStale false when nothing applied yet', () {
      expect(repo.isStale(DateTime(2026, 9, 10)), isFalse);
    });
  });
```

- [ ] **Step 2: Run tests to verify the new ones fail**

Run: `flutter test test/services/wallpaper_repo_test.dart`
Expected: FAIL — `saveCurrent` not defined

- [ ] **Step 3: Extend WallpaperRepo**

Append inside `class WallpaperRepo` (plus imports `../models/potd_item.dart` and `package:path/path.dart` as p):

```dart
  File get _currentFile => File('${baseDir.path}/current.json');
  Directory get _historyDir => Directory('${baseDir.path}/history');

  Future<void> saveCurrent(
      {required PotdItem item, required DateTime appliedAt}) async {
    _historyDir.createSync(recursive: true);
    final stamp = appliedAt
        .toIso8601String()
        .replaceAll(RegExp(r'[-:]'), '')
        .split('.')
        .first; // 20260910T063000
    await File('${_historyDir.path}/$stamp.jpg').writeAsBytes(item.bytes);
    final entry = {
      ..._metaJson(item.meta),
      'appliedAt': appliedAt.toIso8601String(),
    };
    await File('${_historyDir.path}/$stamp.json')
        .writeAsString(jsonEncode(entry));
    await _currentFile.writeAsString(jsonEncode(entry));
    _trimHistory(14);
  }

  Map<String, dynamic> _metaJson(PotdMeta m) => {
        'title': m.title,
        'author': m.author,
        'infoUrl': m.infoUrl,
        'imageUrl': m.imageUrl,
      };

  PotdMeta? _metaFromJson(Map<String, dynamic> j) => PotdMeta(
        title: j['title'] as String? ?? '',
        author: j['author'] as String? ?? '',
        infoUrl: j['infoUrl'] as String? ?? '',
        imageUrl: j['imageUrl'] as String? ?? '',
      );

  PotdMeta? loadCurrentMeta() {
    if (!_currentFile.existsSync()) return null;
    try {
      return _metaFromJson(
          jsonDecode(_currentFile.readAsStringSync()) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  DateTime? currentAppliedAt() {
    if (!_currentFile.existsSync()) return null;
    try {
      final j =
          jsonDecode(_currentFile.readAsStringSync()) as Map<String, dynamic>;
      return DateTime.parse(j['appliedAt'] as String);
    } catch (_) {
      return null;
    }
  }

  List<HistoryEntry> loadHistory() {
    if (!_historyDir.existsSync()) return const [];
    final entries = <HistoryEntry>[];
    for (final f in _historyDir.listSync()) {
      if (!f.path.endsWith('.json')) continue;
      try {
        final j = jsonDecode(File(f.path).readAsStringSync()) as Map<String, dynamic>;
        entries.add(HistoryEntry(
          meta: _metaFromJson(j),
          imageFile: File(f.path.replaceFirst(RegExp(r'\.json$'), '.jpg')),
          appliedAt: DateTime.parse(j['appliedAt'] as String),
        ));
      } catch (_) {/* skip corrupt entries */
      }
    }
    entries.sort((a, b) => b.appliedAt.compareTo(a.appliedAt));
    return entries;
  }

  void _trimHistory(int keep) {
    final sidecars = _historyDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    for (final f in sidecars.skip(keep)) {
      File(f.path.replaceFirst(RegExp(r'\.json$'), '.jpg'))
          .deleteSync(strict: false);
      f.deleteSync(strict: false);
    }
  }

  bool isStale(DateTime now, {int days = 3}) {
    final at = currentAppliedAt();
    if (at == null) return false;
    return now.difference(at).inDays >= days;
  }
```

And at the bottom of the file:

```dart
class HistoryEntry {
  final PotdMeta meta;
  final File imageFile;
  final DateTime appliedAt;

  const HistoryEntry(
      {required this.meta, required this.imageFile, required this.appliedAt});
}
```

Add `path: ^1.9.0` only if the import is used; the code above does not need it — skip that import.

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/services/wallpaper_repo_test.dart`
Expected: PASS (7 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/services/wallpaper_repo.dart test/services/wallpaper_repo_test.dart && git commit -m "feat: repo current-item tracking, history ring, staleness"
```

---

### Task 6: Stålenhag provider

**Files:**
- Create: `lib/providers/stalenhag.dart`
- Create: `lib/providers/provider_factory.dart`
- Create: `test/fixtures/stalenhag.html`
- Test: `test/providers/stalenhag_test.dart`

- [ ] **Step 1: Create fixture test/fixtures/stalenhag.html**

```html
<!DOCTYPE html>
<html>
<head><title>Simon Stalenhag</title></head>
<body>
<a href="css/stylesheet.css">css</a>
<a href="4k/svema_01_big.jpg"><img src="4k/svema_01.jpg" alt=""></a>
<a href="4k/svema_02_big.jpg"><img src="4k/svema_02.jpg" alt=""></a>
<a href="4k/svema_01_big.jpg"><img src="4k/svema_01.jpg" alt=""></a>
<a href="4k/labyrinth_03_big.jpg"></a>
<a href="https://www.redbubble.com/people/simonstalenhag">shop</a>
<a href="4k/es_01_big.jpg"></a>
<img src="4k/tftf_07.jpg">
<a href="4k/tftf_07_big.jpg"></a>
</body>
</html>
```

Unique `_big.jpg` links in order: `svema_01, svema_02, labyrinth_03, es_01, tftf_07` (5 links).

- [ ] **Step 2: Write the failing test**

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wallpaper_changer/providers/provider.dart';
import 'package:wallpaper_changer/providers/stalenhag.dart';

const fixtureHtml = 'test/fixtures/stalenhag.html';

http.Client clientThat(String html) => MockClient((req) async {
      if (req.url.path.endsWith('.jpg')) {
        return http.Response.bytes([9, 9, 9], 200);
      }
      return http.Response(html, 200);
    });

void main() {
  test('fetch returns item with metadata and bytes', () async {
    final html = await File(fixtureHtml).readAsString();
    final p = StalenhagProvider(
        client: clientThat(html), now: () => DateTime(2026, 9, 10));
    final item = await p.fetch();
    expect(item.bytes, [9, 9, 9]);
    expect(item.meta.author, 'Simon Stalenhag');
    expect(item.meta.imageUrl,
        startsWith('https://www.simonstalenhag.se/4k/'));
    expect(item.meta.imageUrl, endsWith('_big.jpg'));
    expect(item.meta.title, contains('svema_'));
  });

  test('rotation is day-deterministic over the link list', () async {
    final html = await File(fixtureHtml).readAsString();
    // 5 links: doy(2026-09-10) = 252 (0-based 253-1=252... computed by code);
    // day index = now - Jan 1 in days
    final picked = <String>[];
    for (final day in [DateTime(2026, 1, 1), DateTime(2026, 1, 2), DateTime(2026, 1, 6)]) {
      final p = StalenhagProvider(client: clientThat(html), now: () => day);
      picked.add((await p.fetch()).meta.imageUrl);
    }
    expect(picked[0], contains('svema_01')); // day 0
    expect(picked[1], contains('svema_02')); // day 1
    expect(picked[2], contains('svema_01')); // day 5 % 5 == 0
  });

  test('html without image links throws PotdException', () async {
    final p = StalenhagProvider(
        client: clientThat('<html><body>redesign</body></html>'),
        now: () => DateTime(2026, 9, 10));
    await expectLater(p.fetch(), throwsA(isA<PotdException>()));
  });

  test('non-200 homepage throws PotdException', () async {
    final p = StalenhagProvider(
        client: MockClient((req) async => http.Response('oops', 500)),
        now: () => DateTime(2026, 9, 10));
    await expectLater(p.fetch(), throwsA(isA<PotdException>()));
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/providers/stalenhag_test.dart`
Expected: FAIL — `stalenhag.dart` not found

- [ ] **Step 4: Write lib/providers/stalenhag.dart**

```dart
import 'package:http/http.dart' as http;

import '../models/potd_item.dart';
import 'provider.dart';

class StalenhagProvider implements PotdProvider {
  final http.Client _client;
  final DateTime Function() _now;
  static const String baseUrl = 'https://www.simonstalenhag.se';

  StalenhagProvider({http.Client? client, DateTime Function()? now})
      : _client = client ?? http.Client(),
        _now = now ?? DateTime.now;

  @override
  String get id => ProviderId.stalenhag.name;

  @override
  String get label => 'Simon Stålenhag';

  @override
  Future<PotdItem> fetch() async {
    final res = await _client.get(Uri.parse('$baseUrl/'));
    if (res.statusCode != 200) {
      throw PotdException('homepage http ${res.statusCode}');
    }
    final links = extractImagePaths(res.body);
    if (links.isEmpty) throw const PotdException('no images found in html');
    final dayIndex = _now().difference(DateTime(_now().year, 1, 1)).inDays;
    final path = links[dayIndex % links.length];
    final imageUrl = '$baseUrl/$path';
    final imgRes = await _client.get(Uri.parse(imageUrl));
    if (imgRes.statusCode != 200 || imgRes.bodyBytes.isEmpty) {
      throw PotdException('image http ${imgRes.statusCode}');
    }
    final name = path
        .split('/')
        .last
        .replaceFirst(RegExp(r'_big\.jpg$'), '');
    return PotdItem(
      meta: PotdMeta(
        title: 'Simon Stålenhag — $name',
        author: 'Simon Stålenhag',
        infoUrl: baseUrl,
        imageUrl: imageUrl,
      ),
      bytes: imgRes.bodyBytes,
    );
  }

  /// Ordered, de-duplicated `4k/xxx_big.jpg` paths from the homepage html.
  static List<String> extractImagePaths(String html) {
    final re = RegExp(r'(?:href|src)="(4k/[A-Za-z0-9_]+_big\.jpg)"');
    return re.allMatches(html).map((m) => m.group(1)!).toSet().toList();
  }
}
```

- [ ] **Step 5: Write lib/providers/provider_factory.dart**

```dart
import 'package:http/http.dart' as http;

import 'apod.dart';
import 'bing.dart';
import 'provider.dart';
import 'stalenhag.dart';
import 'wikimedia.dart';

PotdProvider defaultProviderFor(ProviderId id,
    {http.Client? client, DateTime Function()? now}) {
  switch (id) {
    case ProviderId.stalenhag:
      return StalenhagProvider(client: client, now: now);
    case ProviderId.bing:
      return BingProvider(client: client);
    case ProviderId.apod:
      return ApodProvider(client: client);
    case ProviderId.wikimedia:
      return WikimediaProvider(client: client, now: now);
  }
}
```

(Compile will fail until Tasks 7-9 add the three providers — expected; Step 7 below commits after the compile passes at the end of Task 9. Alternative: commit Task 6 with the factory referencing only Stålenhag and extend in later tasks. **Do that instead** — factory starts as:)

```dart
import 'package:http/http.dart' as http;

import 'provider.dart';
import 'stalenhag.dart';

PotdProvider defaultProviderFor(ProviderId id,
    {http.Client? client, DateTime Function()? now}) {
  switch (id) {
    case ProviderId.stalenhag:
      return StalenhagProvider(client: client, now: now);
    case ProviderId.bing:
    case ProviderId.apod:
    case ProviderId.wikimedia:
      throw UnimplementedError('added in later tasks');
  }
}
```

- [ ] **Step 6: Run tests**

Run: `flutter test test/providers/stalenhag_test.dart && flutter analyze`
Expected: PASS (4 tests), `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add lib/providers test/providers && git commit -m "feat: stalenhag provider with day rotation"
```

---

### Task 7: Bing provider

**Files:**
- Create: `lib/providers/bing.dart`
- Create: `test/fixtures/bing.json`
- Modify: `lib/providers/provider_factory.dart`
- Test: `test/providers/bing_test.dart`

- [ ] **Step 1: Create fixture test/fixtures/bing.json**

```json
{
  "images": [
    {
      "startdate": "20260910",
      "url": "/th?id=OHR.TestHill_EN-US1234_UHD.jpg&rf=LaDigue_UHD.jpg&pid=hp",
      "urlbase": "/th?id=OHR.TestHill_EN-US1234",
      "copyright": "Test Hill somewhere nice (© Photographer)",
      "copyrightlink": "/search?q=test",
      "title": "Test Hill",
      "quiz": "/search?q=Quiz+Test"
    }
  ]
}
```

- [ ] **Step 2: Write the failing test**

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wallpaper_changer/providers/bing.dart';
import 'package:wallpaper_changer/providers/provider.dart';

void main() {
  http.Client clientFor(String body, {int code = 200}) => MockClient((req) async {
        if (req.url.path.contains('_UHD.jpg')) {
          return http.Response.bytes([7, 7], 200);
        }
        return http.Response(body, code);
      });

  test('fetch builds UHD url from urlbase and extracts metadata', () async {
    final body = await File('test/fixtures/bing.json').readAsString();
    final p = BingProvider(client: clientFor(body));
    final item = await p.fetch();
    expect(item.meta.imageUrl,
        'https://www.bing.com/th?id=OHR.TestHill_EN-US1234_UHD.jpg');
    expect(item.meta.title, 'Test Hill');
    expect(item.meta.author, contains('Photographer'));
    expect(item.bytes, [7, 7]);
  });

  test('empty images array throws PotdException', () async {
    final p = BingProvider(client: clientFor('{"images":[]}'));
    await expectLater(p.fetch(), throwsA(isA<PotdException>()));
  });

  test('malformed json throws PotdException', () async {
    final p = BingProvider(client: clientFor('<html>blocked</html>'));
    await expectLater(p.fetch(), throwsA(isA<PotdException>()));
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/providers/bing_test.dart`
Expected: FAIL — `bing.dart` not found

- [ ] **Step 4: Write lib/providers/bing.dart**

```dart
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/potd_item.dart';
import 'provider.dart';

class BingProvider implements PotdProvider {
  final http.Client _client;

  static const String archiveUrl =
      'https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=1&mkt=en-US';

  BingProvider({http.Client? client}) : _client = client ?? http.Client();

  @override
  String get id => ProviderId.bing.name;

  @override
  String get label => 'Bing';

  @override
  Future<PotdItem> fetch() async {
    final res = await _client.get(Uri.parse(archiveUrl));
    if (res.statusCode != 200) {
      throw PotdException('archive http ${res.statusCode}');
    }
    Map<String, dynamic> data;
    try {
      data = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw const PotdException('archive response not json');
    }
    final images = data['images'];
    if (images is! List || images.isEmpty) {
      throw const PotdException('archive has no images');
    }
    final img = images.first as Map<String, dynamic>;
    final urlBase = img['urlbase'];
    if (urlBase is! String || urlBase.isEmpty) {
      throw const PotdException('archive entry missing urlbase');
    }
    final imageUrl = 'https://www.bing.com${urlBase}_UHD.jpg';
    final imgRes = await _client.get(Uri.parse(imageUrl));
    if (imgRes.statusCode != 200 || imgRes.bodyBytes.isEmpty) {
      throw PotdException('image http ${imgRes.statusCode}');
    }
    return PotdItem(
      meta: PotdMeta(
        title: (img['title'] as String?) ?? 'Bing image of the day',
        author: (img['copyright'] as String?) ?? '',
        infoUrl: 'https://www.bing.com/',
        imageUrl: imageUrl,
      ),
      bytes: imgRes.bodyBytes,
    );
  }
}
```

- [ ] **Step 5: Wire into provider_factory.dart**

Replace the `ProviderId.bing` case:

```dart
    case ProviderId.bing:
      return BingProvider(client: client);
```

(and add `import 'bing.dart';`)

- [ ] **Step 6: Run tests + analyze**

Run: `flutter test test/providers && flutter analyze`
Expected: PASS, no issues

- [ ] **Step 7: Commit**

```bash
git add lib/providers/bing.dart lib/providers/provider_factory.dart test && git commit -m "feat: bing provider"
```

---

### Task 8: NASA APOD provider

**Files:**
- Create: `lib/providers/apod.dart`
- Create: `test/fixtures/apod.json`
- Create: `test/fixtures/apod_video.json`
- Modify: `lib/providers/provider_factory.dart`
- Test: `test/providers/apod_test.dart`

- [ ] **Step 1: Create fixtures**

`test/fixtures/apod.json`:

```json
{
  "date": "2026-09-10",
  "explanation": "A test nebula in the sky.",
  "media_type": "image",
  "title": "The Test Nebula",
  "url": "https://apod.nasa.gov/apod/image/2609/test_nebula.jpg",
  "hdurl": "https://apod.nasa.gov/apod/image/2609/test_nebula_big.jpg",
  "copyright": "Hubble Heritage Team (NASA)"
}
```

`test/fixtures/apod_video.json`:

```json
{
  "date": "2026-09-10",
  "media_type": "video",
  "title": "A Video Day",
  "url": "https://www.youtube.com/embed/xyz"
}
```

- [ ] **Step 2: Write the failing test**

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wallpaper_changer/providers/apod.dart';
import 'package:wallpaper_changer/providers/provider.dart';

void main() {
  http.Client clientFor(String body) => MockClient((req) async {
        if (req.url.host == 'apod.nasa.gov' &&
            req.url.path.endsWith('.jpg')) {
          return http.Response.bytes([5, 5], 200);
        }
        return http.Response(body, 200);
      });

  test('fetch extracts metadata and builds info url from date', () async {
    final body = await File('test/fixtures/apod.json').readAsString();
    final item = await ApodProvider(client: clientFor(body)).fetch();
    expect(item.meta.title, 'The Test Nebula');
    expect(item.meta.author, 'Hubble Heritage Team (NASA)');
    expect(item.meta.infoUrl, 'https://apod.nasa.gov/apod/ap260910.html');
    expect(item.meta.imageUrl,
        'https://apod.nasa.gov/apod/image/2609/test_nebula.jpg');
    expect(item.bytes, [5, 5]);
  });

  test('video day throws PotdException', () async {
    final body = await File('test/fixtures/apod_video.json').readAsString();
    await expectLater(ApodProvider(client: clientFor(body)).fetch(),
        throwsA(isA<PotdException>()));
  });

  test('non-200 throws PotdException', () async {
    final p = ApodProvider(
        client: MockClient((req) async => http.Response('rate limited', 429)));
    await expectLater(p.fetch(), throwsA(isA<PotdException>()));
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/providers/apod_test.dart`
Expected: FAIL — `apod.dart` not found

- [ ] **Step 4: Write lib/providers/apod.dart**

```dart
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/potd_item.dart';
import 'provider.dart';

class ApodProvider implements PotdProvider {
  final http.Client _client;

  static const String apiUrl =
      'https://api.nasa.gov/planetary/apod?api_key=DEMO_KEY';

  ApodProvider({http.Client? client}) : _client = client ?? http.Client();

  @override
  String get id => ProviderId.apod.name;

  @override
  String get label => 'NASA APOD';

  @override
  Future<PotdItem> fetch() async {
    final res = await _client.get(Uri.parse(apiUrl));
    if (res.statusCode != 200) {
      throw PotdException('apod http ${res.statusCode}');
    }
    Map<String, dynamic> data;
    try {
      data = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw const PotdException('apod response not json');
    }
    if (data['media_type'] != 'image') {
      throw const PotdException('apod media is not an image');
    }
    final url = data['url'];
    if (url is! String || url.isEmpty) {
      throw const PotdException('apod missing image url');
    }
    final imgRes = await _client.get(Uri.parse(url));
    if (imgRes.statusCode != 200 || imgRes.bodyBytes.isEmpty) {
      throw PotdException('apod image http ${imgRes.statusCode}');
    }
    final date = (data['date'] as String?) ?? '';
    final yymmdd = date.length == 10
        ? '${date.substring(2, 4)}${date.substring(5, 7)}${date.substring(8, 10)}'
        : '';
    return PotdItem(
      meta: PotdMeta(
        title: (data['title'] as String?) ?? 'APOD',
        author: (data['copyright'] as String?) ?? '',
        infoUrl: yymmdd.isEmpty
            ? 'https://apod.nasa.gov/apod/'
            : 'https://apod.nasa.gov/apod/ap$yymmdd.html',
        imageUrl: url,
      ),
      bytes: imgRes.bodyBytes,
    );
  }
}
```

- [ ] **Step 5: Wire into provider_factory.dart**

Replace the `ProviderId.apod` case with `return ApodProvider(client: client);` and add `import 'apod.dart';`

- [ ] **Step 6: Run tests + analyze**

Run: `flutter test test/providers && flutter analyze`
Expected: PASS, no issues

- [ ] **Step 7: Commit**

```bash
git add lib/providers/apod.dart lib/providers/provider_factory.dart test && git commit -m "feat: nasa apod provider"
```

---

### Task 9: Wikimedia POTD provider

**Files:**
- Create: `lib/providers/wikimedia.dart`
- Create: `test/fixtures/wikimedia.json`
- Create: `test/fixtures/wikimedia_video.json`
- Modify: `lib/providers/provider_factory.dart`
- Test: `test/providers/wikimedia_test.dart`

- [ ] **Step 1: Create fixtures**

`test/fixtures/wikimedia.json`:

```json
{
  "tfa": {},
  "mostread": {},
  "image": {
    "title": "File:Some Place.jpg",
    "thumbnail": {
      "source": "https://upload.wikimedia.org/wikipedia/commons/thumb/a/ab/Some_Place.jpg/640px-Some_Place.jpg",
      "width": 640,
      "height": 427
    },
    "image": {
      "source": "https://upload.wikimedia.org/wikipedia/commons/a/ab/Some_Place.jpg",
      "width": 4000,
      "height": 2667
    },
    "file_page": "https://commons.wikimedia.org/wiki/File:Some_Place.jpg",
    "artist": {
      "html": "<a href=\"https://example.com/p\" >Photo Person</a>"
    }
  },
  "news": []
}
```

`test/fixtures/wikimedia_video.json`: same shape but with
`"image": {"title": "File:Clip.webm", "image": {"source": "https://upload.wikimedia.org/.../Clip.webm"}, ...}`

- [ ] **Step 2: Write the failing test**

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wallpaper_changer/providers/provider.dart';
import 'package:wallpaper_changer/providers/wikimedia.dart';

void main() {
  http.Client clientFor(String body) => MockClient((req) async {
        if (req.url.path.toLowerCase().endsWith('.jpg')) {
          return http.Response.bytes([3, 3], 200);
        }
        return http.Response(body, 200);
      });

  test('fetch extracts full-size source, title, artist, file page', () async {
    final body = await File('test/fixtures/wikimedia.json').readAsString();
    final item = await WikimediaProvider(
        client: clientFor(body), now: () => DateTime(2026, 9, 10)).fetch();
    expect(item.meta.imageUrl,
        'https://upload.wikimedia.org/wikipedia/commons/a/ab/Some_Place.jpg');
    expect(item.meta.title, 'Some Place.jpg');
    expect(item.meta.author, 'Photo Person');
    expect(item.meta.infoUrl, 'https://commons.wikimedia.org/wiki/File:Some_Place.jpg');
    expect(item.bytes, [3, 3]);
  });

  test('uses today date in endpoint url', () async {
    Uri? seen;
    final p = WikimediaProvider(
      client: MockClient((req) async {
        seen = req.url;
        return http.Response(
            await File('test/fixtures/wikimedia.json').readAsString(), 200);
      }),
      now: () => DateTime(2026, 9, 10),
    );
    await p.fetch();
    expect(seen!.path, contains('/feed/featured/2026/09/10'));
  });

  test('video day throws PotdException', () async {
    final body = await File('test/fixtures/wikimedia_video.json').readAsString();
    await expectLater(
        WikimediaProvider(
                client: clientFor(body), now: () => DateTime(2026, 9, 10))
            .fetch(),
        throwsA(isA<PotdException>()));
  });

  test('missing image object throws PotdException', () async {
    final p = WikimediaProvider(
        client: clientFor('{"tfa":{}}'), now: () => DateTime(2026, 9, 10));
    await expectLater(p.fetch(), throwsA(isA<PotdException>()));
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/providers/wikimedia_test.dart`
Expected: FAIL — `wikimedia.dart` not found

- [ ] **Step 4: Write lib/providers/wikimedia.dart**

```dart
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/potd_item.dart';
import 'provider.dart';

class WikimediaProvider implements PotdProvider {
  final http.Client _client;
  final DateTime Function() _now;

  WikimediaProvider({http.Client? client, DateTime Function()? now})
      : _client = client ?? http.Client(),
        _now = now ?? DateTime.now;

  @override
  String get id => ProviderId.wikimedia.name;

  @override
  String get label => 'Wikimedia POTD';

  @override
  Future<PotdItem> fetch() async {
    final d = _now();
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    final url = Uri.parse(
        'https://commons.wikimedia.org/api/rest_v1/feed/featured/${d.year}/$mm/$dd');
    final res = await _client.get(url);
    if (res.statusCode != 200) {
      throw PotdException('commons http ${res.statusCode}');
    }
    Map<String, dynamic> data;
    try {
      data = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw const PotdException('commons response not json');
    }
    final image = data['image'];
    if (image is! Map<String, dynamic>) {
      throw const PotdException('no picture of the day');
    }
    final source = (image['image'] as Map<String, dynamic>?)?['source'];
    if (source is! String || source.isEmpty) {
      throw const PotdException('no full-size source');
    }
    if (source.toLowerCase().endsWith('.webm') ||
        source.toLowerCase().endsWith('.ogv')) {
      throw const PotdException('commons media is a video');
    }
    final imgRes = await _client.get(Uri.parse(source));
    if (imgRes.statusCode != 200 || imgRes.bodyBytes.isEmpty) {
      throw PotdException('commons image http ${imgRes.statusCode}');
    }
    final artistRaw = image['artist'];
    String author = '';
    if (artistRaw is Map<String, dynamic>) {
      author = (artistRaw['html'] as String? ?? '')
          .replaceAll(RegExp(r'<[^>]*>'), '')
          .trim();
    } else if (artistRaw is String) {
      author = artistRaw;
    }
    return PotdItem(
      meta: PotdMeta(
        title: ((image['title'] as String?) ?? '').replaceFirst('File:', ''),
        author: author,
        infoUrl: (image['file_page'] as String?) ?? 'https://commons.wikimedia.org/',
        imageUrl: source,
      ),
      bytes: imgRes.bodyBytes,
    );
  }
}
```

- [ ] **Step 5: Wire into provider_factory.dart**

Replace the `ProviderId.wikimedia` case with `return WikimediaProvider(client: client, now: now);` and add `import 'wikimedia.dart';`

- [ ] **Step 6: Run all provider tests + analyze**

Run: `flutter test && flutter analyze`
Expected: all PASS (16 tests so far), no issues

- [ ] **Step 7: Commit**

```bash
git add lib/providers/wikimedia.dart lib/providers/provider_factory.dart test && git commit -m "feat: wikimedia potd provider, factory complete"
```

---

### Task 10: ImageFitter

**Files:**
- Create: `lib/services/image_fitter.dart`
- Test: `test/services/image_fitter_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:wallpaper_changer/models/settings.dart';
import 'package:wallpaper_changer/services/image_fitter.dart';

void main() {
  final fitter = ImageFitter();
  // phone-ish target: 1080x2340
  const tw = 1080, th = 2340;

  test('centerCrop portrait output equals target ratio', () {
    final src = img.Image(width: 3840, height: 2160); // landscape
    final out = fitter.transform(src,
        targetWidth: tw, targetHeight: th, mode: FitMode.centerCrop);
    expect(out.width, tw);
    expect(out.height, th);
  });

  test('centerCrop never upscales beyond source quality', () {
    final src = img.Image(width: 600, height: 400);
    final out = fitter.transform(src,
        targetWidth: tw, targetHeight: th, mode: FitMode.centerCrop);
    // source is smaller than target: keep cropped native size (600x??)
    expect(out.height, 400);
    expect((out.width / out.height - tw / th).abs(), lessThan(0.01));
  });

  test('asIs returns the same image untouched', () {
    final src = img.Image(width: 123, height: 45);
    final out = fitter.transform(src,
        targetWidth: tw, targetHeight: th, mode: FitMode.asIs);
    expect(identical(out, src), isTrue);
  });

  test('blurPad output is exactly target size', () {
    final src = img.Image(width: 2000, height: 1000);
    final out = fitter.transform(src,
        targetWidth: tw, targetHeight: th, mode: FitMode.blurPad);
    expect(out.width, tw);
    expect(out.height, th);
  });

  test('square source cropped to wide target keeps full height', () {
    final src = img.Image(width: 1000, height: 1000);
    final out = fitter.transform(src,
        targetWidth: 2000, targetHeight: 1000, mode: FitMode.centerCrop);
    expect(out.width, 1000);
    expect(out.height, 500);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/image_fitter_test.dart`
Expected: FAIL — `image_fitter.dart` not found

- [ ] **Step 3: Write lib/services/image_fitter.dart**

```dart
import 'package:image/image.dart' as img;

import '../models/settings.dart';

class ImageFitter {
  img.Image transform(
    img.Image source, {
    required int targetWidth,
    required int targetHeight,
    required FitMode mode,
  }) {
    switch (mode) {
      case FitMode.asIs:
        return source;
      case FitMode.centerCrop:
        return _centerCrop(source, targetWidth, targetHeight);
      case FitMode.blurPad:
        return _blurPad(source, targetWidth, targetHeight);
    }
  }

  img.Image _centerCrop(img.Image src, int tw, int th) {
    final srcAspect = src.width / src.height;
    final targetAspect = tw / th;
    int cw, ch;
    if (srcAspect > targetAspect) {
      ch = src.height;
      cw = (ch * targetAspect).round();
    } else {
      cw = src.width;
      ch = (cw / targetAspect).round();
    }
    final x = (src.width - cw) ~/ 2;
    final y = (src.height - ch) ~/ 2;
    var out = img.copyCrop(src, x: x, y: y, width: cw, height: ch);
    if (out.width > tw) {
      out = img.copyResize(out, width: tw, height: th);
    }
    return out;
  }

  img.Image _blurPad(img.Image src, int tw, int th) {
    final bg = _coverTo(src, tw, th);
    bg.gaussianBlur(radius: 16);
    const darken = 0.45;
    for (final p in bg) {
      p.r = (p.r * darken).clamp(0, 255).toInt();
      p.g = (p.g * darken).clamp(0, 255).toInt();
      p.b = (p.b * darken).clamp(0, 255).toInt();
    }
    final fg = _containTo(src, tw, th);
    img.drawImage(bg, fg,
        dstX: (tw - fg.width) ~/ 2, dstY: (th - fg.height) ~/ 2);
    return bg;
  }

  img.Image _coverTo(img.Image src, int tw, int th) {
    final resized = src.width / src.height > tw / th
        ? img.copyResize(src, height: th)
        : img.copyResize(src, width: tw);
    return img.copyCrop(resized,
        x: (resized.width - tw) ~/ 2,
        y: (resized.height - th) ~/ 2,
        width: tw,
        height: th);
  }

  img.Image _containTo(img.Image src, int tw, int th) {
    return src.width / src.height > tw / th
        ? img.copyResize(src, width: tw)
        : img.copyResize(src, height: th);
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/image_fitter_test.dart`
Expected: PASS (5 tests). If `p.r = (…).toInt()` errors with type issues, use `p.setRgba((p.r * darken).round().clamp(0, 255), …)` — same semantics.

- [ ] **Step 5: Commit**

```bash
git add lib/services/image_fitter.dart test/services/image_fitter_test.dart && git commit -m "feat: image fitter (center-crop, as-is, blur-pad)"
```

---

### Task 11: WallpaperApi platform interface

**Files:**
- Create: `lib/platform/wallpaper_api.dart`
- Test: `test/platform/wallpaper_api_test.dart`

- [ ] **Step 1: Write the failing test (MethodChannel encoding via mock handler)**

```dart
import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallpaper_changer/models/settings.dart';
import 'package:wallpaper_changer/platform/wallpaper_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('setWallpaper sends bytes and target flags', () async {
    final api = MethodChannelWallpaperApi();
    Object? method;
    Map<Object?, Object?>? args;
    (TestWidgetsFlutterBinding.instance as dynamic)
        .defaultBinaryMessenger
        .setMockMethodCallHandler(WallpaperApi.channel, (call) async {
      method = call.method;
      args = call.arguments as Map<Object?, Object?>?;
      return true;
    });
    final ok = await api.setWallpaper([1, 2, 3, 4],
        {ScreenTarget.home, ScreenTarget.lock});
    expect(ok, isTrue);
    expect(method, 'set');
    expect(args!['home'], isTrue);
    expect(args!['lock'], isTrue);
    expect(args!['bytes'], [1, 2, 3, 4]);
  });

  test('getScreenSize maps response to Size', () async {
    final api = MethodChannelWallpaperApi();
    (TestWidgetsFlutterBinding.instance as dynamic)
        .defaultBinaryMessenger
        .setMockMethodCallHandler(WallpaperApi.channel, (call) async {
      return {'w': 1080, 'h': 2340};
    });
    expect(await api.getScreenSize(), const Size(1080.0, 2340.0));
  });

  test('notifyStale calls through', () async {
    final api = MethodChannelWallpaperApi();
    String? label;
    (TestWidgetsFlutterBinding.instance as dynamic)
        .defaultBinaryMessenger
        .setMockMethodCallHandler(WallpaperApi.channel, (call) async {
      label = call.arguments['label'] as String?;
      return null;
    });
    await api.notifyStale('Bing');
    expect(label, 'Bing');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/platform/wallpaper_api_test.dart`
Expected: FAIL — `wallpaper_api.dart` not found

- [ ] **Step 3: Write lib/platform/wallpaper_api.dart**

```dart
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/services.dart';

import '../models/settings.dart';

abstract class WallpaperApi {
  static const MethodChannel channel = MethodChannel('wallpaper_changer/wallpaper');

  Future<Size> getScreenSize();

  /// [jpegBytes] must be an encoded jpeg of the final (fitted) image.
  Future<bool> setWallpaper(Uint8List jpegBytes, Set<ScreenTarget> targets);

  Future<void> notifyStale(String providerLabel);
}

class MethodChannelWallpaperApi implements WallpaperApi {
  @override
  Future<Size> getScreenSize() async {
    final r = await WallpaperApi.channel
        .invokeMapMethod<String, dynamic>('screenSize');
    return Size((r!['w'] as num).toDouble(), (r['h'] as num).toDouble());
  }

  @override
  Future<bool> setWallpaper(Uint8List jpegBytes, Set<ScreenTarget> targets) async {
    final ok = await WallpaperApi.channel.invokeMethod<bool>('set', {
      'bytes': jpegBytes,
      'home': targets.contains(ScreenTarget.home),
      'lock': targets.contains(ScreenTarget.lock),
    });
    return ok ?? false;
  }

  @override
  Future<void> notifyStale(String providerLabel) =>
      WallpaperApi.channel.invokeMethod('notifyStale', {'label': providerLabel});
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/platform/wallpaper_api_test.dart && flutter analyze`
Expected: PASS (3 tests), no issues. If the `(binding as dynamic)` cast trips the
analyzer, replace with `TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger`.

- [ ] **Step 5: Commit**

```bash
git add lib/platform test/platform && git commit -m "feat: wallpaper platform api with channel tests"
```

---

### Task 12: PotdService orchestration

**Files:**
- Create: `lib/services/potd_service.dart`
- Test: `test/services/potd_service_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:wallpaper_changer/models/potd_item.dart';
import 'package:wallpaper_changer/models/settings.dart';
import 'package:wallpaper_changer/platform/wallpaper_api.dart';
import 'package:wallpaper_changer/providers/provider.dart';
import 'package:wallpaper_changer/services/image_fitter.dart';
import 'package:wallpaper_changer/services/potd_service.dart';
import 'package:wallpaper_changer/services/wallpaper_repo.dart';
import 'dart:ui';

class FakeProvider implements PotdProvider {
  final PotdItem? item;
  final Object Function()? thrower;
  FakeProvider({this.item}) : thrower = null;
  FakeProvider.failing() : item = null, thrower = () => const PotdException('nope');

  @override
  String get id => 'fake';
  @override
  String get label => 'Fake';
  @override
  Future<PotdItem> fetch() async {
    if (thrower != null) throw thrower!();
    return item!;
  }
}

class FakeApi implements WallpaperApi {
  Size screenSize = const Size(1080, 2340);
  int setCalls = 0;
  int staleCalls = 0;
  bool succeed = true;
  @override
  Future<Size> getScreenSize() async => screenSize;
  @override
  Future<bool> setWallpaper(Uint8List bytes, Set<ScreenTarget> targets) async {
    setCalls++;
    return succeed;
  }
  @override
  Future<void> notifyStale(String providerLabel) async => staleCalls++;
}

PotdItem imageItem(String url) => PotdItem(
      meta: PotdMeta(title: 'T', author: 'A', infoUrl: 'https://i', imageUrl: url),
      bytes: img.encodeJpg(img.Image(width: 64, height: 32)),
    );

PotdService makeService({
  required PotdProvider provider,
  required FakeApi api,
  required WallpaperRepo repo,
  DateTime Function()? now,
}) =>
    PotdService(
      providerFor: (_) => provider,
      api: api,
      repo: repo,
      fitter: ImageFitter(),
      now: now ?? () => DateTime(2026, 9, 10),
    );

void main() {
  late Directory tmp;
  late WallpaperRepo repo;
  late FakeApi api;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('svc_test');
    repo = WallpaperRepo(tmp);
    api = FakeApi();
  });
  tearDown(() async => tmp.deleteSync(recursive: true));

  test('happy path: sets wallpaper, saves to repo', () async {
    final svc = makeService(
        provider: FakeProvider(item: imageItem('https://img/1.jpg')),
        api: api,
        repo: repo);
    expect(await svc.run(), RunOutcome.applied);
    expect(api.setCalls, 1);
    expect(repo.loadCurrentMeta()?.imageUrl, 'https://img/1.jpg');
  });

  test('duplicate url is skipped without setting', () async {
    await repo.saveCurrent(
        item: imageItem('https://img/1.jpg'), appliedAt: DateTime(2026, 9, 9));
    final svc = makeService(
        provider: FakeProvider(item: imageItem('https://img/1.jpg')),
        api: api,
        repo: repo);
    expect(await svc.run(), RunOutcome.duplicate);
    expect(api.setCalls, 0);
  });

  test('wifiOnly + metered connection is skipped', () async {
    final svc = makeService(
        provider: FakeProvider(item: imageItem('https://img/1.jpg')),
        api: api,
        repo: repo);
    expect(await svc.run(unmetered: false), RunOutcome.skippedWifi);
    expect(api.setCalls, 0);
  });

  test('wifiOnly off runs on metered', () async {
    await repo.saveSettings(repo.loadSettings().copyWith(wifiOnly: false));
    final svc = makeService(
        provider: FakeProvider(item: imageItem('https://img/1.jpg')),
        api: api,
        repo: repo);
    expect(await svc.run(unmetered: false), RunOutcome.applied);
  });

  test('provider failure keeps wallpaper, no crash, no save', () async {
    final svc = makeService(
        provider: FakeProvider.failing(), api: api, repo: repo);
    expect(await svc.run(), RunOutcome.failed);
    expect(api.setCalls, 0);
    expect(repo.loadCurrentMeta(), isNull);
  });

  test('stale cache + failure triggers notifyStale', () async {
    await repo.saveCurrent(
        item: imageItem('https://img/old.jpg'),
        appliedAt: DateTime(2026, 9, 1));
    final svc = makeService(
        provider: FakeProvider.failing(), api: api, repo: repo);
    expect(await svc.run(), RunOutcome.failed);
    expect(api.staleCalls, 1);
  });

  test('setWallpaper returning false is a failure, nothing saved', () async {
    api.succeed = false;
    final svc = makeService(
        provider: FakeProvider(item: imageItem('https://img/1.jpg')),
        api: api,
        repo: repo);
    expect(await svc.run(), RunOutcome.failed);
    expect(repo.loadCurrentMeta(), isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/potd_service_test.dart`
Expected: FAIL — `potd_service.dart` not found

- [ ] **Step 3: Write lib/services/potd_service.dart**

```dart
import 'package:image/image.dart' as img;

import '../models/settings.dart';
import '../platform/wallpaper_api.dart';
import '../providers/provider.dart';
import 'image_fitter.dart';
import 'wallpaper_repo.dart';

enum RunOutcome { applied, duplicate, skippedWifi, failed }

class PotdService {
  final PotdProvider Function(ProviderId) providerFor;
  final WallpaperApi api;
  final WallpaperRepo repo;
  final ImageFitter fitter;
  final DateTime Function() now;

  PotdService({
    required this.providerFor,
    required this.api,
    required this.repo,
    required this.fitter,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  Future<RunOutcome> run({bool unmetered = true}) async {
    final settings = repo.loadSettings();
    if (settings.wifiOnly && !unmetered) return RunOutcome.skippedWifi;
    try {
      final provider = providerFor(settings.providerId);
      final item = await provider.fetch();
      if (repo.loadCurrentMeta()?.imageUrl == item.meta.imageUrl) {
        return RunOutcome.duplicate;
      }
      final screen = await api.getScreenSize();
      final source = img.decodeImage(item.bytes);
      if (source == null) throw const PotdException('image undecodable');
      final fitted = fitter.transform(
        source,
        targetWidth: screen.width.round(),
        targetHeight: screen.height.round(),
        mode: settings.fitMode,
      );
      final ok =
          await api.setWallpaper(img.encodeJpg(fitted, quality: 90), settings.screens);
      if (!ok) throw const PotdException('setWallpaper failed');
      await repo.saveCurrent(item: item, appliedAt: now());
      return RunOutcome.applied;
    } on Exception catch (_) {
      if (repo.isStale(now())) {
        final label = providerFor(repo.loadSettings().providerId).label;
        try {
          await api.notifyStale(label);
        } catch (_) {}
      }
      return RunOutcome.failed;
    }
  }
}
```

- [ ] **Step 4: Run full suite**

Run: `flutter test && flutter analyze`
Expected: all PASS (24 tests), no issues

- [ ] **Step 5: Commit**

```bash
git add lib/services/potd_service.dart test/services/potd_service_test.dart && git commit -m "feat: potd service orchestration with stale alarm"
```

---

### Task 13: Kotlin side — channel, WallpaperManager, manifest

**Files:**
- Modify: `android/app/src/main/kotlin/dev/gift/wallpaper_changer/MainActivity.kt`
- Modify: `android/app/src/main/AndroidManifest.xml`

No Dart unit tests here (platform glue); correctness is exercised by the Task 14 app + Task 16 emulator QA.

- [ ] **Step 1: Replace MainActivity.kt**

```kotlin
package dev.gift.wallpaper_changer

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.WallpaperManager
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelId = "wallpaper_changer/wallpaper"

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, channelId)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "screenSize" -> {
                        val m = resources.displayMetrics
                        result.success(mapOf("w" to m.widthPixels, "h" to m.heightPixels))
                    }
                    "set" -> {
                        val bytes = call.argument<ByteArray>("bytes")
                        if (bytes == null) {
                            result.error("bad_args", "bytes missing", null)
                            return@setMethodCallHandler
                        }
                        val home = call.argument<Boolean>("home") ?: false
                        val lock = call.argument<Boolean>("lock") ?: false
                        try {
                            val bmp = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                                ?: throw IllegalArgumentException("undecodable")
                            val wm = WallpaperManager.getInstance(this)
                            var flags = 0
                            if (home) flags = flags or WallpaperManager.FLAG_SYSTEM
                            if (lock) flags = flags or WallpaperManager.FLAG_LOCK
                            wm.setBitmap(bmp, null, true, flags)
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    "notifyStale" -> {
                        val label = call.argument<String>("label") ?: "provider"
                        postStaleNotification(label)
                        result.success(null)
                    }
                    "requestNotifPermission" -> {
                        if (Build.VERSION.SDK_INT >= 33 &&
                            checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) !=
                            PackageManager.PERMISSION_GRANTED) {
                            requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 1)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun postStaleNotification(label: String) {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(
                NotificationChannel("stale", "Provider health", NotificationManager.IMPORTANCE_DEFAULT)
            )
        }
        val text = "No new wallpaper from $label for 3 days — open the app and pick another source."
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(this, "stale")
        } else {
            @Suppress("DEPRECATION") Notification.Builder(this)
        }
        val n = builder
            .setSmallIcon(android.R.drawable.stat_notify_error)
            .setContentTitle("Wallpaper Changer")
            .setContentText(text)
            .setStyle(Notification.BigTextStyle().bigText(text))
            .setAutoCancel(true)
            .build()
        nm.notify(1001, n)
    }
}
```

- [ ] **Step 2: Add permissions to AndroidManifest.xml**

Inside `<manifest>` (above `<application>`):

```xml
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.SET_WALLPAPER"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
```

- [ ] **Step 3: Build debug APK**

Run: `flutter build apk --debug`
Expected: `✓ Built build/app/outputs/flutter-apk/app-debug.apk`

- [ ] **Step 4: Commit**

```bash
git add android && git commit -m "feat: android wallpaper channel, manifest permissions"
```

---

### Task 14: WorkManager wiring + UI

**Files:**
- Create: `lib/background.dart`
- Create: `lib/ui/home_screen.dart`
- Modify: `lib/main.dart` (replace counter demo)
- Test: `test/ui/home_screen_test.dart`

- [ ] **Step 1: Write the failing widget test**

```dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:wallpaper_changer/models/potd_item.dart';
import 'package:wallpaper_changer/services/wallpaper_repo.dart';
import 'package:wallpaper_changer/ui/home_screen.dart';

void main() {
  testWidgets('home screen renders chips, controls, hero, recents', (tester) async {
    final tmp = await Directory.systemTemp.createTemp('ui_test');
    final repo = WallpaperRepo(tmp);
    await repo.saveCurrent(
      item: PotdItem(
        meta: const PotdMeta(
            title: 'Test Art', author: 'A', infoUrl: 'https://i', imageUrl: 'https://img/1.jpg'),
        bytes: img.encodeJpg(img.Image(width: 16, height: 16)),
      ),
      appliedAt: DateTime(2026, 9, 10),
    );
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(
        repo: repo,
        onRefresh: () async => true,
        onSettingsChanged: (s) async {},
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Simon Stålenhag'), findsOneWidget);
    expect(find.text('Bing'), findsOneWidget);
    expect(find.text('NASA APOD'), findsOneWidget);
    expect(find.text('Wikimedia POTD'), findsOneWidget);
    expect(find.text('Refresh now'), findsOneWidget);
    expect(find.byType(Image), findsWidgets);
    await tmp.deleteSync(recursive: true);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/home_screen_test.dart`
Expected: FAIL — `home_screen.dart` not found

- [ ] **Step 3: Write lib/ui/home_screen.dart**

```dart
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/settings.dart';
import '../providers/provider.dart';
import '../services/potd_service.dart';
import '../services/wallpaper_repo.dart';

class HomeScreen extends StatefulWidget {
  final WallpaperRepo repo;
  final Future<bool> Function() onRefresh;
  final Future<void> Function(Settings) onSettingsChanged;

  const HomeScreen({
    super.key,
    required this.repo,
    required this.onRefresh,
    required this.onSettingsChanged,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Settings _settings;
  List<HistoryEntry> _history = const [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _settings = widget.repo.loadSettings();
    _history = widget.repo.loadHistory();
  }

  Future<void> _save(Settings s) async {
    setState(() => _settings = s);
    await widget.repo.saveSettings(s);
    await widget.onSettingsChanged(s);
  }

  Future<void> _refresh() async {
    setState(() => _busy = true);
    try {
      await widget.onRefresh();
    } finally {
      setState(() {
        _busy = false;
        _history = widget.repo.loadHistory();
      });
    }
  }

  String get _screensLabel {
    final both = _settings.screens.containsAll(ScreenTarget.values);
    if (both) return 'Both';
    return _settings.screens.contains(ScreenTarget.home) ? 'Home' : 'Lock';
  }

  @override
  Widget build(BuildContext context) {
    final hero = _history.isNotEmpty ? _history.first : null;
    return Scaffold(
      appBar: AppBar(title: const Text('Wallpaper Changer')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (hero != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 16 / 11,
                child: Image.file(
                  File(hero.imageFile.path),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(color: Colors.grey),
                ),
              ),
            )
          else
            Container(
              height: 180,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(child: Text('No wallpaper yet — hit Refresh')),
            ),
          const SizedBox(height: 8),
          if (hero != null)
            Text(hero.meta.title,
                style: Theme.of(context).textTheme.titleSmall,
                overflow: TextOverflow.ellipsis),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              for (final id in ProviderId.values)
                ChoiceChip(
                  label: Text(_labels[id]!),
                  selected: _settings.providerId == id,
                  onSelected: _busy
                      ? null
                      : (_) => _save(_settings.copyWith(providerId: id)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _screensLabel,
            decoration: const InputDecoration(labelText: 'Screens'),
            items: const [
              DropdownMenuItem(value: 'Both', child: Text('Both')),
              DropdownMenuItem(value: 'Home', child: Text('Home')),
              DropdownMenuItem(value: 'Lock', child: Text('Lock')),
            ],
            onChanged: _busy
                ? null
                : (v) {
                    final screens = switch (v) {
                      'Home' => const {ScreenTarget.home},
                      'Lock' => const {ScreenTarget.lock},
                      _ => const {ScreenTarget.home, ScreenTarget.lock},
                    };
                    _save(_settings.copyWith(screens: screens));
                  },
          ),
          DropdownButtonFormField<FitMode>(
            initialValue: _settings.fitMode,
            decoration: const InputDecoration(labelText: 'Fit'),
            items: const [
              DropdownMenuItem(value: FitMode.centerCrop, child: Text('Center-crop')),
              DropdownMenuItem(value: FitMode.asIs, child: Text('As-is')),
              DropdownMenuItem(value: FitMode.blurPad, child: Text('Blur-pad')),
            ],
            onChanged: _busy
                ? null
                : (v) => _save(_settings.copyWith(fitMode: v)),
          ),
          SwitchListTile(
            title: const Text('Wi-Fi only'),
            value: _settings.wifiOnly,
            onChanged: _busy
                ? null
                : (v) => _save(_settings.copyWith(wifiOnly: v)),
          ),
          FilledButton(
            onPressed: _busy ? null : _refresh,
            child: _busy
                ? const SizedBox(
                    height: 18, width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Refresh now'),
          ),
          const SizedBox(height: 12),
          if (_history.length > 1) ...[
            Text('Recent', style: Theme.of(context).textTheme.labelMedium),
            SizedBox(
              height: 72,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final h in _history.skip(1))
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.file(
                          File(h.imageFile.path),
                          height: 72,
                          width: 128,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              Container(width: 128, color: Colors.grey),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

const _labels = {
  ProviderId.stalenhag: 'Simon Stålenhag',
  ProviderId.bing: 'Bing',
  ProviderId.apod: 'NASA APOD',
  ProviderId.wikimedia: 'Wikimedia POTD',
};
```

Note: `DropdownButtonFormField` uses `value:` in some Flutter versions and `initialValue:` in others — use whichever `flutter analyze` accepts on 3.47.

- [ ] **Step 4: Write lib/background.dart**

```dart
import 'package:workmanager/workmanager.dart';

import 'platform/wallpaper_api.dart';
import 'providers/provider_factory.dart';
import 'services/image_fitter.dart';
import 'services/potd_service.dart';
import 'services/wallpaper_repo.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      final repo = await WallpaperRepo.openDefault();
      final service = PotdService(
        providerFor: (id) => defaultProviderFor(id),
        api: MethodChannelWallpaperApi(),
        repo: repo,
        fitter: ImageFitter(),
      );
      await service.run(unmetered: true);
      return true;
    } catch (_) {
      return false;
    }
  });
}
```

Add to `WallpaperRepo` (Task 5 file):

```dart
  static Future<WallpaperRepo> openDefault() async {
    final dir = await getApplicationDocumentsDirectory();
    return WallpaperRepo(dir);
  }
```

with `import 'package:path_provider/path_provider.dart';` at top.

- [ ] **Step 5: Replace lib/main.dart**

```dart
import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';

import 'background.dart';
import 'models/settings.dart';
import 'platform/wallpaper_api.dart';
import 'providers/provider_factory.dart';
import 'services/image_fitter.dart';
import 'services/potd_service.dart';
import 'services/wallpaper_repo.dart';
import 'ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Workmanager().initialize(callbackDispatcher);
  final repo = await WallpaperRepo.openDefault();
  await _registerDailyTask(repo.loadSettings());
  runApp(App(repo: repo));
}

Future<void> _registerDailyTask(Settings settings) async {
  await Workmanager().registerPeriodicTask(
    'potdDaily',
    'potdDaily',
    frequency: const Duration(hours: 24),
    constraints: Constraints(
      networkType:
          settings.wifiOnly ? NetworkType.unmetered : NetworkType.connected,
    ),
    backoffPolicy: BackoffPolicy.exponential,
    existingWorkPolicy: ExistingWorkPolicy.keep,
  );
}

class App extends StatelessWidget {
  final WallpaperRepo repo;

  const App({super.key, required this.repo});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wallpaper Changer',
      theme: ThemeData(colorSchemeSeed: const Color(0xFF4A6CF7), useMaterial3: true),
      home: Builder(builder: (context) {
        WallpaperApi.channel.invokeMethod('requestNotifPermission');
        return HomeScreen(
          repo: repo,
          onRefresh: () async {
            final service = PotdService(
              providerFor: (id) => defaultProviderFor(id),
              api: MethodChannelWallpaperApi(),
              repo: repo,
              fitter: ImageFitter(),
            );
            final outcome = await service.run(unmetered: true);
            return outcome == RunOutcome.applied;
          },
          onSettingsChanged: (s) => _registerDailyTask(s),
        );
      }),
    );
  }
}
```

- [ ] **Step 6: Run widget test + full suite + analyze**

Run: `flutter test && flutter analyze`
Expected: all PASS (25 tests), no issues

- [ ] **Step 7: Build debug APK and commit**

Run: `flutter build apk --debug`
Expected: built apk

```bash
git add lib test && git commit -m "feat: workmanager daily task and single-screen ui"
```

---

### Task 15: Release signing + release workflow + README

**Files:**
- Modify: `android/app/build.gradle.kts`
- Create: `.github/workflows/release.yml`
- Create: `README.md`

- [ ] **Step 1: Add signing config to android/app/build.gradle.kts**

At the top of the file add:

```kotlin
import java.io.FileInputStream
import java.util.Properties

val keystorePropsFile = rootProject.file("key.properties")
val keystoreProps = Properties().apply {
    if (keystorePropsFile.exists()) keystoreProps.load(FileInputStream(keystorePropsFile))
}
```

Inside `android { ... }` add (next to `buildTypes`):

```kotlin
    signingConfigs {
        create("release") {
            if (keystorePropsFile.exists()) {
                keyAlias = keystoreProps["keyAlias"] as String
                keyPassword = keystoreProps["keyPassword"] as String
                storeFile = rootProject.file(keystoreProps["storeFile"] as String)
                storePassword = keystoreProps["storePassword"] as String
            }
        }
    }
    buildTypes {
        release {
            signingConfig = if (keystorePropsFile.exists())
                signingConfigs.getByName("release") else null
        }
    }
```

(Merge into the existing `release` block if the template already defines one — keep `isMinifyEnabled` etc. as generated. `key.properties` is already gitignored.)

- [ ] **Step 2: Write .github/workflows/release.yml**

```yaml
name: release
on:
  push:
    tags: ['v*']
jobs:
  release:
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
      - run: flutter pub get
      - run: flutter analyze
      - run: flutter test
      - name: Fail fast with clear message if signing secrets missing
        if: ${{ secrets.KEYSTORE_BASE64 == '' }}
        run: |
          echo "::error::KEYSTORE_BASE64 secret is not set. Generate a keystore (see README) and add repo secrets: KEYSTORE_BASE64, KEYSTORE_PASSWORD, KEY_ALIAS, KEY_PASSWORD."
          exit 1
      - name: Decode keystore
        run: echo "${{ secrets.KEYSTORE_BASE64 }}" | base64 -d > android/app/upload-keystore.jks
      - name: Write key.properties
        run: |
          cat > android/key.properties <<EOF
          storeFile=app/upload-keystore.jks
          storePassword=${{ secrets.KEYSTORE_PASSWORD }}
          keyAlias=${{ secrets.KEY_ALIAS }}
          keyPassword=${{ secrets.KEY_PASSWORD }}
          EOF
      - run: flutter build apk --release
      - uses: softprops/action-gh-release@v2
        with:
          files: build/app/outputs/flutter-apk/app-release.apk
          generate_release_notes: true
```

- [ ] **Step 3: Write README.md**

```markdown
# Wallpaper Changer

Flutter Android app that changes your wallpaper daily from the same sources as
KDE Plasma's Picture of the Day plugin: Simon Stålenhag, Bing, NASA APOD, and
Wikimedia Commons POTD.

## Dev

    flutter pub get
    flutter test
    flutter run

## Release signing (one-time setup)

1. Generate a keystore (keep it safe, it must never change):

       keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload

2. Base64 it:

       base64 -w0 upload-keystore.jks

3. Add GitHub repo secrets: `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`,
   `KEY_ALIAS`, `KEY_PASSWORD`.

4. Bump `version:` in `pubspec.yaml`, commit, then tag:

       git tag v0.1.0 && git push origin v0.1.0

CI runs tests, builds, signs, and publishes the APK to a GitHub Release.

## Design docs

See `docs/superpowers/specs/`.
```

- [ ] **Step 4: Verify release YAML + local build with debug signing unaffected**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release.yml'))" && flutter build apk --debug && echo OK`

- [ ] **Step 5: Commit**

```bash
git add android/app/build.gradle.kts .github README.md && git commit -m "ci: signed release pipeline and readme"
```

---

### Task 16: Emulator QA (end-to-end, agentic)

**Files:** none (verification only; findings become fixes in follow-up commits)

- [ ] **Step 1: Boot emulator**

Run: `emulator -avd test_device -no-snapshot-load -no-boot-anim &` then `adb wait-for-device && adb shell 'while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 2; done; echo BOOTED'`
Expected: `BOOTED`

- [ ] **Step 2: Install + launch, first run applies wallpaper**

```bash
flutter build apk --debug && adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell am start -n dev.gift.wallpaper_changer/.MainActivity
adb logcat -d | grep -i wallpaper | tail -5
```
Expected: app opens, no crash; after tapping Refresh now, logcat shows the channel `set` call. Home screen wallpaper visually changed (screenshot: `adb exec-out screencap -p > /tmp/qa_home.png`).

- [ ] **Step 3: Run spec §10 checklist scenarios**

- Lock+Home: `adb shell dumpsys wallpaper | head -20` shows system+lock bitmaps
- Airplane: `adb shell svc wifi disable && adb shell svc data disable`, trigger refresh, expect failure retained + no crash; re-enable, refresh succeeds
- Reboot: `adb reboot`, wait, confirm app still installed, force WorkManager run via `adb shell am broadcast -a androidx.work.diagnostics.REQUEST_DIAGNOSTICS -p dev.gift.wallpaper_changer` (lists work state)
- Wi-Fi only: set metered simulation `adb shell cmd connectivity airplane-mode enable` variant; confirm skippedWifi path via logcat
- Stale: set device date forward 4 days (`adb root && adb shell date @<epoch+4d>`), refresh with broken provider (temporarily point `apiUrl` at `http://127.0.0.1:1` in a debug build), expect stale notification: `adb shell dumpsys notification --noredact | grep -A3 stale`

- [ ] **Step 4: Record results**

Append outcomes (pass/fail + screenshots paths) to the release commit message or QA notes file `docs/superpowers/qa/<tag>.md` and commit:

```bash
git add docs/superpowers/qa && git commit -m "docs: emulator qa results"
```

---

## Plan self-review

1. **Spec coverage** — providers (Tasks 6-9), fit modes + per-device crop (10), screens/home-lock (13, 14), auto daily rotation + constraints (14), reliability/backoff/cache/stale alarm (5, 12, 14), video-day failure (8, 9), UI single screen (14), CI verify (2), CI release + tags (15), TDD throughout (every task), emulator QA (16). Gap check: notification permission request — Task 13 `requestNotifPermission` + Task 14 invocation. Covered.
2. **Placeholders** — none; every step has complete code or exact commands.
3. **Type consistency** — `PotdItem.meta` used everywhere (providers, repo, service, tests); `Settings.copyWith` used by UI; `RunOutcome` shared between service and main.dart; `WallpaperApi.channel` static const used in tests and app; `repo.saveCurrent({item, appliedAt})` signature matches all call sites.
