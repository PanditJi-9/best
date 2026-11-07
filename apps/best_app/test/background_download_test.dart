import 'dart:io';

import 'package:best_app/src/download/background_download_client.dart';
import 'package:best_app/src/network.dart';
import 'package:best_app/src/providers.dart';
import 'package:best_data/best_data.dart';
import 'package:best_domain/best_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Bridge extends BackgroundDownloadClient {
  _Bridge() : super(enabled: true);
  final snapshots = <BackgroundDownloadSnapshot>[];
  bool accepted = true;

  @override
  Future<bool> initialize({
    required Future<void> Function(String, String?) onAction,
    required void Function(String) onFailure,
  }) async => true;

  @override
  Future<bool> publish(BackgroundDownloadSnapshot snapshot) async {
    snapshots.add(snapshot);
    return accepted;
  }

  @override
  void dispose() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('background snapshots contain display data, not a parallel file plan', () {
    const snapshot = BackgroundDownloadSnapshot(
      pending: true, wifiOnly: true, title: 'A work', detail: '1 of 3 pages',
      pauseLabel: 'Pause', unitId: 'unit', progress: 1, total: 3,
    );
    final map = snapshot.toMap();
    expect(map['pending'], isTrue);
    expect(map['progress'], 1);
    for (final key in ['urlsJson', 'pagesJson', 'targetDir', 'headers']) {
      expect(map.containsKey(key), isFalse);
    }
  });

  test('notification stop pauses the existing row without losing its prefix', () async {
    SharedPreferences.setMockInitialValues({'wifi_only': true});
    final preferences = await SharedPreferences.getInstance();
    final repository = MemoryLibraryRepository();
    const task = DownloadTask(unitId: 'unit', mediaId: 'work', sourceId: 'source',
      mediaUrl: 'work-url', unitUrl: 'unit-url', mediaTitle: 'A work',
      unitTitle: 'Chapter 1', total: 3, completed: 1, bytes: 50,
      directory: '/saved-prefix', status: DownloadStatus.queued);
    await repository.saveDownload(task);
    final bridge = _Bridge();
    final container = ProviderContainer(overrides: [
      preferencesProvider.overrideWithValue(preferences),
      repositoryProvider.overrideWithValue(repository),
      sourceRegistryProvider.overrideWithValue(SourceRegistry.fixed([])),
      backgroundDownloadClientProvider.overrideWithValue(bridge),
      downloadRootProvider.overrideWithValue(Directory('/unused-download-root')),
      networkProvider.overrideWith((ref) => Stream.value(NetworkKind.mobile)),
    ]);
    addTearDown(container.dispose);
    // Riverpod 3 pauses unobserved streams. Keep the same listeners the app's
    // root owns instead of waiting on an unobserved network Future forever.
    final networkSubscription = container.listen(networkProvider, (_, next) {});
    addTearDown(networkSubscription.close);
    await container.read(networkProvider.future);
    final backgroundSubscription = container.listen(backgroundDownloadsProvider,
        (_, next) {});
    addTearDown(backgroundSubscription.close);
    final notifier = container.read(backgroundDownloadsProvider.notifier);
    await notifier.ready;
    expect(bridge.snapshots.last.pending, isTrue);
    await notifier.notificationAction('stop', 'unit');
    final saved = (await repository.downloadFor('unit'))!;
    expect(saved.status, DownloadStatus.paused);
    expect(saved.completed, 1);
    expect(saved.bytes, 50);
    expect(saved.directory, '/saved-prefix');
    expect(bridge.snapshots.last.pending, isFalse);
    await notifier.notificationAction('open', null);
    expect(container.read(backgroundDownloadsProvider).openRequests, 1);
  });
}
