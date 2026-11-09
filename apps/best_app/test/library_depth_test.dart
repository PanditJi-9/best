import 'package:best_app/src/providers.dart';
import 'package:best_data/best_data.dart';
import 'package:best_domain/best_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MemoryLibraryRepository repository;
  late SharedPreferences preferences;
  late ProviderContainer container;

  Media work(String title, List<String> tags, {bool favorite = false}) => Media(
        ref: SourceRef('test', title),
        title: title,
        kind: MediaKind.manga,
        inLibrary: true,
        tags: tags,
        favorite: favorite,
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'categories_v1': ['Fantasy', 'Romance', 'Empty', 'Hidden'],
      'hidden_categories_v1': ['Hidden'],
    });
    preferences = await SharedPreferences.getInstance();
    repository = MemoryLibraryRepository(seed: [
      work('Blue Echo', ['Fantasy'], favorite: true),
      work('Blue Night', ['Romance']),
      work('Blue Secret', ['Hidden', 'Fantasy']),
      work('Green Echo', []),
    ]);
    container = ProviderContainer(overrides: [
      repositoryProvider.overrideWithValue(repository),
      preferencesProvider.overrideWithValue(preferences),
    ]);
  });

  tearDown(() async {
    container.dispose();
    await repository.close();
  });

  test('search tab counts ignore the selected category and hidden works',
      () async {
    final controller = container.read(libraryQueryProvider.notifier);
    controller.setTag('Romance');
    controller.setSearch('src:test, echo');
    final tabs = await container.read(libraryVisibleTabsProvider.future);
    expect(tabs.total, 2);
    expect(tabs.uncategorized, 1);
    expect(tabs.categories.map((category) => category.name), ['Fantasy']);
    expect(tabs.categories.single.count, 1);
    // The category manager is not narrowed by the on-screen search.
    expect((await container.read(libraryCategoriesProvider.future)).length, 4);
  });

  test('keeping empty categories keeps zero counts, not unfiltered counts',
      () async {
    container.read(libraryQueryProvider.notifier).setSearch('echo');
    await container
        .read(libraryShowEmptyCategoriesProvider.notifier)
        .set(true);
    final tabs = await container.read(libraryVisibleTabsProvider.future);
    expect({for (final category in tabs.categories) category.name: category.count},
        {'Fantasy': 1, 'Romance': 0, 'Empty': 0});
    expect(preferences.getBool('library_show_empty_categories'), isTrue);
    container.invalidate(libraryShowEmptyCategoriesProvider);
    expect(container.read(libraryShowEmptyCategoriesProvider), isTrue);
  });

  test('filters hide empty tabs and revealing hidden works updates counts',
      () async {
    final controller = container.read(libraryQueryProvider.notifier);
    controller.setFilter(LibraryFilter.favorites);
    final filtered = await container.read(libraryVisibleTabsProvider.future);
    expect(filtered.categories.map((category) => category.name), ['Fantasy']);
    controller.setFilter(LibraryFilter.all);
    controller.setSearch('blue');
    container.read(revealHiddenProvider.notifier).set(true);
    final revealed = await container.read(libraryVisibleTabsProvider.future);
    expect(revealed.total, 3);
    expect({for (final category in revealed.categories) category.name: category.count},
        {'Fantasy': 2, 'Romance': 1, 'Hidden': 1});
  });

  test('selecting shuffle again changes only the seed and order choice', () {
    final controller = container.read(libraryQueryProvider.notifier);
    controller.setSearch('blue');
    controller.setFilter(LibraryFilter.favorites);
    controller.setSort(LibrarySort.random);
    final first = container.read(libraryQueryProvider);
    controller.setSort(LibrarySort.random);
    final next = container.read(libraryQueryProvider);
    expect(next.randomSeed, greaterThan(first.randomSeed));
    expect(next.search, first.search);
    expect(next.filter, first.filter);
    expect(next.sort, LibrarySort.random);
    controller.setSort(LibrarySort.title);
    expect(container.read(libraryQueryProvider).randomSeed, 0);
  });
}
