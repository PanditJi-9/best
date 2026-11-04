import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'meta_models.dart';
import 'meta_repository.dart';

final Provider<MetaRepository> metaRepositoryProvider =
    Provider<MetaRepository>(
  (ref) => MetaRepository(client: ref.watch(httpClientProvider)),
);

/// Bumped by pull-to-refresh and by the retry buttons.
///
/// Every catalogue caches its answers, so invalidating the provider alone
/// would hand back the same cached page. A bump tells the repository to skip
/// its cache once, which keeps a pull honest without hammering the sites.
class MetaRefreshController extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final NotifierProvider<MetaRefreshController, int> metaRefreshProvider =
    NotifierProvider<MetaRefreshController, int>(MetaRefreshController.new);

final FutureProvider<MetaHome> metaHomeProvider = FutureProvider<MetaHome>(
  (ref) => ref.watch(metaRepositoryProvider).home(
        generation: ref.watch(metaRefreshProvider),
      ),
);

/// The manhwa shelf on its own, because hwa.so answers much slower than the
/// other three catalogues. It fills in after the page is already readable.
final FutureProvider<List<MetaWork>> metaManhwaProvider =
    FutureProvider<List<MetaWork>>(
  (ref) => ref.watch(metaRepositoryProvider).list(
        MetaListKind.hwaTop,
        generation: ref.watch(metaRefreshProvider),
      ),
);

final metaDetailProvider = FutureProvider.family<MetaWork, MetaKey>(
  (ref, key) => ref.watch(metaRepositoryProvider).detail(
        key.source,
        key.id,
        generation: ref.watch(metaRefreshProvider),
      ),
);

final metaSearchProvider = FutureProvider.family<MetaSearchResults, String>(
  (ref, query) => ref.watch(metaRepositoryProvider).search(
        query,
        generation: ref.watch(metaRefreshProvider),
      ),
);

final metaListProvider = FutureProvider.family<List<MetaWork>, MetaListKind>(
  (ref, kind) => ref.watch(metaRepositoryProvider).list(
        kind,
        generation: ref.watch(metaRefreshProvider),
      ),
);
