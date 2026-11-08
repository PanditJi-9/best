import 'package:best_data/best_data.dart';
import 'package:best_domain/best_domain.dart';
import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'l10n/generated/app_localizations.dart';
import 'navigation.dart';
import 'providers.dart';

/// Opening a work always lands it in the local catalogue first.
///
/// The series screen reads from storage, not from a widget argument, so a deep
/// link or a cold restart opens the same screen with the same data. Opening is
/// not the same as adding to the shelf: `inLibrary` is left untouched.
Future<void> openSeries(
  BuildContext context,
  WidgetRef ref,
  Media media,
) async {
  final repository = ref.read(repositoryProvider);
  await repository.saveMedia(
    media.copyWith(lastOpenedAt: DateTime.now().millisecondsSinceEpoch),
  );
  if (!context.mounted) return;
  context.push(Routes.seriesOf(media));
}

Future<void> openReader(
  BuildContext context,
  WidgetRef ref,
  Media media,
  MediaUnit unit, {
  bool fromStart = false,
}) async {
  await ref.read(repositoryProvider).saveMedia(
        media.copyWith(lastOpenedAt: DateTime.now().millisecondsSinceEpoch),
      );
  if (!context.mounted) return;
  context.push(Routes.readerOf(media, unit, fromStart: fromStart));
}

/// One tap, the right engine: a chapter opens the page reader, an episode opens
/// the video player. Keeping the choice here means every entry point (series
/// page, continue rail, deep link) behaves the same.
Future<void> openUnit(
  BuildContext context,
  WidgetRef ref,
  Media media,
  MediaUnit unit, {
  bool fromStart = false,
}) {
  if (media.kind.isReading) {
    return openReader(context, ref, media, unit, fromStart: fromStart);
  }
  return openWatch(context, ref, media, unit, fromStart: fromStart);
}

Future<void> openWatch(
  BuildContext context,
  WidgetRef ref,
  Media media,
  MediaUnit unit, {
  bool fromStart = false,
}) async {
  await ref.read(repositoryProvider).saveMedia(
        media.copyWith(lastOpenedAt: DateTime.now().millisecondsSinceEpoch),
      );
  if (!context.mounted) return;
  context.push(Routes.watchOf(media, unit, fromStart: fromStart));
}

/// The guide is fetched, saved and opened exactly like a real source, so the
/// first-run path exercises the same code as every later one.
Future<void> openGuide(BuildContext context, WidgetRef ref) async {
  const source = DemoSource();
  // The showcase is the guide's playable drama, so the first thing a new
  // reader opens is the video the guide actually ships.
  var media = source.showcase;
  if (media == null) {
    final works = await source.popular();
    if (works.isEmpty) return;
    media = works.first;
  }
  await ref.read(repositoryProvider).saveMedia(media);
  if (!context.mounted) return;
  context.push(Routes.seriesOf(media));
}

/// The person's plan for a work. A plan implies the shelf: marking something
/// "planned" while it is not in the library would hide it from the only place
/// the plan is visible.
Future<void> setReadingState(
  BuildContext context,
  WidgetRef ref,
  Media media,
  ReadingState state,
) async {
  final repository = ref.read(repositoryProvider);
  await repository.setReadingState(media.id, state);
  if (state != ReadingState.none && !media.inLibrary) {
    await repository.setInLibrary(media.id, true);
  }
}

/// The category registry of the shelf a work belongs to.
ShelfCategoriesController _categoriesOf(WidgetRef ref, MediaKind kind) {
  return LibraryShelf.of(kind) == LibraryShelf.watching
      ? ref.read(watchingCategoriesProvider.notifier)
      : ref.read(categoriesProvider.notifier);
}

/// Category names a work can be put into: the shelf's own names, minus hidden
/// ones unless the person revealed them. A work put into a hidden category
/// would vanish from the shelf the moment it was added.
List<String> _pickableCategoryNames(WidgetRef ref, MediaKind kind) {
  final names = LibraryShelf.of(kind) == LibraryShelf.watching
      ? ref.read(watchingCategoriesProvider)
      : ref.read(categoriesProvider);
  final hidden = ref.read(hiddenCategoriesProvider);
  final reveal = ref.read(revealHiddenProvider);
  return [
    for (final name in names)
      if (reveal || !hidden.contains(name)) name,
  ];
}

/// Adds one list name to a work, keeping the person's order and ignoring
/// duplicates. Lists are tags: one storage shape, one editor.
Future<void> addTag(WidgetRef ref, Media media, String tag) async {
  final clean = tag.trim();
  if (clean.isEmpty) return;
  // A list typed on a series page is a category from that moment on, even if
  // the work is later removed from it. It belongs to the work's own shelf.
  await _categoriesOf(ref, media.kind).add(clean);
  final repository = ref.read(repositoryProvider);
  // Read the work again: the page may hold a copy from before another edit.
  final current = await repository.mediaById(media.id) ?? media;
  if (current.tags.contains(clean)) return;
  await repository.setTags(media.id, [...current.tags, clean]);
}

/// Adds one category to many works at once. Used by the library's selection
/// bar; each work keeps its other categories and their order.
Future<void> addTagToWorks(
  WidgetRef ref,
  Iterable<Media> works,
  String tag,
) async {
  final clean = tag.trim();
  if (clean.isEmpty) return;
  final repository = ref.read(repositoryProvider);
  for (final selected in works) {
    final media = await repository.mediaById(selected.id) ?? selected;
    if (!media.inLibrary) continue;
    await _categoriesOf(ref, media.kind).add(clean);
    if (media.tags.contains(clean)) continue;
    await repository.setTags(media.id, [...media.tags, clean]);
  }
}

/// Takes one category off many works. Each work keeps its other categories.
Future<void> removeTagFromWorks(
  WidgetRef ref,
  Iterable<Media> works,
  String tag,
) async {
  final repository = ref.read(repositoryProvider);
  for (final selected in works) {
    final media = await repository.mediaById(selected.id) ?? selected;
    if (!media.tags.contains(tag)) continue;
    await repository.setTags(media.id, [
      for (final existing in media.tags)
        if (existing != tag) existing,
    ]);
  }
}

/// The one way a work enters the library. With no categories on its shelf it
/// lands on the Default tab at once; with categories, the person picks the
/// tab first. Returns whether the work was added.
Future<bool> addMediaToLibrary(
  BuildContext context,
  WidgetRef ref,
  Media media,
) async {
  if (media.inLibrary) return false;
  final repository = ref.read(repositoryProvider);
  final names = _pickableCategoryNames(ref, media.kind);
  if (names.isEmpty) {
    await repository.setInLibrary(media.id, true);
    return true;
  }

  final l10n = AppLocalizations.of(context);
  // An empty answer means Default; null means the person backed out.
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
            child: Text(
              l10n.addToLibraryChoose,
              style: BestType.sectionTitle(context),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.inbox_outlined, size: 20),
            title: Text(l10n.categoryDefault),
            onTap: () => Navigator.of(sheetContext).pop(''),
          ),
          for (final name in names)
            ListTile(
              leading: const Icon(Icons.folder_outlined, size: 20),
              title: Text(name),
              onTap: () => Navigator.of(sheetContext).pop(name),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (choice == null) return false;
  if (choice.isNotEmpty) await addTag(ref, media, choice);
  await repository.setInLibrary(media.id, true);
  return true;
}

Future<void> removeTag(WidgetRef ref, Media media, String tag) async {
  final remaining = media.tags.where((item) => item != tag).toList();
  if (remaining.length == media.tags.length) return;
  await ref.read(repositoryProvider).setTags(media.id, remaining);
}
