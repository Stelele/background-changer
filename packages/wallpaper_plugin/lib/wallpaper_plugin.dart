/// Platform channel implementation lives on the Android side (WallpaperPlugin.kt).
///
/// The app communicates over the raw MethodChannel
/// 'wallpaper_changer/wallpaper' via its own
/// `lib/platform/wallpaper_api.dart` — this package exists purely so the
/// plugin class is registered with every FlutterEngine (including
/// workmanager's headless engine) via GeneratedPluginRegistrant.
library;
