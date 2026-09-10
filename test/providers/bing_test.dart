import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wallpaper_changer/providers/bing.dart';
import 'package:wallpaper_changer/providers/provider.dart';

void main() {
  http.Client clientFor(String body, {int code = 200}) => MockClient((req) async {
        // urlbase contains "?id=", so the _UHD.jpg marker sits in the query,
        // not the path — match on the whole URL.
        if (req.url.toString().contains('_UHD.jpg')) {
          return http.Response.bytes([7, 7], 200);
        }
        return http.Response(body, code);
      });

  test('fetch builds UHD url from urlbase and extracts metadata', () async {
    final body = await File('test/fixtures/bing.json').readAsString();
    final p = BingProvider(client: clientFor(body));
    final item = await p.fetch();
    expect(item.meta.imageUrl,
        'https://www.bing.com/th?id=OHR.TestHill_EN-US1234_UHD.jpg');
    expect(item.meta.title, 'Test Hill');
    expect(item.meta.author, contains('Photographer'));
    expect(item.bytes.toList(), [7, 7]);
  });

  test('empty images array throws PotdException', () async {
    final p = BingProvider(client: clientFor('{"images":[]}'));
    await expectLater(p.fetch(), throwsA(isA<PotdException>()));
  });

  test('malformed json throws PotdException', () async {
    final p = BingProvider(client: clientFor('<html>blocked</html>'));
    await expectLater(p.fetch(), throwsA(isA<PotdException>()));
  });

  test('non-map images entry throws PotdException', () async {
    final p = BingProvider(client: clientFor('{"images":["garbage"]}'));
    await expectLater(p.fetch(), throwsA(isA<PotdException>()));
  });

  test('image 404 throws PotdException', () async {
    final body = await File('test/fixtures/bing.json').readAsString();
    final p = BingProvider(
        client: MockClient((req) async => req.url.toString().contains('_UHD.jpg')
            ? http.Response('missing', 404)
            : http.Response(body, 200)));
    await expectLater(p.fetch(), throwsA(isA<PotdException>()));
  });

  test('timeout on stalled archive request throws PotdException', () async {
    final p = BingProvider(
        client: MockClient((req) async => Completer<http.Response>().future),
        timeout: const Duration(milliseconds: 20));
    await expectLater(p.fetch(), throwsA(isA<PotdException>()));
  });
}
