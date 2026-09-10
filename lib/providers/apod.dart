import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/potd_item.dart';
import 'provider.dart';
import 'provider_http.dart';

class ApodProvider implements PotdProvider {
  final http.Client _client;
  final Duration timeout;

  static const String apiUrl =
      'https://api.nasa.gov/planetary/apod?api_key=DEMO_KEY';

  ApodProvider({http.Client? client, this.timeout = const Duration(seconds: 30)})
      : _client = client ?? http.Client();

  @override
  String get id => ProviderId.apod.name;

  @override
  String get label => 'NASA APOD';

  @override
  Future<PotdItem> fetch() async {
    final res = await providerGet(_client, Uri.parse(apiUrl), 'archive', timeout);
    if (res.statusCode != 200) {
      throw PotdException('apod http ${res.statusCode}');
    }
    Map<String, dynamic> data;
    try {
      data = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw const PotdException('apod response not json');
    }
    if (data['media_type'] != 'image') {
      throw const PotdException('apod media is not an image');
    }
    final url = data['url'];
    if (url is! String || url.isEmpty) {
      throw const PotdException('apod missing image url');
    }
    // Uri.parse throws a raw FormatException on malformed input and the http
    // client throws ArgumentError on scheme-less urls — both would escape the
    // PotdException-only contract, so validate before parsing.
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw const PotdException('apod invalid image url');
    }
    final imgRes = await providerGet(_client, uri, 'image', timeout);
    if (imgRes.statusCode != 200) {
      throw PotdException('image http ${imgRes.statusCode}');
    }
    final b = imgRes.bodyBytes;
    if (b.isEmpty) {
      throw const PotdException('image empty body');
    }
    // APOD serves mostly JPEGs but occasionally PNGs — accept either magic.
    final isJpeg = b.length >= 2 && b[0] == 0xFF && b[1] == 0xD8;
    final isPng = b.length >= 4 &&
        b[0] == 0x89 &&
        b[1] == 0x50 &&
        b[2] == 0x4E &&
        b[3] == 0x47;
    if (!isJpeg && !isPng) {
      throw const PotdException('image not jpeg/png');
    }
    final date = data['date'];
    final ds = date is String ? date : '';
    final yymmdd = ds.length == 10
        ? '${ds.substring(2, 4)}${ds.substring(5, 7)}${ds.substring(8, 10)}'
        : '';
    final title = data['title'];
    final copyright = data['copyright'];
    return PotdItem(
      meta: PotdMeta(
        title: title is String ? title : 'APOD',
        author: copyright is String ? copyright : '',
        infoUrl: yymmdd.isEmpty
            ? 'https://apod.nasa.gov/apod/'
            : 'https://apod.nasa.gov/apod/ap$yymmdd.html',
        imageUrl: url,
      ),
      bytes: b,
    );
  }
}
