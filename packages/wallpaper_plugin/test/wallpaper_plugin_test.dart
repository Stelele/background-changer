import 'package:flutter_test/flutter_test.dart';
import 'package:wallpaper_plugin/wallpaper_plugin.dart';
import 'package:wallpaper_plugin/wallpaper_plugin_platform_interface.dart';
import 'package:wallpaper_plugin/wallpaper_plugin_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockWallpaperPluginPlatform
    with MockPlatformInterfaceMixin
    implements WallpaperPluginPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final WallpaperPluginPlatform initialPlatform = WallpaperPluginPlatform.instance;

  test('$MethodChannelWallpaperPlugin is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelWallpaperPlugin>());
  });

  test('getPlatformVersion', () async {
    WallpaperPlugin wallpaperPlugin = WallpaperPlugin();
    MockWallpaperPluginPlatform fakePlatform = MockWallpaperPluginPlatform();
    WallpaperPluginPlatform.instance = fakePlatform;

    expect(await wallpaperPlugin.getPlatformVersion(), '42');
  });
}
