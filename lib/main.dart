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

// Unique name of the periodic task chain in WorkManager. Renaming it would
// orphan the old chain (both names would run), so it keeps its original id
// even though the period is now hourly — the task itself decides cheaply
// whether an image is needed.
const _uniqueName = 'wallpaper-daily';
const _taskName = 'wallpaperDailyRefresh';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Workmanager().initialize(callbackDispatcher);
  final repo = await WallpaperRepo.openDefault();
  // Update, never Keep: the periodic spec lives in WorkManager's persistent
  // DB, so Keep would pin the phone to whatever period a previous install
  // registered (e.g. the old 24h chain) instead of the current one.
  await _registerDailyTask(repo.loadSettings(), update: true);
  runApp(App(repo: repo));
}

Future<void> _registerDailyTask(Settings s, {bool update = false}) async {
  await Workmanager().registerPeriodicTask(
    _uniqueName,
    _taskName,
    // Hourly cadence is deliberate: Samsung One UI strips scheduled jobs of
    // sleeping apps and only re-enqueues them at next app launch, so a 24h
    // chain can sit un-scheduled for days and the wallpaper goes stale. An
    // hourly chain self-heals after each run, and background.dart gates its
    // cost to at most one fetch per local day.
    frequency: const Duration(hours: 1),
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

/// One UI battery management un-schedules the periodic task of apps it puts
/// to sleep; exempting the app from battery optimizations is what keeps the
/// chain alive. Ask (via the system dialog) once per process, non-fatal.
Future<void> _ensureBatteryExemption() async {
  try {
    final ignoring =
        await WallpaperApi.channel.invokeMethod<bool>(
            'isIgnoringBatteryOptimizations');
    if (ignoring == true) return;
    await WallpaperApi.channel
        .invokeMethod('requestIgnoreBatteryOptimizations');
  } catch (_) {
    // Exemption is a best-effort ask; the hourly chain still helps.
  }
}

class App extends StatelessWidget {
  final WallpaperRepo repo;

  const App({super.key, required this.repo});

  @override
  Widget build(BuildContext context) {
    if (!_permAsked) {
      _permAsked = true;
      unawaited(WallpaperApi.channel.invokeMethod('requestNotifPermission'));
      unawaited(_ensureBatteryExemption());
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
