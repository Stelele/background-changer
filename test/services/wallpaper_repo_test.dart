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
