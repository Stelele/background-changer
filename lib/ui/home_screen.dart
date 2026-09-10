import 'dart:io';

import 'package:flutter/material.dart';

import '../models/settings.dart';
import '../providers/provider.dart';
import '../services/wallpaper_repo.dart';

class HomeScreen extends StatefulWidget {
  final WallpaperRepo repo;
  final Future<bool> Function() onRefresh;
  final Future<void> Function(Settings) onSettingsChanged;

  const HomeScreen({
    super.key,
    required this.repo,
    required this.onRefresh,
    required this.onSettingsChanged,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Settings _settings;
  List<HistoryEntry> _history = const [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _settings = widget.repo.loadSettings();
    _history = widget.repo.loadHistory();
  }

  Future<void> _save(Settings s) async {
    setState(() => _settings = s);
    await widget.repo.saveSettings(s);
    await widget.onSettingsChanged(s);
  }

  Future<void> _refresh() async {
    setState(() => _busy = true);
    try {
      await widget.onRefresh();
    } finally {
      setState(() {
        _busy = false;
        _history = widget.repo.loadHistory();
      });
    }
  }

  String get _screensLabel {
    final both = _settings.screens.containsAll(ScreenTarget.values);
    if (both) return 'Both';
    return _settings.screens.contains(ScreenTarget.home) ? 'Home' : 'Lock';
  }

  @override
  Widget build(BuildContext context) {
    final hero = _history.isNotEmpty ? _history.first : null;
    return Scaffold(
      appBar: AppBar(title: const Text('Wallpaper Changer')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (hero != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 16 / 11,
                child: Image.file(
                  File(hero.imageFile.path),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(color: Colors.grey),
                ),
              ),
            )
          else
            Container(
              height: 180,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(child: Text('No wallpaper yet — hit Refresh')),
            ),
          const SizedBox(height: 8),
          if (hero != null)
            Text(hero.meta.title,
                style: Theme.of(context).textTheme.titleSmall,
                overflow: TextOverflow.ellipsis),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              for (final id in ProviderId.values)
                ChoiceChip(
                  label: Text(_labels[id]!),
                  selected: _settings.providerId == id,
                  onSelected: _busy
                      ? null
                      : (_) => _save(_settings.copyWith(providerId: id)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _screensLabel,
            decoration: const InputDecoration(labelText: 'Screens'),
            items: const [
              DropdownMenuItem(value: 'Both', child: Text('Both')),
              DropdownMenuItem(value: 'Home', child: Text('Home')),
              DropdownMenuItem(value: 'Lock', child: Text('Lock')),
            ],
            onChanged: _busy
                ? null
                : (v) {
                    final screens = switch (v) {
                      'Home' => const {ScreenTarget.home},
                      'Lock' => const {ScreenTarget.lock},
                      _ => const {ScreenTarget.home, ScreenTarget.lock},
                    };
                    _save(_settings.copyWith(screens: screens));
                  },
          ),
          DropdownButtonFormField<FitMode>(
            initialValue: _settings.fitMode,
            decoration: const InputDecoration(labelText: 'Fit'),
            items: const [
              DropdownMenuItem(value: FitMode.centerCrop, child: Text('Center-crop')),
              DropdownMenuItem(value: FitMode.asIs, child: Text('As-is')),
              DropdownMenuItem(value: FitMode.blurPad, child: Text('Blur-pad')),
            ],
            onChanged: _busy
                ? null
                : (v) => _save(_settings.copyWith(fitMode: v)),
          ),
          SwitchListTile(
            title: const Text('Wi-Fi only'),
            value: _settings.wifiOnly,
            onChanged: _busy
                ? null
                : (v) => _save(_settings.copyWith(wifiOnly: v)),
          ),
          FilledButton(
            onPressed: _busy ? null : _refresh,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Refresh now'),
          ),
          const SizedBox(height: 12),
          if (_history.length > 1)
            SizedBox(
              height: 72,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final h in _history.skip(1))
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.file(
                          File(h.imageFile.path),
                          height: 72,
                          width: 128,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              Container(width: 128, color: Colors.grey),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

const _labels = {
  ProviderId.stalenhag: 'Simon Stålenhag',
  ProviderId.bing: 'Bing',
  ProviderId.apod: 'NASA APOD',
  ProviderId.wikimedia: 'Wikimedia POTD',
};
