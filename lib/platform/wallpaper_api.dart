import 'package:flutter/services.dart';

import '../models/settings.dart';

abstract class WallpaperApi {
  static const MethodChannel channel =
      MethodChannel('wallpaper_changer/wallpaper');

  Future<Size> getScreenSize();

  /// [jpegBytes] must be encoded image bytes of the final (fitted) image.
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
  Future<bool> setWallpaper(
      Uint8List jpegBytes, Set<ScreenTarget> targets) async {
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
