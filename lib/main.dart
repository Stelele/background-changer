import 'dart:async';

import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';

import 'background.dart';
import 'models/settings.dart';
import 'platform/wallpaper_api.dart';
import 'providers/provider_factory.dart';
import 'services/image_fitter.dart';
import 'services/potd_service.dart';
import 'services/wallpaper_repo.dart';
import 'ui/home_screen.dart';

const _uniqueName = 'wallpaper-daily';
const _taskName = 'wallpaperDailyRefresh';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Workmanager().initialize(callbackDispatcher);
  final repo = await WallpaperRepo.openDefault();
  await _registerDailyTask(repo.loadSettings());
  runApp(App(repo: repo));
}

Future<void> _registerDailyTask(Settings s, {bool update = false}) async {
  await Workmanager().registerPeriodicTask(
    _uniqueName,
    _taskName,
    frequency: const Duration(hours: 24),
    constraints: Constraints(
      networkType: s.wifiOnly ? NetworkType.unmetered : NetworkType.connected,
    ),
    existingWorkPolicy: update
        ? ExistingPeriodicWorkPolicy.update
        : ExistingPeriodicWorkPolicy.keep,
  );
}

/// Android 13+ POST_NOTIFICATIONS must be requested from a visible Activity;
/// one guard so we only ask once per app process.
var _permAsked = false;

class App extends StatelessWidget {
  final WallpaperRepo repo;

  const App({super.key, required this.repo});

  @override
  Widget build(BuildContext context) {
    if (!_permAsked) {
      _permAsked = true;
      unawaited(WallpaperApi.channel.invokeMethod('requestNotifPermission'));
    }
    return MaterialApp(
      title: 'Wallpaper Changer',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4A6CF7)),
      ),
      home: HomeScreen(
        repo: repo,
        onRefresh: () async {
          final service = PotdService(
            providerFor: (id) => defaultProviderFor(id),
            api: MethodChannelWallpaperApi(),
            repo: repo,
            fitter: ImageFitter(),
          );
          final outcome = await service.run(unmetered: true);
          return outcome == RunOutcome.applied;
        },
        onSettingsChanged: (s) => _registerDailyTask(s, update: true),
      ),
    );
  }
}
