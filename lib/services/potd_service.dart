import 'dart:typed_data';

import 'package:flutter/services.dart' show Size;
import 'package:image/image.dart' as img;

import '../models/potd_item.dart';
import '../models/settings.dart';
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

  /// Serializes concurrent runs so two triggers (timer + manual) can't both
  /// fetch/set before the first has saved its current-image marker.
  Future<void> _gate = Future<void>.value();

  Future<RunOutcome> run({bool unmetered = true}) {
    final outcome = _gate.then((_) => _run(unmetered: unmetered));
    _gate = outcome.then((_) {}, onError: (_) {});
    return outcome;
  }

  Future<RunOutcome> _run({bool unmetered = true}) async {
    final settings = repo.loadSettings();
    if (settings.wifiOnly && !unmetered) return RunOutcome.skippedWifi;
    try {
      final provider = providerFor(settings.providerId);
      final item = await provider.fetch();
      if (repo.loadCurrentMeta()?.imageUrl == item.meta.imageUrl) {
        return RunOutcome.duplicate;
      }
      final screen = await api.getScreenSize();
      final jpegBytes = _fitAndEncode(item, settings, screen);
      final ok = await api.setWallpaper(jpegBytes, settings.screens);
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

  /// package:image's decoder can throw (e.g. RangeError from a format
  /// probe on truncated bytes), not just return null, and the fitter can
  /// throw Error types too — funnel any pipeline failure into a
  /// PotdException so _run's `on Exception` boundary always holds.
  Uint8List _fitAndEncode(PotdItem item, Settings settings, Size screen) {
    try {
      final source = img.decodeImage(item.bytes);
      if (source == null) throw const PotdException('image undecodable');
      final fitted = fitter.transform(
        source,
        targetWidth: screen.width.round(),
        targetHeight: screen.height.round(),
        mode: settings.fitMode,
      );
      return img.encodeJpg(fitted, quality: 90);
    } on PotdException {
      rethrow;
    } catch (_) {
      throw const PotdException('image pipeline failed');
    }
  }
}
