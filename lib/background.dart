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
