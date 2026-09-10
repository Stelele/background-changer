import 'dart:convert';
import 'dart:io';

import '../models/potd_item.dart';
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

  File get _currentFile => File('${baseDir.path}/current.json');
  Directory get _historyDir => Directory('${baseDir.path}/history');

  Future<void> saveCurrent(
      {required PotdItem item, required DateTime appliedAt}) async {
    _historyDir.createSync(recursive: true);
    final stamp = appliedAt
        .toUtc()
        .toIso8601String()
        .replaceAll(RegExp(r'[-:]'), '')
        .split('.')
        .first; // 20260910T063000
    await File('${_historyDir.path}/$stamp.jpg').writeAsBytes(item.bytes);
    final entry = {
      ..._metaJson(item.meta),
      'appliedAt': appliedAt.toUtc().toIso8601String(),
    };
    await File('${_historyDir.path}/$stamp.json')
        .writeAsString(jsonEncode(entry));
    final tmp = File('${baseDir.path}/current.json.tmp');
    await tmp.writeAsString(jsonEncode(entry));
    await tmp.rename(_currentFile.path);
    _trimHistory(14);
  }

  Map<String, dynamic> _metaJson(PotdMeta m) => {
        'title': m.title,
        'author': m.author,
        'infoUrl': m.infoUrl,
        'imageUrl': m.imageUrl,
      };

  PotdMeta _metaFromJson(Map<String, dynamic> j) => PotdMeta(
        title: j['title'] as String? ?? '',
        author: j['author'] as String? ?? '',
        infoUrl: j['infoUrl'] as String? ?? '',
        imageUrl: j['imageUrl'] as String? ?? '',
      );

  PotdMeta? loadCurrentMeta() {
    if (!_currentFile.existsSync()) return null;
    try {
      return _metaFromJson(
          jsonDecode(_currentFile.readAsStringSync()) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  DateTime? currentAppliedAt() {
    if (!_currentFile.existsSync()) return null;
    try {
      final j =
          jsonDecode(_currentFile.readAsStringSync()) as Map<String, dynamic>;
      return DateTime.parse(j['appliedAt'] as String);
    } catch (_) {
      return null;
    }
  }

  List<HistoryEntry> loadHistory() {
    if (!_historyDir.existsSync()) return const [];
    final entries = <HistoryEntry>[];
    for (final f in _historyDir.listSync()) {
      if (!f.path.endsWith('.json')) continue;
      try {
        final j = jsonDecode(File(f.path).readAsStringSync()) as Map<String, dynamic>;
        entries.add(HistoryEntry(
          meta: _metaFromJson(j),
          imageFile: File(f.path.replaceFirst(RegExp(r'\.json$'), '.jpg')),
          appliedAt: DateTime.parse(j['appliedAt'] as String),
        ));
      } catch (_) {/* skip corrupt entries */
      }
    }
    entries.sort((a, b) => b.appliedAt.compareTo(a.appliedAt));
    return entries;
  }

  void _trimHistory(int keep) {
    final sidecars = _historyDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    for (final f in sidecars.skip(keep)) {
      final img = File(f.path.replaceFirst(RegExp(r'\.json$'), '.jpg'));
      if (img.existsSync()) img.deleteSync();
      if (f.existsSync()) f.deleteSync();
    }
    final sidecarPaths = sidecars.map((f) => f.path).toSet();
    for (final f in _historyDir.listSync()) {
      if (f is! File || !f.path.endsWith('.jpg')) continue;
      final sidecar = f.path.replaceFirst(RegExp(r'\.jpg$'), '.json');
      if (!sidecarPaths.contains(sidecar) && !File(sidecar).existsSync()) {
        f.deleteSync();
      }
    }
  }

  bool isStale(DateTime now, {int days = 3}) {
    final at = currentAppliedAt();
    if (at == null) return false;
    return now.difference(at).inDays >= days;
  }
}

class HistoryEntry {
  final PotdMeta meta;
  final File imageFile;
  final DateTime appliedAt;

  const HistoryEntry(
      {required this.meta, required this.imageFile, required this.appliedAt});
}
