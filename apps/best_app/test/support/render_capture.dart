import 'dart:io';
import 'dart:ui' as ui;

import 'package:best_ui/best_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> loadBestTestFonts() async {
  for (final font in [
    (
      BestFonts.text,
      'packages/best_ui/assets/fonts/IBMPlexSansArabic-Regular.ttf'
    ),
    (BestFonts.display, 'packages/best_ui/assets/fonts/Amiri-Regular.ttf'),
    (BestFontFamily.heading, 'packages/best_ui/assets/fonts/Cairo-Regular.ttf'),
    (
      BestFontFamily.mono,
      'packages/best_ui/assets/fonts/JetBrainsMono-Medium.ttf'
    ),
    ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
  ]) {
    await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
  }
}

Future<void> captureRender(
    WidgetTester tester, GlobalKey key, String name) async {
  await tester.pump();
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    await Directory('build').create(recursive: true);
    await File('build/$name').writeAsBytes(bytes!.buffer.asUint8List());
  });
}
