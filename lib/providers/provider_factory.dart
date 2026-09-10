import 'package:http/http.dart' as http;

import 'apod.dart';
import 'bing.dart';
import 'provider.dart';
import 'stalenhag.dart';

PotdProvider defaultProviderFor(ProviderId id,
    {http.Client? client, DateTime Function()? now}) {
  switch (id) {
    case ProviderId.stalenhag:
      return StalenhagProvider(client: client, now: now);
    case ProviderId.bing:
      return BingProvider(client: client);
    case ProviderId.apod:
      return ApodProvider(client: client);
    case ProviderId.wikimedia:
      throw const PotdException('provider not yet implemented');
  }
}
