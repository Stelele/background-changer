import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallpaper_changer/models/settings.dart';
import 'package:wallpaper_changer/platform/wallpaper_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(WallpaperApi.channel, null);
  });

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

  test('setWallpaper returns false when platform reply is null', () async {
    final api = MethodChannelWallpaperApi();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(WallpaperApi.channel, (call) async => null);
    expect(
        await api.setWallpaper(
            Uint8List.fromList([9]), {ScreenTarget.home}),
        isFalse);
  });

  test('setWallpaper throws when no targets selected', () async {
    final api = MethodChannelWallpaperApi();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(WallpaperApi.channel, (call) async => true);
    expect(
        api.setWallpaper(Uint8List.fromList([1]), <ScreenTarget>{}),
        throwsA(isA<Exception>()));
  });

  test('setWallpaper sends correct flags for lock-only target', () async {
    final api = MethodChannelWallpaperApi();
    Map<Object?, Object?>? args;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(WallpaperApi.channel, (call) async {
      args = call.arguments as Map<Object?, Object?>?;
      return true;
    });
    await api.setWallpaper(Uint8List.fromList([1]), {ScreenTarget.lock});
    expect(args!['home'], isFalse);
    expect(args!['lock'], isTrue);
    expect(args!['bytes'], [1]);
  });

  test('getScreenSize maps response to Size', () async {
    final api = MethodChannelWallpaperApi();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(WallpaperApi.channel, (call) async {
      return {'w': 1080, 'h': 2340};
    });
    expect(await api.getScreenSize(), const Size(1080.0, 2340.0));
  });

  test('getScreenSize throws Exception when reply is null', () async {
    final api = MethodChannelWallpaperApi();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(WallpaperApi.channel, (call) async => null);
    expect(api.getScreenSize(), throwsA(isA<Exception>()));
  });

  test('getScreenSize throws Exception when reply has non-numeric w/h', () async {
    final api = MethodChannelWallpaperApi();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(WallpaperApi.channel, (call) async {
      return {'w': 'x', 'h': 2};
    });
    expect(api.getScreenSize(), throwsA(isA<Exception>()));
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
