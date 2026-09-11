import '../models/potd_item.dart';

enum ProviderId { stalenhag, bing, apod, wikimedia }

abstract class PotdProvider {
  String get id;
  String get label;
  Future<PotdItem> fetch();
}

class PotdException implements Exception {
  final String reason;
  const PotdException(this.reason);

  @override
  String toString() => 'PotdException: $reason';
}
