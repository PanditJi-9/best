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

  test('health records the latest success and failure and persists', () async {
    final preferences = await _preferences(<String, Object>{});
    final container = ProviderContainer(
      overrides: [preferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(sourceHealthProvider.notifier);
    notifier.recordSuccess('alpha', const Duration(milliseconds: 1200));

    var health = container.read(sourceHealthProvider)['alpha']!;
    expect(health.tested, isTrue);
    expect(health.failed, isFalse);
    expect(health.lastLatencyMs, 1200);

    notifier.recordFailure('alpha', Exception('offline'));
    health = container.read(sourceHealthProvider)['alpha']!;
    expect(health.failed, isTrue);
    expect(health.lastError, 'Exception: offline');

    // A later success clears the failure state without losing the evidence
    // that the source has failed before.
    notifier.recordSuccess('alpha', const Duration(seconds: 5));
    health = container.read(sourceHealthProvider)['alpha']!;
    expect(health.failed, isFalse);
    expect(health.slow, isTrue);

    await notifier.flush();
    expect(preferences.getString('source_health_v1'), isNotNull);

    final restored = ProviderContainer(
      overrides: [preferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(restored.dispose);
    final restoredHealth = restored.read(sourceHealthProvider)['alpha']!;
    expect(restoredHealth.lastSuccessAt, health.lastSuccessAt);
    expect(restoredHealth.lastFailureAt, health.lastFailureAt);
    expect(restoredHealth.lastLatencyMs, 5000);
  });

  test('a corrupt cache is ignored instead of breaking Manage sources', () async {
    final preferences = await _preferences(<String, Object>{
      'source_health_v1': '{not json',
    });
    final container = ProviderContainer(
      overrides: [preferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(container.dispose);

    expect(container.read(sourceHealthProvider), isEmpty);
  });
}
