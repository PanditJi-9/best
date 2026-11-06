import 'dart:async';
import 'dart:io';

import 'package:best_app/src/network.dart';
import 'package:best_app/src/providers.dart';
import 'package:best_data/best_data.dart';
import 'package:best_domain/best_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Source implements SourceAdapter {
  const _Source(this.id);
  @override
  final String id;
  @override
  String get name => id;
  @override
  String get language => 'all';
  @override
  Future<Media> details(Media media) async => media;
  @override
  Future<List<Media>> popular({int page = 1}) async => [];
  @override
  Future<List<Media>> search(String query, {int page = 1}) async => [];
  @override
  Future<List<MediaUnit>> units(Media media) async => [];
  @override
  Future<List<MediaResource>> resources(MediaUnit unit) async => const [
        ImageResource('https://images.test/1'),
        ImageResource('https://images.test/2'),
      ];
}

class _Sources extends Notifier<List<SourceAdapter>> {
  @override
  List<SourceAdapter> build() => const [_Source('test')];
  void add(SourceAdapter source) => state = [...state, source];
}

final _sourcesProvider =
    NotifierProvider<_Sources, List<SourceAdapter>>(_Sources.new);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'source updates do not replace a live download manager or start another file writer',
      () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final repository = MemoryLibraryRepository();
    final directory =
        await Directory.systemTemp.createTemp('best-download-lifecycle-');
    const media = Media(
        ref: SourceRef('test', 'work'), title: 'Work', kind: MediaKind.manga);
    final unit = MediaUnit(
        mediaId: media.id,
        url: 'chapter-1',
        number: 1,
        title: 'Chapter 1',
        kind: UnitKind.chapter,
        pageCount: 2);
    await repository.saveMedia(media);
    await repository.saveUnits([unit]);
    final started = Completer<void>();
    final gate = Completer<void>();
    var requests = 0;
    final client = MockClient((_) async {
      if (++requests == 1) {
        started.complete();
        await gate.future;
      }
      return http.Response.bytes([1, 2, 3], 200);
    });
    final container = ProviderContainer(overrides: [
      preferencesProvider.overrideWithValue(preferences),
      repositoryProvider.overrideWithValue(repository),
      downloadRootProvider.overrideWithValue(directory),
      httpClientProvider.overrideWithValue(client),
      networkProvider.overrideWith((ref) => Stream.value(NetworkKind.wifi)),
      sourceRegistryProvider.overrideWith(
          (ref) => SourceRegistry.fixed(ref.watch(_sourcesProvider))),
    ]);
    final manager = container.read(downloadManagerProvider);
    addTearDown(() async {
      if (!gate.isCompleted) gate.complete();
      container.dispose();
      await manager.pump();
      await repository.close();
      client.close();
      await directory.delete(recursive: true);
    });
    await manager.enqueue(media, unit);
    await started.future;
    container.read(_sourcesProvider.notifier).add(const _Source('another'));
    expect(identical(container.read(downloadManagerProvider), manager), isTrue);
    gate.complete();
    await manager.pump();
    final task = (await repository.downloadFor(unit.id))!;
    expect(task.isFinished, isTrue);
    expect(requests, 2);
    expect((await manager.checkStored(unit.id)).checksummed, isTrue);
  });
}
