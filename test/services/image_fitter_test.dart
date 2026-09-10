import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:wallpaper_changer/models/settings.dart';
import 'package:wallpaper_changer/services/image_fitter.dart';

void main() {
  final fitter = ImageFitter();
  const tw = 1080, th = 2340; // phone-ish portrait target

  test('centerCrop portrait output equals target ratio', () {
    final src = img.Image(width: 3840, height: 2160); // landscape
    final out = fitter.transform(src,
        targetWidth: tw, targetHeight: th, mode: FitMode.centerCrop);
    expect(out.width, tw);
    expect(out.height, th);
  });

  test('centerCrop keeps small-source crop unscaled', () {
    final src = img.Image(width: 600, height: 400);
    final out = fitter.transform(src,
        targetWidth: tw, targetHeight: th, mode: FitMode.centerCrop);
    expect(out.height, 400);
    expect((out.width / out.height - tw / th).abs(), lessThan(0.01));
  });

  test('panorama is not mega-upscaled', () {
    final src = img.Image(width: 8000, height: 400);
    final out = fitter.transform(src,
        targetWidth: tw, targetHeight: th, mode: FitMode.centerCrop);
    expect(out.width, (400 * tw / th).round()); // 185: crop kept, no resize
    expect(out.height, 400);
  });

  test('exif orientation baked before cropping', () {
    final src = img.Image(width: 100, height: 40);
    // orientation 6 = rotate 90 CW: baked dims become 40x100
    src.exif.imageIfd.orientation = 6;
    // asIs returns the image untouched apart from the entry bake, so the
    // swapped dims prove the bake runs before the mode switch.
    final asIs = fitter.transform(src,
        targetWidth: 1, targetHeight: 1, mode: FitMode.asIs);
    expect(asIs.width, 40);
    expect(asIs.height, 100);
    // On the baked 40x100 image, centerCrop to 20x50 matches aspect (0.4)
    // and has pixel budget, so it resolves to the exact target size.
    final out = fitter.transform(src,
        targetWidth: 20, targetHeight: 50, mode: FitMode.centerCrop);
    expect(out.width, 20);
    expect(out.height, 50);
  });

  test('asIs returns the same image untouched', () {
    final src = img.Image(width: 123, height: 45);
    final out = fitter.transform(src,
        targetWidth: tw, targetHeight: th, mode: FitMode.asIs);
    expect(identical(out, src), isTrue);
  });

  test('blurPad output is exactly target size', () {
    final src = img.Image(width: 2000, height: 1000);
    final out = fitter.transform(src,
        targetWidth: tw, targetHeight: th, mode: FitMode.blurPad);
    expect(out.width, tw);
    expect(out.height, th);
  });

  test('square source cropped to wide target keeps full height', () {
    final src = img.Image(width: 1000, height: 1000);
    final out = fitter.transform(src,
        targetWidth: 2000, targetHeight: 1000, mode: FitMode.centerCrop);
    expect(out.width, 1000);
    expect(out.height, 500);
  });

  test('png source decodable upstream (sanity for mixed sources)', () {
    final bytes = img.encodePng(img.Image(width: 50, height: 80));
    final src = img.decodeImage(bytes);
    expect(src, isNotNull);
    final out = fitter.transform(src!,
        targetWidth: 100, targetHeight: 200, mode: FitMode.centerCrop);
    expect(out.width / out.height, closeTo(0.5, 0.01));
  });
}
