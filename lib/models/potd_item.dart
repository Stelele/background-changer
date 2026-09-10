import 'dart:typed_data';

class PotdMeta {
  final String title;
  final String author;
  final String infoUrl;
  final String imageUrl;

  const PotdMeta({
    required this.title,
    required this.author,
    required this.infoUrl,
    required this.imageUrl,
  });
}

class PotdItem {
  final PotdMeta meta;
  final Uint8List bytes;

  const PotdItem({required this.meta, required this.bytes});
}
