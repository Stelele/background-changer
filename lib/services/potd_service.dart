import 'package:image/image.dart' as img;

import '../platform/wallpaper_api.dart';
import '../providers/provider.dart';
import 'image_fitter.dart';
import 'wallpaper_repo.dart';

enum RunOutcome { applied, duplicate, skippedWifi, failed }

class PotdService {
  final PotdProvider Function(ProviderId) providerFor;
  final WallpaperApi api;
  final WallpaperRepo repo;
  final ImageFitter fitter;
  final DateTime Function() now;

  PotdService({
    required this.providerFor,
    required this.api,
    required this.repo,
    required this.fitter,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  Future<RunOutcome> run({bool unmetered = true}) async {
    final settings = repo.loadSettings();
    if (settings.wifiOnly && !unmetered) return RunOutcome.skippedWifi;
    try {
      final provider = providerFor(settings.providerId);
      final item = await provider.fetch();
      if (repo.loadCurrentMeta()?.imageUrl == item.meta.imageUrl) {
        return RunOutcome.duplicate;
      }
      final screen = await api.getScreenSize();
      // package:image's decoder can throw (e.g. RangeError from a format
      // probe on truncated bytes), not just return null — treat any decode
      // failure as an undecodable image so the pipeline never crashes.
      img.Image? source;
      try {
        source = img.decodeImage(item.bytes);
      } catch (_) {
        source = null;
      }
      if (source == null) throw const PotdException('image undecodable');
      final fitted = fitter.transform(
        source,
        targetWidth: screen.width.round(),
        targetHeight: screen.height.round(),
        mode: settings.fitMode,
      );
      final ok = await api.setWallpaper(
          img.encodeJpg(fitted, quality: 90), settings.screens);
      if (!ok) throw const PotdException('setWallpaper failed');
      await repo.saveCurrent(item: item, appliedAt: now());
      return RunOutcome.applied;
    } on Exception {
      if (repo.isStale(now())) {
        final label = providerFor(repo.loadSettings().providerId).label;
        try {
          await api.notifyStale(label);
        } catch (_) {}
      }
      return RunOutcome.failed;
    }
  }
}
