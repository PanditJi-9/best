import 'dart:ui' as ui;

import 'package:best_app/src/l10n/generated/app_localizations.dart';
import 'package:best_app/src/widgets/chapter_list_sheet.dart';
import 'package:best_domain/best_domain.dart';
import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/render_capture.dart';

List<MediaUnit> _units({UnitKind kind = UnitKind.chapter, int count = 300}) => [
      for (var number = count; number > 0; number--)
        MediaUnit(
          mediaId: 'test::work',
          url: 'unit-$number',
          number: number.toDouble(),
          title: '${kind == UnitKind.chapter ? 'Chapter' : 'Episode'} $number',
          kind: kind,
        ),
    ];

Future<({GlobalKey capture, List<MediaUnit> selected})> _open(
  WidgetTester tester, {
  required List<MediaUnit> units,
  required String current,
  String? initial,
  String language = 'en',
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final capture = GlobalKey();
  final selected = <MediaUnit>[];
  await tester.pumpWidget(RepaintBoundary(
      key: capture,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: bestTheme(Brightness.dark),
        locale: Locale(language),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!),
        home: Scaffold(
            body: Builder(
                builder: (context) => Center(
                        child: FilledButton(
                      onPressed: () => showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          useSafeArea: true,
                          showDragHandle: false,
                          builder: (sheetContext) => ChapterListSheet(
                                units: units,
                                currentUnitId: current,
                                initialUnitId: initial,
                                workTitle: 'A long saved series',
                                onSelected: (unit) {
                                  selected.add(unit);
                                  Navigator.of(sheetContext).pop();
                                },
                              )),
                      child: const Text('Open list'),
                    )))),
      )));
  await tester.tap(find.text('Open list'));
  await tester.pumpAndSettle();
  return (capture: capture, selected: selected);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    WidgetController.hitTestWarningShouldBeFatal = true;
    await loadBestTestFonts();
  });

  testWidgets(
      'a long list opens at the real current chapter and does not reload it',
      (tester) async {
    final units = _units();
    final current = units.firstWhere((unit) => unit.number == 240);
    final fixture = await _open(tester, units: units, current: current.id);
    final semantics = tester.ensureSemantics();
    try {
      final row = find.byKey(ValueKey('chapter-picker-${current.id}'));
      expect(row, findsOneWidget);
      expect(tester.getCenter(row).dy, lessThan(844));
      expect(tester.getSemantics(row).flagsCollection.isSelected,
          ui.Tristate.isTrue);
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(fixture.selected, isEmpty);
      expect(find.byType(ChapterListSheet), findsOneWidget);
      await captureRender(
          tester, fixture.capture, 'chapter-tools-current-en.png');
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
      'Arabic/Persian chapter numbers search without changing source identities',
      (tester) async {
    final units = _units();
    final before = units.map((unit) => unit.id).toList();
    final fixture = await _open(tester, units: units, current: units.first.id);
    await tester.enterText(
        find.byKey(const ValueKey('chapter-picker-search')), 'الفصل ٢۵٠');
    await tester.pumpAndSettle();
    final target = units.firstWhere((unit) => unit.number == 250);
    final row = find.byKey(ValueKey('chapter-picker-${target.id}'));
    expect(row, findsOneWidget);
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(fixture.selected.single.id, target.id);
    expect(units.map((unit) => unit.id), before);
  });

  testWidgets(
      'finding current clears a search and keeps it visible after sorting',
      (tester) async {
    final units = _units();
    final current = units.firstWhere((unit) => unit.number == 240);
    await _open(tester, units: units, current: current.id);
    await tester.enterText(
        find.byKey(const ValueKey('chapter-picker-search')), 'no match');
    await tester.pumpAndSettle();
    expect(find.text('No chapters or episodes match'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('chapter-picker-current')));
    await tester.pumpAndSettle();
    final row = find.byKey(ValueKey('chapter-picker-${current.id}'));
    expect(row, findsOneWidget);
    await tester.tap(find.byTooltip('Newest first'));
    await tester.pumpAndSettle();
    expect(row, findsOneWidget);
    expect(tester.getCenter(row).dy, lessThan(844));
  });

  testWidgets(
      'a next-up focus is not falsely marked as a currently read chapter',
      (tester) async {
    final units = _units();
    final next = units.firstWhere((unit) => unit.number == 249);
    await _open(tester, units: units, current: '', initial: next.id);
    final semantics = tester.ensureSemantics();
    try {
      final row = find.byKey(ValueKey('chapter-picker-${next.id}'));
      expect(row, findsOneWidget);
      expect(tester.getSemantics(row).flagsCollection.isSelected,
          ui.Tristate.isFalse);
      expect(
          find.byKey(const ValueKey('chapter-picker-current')), findsNothing);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
      'episode lists use episode labels and the same complete numeric search',
      (tester) async {
    final units = _units(kind: UnitKind.episode, count: 10);
    final fixture = await _open(tester, units: units, current: units.last.id);
    expect(find.text('Episodes'), findsOneWidget);
    expect(find.text('Chapters'), findsNothing);
    expect(find.byTooltip('Find current episode'), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('chapter-picker-search')), 'الحلقة ٢');
    await tester.pumpAndSettle();
    final target = units.firstWhere((unit) => unit.number == 2);
    await tester.tap(find.byKey(ValueKey('chapter-picker-${target.id}')));
    await tester.pumpAndSettle();
    expect(fixture.selected.single.kind, UnitKind.episode);
    expect(fixture.selected.single.id, target.id);
  });

  testWidgets(
      'Arabic large text and an open keyboard keep the picker usable on a narrow phone',
      (tester) async {
    final units = _units();
    final current = units.firstWhere((unit) => unit.number == 240);
    final fixture = await _open(tester,
        units: units,
        current: current.id,
        language: 'ar',
        size: const Size(320, 640),
        textScale: 1.35);
    await captureRender(
        tester, fixture.capture, 'chapter-tools-current-ar.png');
    tester.view.viewInsets = const FakeViewPadding(bottom: 250);
    await tester.enterText(
        find.byKey(const ValueKey('chapter-picker-search')), '٢٥٠');
    await tester.pumpAndSettle();
    expect(find.text('الفصل 250'), findsOneWidget);
    await captureRender(
        tester, fixture.capture, 'chapter-tools-keyboard-ar.png');
    expect(tester.takeException(), isNull);
  });
}
