import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wallpaper_changer/providers/provider.dart';
import 'package:wallpaper_changer/providers/provider_http.dart';

void main() {
  test('raw IOException mapped to PotdException', () async {
    final client = MockClient((req) async => throw const SocketException('tls boom'));
    await expectLater(
        providerGet(client, Uri.parse('https://x/'), 'image', const Duration(seconds: 1)),
        throwsA(isA<PotdException>()));
  });

  test('client exception mapped to PotdException with reason', () async {
    final client = MockClient(
        (req) async => throw http.ClientException('offline'));
    await expectLater(
        providerGet(client, Uri.parse('https://x/'), 'archive', const Duration(seconds: 1)),
        throwsA(isA<PotdException>()));
  });

  test('timeout mapped to PotdException with what', () async {
    final client = MockClient((req) async => await Completer<http.Response>().future);
    await expectLater(
        providerGet(client, Uri.parse('https://x/'), 'homepage', const Duration(milliseconds: 20)),
        throwsA(isA<PotdException>()));
  });

  test('success passes response through', () async {
    final client = MockClient((req) async => http.Response('ok', 200));
    final res = await providerGet(
        client, Uri.parse('https://x/'), 'archive', const Duration(seconds: 1));
    expect(res.statusCode, 200);
  });
}
