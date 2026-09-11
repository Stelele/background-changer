import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:wallpaper_changer/models/settings.dart';
import 'package:wallpaper_changer/services/image_fitter.dart';

void main() {
  final fitter = ImageFitter();
  const tw = 1080, th = 2340; // phone-ish portrait target
  // Orientation-agnostic policy: outputs are SQUARES sized to
  // max(targetWidth, targetHeight) so portrait shows the center strip and
  // landscape the center band — no black bars, no re-crop artefacts.

  test('centerCrop 4K landscape becomes target-side square', () {
    final src = img.Image(width: 3840, height: 2160);
    final out = fitter.transform(src,
        targetWidth: tw, targetHeight: th, mode: FitMode.centerCrop);
    // side = max(tw, th) = 2340; crop 2160 (limited by source height);
    // budget 2340^2 <= 3840*2160 and upscale 1.083 <= 2.5 → exact side.
    expect(out.width, th);
    expect(out.height, th);
  });

  test('centerCrop keeps small-source crop unscaled', () {
    final src = img.Image(width: 600, height: 400);
    final out = fitter.transform(src,
        targetWidth: tw, targetHeight: th, mode: FitMode.centerCrop);
    // side limited by source: 400; budget fails → no upscale.
    expect(out.width, 400);
    expect(out.height, 400);
  });

  test('panorama is not mega-upscaled', () {
    final src = img.Image(width: 8000, height: 400);
    final out = fitter.transform(src,
        targetWidth: tw, targetHeight: th, mode: FitMode.centerCrop);
    // side limited by source height 400; budget 2340^2 > 8000*400 → kept.
    expect(out.width, 400);
    expect(out.height, 400);
  });

  test('sub-2.5MP 2048x1152 source stays at native square', () {
    final src = img.Image(width: 2048, height: 1152);
    final out = fitter.transform(src,
        targetWidth: tw, targetHeight: th, mode: FitMode.centerCrop);
    // budget 2340^2 (5.48M) > 2.36M source pixels → 1152x1152, OS scales.
    expect(out.width, 1152);
    expect(out.height, 1152);
  });

  test('square source to wide target returns centered square', () {
    final src = img.Image(width: 1000, height: 1000);
    final out = fitter.transform(src,
        targetWidth: 2000, targetHeight: 1000, mode: FitMode.centerCrop);
    // targetSide 2000 > min(1000) → crop 1000; budget 4M > 1M → no resize.
    expect(out.width, 1000);
    expect(out.height, 1000);
  });

  test('center strip of the square equals the portrait crop content', () {
    // Left half red, right half blue; square center-crop must keep the
    // vertical red|blue boundary visible in the center column strip.
    final src = img.Image(width: 400, height: 200);
    for (final p in src) {
      final red = p.x < 200;
      p.r = red ? 255 : 0;
      p.g = 0;
      p.b = red ? 0 : 255;
    }
    final out = fitter.transform(src,
        targetWidth: 100, targetHeight: 200, mode: FitMode.centerCrop);
    expect(out.width, 200);
    expect(out.height, 200);
    final leftMid = out.getPixel(40, 100); // inside center 100-wide strip
    final rightMid = out.getPixel(160, 100);
    expect(leftMid.r, 255);
    expect(leftMid.b, 0);
    expect(rightMid.b, 255);
    expect(rightMid.r, 0);
  });

  test('asIs returns the same image untouched', () {
    final src = img.Image(width: 123, height: 45);
    final out = fitter.transform(src,
        targetWidth: tw, targetHeight: th, mode: FitMode.asIs);
    expect(identical(out, src), isTrue);
  });

  test('blurPad output is exactly target-side square', () {
    final src = img.Image(width: 2000, height: 1000);
    final out = fitter.transform(src,
        targetWidth: tw, targetHeight: th, mode: FitMode.blurPad);
    expect(out.width, th);
    expect(out.height, th);
  });

  test('exif orientation baked before mode dispatch', () {
    final src = img.Image(width: 100, height: 40);
    src.exif.imageIfd.orientation = 6; // 90° CW: baked dims become 40x100
    final asIs = fitter.transform(src,
        targetWidth: 1, targetHeight: 1, mode: FitMode.asIs);
    expect(asIs.width, 40);
    expect(asIs.height, 100);
    // (A centered square crop commutes with 90° rotations, so the centerCrop
    // geometry itself is orientation-independent — bake is proven above.)
  });

  test('png source decodable upstream (sanity for mixed sources)', () {
    final bytes = img.encodePng(img.Image(width: 50, height: 80));
    final src = img.decodeImage(bytes);
    expect(src, isNotNull);
    final out = fitter.transform(src!,
        targetWidth: 100, targetHeight: 200, mode: FitMode.centerCrop);
    expect(out.width, out.height); // square by construction
    expect(out.width, 50); // limited by source min dimension
  });
}
