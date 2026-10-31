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
  final source = const DemoSource();
  final works = await source.popular();
  if (works.isEmpty) return;
  final media = works.first;
  await ref.read(repositoryProvider).saveMedia(media);
  if (!context.mounted) return;
  context.push(Routes.seriesOf(media));
}
