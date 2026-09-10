import 'package:http/http.dart' as http;

import 'provider.dart';
import 'stalenhag.dart';

PotdProvider defaultProviderFor(ProviderId id,
    {http.Client? client, DateTime Function()? now}) {
  switch (id) {
    case ProviderId.stalenhag:
      return StalenhagProvider(client: client, now: now);
    case ProviderId.bing:
    case ProviderId.apod:
    case ProviderId.wikimedia:
      throw const PotdException('provider not yet implemented');
  }
}
