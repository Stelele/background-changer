import 'dart:convert';
import 'dart:io';

import '../models/settings.dart';

class WallpaperRepo {
  final Directory baseDir;

  WallpaperRepo(this.baseDir);

  File get _settingsFile => File('${baseDir.path}/settings.json');

  Settings loadSettings() {
    if (!_settingsFile.existsSync()) return const Settings();
    try {
      final json =
          jsonDecode(_settingsFile.readAsStringSync()) as Map<String, dynamic>;
      return Settings.fromJson(json);
    } catch (_) {
      return const Settings();
    }
  }

  Future<void> saveSettings(Settings settings) async {
    await _settingsFile.writeAsString(jsonEncode(settings.toJson()));
  }
}
