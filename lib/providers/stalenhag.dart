import 'dart:async';

import 'package:http/http.dart' as http;

import '../models/potd_item.dart';
import 'provider.dart';

class StalenhagProvider implements PotdProvider {
  final http.Client _client;
  final DateTime Function() _now;
  final Duration timeout;
  static const String baseUrl = 'https://www.simonstalenhag.se';

  StalenhagProvider({
    http.Client? client,
    DateTime Function()? now,
    this.timeout = const Duration(seconds: 30),
  })  : _client = client ?? http.Client(),
        _now = now ?? DateTime.now;

  @override
  String get id => ProviderId.stalenhag.name;

  @override
  String get label => 'Simon Stålenhag';

  @override
  Future<PotdItem> fetch() async {
    try {
      final res = await _client.get(Uri.parse('$baseUrl/')).timeout(timeout);
      if (res.statusCode != 200) {
        throw PotdException('homepage http ${res.statusCode}');
      }
      final links = extractImagePaths(res.body);
      if (links.isEmpty) throw const PotdException('no images found in html');
      // Calendar-day index since Jan 1, normalized to UTC so the rotation is
      // deterministic regardless of the host timezone / DST.
      final today = _now();
      final dayIndex = DateTime.utc(today.year, today.month, today.day)
          .difference(DateTime.utc(today.year, 1, 1))
          .inDays;
      final path = links[dayIndex % links.length];
      final imageUrl = '$baseUrl/$path';
      final imgRes = await _client.get(Uri.parse(imageUrl)).timeout(timeout);
      if (imgRes.statusCode != 200) {
        throw PotdException('image http ${imgRes.statusCode}');
      }
      if (imgRes.bodyBytes.isEmpty) {
        throw const PotdException('image empty body');
      }
      final name = path
          .split('/')
          .last
          .replaceFirst(RegExp(r'_big\.jpg$'), '');
      return PotdItem(
        meta: PotdMeta(
          title: 'Simon Stålenhag — $name',
          author: 'Simon Stålenhag',
          infoUrl: baseUrl,
          imageUrl: imageUrl,
        ),
        bytes: imgRes.bodyBytes,
      );
    } on TimeoutException {
      throw const PotdException('timeout');
    }
  }

  /// Ordered, de-duplicated `4k/xxx_big.jpg` paths from the homepage html,
  /// excluding map/key artwork (`_karta_` / `_nyckel_` files).
  static List<String> extractImagePaths(String html) {
    final re = RegExp(r'(?:href|src)="(4k/[A-Za-z0-9_]+_big\.jpg)"');
    return re
        .allMatches(html)
        .map((m) => m.group(1)!)
        .where((p) => !p.contains('_karta_') && !p.contains('_nyckel_'))
        .toSet()
        .toList();
  }
}
