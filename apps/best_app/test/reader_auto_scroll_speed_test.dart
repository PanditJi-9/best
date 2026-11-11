import 'package:best_app/src/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(SharedPreferences, ProviderContainer)> setup(
    Map<String, Object> values,
  ) async {
    SharedPreferences.setMockInitialValues(values);
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      preferencesProvider.overrideWithValue(preferences),
    ]);
    addTearDown(container.dispose);
    return (preferences, container);
  }

  test('defaults to 1x when nothing was saved', () async {
    final (_, container) = await setup({});
    expect(container.read(readerAutoScrollSpeedProvider), 1.0);
  });

  test('restores a saved speed', () async {
    final (_, container) = await setup({'reader_auto_scroll_speed': 2.0});
    expect(container.read(readerAutoScrollSpeedProvider), 2.0);
  });

  test('a saved speed outside the cycle falls back to 1x', () async {
    final (_, container) = await setup({'reader_auto_scroll_speed': 7.0});
    expect(container.read(readerAutoScrollSpeedProvider), 1.0);
  });

  test('a new speed is kept in state and written to preferences', () async {
    final (preferences, container) = await setup({});
    container.read(readerAutoScrollSpeedProvider.notifier).setSpeed(3.0);
    expect(container.read(readerAutoScrollSpeedProvider), 3.0);
    await Future<void>.delayed(Duration.zero);
    expect(preferences.getDouble('reader_auto_scroll_speed'), 3.0);
  });
}
