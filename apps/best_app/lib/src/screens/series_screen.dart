import 'package:best_domain/best_domain.dart';
import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../actions.dart';
import '../l10n/generated/app_localizations.dart';
import '../labels.dart';
import '../providers.dart';

class SeriesScreen extends ConsumerWidget {
  const SeriesScreen({super.key, required this.sourceId, required this.url});

  final String sourceId;
  final String url;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final key = (sourceId: sourceId, url: url);
    final data = ref.watch(seriesProvider(key));

    return data.when(
      loading: () => Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, stack) => Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          icon: Icons.cloud_off_outlined,
          title: l10n.sourceError,
          body: '$error',
          action: FilledButton.icon(
            onPressed: () => ref.invalidate(seriesProvider(key)),
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(l10n.retry),
          ),
        ),
      ),
      data: (series) => _SeriesBody(data: series, seriesKey: key),
    );
  }
}

class _SeriesBody extends ConsumerWidget {
  const _SeriesBody({required this.data, required this.seriesKey});

  final SeriesData data;
  final SeriesKey seriesKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final media = data.media;
    final units = data.units;
    final next = _nextUnit(units, data.progress);
    final hasProgress = data.progress.values.any(
      (progress) => progress.position > 0 || progress.completed,
    );

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 300,
            backgroundColor: BestColors.ink,
            foregroundColor: Colors.white,
            title: Text(
              media.displayTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  BestCover(
                    title: media.displayTitle,
                    url: media.coverUrl,
                    radius: 0,
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.black12, Colors.black, Colors.black87],
                        stops: [0.25, 0.75, 1],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 112,
                    height: 168,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(BestRadius.md),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.22),
                            blurRadius: 18,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: BestCover(
                        title: media.displayTitle,
                        url: media.coverUrl,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          media.displayTitle,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            height: 1.15,
                            letterSpacing: -0.6,
                          ),
                        ),
                        if (media.nativeTitle != null &&
                            media.nativeTitle!.trim().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            media.nativeTitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            _MetaPill(label: kindLabel(l10n, media.kind)),
                            if (media.year != null)
                              _MetaPill(label: '${media.year}'),
                            _MetaPill(label: statusLabel(l10n, media.status)),
                          ],
                        ),
                        if (media.author != null &&
                            media.author!.trim().isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(
                            media.author!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: next == null
                          ? null
                          : () => openReader(context, ref, media, next),
                      icon: Icon(
                        media.kind.isReading
                            ? Icons.menu_book_outlined
                            : Icons.play_arrow_rounded,
                        size: 20,
                      ),
                      label: Text(
                        hasProgress ? l10n.continueReading : l10n.startReading,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: media.favorite ? l10n.unfavorite : l10n.favorite,
                    onPressed: () async {
                      await ref
                          .read(repositoryProvider)
                          .setFavorite(media.id, !media.favorite);
                      if (!context.mounted) return;
                      ref.invalidate(seriesProvider(seriesKey));
                    },
                    icon: Icon(
                      media.favorite ? Icons.favorite : Icons.favorite_border,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: media.inLibrary
                        ? l10n.removeFromLibrary
                        : l10n.addToLibrary,
                    onPressed: () async {
                      await ref
                          .read(repositoryProvider)
                          .setInLibrary(media.id, !media.inLibrary);
                      if (!context.mounted) return;
                      ref.invalidate(seriesProvider(seriesKey));
                    },
                    icon: Icon(
                      media.inLibrary
                          ? Icons.library_add_check
                          : Icons.library_add_outlined,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (media.genres.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final genre in media.genres)
                      _MetaPill(label: genre, muted: true),
                  ],
                ),
              ),
            ),
          if (media.synopsis != null && media.synopsis!.trim().isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionHeader(title: l10n.aboutWork),
                    Text(
                      media.synopsis!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        height: 1.65,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SectionHeader(
                title: media.kind.isReading ? l10n.chapters : l10n.episodes,
                trailing: Text(
                  l10n.unitCount(units.length),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
          if (units.isEmpty)
            SliverToBoxAdapter(
              child: EmptyState(
                icon: Icons.inbox_outlined,
                title: l10n.noUnits,
                body: l10n.nothingHereBody,
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                final unit = units[index];
                return _UnitTile(
                  unit: unit,
                  progress: data.progress[unit.id],
                  onTap: () => openReader(context, ref, media, unit),
                );
              }, childCount: units.length),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 28)),
        ],
      ),
    );
  }

  static MediaUnit? _nextUnit(
    List<MediaUnit> units,
    Map<String, UnitProgress> progress,
  ) {
    if (units.isEmpty) return null;
    for (final unit in units) {
      final saved = progress[unit.id];
      if (saved != null && !saved.completed && saved.position > 0) return unit;
    }
    for (final unit in units) {
      if (!(progress[unit.id]?.completed ?? false)) return unit;
    }
    return units.last;
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.label, this.muted = false});

  final String label;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: muted
            ? theme.colorScheme.surfaceContainerHighest
            : theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(BestRadius.pill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: muted
                ? theme.colorScheme.onSurfaceVariant
                : theme.colorScheme.onPrimaryContainer,
          ),
        ),
      ),
    );
  }
}

class _UnitTile extends StatelessWidget {
  const _UnitTile({
    required this.unit,
    required this.progress,
    required this.onTap,
  });

  final MediaUnit unit;
  final UnitProgress? progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final saved = progress;
    final completed = saved?.completed ?? false;
    final started = saved != null && saved.position > 0 && !completed;

    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                shortNumber(unit.number),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    unit.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _subtitle(l10n, unit),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (completed)
              const Icon(Icons.check_circle, color: BestColors.jade, size: 22)
            else if (started)
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  value: saved.fraction,
                  strokeWidth: 2.6,
                ),
              )
            else
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }

  String _subtitle(AppLocalizations l10n, MediaUnit unit) {
    final parts = <String>[];
    final date = shortDate(unit.publishedAt);
    if (date.isNotEmpty) parts.add(date);
    if (unit.pageCount > 0) parts.add(l10n.pages(unit.pageCount));
    return parts.join(' · ');
  }
}
