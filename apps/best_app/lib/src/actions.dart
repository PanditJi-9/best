import 'package:best_data/best_data.dart';
import 'package:best_domain/best_domain.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
  MediaUnit unit,
) async {
  await ref.read(repositoryProvider).saveMedia(
        media.copyWith(lastOpenedAt: DateTime.now().millisecondsSinceEpoch),
      );
  if (!context.mounted) return;
  context.push(Routes.readerOf(media, unit));
}

/// One tap, the right engine: a chapter opens the page reader, an episode opens
/// the video player. Keeping the choice here means every entry point (series
/// page, continue rail, deep link) behaves the same.
Future<void> openUnit(
  BuildContext context,
  WidgetRef ref,
  Media media,
  MediaUnit unit,
) {
  if (media.kind.isReading) return openReader(context, ref, media, unit);
  return openWatch(context, ref, media, unit);
}

Future<void> openWatch(
  BuildContext context,
  WidgetRef ref,
  Media media,
  MediaUnit unit,
) async {
  await ref.read(repositoryProvider).saveMedia(
        media.copyWith(lastOpenedAt: DateTime.now().millisecondsSinceEpoch),
      );
  if (!context.mounted) return;
  context.push(Routes.watchOf(media, unit));
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

/// Adds one list name to a work, keeping the person's order and ignoring
/// duplicates. Lists are tags: one storage shape, one editor.
Future<void> addTag(WidgetRef ref, Media media, String tag) async {
  final clean = tag.trim();
  if (clean.isEmpty) return;
  final existing = media.tags;
  if (existing.contains(clean)) return;
  await ref.read(repositoryProvider).setTags(media.id, [...existing, clean]);
}

Future<void> removeTag(WidgetRef ref, Media media, String tag) async {
  final remaining = media.tags.where((item) => item != tag).toList();
  if (remaining.length == media.tags.length) return;
  await ref.read(repositoryProvider).setTags(media.id, remaining);
}
