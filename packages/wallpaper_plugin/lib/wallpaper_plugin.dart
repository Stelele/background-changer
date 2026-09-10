
import 'wallpaper_plugin_platform_interface.dart';

class WallpaperPlugin {
  Future<String?> getPlatformVersion() {
    return WallpaperPluginPlatform.instance.getPlatformVersion();
  }
}
