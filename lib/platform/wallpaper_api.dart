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
    final r = await WallpaperApi.channel.invokeMethod('screenSize');
    if (r is! Map) {
      throw Exception('screenSize reply not a map');
    }
    final w = r['w'];
    final h = r['h'];
    if (w is! num || h is! num) {
      throw Exception('screenSize reply missing w/h');
    }
    return Size(w.toDouble(), h.toDouble());
  }

  @override
  Future<bool> setWallpaper(
      Uint8List jpegBytes, Set<ScreenTarget> targets) async {
    if (targets.isEmpty) {
      throw Exception('setWallpaper: no screen targets selected');
    }
    final reply = await WallpaperApi.channel.invokeMethod('set', {
      'bytes': jpegBytes,
      'home': targets.contains(ScreenTarget.home),
      'lock': targets.contains(ScreenTarget.lock),
    });
    if (reply != null && reply is! bool) {
      throw Exception('setWallpaper reply not a bool');
    }
    return reply ?? false;
  }

  @override
  Future<void> notifyStale(String providerLabel) =>
      WallpaperApi.channel.invokeMethod('notifyStale', {'label': providerLabel});
}
