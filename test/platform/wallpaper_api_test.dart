import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallpaper_changer/models/settings.dart';
import 'package:wallpaper_changer/platform/wallpaper_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('setWallpaper sends bytes and target flags', () async {
    final api = MethodChannelWallpaperApi();
    String? method;
    Map<Object?, Object?>? args;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(WallpaperApi.channel, (call) async {
      method = call.method;
      args = call.arguments as Map<Object?, Object?>?;
      return true;
    });
    final ok = await api.setWallpaper(
        Uint8List.fromList([1, 2, 3, 4]), {ScreenTarget.home, ScreenTarget.lock});
    expect(ok, isTrue);
    expect(method, 'set');
    expect(args!['home'], isTrue);
    expect(args!['lock'], isTrue);
    expect(args!['bytes'], [1, 2, 3, 4]);
  });

  test('setWallpaper returns false when platform reports failure', () async {
    final api = MethodChannelWallpaperApi();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(WallpaperApi.channel, (call) async => false);
    expect(
        await api.setWallpaper(
            Uint8List.fromList([9]), {ScreenTarget.home}),
        isFalse);
  });

  test('getScreenSize maps response to Size', () async {
    final api = MethodChannelWallpaperApi();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(WallpaperApi.channel, (call) async {
      return {'w': 1080, 'h': 2340};
    });
    expect(await api.getScreenSize(), const Size(1080.0, 2340.0));
  });

  test('notifyStale calls through with label', () async {
    final api = MethodChannelWallpaperApi();
    String? label;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(WallpaperApi.channel, (call) async {
      label = call.arguments['label'] as String?;
      return null;
    });
    await api.notifyStale('Bing');
    expect(label, 'Bing');
  });
}
