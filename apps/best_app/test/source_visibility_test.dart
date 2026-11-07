import 'package:best_app/src/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<SharedPreferences> _preferences(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('hiding a source persists and never hides the last one', () async {
    final preferences = await _preferences(<String, Object>{});
    final container = ProviderContainer(
      overrides: [preferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(sourceVisibilityProvider.notifier);
    const all = ['alpha', 'beta'];

    expect(await notifier.setVisible('alpha', false, allIds: all), isTrue);
    expect(container.read(sourceVisibilityProvider), {'alpha'});
    expect(preferences.getStringList('hidden_sources_v1'), ['alpha']);

    // One source must stay visible, otherwise Home has no catalogue at all.
    expect(await notifier.setVisible('beta', false, allIds: all), isFalse);
    expect(container.read(sourceVisibilityProvider), {'alpha'});

    expect(await notifier.setVisible('alpha', true, allIds: all), isTrue);
    expect(container.read(sourceVisibilityProvider), isEmpty);
  });

  test('the hidden set survives a new container', () async {
    final preferences = await _preferences(
      <String, Object>{
        'hidden_sources_v1': ['alpha', 'gamma'],
      },
    );
    final container = ProviderContainer(
      overrides: [preferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(container.dispose);

    expect(container.read(sourceVisibilityProvider), {'alpha', 'gamma'});
    expect(container.read(sourceVisibilityProvider.notifier).isVisible('beta'),
        isTrue);
    expect(container.read(sourceVisibilityProvider.notifier).isVisible('alpha'),
        isFalse);
  });
}
