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

  test('centerCrop never upscales beyond source quality', () {
    final src = img.Image(width: 600, height: 400);
    final out = fitter.transform(src,
        targetWidth: tw, targetHeight: th, mode: FitMode.centerCrop);
    expect(out.height, 400);
    expect((out.width / out.height - tw / th).abs(), lessThan(0.01));
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
