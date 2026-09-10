import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/potd_item.dart';
import 'provider.dart';
import 'provider_http.dart';

class WikimediaProvider implements PotdProvider {
  final http.Client _client;
  final DateTime Function() _now;
  final Duration timeout;

  static const _ua = {'User-Agent': 'WallpaperChanger/0.1 (personal Flutter app)'};

  WikimediaProvider({
    http.Client? client,
    DateTime Function()? now,
    this.timeout = const Duration(seconds: 30),
  })  : _client = client ?? http.Client(),
        _now = now ?? DateTime.now;

  @override
  String get id => ProviderId.wikimedia.name;

  @override
  String get label => 'Wikimedia POTD';

  @override
  Future<PotdItem> fetch() async {
    final d = _now();
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    final url = Uri.parse(
        'https://commons.wikimedia.org/api/rest_v1/feed/featured/${d.year}/$mm/$dd');
    final res = await providerGet(_client, url, 'feed', timeout, headers: _ua);
    if (res.statusCode != 200) {
      throw PotdException('commons http ${res.statusCode}');
    }
    Map<String, dynamic> data;
    try {
      data = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw const PotdException('commons response not json');
    }
    final image = data['image'];
    if (image is! Map<String, dynamic>) {
      throw const PotdException('no picture of the day');
    }
    final imgObj = image['image'];
    final rawSource = imgObj is Map<String, dynamic> ? imgObj['source'] : null;
    if (rawSource is! String || rawSource.isEmpty) {
      throw const PotdException('no full-size source');
    }
    final source = rawSource.split('?').first;
    final lower = source.toLowerCase();
    if (!lower.endsWith('.jpg') && !lower.endsWith('.jpeg') && !lower.endsWith('.png')) {
      throw const PotdException('commons media is not a still image');
    }
    final uri = Uri.tryParse(source);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
      throw const PotdException('commons invalid image url');
    }
    final imgRes = await providerGet(_client, uri, 'image', timeout, headers: _ua);
    if (imgRes.statusCode != 200) {
      throw PotdException('image http ${imgRes.statusCode}');
    }
    final b = imgRes.bodyBytes;
    if (b.isEmpty) {
      throw const PotdException('image empty body');
    }
    final isJpeg = b.length >= 2 && b[0] == 0xFF && b[1] == 0xD8;
    final isPng = b.length >= 4 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47;
    if (!isJpeg && !isPng) {
      throw const PotdException('image not jpeg or png');
    }
    final artistRaw = image['artist'];
    String author = '';
    if (artistRaw is Map<String, dynamic>) {
      final html = artistRaw['html'];
      // Decode entities with &amp; last so '&amp;lt;' yields the literal
      // text '&lt;' instead of double-decoding to '<'.
      author = (html is String ? html : '')
          .replaceAll(RegExp(r'<[^>]*>'), '')
          .replaceAll('&quot;', '"')
          .replaceAll('&#39;', "'")
          .replaceAll('&apos;', "'")
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .replaceAll('&nbsp;', ' ')
          .replaceAll('&amp;', '&')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
    } else if (artistRaw is String) {
      author = artistRaw.replaceAll(RegExp(r'\s+'), ' ').trim();
    }
    final title = image['title'];
    final filePage = image['file_page'];
    return PotdItem(
      meta: PotdMeta(
        title: title is String ? title.replaceFirst('File:', '') : 'Wikimedia POTD',
        author: author,
        infoUrl: filePage is String ? filePage : 'https://commons.wikimedia.org/',
        imageUrl: source,
      ),
      bytes: b,
    );
  }
}
