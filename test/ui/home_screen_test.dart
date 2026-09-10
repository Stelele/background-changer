import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:wallpaper_changer/models/potd_item.dart';
import 'package:wallpaper_changer/services/wallpaper_repo.dart';
import 'package:wallpaper_changer/ui/home_screen.dart';

void main() {
  testWidgets('home screen renders chips, controls, hero, recents',
      (tester) async {
    // Real dart:io must run outside the fake async zone.
    final tmp =
        (await tester.runAsync(() => Directory.systemTemp.createTemp('ui_test')))!;
    addTearDown(() => tmp.deleteSync(recursive: true));
    final repo = WallpaperRepo(tmp);
    await tester.runAsync(() => repo.saveCurrent(
          item: PotdItem(
            meta: const PotdMeta(
                title: 'Test Art',
                author: 'A',
                infoUrl: 'https://i',
                imageUrl: 'https://img/1.jpg'),
            bytes: img.encodeJpg(img.Image(width: 16, height: 16)),
          ),
          appliedAt: DateTime(2026, 9, 10),
        ));
    // Large surface so the lazily-built ListView constructs all children
    // (default 800x600 viewport only builds the hero and clips the controls).
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(
        repo: repo,
        onRefresh: () async => true,
        onSettingsChanged: (s) async {},
      ),
    ));
    // pumpAndSettle never settles here: the hero Image.file stream stays
    // pending in the fake async zone (real IO), so pump fixed frames.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final ex = tester.takeException();
    expect(ex, isNull, reason: 'unexpected build exception: $ex');
    expect(find.text('Wallpaper Changer'), findsOneWidget);
    expect(find.text('Simon Stålenhag'), findsOneWidget);
    expect(find.text('Bing'), findsOneWidget);
    expect(find.text('NASA APOD'), findsOneWidget);
    expect(find.text('Wikimedia POTD'), findsOneWidget);
    expect(find.text('Refresh now'), findsOneWidget);
    expect(find.text('Wi-Fi only'), findsOneWidget);
    expect(find.text('Test Art'), findsOneWidget);
    expect(find.byType(Image), findsWidgets);
  });
}
