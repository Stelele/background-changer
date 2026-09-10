import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wallpaper_changer/providers/apod.dart';
import 'package:wallpaper_changer/providers/provider.dart';

void main() {
  http.Client clientFor(String body, {int code = 200}) => MockClient((req) async {
        if (req.url.host == 'apod.nasa.gov' && req.url.path.endsWith('.jpg')) {
          return http.Response.bytes([0xFF, 0xD8, 5, 5], 200);
        }
        if (req.url.host == 'apod.nasa.gov' && req.url.path.endsWith('.png')) {
          return http.Response.bytes([0x89, 0x50, 0x4E, 0x47, 1, 2], 200);
        }
        return http.Response(body, code);
      });

  test('fetch extracts metadata and builds info url from date', () async {
    final body = await File('test/fixtures/apod.json').readAsString();
    final item = await ApodProvider(client: clientFor(body)).fetch();
    expect(item.meta.title, 'The Test Nebula');
    expect(item.meta.author, 'Hubble Heritage Team (NASA)');
    expect(item.meta.infoUrl, 'https://apod.nasa.gov/apod/ap260910.html');
    expect(item.meta.imageUrl,
        'https://apod.nasa.gov/apod/image/2609/test_nebula.jpg');
    expect(item.bytes.toList(), [0xFF, 0xD8, 5, 5]);
  });

  test('video day throws PotdException', () async {
    final body = await File('test/fixtures/apod_video.json').readAsString();
    await expectLater(
        ApodProvider(client: clientFor(body)).fetch(), throwsA(isA<PotdException>()));
  });

  test('non-200 throws PotdException', () async {
    final p = ApodProvider(
        client: MockClient((req) async => http.Response('rate limited', 429)));
    await expectLater(p.fetch(), throwsA(isA<PotdException>()));
  });

  test('missing copyright becomes empty author', () async {
    final minimal = '{"date":"2026-09-10","media_type":"image","title":"T","url":"https://apod.nasa.gov/apod/image/2609/t.jpg"}';
    final item = await ApodProvider(client: clientFor(minimal)).fetch();
    expect(item.meta.author, '');
  });

  test('malformed json throws PotdException', () async {
    final p = ApodProvider(client: clientFor('<html>blocked</html>'));
    await expectLater(p.fetch(), throwsA(isA<PotdException>()));
  });

  test('png magic image body is accepted', () async {
    final body = await File('test/fixtures/apod_png.json').readAsString();
    final item = await ApodProvider(client: clientFor(body)).fetch();
    expect(item.meta.imageUrl,
        'https://apod.nasa.gov/apod/image/2609/test_nebula.png');
    expect(item.bytes.toList(), [0x89, 0x50, 0x4E, 0x47, 1, 2]);
  });

  test('malformed image url throws PotdException, not FormatException', () async {
    const body =
        '{"date":"2026-09-10","media_type":"image","title":"T","url":":::bad:::"}';
    final p = ApodProvider(client: clientFor(body));
    await expectLater(p.fetch(), throwsA(isA<PotdException>()));
  });
}
