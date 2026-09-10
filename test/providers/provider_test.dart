import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallpaper_changer/models/potd_item.dart';
import 'package:wallpaper_changer/providers/provider.dart';
import 'package:wallpaper_changer/providers/provider_factory.dart';

void main() {
  test('PotdMeta and PotdItem hold their values', () {
    final meta = PotdMeta(
      title: 'T', author: 'A', infoUrl: 'https://i', imageUrl: 'https://img',
    );
    final item = PotdItem(meta: meta, bytes: Uint8List.fromList([1, 2, 3]));
    expect(item.meta.title, 'T');
    expect(item.bytes, [1, 2, 3]);
  });

  test('PotdException exposes reason', () {
    expect(const PotdException('no images').toString(), contains('no images'));
  });

  test('ProviderId covers all four sources', () {
    expect(ProviderId.values.map((e) => e.name),
        ['stalenhag', 'bing', 'apod', 'wikimedia']);
  });

  test('unimplemented factory ids throw PotdException, not UnimplementedError', () {
    for (final id in [ProviderId.bing, ProviderId.apod, ProviderId.wikimedia]) {
      expect(() => defaultProviderFor(id), throwsA(isA<PotdException>()));
    }
  });
}
