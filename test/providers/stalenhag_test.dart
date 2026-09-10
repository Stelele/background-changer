import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wallpaper_changer/providers/provider.dart';
import 'package:wallpaper_changer/providers/stalenhag.dart';

const fixtureHtml = 'test/fixtures/stalenhag.html';

http.Client clientThat(String html) => MockClient((req) async {
      if (req.url.path.endsWith('.jpg')) {
        return http.Response.bytes([0xFF, 0xD8, 9, 9], 200);
      }
      return http.Response(html, 200);
    });

void main() {
  test('fetch returns item with metadata and bytes', () async {
    final html = await File(fixtureHtml).readAsString();
    final p = StalenhagProvider(
        client: clientThat(html), now: () => DateTime(2026, 9, 10));
    final item = await p.fetch();
    expect(item.bytes, [0xFF, 0xD8, 9, 9]);
    expect(item.meta.author, 'Simon Stålenhag');
    expect(item.meta.imageUrl,
        startsWith('https://www.simonstalenhag.se/4k/'));
    expect(item.meta.imageUrl, endsWith('_big.jpg'));
    expect(item.meta.title, contains('labyrinth_03')); // day 252 % 5 == 2
  });

  test('rotation is day-deterministic over the link list', () async {
    final html = await File(fixtureHtml).readAsString();
    final picked = <String>[];
    for (final day in [DateTime(2026, 1, 1), DateTime(2026, 1, 2), DateTime(2026, 1, 6)]) {
      final p = StalenhagProvider(client: clientThat(html), now: () => day);
      picked.add((await p.fetch()).meta.imageUrl);
    }
    expect(picked[0], contains('svema_01')); // day 0
    expect(picked[1], contains('svema_02')); // day 1
    expect(picked[2], contains('svema_01')); // day 5 % 5 == 0
  });

  test('html without image links throws PotdException', () async {
    final p = StalenhagProvider(
        client: clientThat('<html><body>redesign</body></html>'),
        now: () => DateTime(2026, 9, 10));
    await expectLater(p.fetch(), throwsA(isA<PotdException>()));
  });

  test('non-200 homepage throws PotdException', () async {
    final p = StalenhagProvider(
        client: MockClient((req) async => http.Response('oops', 500)),
        now: () => DateTime(2026, 9, 10));
    await expectLater(p.fetch(), throwsA(isA<PotdException>()));
  });

  // --- Fix 1: timeout ---

  test('stalled request times out as PotdException', () async {
    final neverCompletes = MockClient((_) async {
      await Completer<void>().future; // never resolves
      return http.Response('', 200);
    });
    final p = StalenhagProvider(
      client: neverCompletes,
      now: () => DateTime(2026, 9, 10),
      timeout: const Duration(milliseconds: 20),
    );
    await expectLater(p.fetch(), throwsA(isA<PotdException>()));
  });

  // --- Fix 2: non-artwork images filtered ---

  test('extractImagePaths filters karta and nyckel', () {
    const html = '''
    <a href="4k/svema_karta_big.jpg"></a>
    <a href="4k/svema_nyckel_big.jpg"></a>
    <a href="4k/svema_01_big.jpg"></a>
    ''';
    final paths = StalenhagProvider.extractImagePaths(html);
    expect(paths, ['4k/svema_01_big.jpg']);
  });

  // --- Fix 3: image download failure ---

  test('404 on image download throws PotdException', () async {
    final html = await File(fixtureHtml).readAsString();
    final client = MockClient((req) async {
      if (req.url.path.endsWith('.jpg')) {
        return http.Response('missing', 404);
      }
      return http.Response(html, 200);
    });
    final p = StalenhagProvider(
        client: client, now: () => DateTime(2026, 9, 10));
    await expectLater(p.fetch(), throwsA(isA<PotdException>()));
  });

  // --- Fix 4: misleading empty-body error message ---

  test('non-200 image gives status-code error, empty body gives empty-body error', () async {
    final html = await File(fixtureHtml).readAsString();

    // 404 → status-code message
    final client404 = MockClient((req) async {
      if (req.url.path.endsWith('.jpg')) return http.Response('no', 404);
      return http.Response(html, 200);
    });
    final p404 = StalenhagProvider(
        client: client404, now: () => DateTime(2026, 9, 10));
    await expectLater(p404.fetch(), throwsA(
        isA<PotdException>().having((e) => e.reason, 'reason', contains('404'))));

    // 200 but empty body → empty-body message
    final clientEmpty = MockClient((req) async {
      if (req.url.path.endsWith('.jpg')) {
        return http.Response.bytes([], 200);
      }
      return http.Response(html, 200);
    });
    final pEmpty = StalenhagProvider(
        client: clientEmpty, now: () => DateTime(2026, 9, 10));
    await expectLater(pEmpty.fetch(), throwsA(
        isA<PotdException>().having((e) => e.reason, 'reason', contains('empty'))));
  });

  test('network failure throws PotdException', () async {
    final p = StalenhagProvider(
        client: MockClient((req) async => throw http.ClientException('offline')),
        now: () => DateTime(2026, 9, 10));
    await expectLater(
        p.fetch(),
        throwsA(isA<PotdException>()
            .having((e) => e.reason, 'reason', contains('network'))));
  });

  test('non-jpeg image body throws PotdException', () async {
    final html = await File(fixtureHtml).readAsString();
    final client = MockClient((req) async {
      if (req.url.path.endsWith('.jpg')) {
        return http.Response.bytes([9, 9, 9], 200);
      }
      return http.Response(html, 200);
    });
    final p = StalenhagProvider(
        client: client, now: () => DateTime(2026, 9, 10));
    await expectLater(
        p.fetch(),
        throwsA(isA<PotdException>()
            .having((e) => e.reason, 'reason', contains('jpeg'))));
  });
}
