import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'provider.dart';

/// GET [url] with a timeout, mapping every failure mode to [PotdException]
/// (contract: provider fetches never throw anything else).
Future<http.Response> providerGet(
  http.Client client,
  Uri url,
  String what,
  Duration timeout, {
  Map<String, String>? headers,
}) async {
  try {
    return await client.get(url, headers: headers).timeout(timeout);
  } on TimeoutException {
    throw PotdException('$what timeout');
  } on http.ClientException catch (e) {
    throw PotdException('network $what: ${e.message}');
  } on IOException catch (e) {
    throw PotdException('network $what: $e');
  }
}
