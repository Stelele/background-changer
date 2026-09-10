import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'wallpaper_plugin_method_channel.dart';

abstract class WallpaperPluginPlatform extends PlatformInterface {
  /// Constructs a WallpaperPluginPlatform.
  WallpaperPluginPlatform() : super(token: _token);

  static final Object _token = Object();

  static WallpaperPluginPlatform _instance = MethodChannelWallpaperPlugin();

  /// The default instance of [WallpaperPluginPlatform] to use.
  ///
  /// Defaults to [MethodChannelWallpaperPlugin].
  static WallpaperPluginPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [WallpaperPluginPlatform] when
  /// they register themselves.
  static set instance(WallpaperPluginPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
