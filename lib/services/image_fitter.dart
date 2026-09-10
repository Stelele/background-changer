import 'package:image/image.dart' as img;

import '../models/settings.dart';

class ImageFitter {
  img.Image transform(
    img.Image source, {
    required int targetWidth,
    required int targetHeight,
    required FitMode mode,
  }) {
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
    // Scale to exactly the target only when the source carries at least as
    // many pixels as the target would need; otherwise keep the crop at
    // native source resolution so we never upscale beyond source quality.
    if (tw * th <= src.width * src.height) {
      out = img.copyResize(out, width: tw, height: th);
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
        ? img.copyResize(src, height: th)
        : img.copyResize(src, width: tw);
    return img.copyCrop(resized,
        x: (resized.width - tw) ~/ 2,
        y: (resized.height - th) ~/ 2,
        width: tw,
        height: th);
  }

  img.Image _containTo(img.Image src, int tw, int th) {
    return src.width / src.height > tw / th
        ? img.copyResize(src, width: tw)
        : img.copyResize(src, height: th);
  }
}
