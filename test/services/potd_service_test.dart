import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:wallpaper_changer/models/potd_item.dart';
import 'package:wallpaper_changer/models/settings.dart';
import 'package:wallpaper_changer/platform/wallpaper_api.dart';
import 'package:wallpaper_changer/providers/provider.dart';
import 'package:wallpaper_changer/services/image_fitter.dart';
import 'package:wallpaper_changer/services/potd_service.dart';
import 'package:wallpaper_changer/services/wallpaper_repo.dart';

class FakeProvider implements PotdProvider {
  final PotdItem? item;
  final Object Function()? thrower;
  FakeProvider({this.item}) : thrower = null;
  FakeProvider.failing()
      : item = null,
        // Parentheses required: in an initializer list the parser reads `= ()`
        // as the empty record literal, so a bare `() => ...` closure breaks.
        thrower = (() => const PotdException('nope'));

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
  Size screenSize = const Size(1080.0, 2340.0);
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
      meta: PotdMeta(
          title: 'T', author: 'A', infoUrl: 'https://i', imageUrl: url),
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
        item: imageItem('https://img/1.jpg'),
        appliedAt: DateTime(2026, 9, 9));
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
    final svc = makeService(provider: FakeProvider.failing(), api: api, repo: repo);
    expect(await svc.run(), RunOutcome.failed);
    expect(api.setCalls, 0);
    expect(repo.loadCurrentMeta(), isNull);
  });

  test('stale cache + failure triggers notifyStale', () async {
    await repo.saveCurrent(
        item: imageItem('https://img/old.jpg'),
        appliedAt: DateTime(2026, 9, 1));
    final svc = makeService(provider: FakeProvider.failing(), api: api, repo: repo);
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

  test('undecodable bytes are a failure', () async {
    final bad = PotdItem(
        meta: PotdMeta(
            title: 'T', author: 'A', infoUrl: 'https://i', imageUrl: 'https://img/bad'),
        bytes: Uint8List.fromList([1, 2, 3]));
    final svc = makeService(provider: FakeProvider(item: bad), api: api, repo: repo);
    expect(await svc.run(), RunOutcome.failed);
    expect(api.setCalls, 0);
  });
}
