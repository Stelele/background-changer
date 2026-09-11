import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallpaper_changer/models/potd_item.dart';
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

  group('current + history', () {
    PotdItem item(String url) => PotdItem(
          meta: PotdMeta(
              title: 'T', author: 'A', infoUrl: 'https://i', imageUrl: url),
          bytes: Uint8List.fromList([1, 2, 3]),
        );

    test('saveCurrent persists meta + appliedAt + image, load roundtrips', () async {
      final at = DateTime(2026, 9, 10, 6, 30);
      await repo.saveCurrent(item: item('https://img/1.jpg'), appliedAt: at);
      expect(repo.loadCurrentMeta()?.imageUrl, 'https://img/1.jpg');
      expect(repo.currentAppliedAt()!.toLocal(), at);
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

    test('orphan jpg swept by trim', () async {
      // Manually create an orphan .jpg with no .json sidecar
      final historyDir = Directory('${tmp.path}/history');
      historyDir.createSync(recursive: true);
      File('${historyDir.path}/orphan.jpg').writeAsBytesSync([0xFF, 0xD8]);
      expect(File('${historyDir.path}/orphan.jpg').existsSync(), isTrue);

      // One saveCurrent call triggers _trimHistory which should sweep orphans
      await repo.saveCurrent(
        item: item('https://img/new.jpg'),
        appliedAt: DateTime(2026, 9, 10),
      );

      expect(File('${historyDir.path}/orphan.jpg').existsSync(), isFalse,
          reason: 'orphan .jpg without .json sidecar should be swept by trim');
    });

    test('corrupt current.json yields null meta + not stale', () async {
      // Write garbage to current.json
      File('${tmp.path}/current.json').writeAsStringSync('NOT VALID JSON {{{');
      expect(repo.loadCurrentMeta(), isNull,
          reason: 'corrupt file should return null meta');
      expect(repo.currentAppliedAt(), isNull,
          reason: 'corrupt file should return null appliedAt');
      expect(repo.isStale(DateTime(2026, 9, 10)), isFalse,
          reason: 'null appliedAt means not stale');
    });

    test('corrupt history sidecar is skipped', () async {
      // Create one valid entry
      await repo.saveCurrent(
        item: item('https://img/good.jpg'),
        appliedAt: DateTime(2026, 9, 10),
      );
      // Add a garbage .json file in the history dir
      final historyDir = Directory('${tmp.path}/history');
      File('${historyDir.path}/bad.json').writeAsStringSync('garbage');
      // Should not crash, should return only the valid entry
      final h = repo.loadHistory();
      expect(h.length, 1);
      expect(h.first.meta.imageUrl, 'https://img/good.jpg');
    });
  });
}
