import 'package:workmanager/workmanager.dart';

import 'platform/wallpaper_api.dart';
import 'providers/provider_factory.dart';
import 'services/image_fitter.dart';
import 'services/potd_service.dart';
import 'services/wallpaper_repo.dart';

/// Entry point for the headless background isolate spawned by Workmanager.
/// Runs the daily wallpaper refresh without any UI.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      final repo = await WallpaperRepo.openDefault();
      // Hourly chain: bail out cheaply — no provider fetch, no network —
      // when today's wallpaper is already applied in the device timezone.
      if (_appliedTodayLocal(repo)) return true;
      final service = PotdService(
        providerFor: (id) => defaultProviderFor(id),
        api: MethodChannelWallpaperApi(),
        repo: repo,
        fitter: ImageFitter(),
      );
      await service.run(unmetered: true);
      return true;
    } catch (_) {
      return false;
    }
  });
}

/// True once per local day: appliedAt is stored as UTC, but "today" is what
/// the user sees, so compare against the start of the local day.
bool _appliedTodayLocal(WallpaperRepo repo) {
  final at = repo.currentAppliedAt();
  if (at == null) return false;
  final now = DateTime.now();
  return at.isAfter(DateTime(now.year, now.month, now.day));
}
