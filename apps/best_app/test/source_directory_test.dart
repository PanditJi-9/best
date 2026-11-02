import 'dart:io';
import 'dart:ui' as ui;

import 'package:best_app/src/extension_host.dart';
import 'package:best_app/src/l10n/generated/app_localizations.dart';
import 'package:best_app/src/providers.dart';
import 'package:best_app/src/screens/source_directory_screen.dart';
import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'extension_installer_test.dart' show Host, Repository, entry;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final item in [
      (BestFonts.text, 'IBMPlexSansArabic-Regular.ttf'),
      (BestFonts.display, 'Amiri-Regular.ttf'),
    ]) {
      final loader = FontLoader(item.$1)
        ..addFont(rootBundle.load('packages/best_ui/assets/fonts/${item.$2}'));
      await loader.load();
    }
  });
  final entries = [
    entry('AniZone', kind: 'anime'),
    entry('MangaDex'),
    for (var i = 0; i < 1227; i++) entry('Site$i')
  ];
  final capture = GlobalKey();

  Future<Host> open(WidgetTester tester,
      {String locale = 'en',
      Brightness brightness = Brightness.dark,
      double scale = 1}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final host = Host();
    final installer = ExtensionInstaller(
        host: host, repository: Repository(entries), preferences: null);
    await tester.pumpWidget(ProviderScope(
        overrides: [
          extensionHostProvider.overrideWithValue(host),
          extensionInstallerProvider.overrideWithValue(installer),
          extensionDirectoryProvider.overrideWith(
              (ref) async => ExtensionDirectory(entries: entries)),
        ],
        child: MaterialApp(
            theme: bestTheme(brightness),
            locale: Locale(locale),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!),
            home: RepaintBoundary(
                key: capture, child: const SourceDirectoryScreen()))));
    await tester.pumpAndSettle();
    return host;
  }

  Future<void> image(WidgetTester tester, String name) async {
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final boundary =
          capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final rendered = await boundary.toImage();
      final data = await rendered.toByteData(format: ui.ImageByteFormat.png);
      rendered.dispose();
      await Directory('build').create(recursive: true);
      await File('build/source-directory-$name.png')
          .writeAsBytes(data!.buffer.asUint8List());
    });
  }

  testWidgets(
      'English directory renders 1000+ choices lazily and activates only after trust',
      (tester) async {
    final host = await open(tester);
    expect(find.textContaining('1229 extensions'), findsOneWidget);
    expect(find.byKey(ValueKey(entries.last.packageName)), findsNothing);
    expect(host.attempts, isEmpty);
    await image(tester, 'en');
    await tester.tap(find.text('Activate').first);
    await tester.pumpAndSettle();
    expect(find.text('Trust this extension publisher?'), findsOneWidget);
    expect(host.attempts, isEmpty);
    await tester.tap(find.text('Trust & activate'));
    await tester.pumpAndSettle();
    expect(host.attempts, [entries.first.packageName]);
    expect(
        find.text('Remove extension'), findsNothing); // Lives in the row menu.
    await tester.tap(find.byTooltip('Extension details').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove extension'));
    await tester.pumpAndSettle();
    expect(host.inventory, isNotEmpty); // Confirmation has not been accepted.
    await tester.tap(find.text('Remove extension').last);
    await tester.pumpAndSettle();
    expect(host.inventory, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('searching exact package never requests any site or APK',
      (tester) async {
    final host = await open(tester);
    await tester.enterText(find.byKey(const ValueKey('directory-search')),
        entries.last.packageName);
    await tester.pumpAndSettle();
    expect(find.text(entries.last.name), findsOneWidget);
    expect(find.text('AniZone'), findsNothing);
    expect(host.attempts, isEmpty);
    await tester.tap(find.text('Anime'));
    await tester.pumpAndSettle();
    expect(find.text('No matching extensions'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Arabic RTL directory uses the same full catalogue',
      (tester) async {
    await open(tester, locale: 'ar');
    expect(find.textContaining('1229 إضافة'), findsOneWidget);
    expect(
        Directionality.of(tester.element(find.byType(SourceDirectoryScreen))),
        TextDirection.rtl);
    await image(tester, 'ar');
    expect(find.text('تفعيل'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'large Arabic text and light theme remain scrollable without overflow',
      (tester) async {
    await open(tester, locale: 'ar', brightness: Brightness.light, scale: 2);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -450));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
