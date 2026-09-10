import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wallpaper_changer/providers/provider.dart';
import 'package:wallpaper_changer/providers/wikimedia.dart';

void main() {
  http.Client clientFor(String body) => MockClient((req) async {
        if (req.url.path.toLowerCase().endsWith('.jpg')) {
          return http.Response.bytes([0xFF, 0xD8, 3, 3], 200);
        }
        return http.Response(body, 200);
      });

  test('fetch extracts full-size source, title, artist, file page', () async {
    final body = await File('test/fixtures/wikimedia.json').readAsString();
    final item = await WikimediaProvider(
        client: clientFor(body), now: () => DateTime(2026, 9, 10)).fetch();
    expect(item.meta.imageUrl,
        'https://upload.wikimedia.org/wikipedia/commons/a/ab/Some_Place.jpg');
    expect(item.meta.title, 'Some Place.jpg');
    expect(item.meta.author, 'Photo Person');
    expect(item.meta.infoUrl, 'https://commons.wikimedia.org/wiki/File:Some_Place.jpg');
    expect(item.bytes.toList(), [0xFF, 0xD8, 3, 3]);
  });

  test('stores imageUrl without tracking query', () async {
    final body = await File('test/fixtures/wikimedia.json').readAsString();
    final item = await WikimediaProvider(
        client: clientFor(body), now: () => DateTime(2026, 9, 10)).fetch();
    expect(item.meta.imageUrl,
        'https://upload.wikimedia.org/wikipedia/commons/a/ab/Some_Place.jpg');
    expect(item.meta.imageUrl.contains('?'), isFalse);
  });

  test('decodes html entities in artist name', () async {
    final body = (await File('test/fixtures/wikimedia.json').readAsString())
        .replaceAll('Photo Person', 'Ben &amp; Jerry');
    final item = await WikimediaProvider(
        client: clientFor(body), now: () => DateTime(2026, 9, 10)).fetch();
    expect(item.meta.author, 'Ben & Jerry');
  });

  test('uses today date in endpoint url and sends user-agent', () async {
    Uri? seen;
    Map<String, String>? seenHeaders;
    final p = WikimediaProvider(
      client: MockClient((req) async {
        if (req.url.path.endsWith('.jpg')) {
          return http.Response.bytes([0xFF, 0xD8, 3, 3], 200);
        }
        seen = req.url;
        seenHeaders = req.headers;
        return http.Response(
            await File('test/fixtures/wikimedia.json').readAsString(), 200);
      }),
      now: () => DateTime(2026, 9, 10),
    );
    await p.fetch();
    expect(seen!.path, contains('/feed/featured/2026/09/10'));
    expect(seenHeaders?['User-Agent'] ?? seenHeaders?['user-agent'], contains('WallpaperChanger'));
  });

  test('video day throws PotdException', () async {
    final body = await File('test/fixtures/wikimedia_video.json').readAsString();
    await expectLater(
        WikimediaProvider(
                client: clientFor(body), now: () => DateTime(2026, 9, 10))
            .fetch(),
        throwsA(isA<PotdException>()));
  });

  test('missing image object throws PotdException', () async {
    final p = WikimediaProvider(
        client: clientFor('{"tfa":{}}'), now: () => DateTime(2026, 9, 10));
    await expectLater(p.fetch(), throwsA(isA<PotdException>()));
  });

  test('png image accepted', () async {
    final body = (await File('test/fixtures/wikimedia.json').readAsString())
        .replaceAll('Some_Place.jpg', 'Some_Place.png');
    final client = MockClient((req) async {
      if (req.url.path.toLowerCase().endsWith('.png')) {
        return http.Response.bytes([0x89, 0x50, 0x4E, 0x47, 1], 200);
      }
      return http.Response(body, 200);
    });
    final item = await WikimediaProvider(
        client: client, now: () => DateTime(2026, 9, 10)).fetch();
    expect(item.meta.imageUrl, endsWith('.png'));
  });
}
