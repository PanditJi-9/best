import 'dart:convert';

import 'package:best_app/src/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences preferences;
  late ProviderContainer container;

  Future<void> prepare([Map<String, Object> values = const {}]) async {
    SharedPreferences.setMockInitialValues(values);
    preferences = await SharedPreferences.getInstance();
    container = ProviderContainer(overrides: [
      preferencesProvider.overrideWithValue(preferences),
    ]);
  }

  tearDown(() => container.dispose());

  test('history filters start empty and persist every choice', () async {
    await prepare();
    expect(container.read(historyFilterProvider), const HistoryFilter());

    final controller = container.read(historyFilterProvider.notifier);
    controller.setKind(HistoryKindFilter.watching);
    controller.setOnlyUnread(true);
    controller.setOnlyFavorites(true);

    final expected = const HistoryFilter(
      kind: HistoryKindFilter.watching,
      onlyUnread: true,
      onlyFavorites: true,
    );
    expect(container.read(historyFilterProvider), expected);
    expect(expected.isActive, isTrue);
    expect(expected.activeCount, 3);

    final raw = preferences.getString('history_filters_v1');
    expect(raw, isNotNull);
    expect(jsonDecode(raw!), expected.toJson());

    controller.setOnlyUnread(false);
    controller.clear();
    expect(container.read(historyFilterProvider), const HistoryFilter());
    expect(
      jsonDecode(preferences.getString('history_filters_v1')!),
      const HistoryFilter().toJson(),
    );
  });

  test('stored filters survive a restart', () async {
    await prepare({
      'history_filters_v1': jsonEncode(
        const HistoryFilter(
          kind: HistoryKindFilter.reading,
          onlyNotOnShelf: true,
        ).toJson(),
      ),
    });
    expect(
      container.read(historyFilterProvider),
      const HistoryFilter(
        kind: HistoryKindFilter.reading,
        onlyNotOnShelf: true,
      ),
    );
  });

  test('a corrupt filter preference falls back to showing everything',
      () async {
    await prepare({'history_filters_v1': '{not json'});
    expect(container.read(historyFilterProvider), const HistoryFilter());
  });
}
