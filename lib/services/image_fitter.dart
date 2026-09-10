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

  img.Image _centerCrop(img.Image src, int tw, int th) {
    final srcAspect = src.width / src.height;
    final targetAspect = tw / th;
    int cw, ch;
    if (srcAspect > targetAspect) {
      ch = src.height;
      cw = (ch * targetAspect).round();
    } else {
      cw = src.width;
      ch = (cw / targetAspect).round();
    }
    final x = (src.width - cw) ~/ 2;
    final y = (src.height - ch) ~/ 2;
    var out = img.copyCrop(src, x: x, y: y, width: cw, height: ch);
    const maxUpscale = 2.5;
    final cropPx = cw * ch;
    final upscale = math.max(tw / cw, th / ch);
    // Resize to the exact target only when the source has enough pixels
    // overall AND the required upscale from the crop is modest; otherwise
    // keep the crop and let the OS scale it.
    if (tw * th <= src.width * src.height &&
        cropPx > 0 &&
        upscale <= maxUpscale) {
      out = img.copyResize(
        out,
        width: tw,
        height: th,
        interpolation: img.Interpolation.average,
      );
    }
    return out;
  }

  img.Image _blurPad(img.Image src, int tw, int th) {
    final bg = img.gaussianBlur(_coverTo(src, tw, th), radius: 16);
    const darken = 0.45;
    for (final p in bg) {
      p.r = (p.r * darken).round().clamp(0, 255);
      p.g = (p.g * darken).round().clamp(0, 255);
      p.b = (p.b * darken).round().clamp(0, 255);
    }
    final fg = _containTo(src, tw, th);
    img.compositeImage(bg, fg,
        dstX: (tw - fg.width) ~/ 2, dstY: (th - fg.height) ~/ 2);
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
