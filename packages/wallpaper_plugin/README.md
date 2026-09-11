# wallpaper_plugin

Local path-dependency plugin package. Its only purpose is carrying the Android
`WallpaperPlugin` (channel `wallpaper_changer/wallpaper`) so that
GeneratedPluginRegistrant registers it on every FlutterEngine — including the
headless engine the `workmanager` plugin creates for background jobs.

All Dart-side access happens in the app via `lib/platform/wallpaper_api.dart`.
