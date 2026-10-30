import 'package:best_app/src/app.dart';
import 'package:best_app/src/providers.dart';
import 'package:best_data/best_data.dart';
import 'package:best_domain/best_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _pumpApp(
  WidgetTester tester, {
  LibraryRepository? repository,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final preferences = await SharedPreferences.getInstance();
  final scope = ProviderScope(
    overrides: [
      repositoryProvider
          .overrideWithValue(repository ?? MemoryLibraryRepository()),
      preferencesProvider.overrideWithValue(preferences),
    ],
    child: const BestApp(),
  );
  await tester.pumpWidget(scope);
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(
    tester.element(find.byType(BestApp)),
    listen: false,
  );
}

void main() {
  testWidgets('the shelf renders, then flips to Arabic and RTL', (
    tester,
  ) async {
    final repository = MemoryLibraryRepository();
    final media = Media(
      ref: const SourceRef('test', 'blue-echo'),
      title: 'Blue Echo',
      kind: MediaKind.manhwa,
      inLibrary: true,
      addedAt: 1,
      lastOpenedAt: 2,
    );
    await repository.saveMedia(media);
    await repository.saveUnits([
      MediaUnit(
        mediaId: media.id,
        url: 'unit-1',
        number: 1,
        title: 'Chapter 1',
        kind: UnitKind.chapter,
        pageCount: 10,
      ),
    ]);
    await repository.saveProgress(
      UnitProgress(
        unitId: '${media.id}::unit-1',
        position: 3,
        total: 10,
        updatedAt: 5,
      ),
    );

    final container = await _pumpApp(tester, repository: repository);

    expect(find.text('Blue Echo'), findsWidgets);
    expect(find.text('Continue reading'), findsOneWidget);
    expect(find.text('Library'), findsWidgets);
    expect(find.text('Page 4 of 10'), findsOneWidget);

    container.read(settingsProvider.notifier).setLanguage('ar');
    await tester.pumpAndSettle();

    expect(find.text('متابعة القراءة'), findsOneWidget);
    expect(find.text('المكتبة'), findsWidgets);
    expect(
      Directionality.of(tester.element(find.text('بست'))),
      TextDirection.rtl,
    );
  });

  testWidgets('the guide opens a series and a readable page', (tester) async {
    await _pumpApp(tester);

    expect(find.text('Your shelf is waiting'), findsOneWidget);
    await tester.tap(find.text('Open the guide'));
    await tester.pumpAndSettle();

    expect(find.text('ظل الغابة'), findsWidgets);
    expect(find.text('Start reading'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Chapter 1'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chapter 1'));
    await tester.pumpAndSettle();

    expect(find.textContaining('صفحة 1'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Language'), findsOneWidget);
  });
}
