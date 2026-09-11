import 'dart:math' as math;

import 'package:image/image.dart' as img;

import '../models/settings.dart';

class ImageFitter {
  img.Image transform(
    img.Image source, {
    required int targetWidth,
    required int targetHeight,
    required FitMode mode,
  }) {
    // Bake EXIF orientation once up front so every mode sees correctly
    // oriented pixels (orientation 6, e.g., swaps width and height).
    final orientation = source.exif.imageIfd.orientation ?? 1;
    if (orientation > 1 && orientation < 9) {
      source = img.bakeOrientation(source);
    }
    switch (mode) {
      case FitMode.asIs:
        return source;
      case FitMode.centerCrop:
        return _centerCrop(source, targetWidth, targetHeight);
      case FitMode.blurPad:
        return _blurPad(source, targetWidth, targetHeight);
    }
  }

  /// Orientation-agnostic square cover-crop.
  ///
  /// A square of side max(tw, th) lets the launcher show the center strip in
  /// portrait and the center band in landscape — both pixel-perfect from a
  /// single bitmap, so rotating never produces black bars or stretched crops.
  img.Image _centerCrop(img.Image src, int tw, int th) {
    final targetSide = math.max(tw, th);
    final cropSide = math.min(targetSide, math.min(src.width, src.height));
    final x = (src.width - cropSide) ~/ 2;
    final y = (src.height - cropSide) ~/ 2;
    var out = img.copyCrop(src, x: x, y: y, width: cropSide, height: cropSide);
    const maxUpscale = 2.5;
    final upscale = targetSide / cropSide;
    // Resize to the exact target side only when the source has enough pixels
    // overall AND the required upscale is modest; otherwise keep the crop and
    // let the OS scale it.
    if (cropSide > 0 &&
        targetSide * targetSide <= src.width * src.height &&
        upscale <= maxUpscale) {
      out = img.copyResize(
        out,
        width: targetSide,
        height: targetSide,
        interpolation: img.Interpolation.average,
      );
    }
    return out;
  }

  img.Image _blurPad(img.Image src, int tw, int th) {
    final side = math.max(tw, th);
    final bg = img.gaussianBlur(_coverTo(src, side, side), radius: 16);
    const darken = 0.45;
    for (final p in bg) {
      p.r = (p.r * darken).round().clamp(0, 255);
      p.g = (p.g * darken).round().clamp(0, 255);
      p.b = (p.b * darken).round().clamp(0, 255);
    }
    final fg = _containTo(src, side, side);
    img.compositeImage(bg, fg,
        dstX: (side - fg.width) ~/ 2, dstY: (side - fg.height) ~/ 2);
    return bg;
  }

  img.Image _coverTo(img.Image src, int tw, int th) {
    final resized = src.width / src.height > tw / th
        ? img.copyResize(src, height: th,
            interpolation: img.Interpolation.average)
        : img.copyResize(src, width: tw,
            interpolation: img.Interpolation.average);
    return img.copyCrop(resized,
        x: (resized.width - tw) ~/ 2,
        y: (resized.height - th) ~/ 2,
        width: tw,
        height: th);
  }

  img.Image _containTo(img.Image src, int tw, int th) {
    return src.width / src.height > tw / th
        ? img.copyResize(src, width: tw,
            interpolation: img.Interpolation.average)
        : img.copyResize(src, height: th,
            interpolation: img.Interpolation.average);
  }
}
