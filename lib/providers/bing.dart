import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/potd_item.dart';
import 'provider.dart';
import 'provider_http.dart';

class BingProvider implements PotdProvider {
  final http.Client _client;
  final Duration timeout;

  static const String archiveUrl =
      'https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=1&mkt=en-US';

  BingProvider({http.Client? client, this.timeout = const Duration(seconds: 30)})
      : _client = client ?? http.Client();

  @override
  String get id => ProviderId.bing.name;

  @override
  String get label => 'Bing';

  @override
  Future<PotdItem> fetch() async {
    final res = await providerGet(_client, Uri.parse(archiveUrl), 'archive', timeout);
    if (res.statusCode != 200) {
      throw PotdException('archive http ${res.statusCode}');
    }
    Map<String, dynamic> data;
    try {
      data = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw const PotdException('archive response not json');
    }
    final images = data['images'];
    if (images is! List || images.isEmpty) {
      throw const PotdException('archive has no images');
    }
    if (images.first is! Map<String, dynamic>) {
      throw const PotdException('archive entry malformed');
    }
    final img = images.first as Map<String, dynamic>;
    final urlBase = img['urlbase'];
    if (urlBase is! String || urlBase.isEmpty) {
      throw const PotdException('archive entry missing urlbase');
    }
    final imageUrl = 'https://www.bing.com${urlBase}_UHD.jpg';
    final imgRes = await providerGet(_client, Uri.parse(imageUrl), 'image', timeout);
    if (imgRes.statusCode != 200) {
      throw PotdException('image http ${imgRes.statusCode}');
    }
    final b = imgRes.bodyBytes;
    if (b.isEmpty) {
      throw const PotdException('image empty body');
    }
    if (b.length < 2 || b[0] != 0xFF || b[1] != 0xD8) {
      throw const PotdException('image not jpeg');
    }
    return PotdItem(
      meta: PotdMeta(
        // `is String` guards rather than `as String?` casts: a malformed
        // non-string field degrades to a fallback instead of escaping as a
        // raw TypeError.
        title: img['title'] is String ? img['title'] as String : 'Bing image of the day',
        author: img['copyright'] is String ? img['copyright'] as String : '',
        infoUrl: 'https://www.bing.com/',
        imageUrl: imageUrl,
      ),
      bytes: imgRes.bodyBytes,
    );
  }
}
