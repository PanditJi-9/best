import 'package:best_domain/best_domain.dart';
import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
    final downloads =
        ref.watch(downloadsProvider).value ?? const <DownloadTask>[];
    final tasks = {for (final task in downloads) task.unitId: task};
    final canDownload = media.kind.isReading;
    final offlineCount = tasks.values
        .where((task) => task.mediaId == media.id && task.isFinished)
        .length;
    final pendingDownloads = units.where((unit) {
      final task = tasks[unit.id];
      return task == null || task.isFailed;
    }).length;
    final next = _nextUnit(units, data.progress);
    final hasProgress = data.progress.values.any(
      (progress) => progress.position > 0 || progress.completed,
    );
    final completed = units
        .where((unit) => data.progress[unit.id]?.completed ?? false)
        .length;
    final percent =
        units.isEmpty ? 0 : (completed * 100 / units.length).round();

    return Scaffold(
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: _Hero(
                  title: media.displayTitle,
                  coverUrl: media.coverUrl,
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        media.displayTitle,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.8,
                          height: 1.08,
                        ),
                      ),
                      if (media.nativeTitle != null &&
                          media.nativeTitle!.trim().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          media.nativeTitle!,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          _MetaDot(label: kindLabel(l10n, media.kind)),
                          if (media.year != null)
                            _MetaDot(label: '${media.year}'),
                          _MetaDot(label: statusLabel(l10n, media.status)),
                          if (offlineCount > 0)
                            _MetaDot(
                              label: l10n.offlineCount(offlineCount),
                              accent: true,
                            ),
                        ],
                      ),
                      if (media.author != null &&
                          media.author!.trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          media.author!,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (media.genres.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final genre in media.genres.take(5))
                              _GenrePill(label: genre),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: next == null
                          ? null
                          : () => openUnit(context, ref, media, next),
                      icon: Icon(
                        media.kind.isReading
                            ? Icons.menu_book_rounded
                            : Icons.play_arrow_rounded,
                        size: 20,
                      ),
                      label: Text(
                        media.kind.isReading
                            ? (hasProgress
                                ? l10n.continueReading
                                : l10n.startReading)
                            : (hasProgress
                                ? l10n.continueWatching
                                : l10n.startWatching),
                      ),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                  child: _ShelfPlan(media: media),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                  child: StatStrip(
                    stats: [
                      StatItem(
                        value: '${units.length}',
                        label: media.kind.isReading
                            ? l10n.chapters
                            : l10n.episodes,
                      ),
                      StatItem(
                        value: '$offlineCount',
                        label: l10n.offlineLabel,
                      ),
                      StatItem(value: '$percent%', label: l10n.progressLabel),
                    ],
                  ),
                ),
              ),
              if (media.synopsis != null && media.synopsis!.trim().isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SectionHeader(title: l10n.aboutWork),
                        _Synopsis(text: media.synopsis!),
                      ],
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: SectionHeader(
                    title: media.kind.isReading ? l10n.chapters : l10n.episodes,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          l10n.unitCount(units.length),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (canDownload && pendingDownloads > 0) ...[
                          const SizedBox(width: 2),
                          IconButton(
                            tooltip: l10n.downloadAll,
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _downloadAll(
                              context,
                              ref,
                              media,
                              units,
                              tasks,
                            ),
                            icon: const Icon(
                              Icons.download_for_offline_outlined,
                              size: 20,
                            ),
                          ),
                        ],
                      ],
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
                    final task = tasks[unit.id];
                    return _UnitTile(
                      unit: unit,
                      progress: data.progress[unit.id],
                      download: task,
                      canDownload: canDownload,
                      onTap: () => openUnit(context, ref, media, unit),
                      onDownload: () => _download(context, ref, media, unit),
                      onPause: task == null
                          ? null
                          : () => ref
                              .read(downloadManagerProvider)
                              .pause(task.unitId),
                      onResume: task == null
                          ? null
                          : () => ref
                              .read(downloadManagerProvider)
                              .resume(task.unitId),
                    );
                  }, childCount: units.length),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 28)),
            ],
          ),
          PositionedDirectional(
            top: MediaQuery.paddingOf(context).top + 8,
            start: 12,
            child: _GlassCircle(
              tooltip: l10n.backToSeries,
              icon: Icons.arrow_back_rounded,
              onTap: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  Navigator.of(context).maybePop();
                }
              },
            ),
          ),
          PositionedDirectional(
            top: MediaQuery.paddingOf(context).top + 8,
            end: 12,
            child: Column(
              children: [
                _GlassCircle(
                  tooltip: media.favorite ? l10n.unfavorite : l10n.favorite,
                  icon: media.favorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  active: media.favorite,
                  onTap: () async {
                    await ref
                        .read(repositoryProvider)
                        .setFavorite(media.id, !media.favorite);
                    if (!context.mounted) return;
                    ref.invalidate(seriesProvider(seriesKey));
                  },
                ),
                const SizedBox(height: BestSpace.sm),
                _GlassCircle(
                  tooltip: media.inLibrary
                      ? l10n.removeFromLibrary
                      : l10n.addToLibrary,
                  icon: media.inLibrary
                      ? Icons.library_add_check_rounded
                      : Icons.library_add_outlined,
                  active: media.inLibrary,
                  onTap: () async {
                    await ref
                        .read(repositoryProvider)
                        .setInLibrary(media.id, !media.inLibrary);
                    if (!context.mounted) return;
                    ref.invalidate(seriesProvider(seriesKey));
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadAll(
    BuildContext context,
    WidgetRef ref,
    Media media,
    List<MediaUnit> units,
    Map<String, DownloadTask> tasks,
  ) async {
    final l10n = AppLocalizations.of(context);
    final pending = units.where((unit) {
      final task = tasks[unit.id];
      return task == null || task.isFailed;
    }).toList(growable: false);
    if (pending.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.downloadAllTitle),
        content: Text(l10n.downloadAllBody(pending.length)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.downloadAll),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final manager = ref.read(downloadManagerProvider);
    for (final unit in pending) {
      await manager.enqueue(media, unit);
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.downloadAllQueued(pending.length))),
    );
  }

  Future<void> _download(
    BuildContext context,
    WidgetRef ref,
    Media media,
    MediaUnit unit,
  ) async {
    await ref.read(downloadManagerProvider).enqueue(media, unit);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).downloadStarted)),
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

/// A cover floating over the blurred artwork. The 420px block is deliberately
/// taller than the backdrop so the cover can sit half-in, half-out without a
/// negative margin or an overflow.
class _Hero extends StatelessWidget {
  const _Hero({required this.title, required this.coverUrl});

  final String title;
  final String? coverUrl;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 416,
      child: Stack(
        fit: StackFit.expand,
        children: [
          SizedBox(
            height: 300,
            child: BestBackdrop(title: title, url: coverUrl),
          ),
          Positioned(
            top: 222,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 124,
                height: 186,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(BestRadius.md),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.45),
                      blurRadius: 26,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: BestCover(title: title, url: coverUrl),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaDot extends StatelessWidget {
  const _MetaDot({required this.label, this.accent = false});

  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      label,
      style: theme.textTheme.labelMedium?.copyWith(
        color: accent ? BestColors.jade : theme.colorScheme.onSurfaceVariant,
        fontWeight: accent ? FontWeight.w700 : FontWeight.w500,
      ),
    );
  }
}

class _GenrePill extends StatelessWidget {
  const _GenrePill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(BestRadius.pill),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _GlassCircle extends StatelessWidget {
  const _GlassCircle({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.active = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      style: IconButton.styleFrom(
        fixedSize: const Size(42, 42),
        backgroundColor:
            active ? BestColors.jade : Colors.black.withValues(alpha: 0.5),
        foregroundColor: active ? BestColors.ink : Colors.white,
        side: BorderSide(
          color:
              active ? BestColors.jade : Colors.white.withValues(alpha: 0.18),
        ),
      ),
      icon: Icon(icon, size: 20),
    );
  }
}

class _Synopsis extends StatefulWidget {
  const _Synopsis({required this.text});

  final String text;

  @override
  State<_Synopsis> createState() => _SynopsisState();
}

class _SynopsisState extends State<_Synopsis> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.text,
          maxLines: _open ? null : 4,
          overflow: _open ? null : TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            height: 1.7,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        TextButton(
          onPressed: () => setState(() => _open = !_open),
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          ),
          child: Text(_open ? l10n.less : l10n.more),
        ),
      ],
    );
  }
}

class _UnitTile extends StatelessWidget {
  const _UnitTile({
    required this.unit,
    required this.progress,
    required this.download,
    required this.canDownload,
    required this.onTap,
    required this.onDownload,
    required this.onPause,
    required this.onResume,
  });

  final MediaUnit unit;
  final UnitProgress? progress;
  final DownloadTask? download;
  final bool canDownload;
  final VoidCallback onTap;
  final VoidCallback onDownload;
  final VoidCallback? onPause;
  final VoidCallback? onResume;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final saved = progress;
    final completed = saved?.completed ?? false;
    final started = saved != null && saved.position > 0 && !completed;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Material(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(BestRadius.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(BestRadius.md),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 34,
                  height: 34,
                  child: Center(
                    child: completed
                        ? const Icon(
                            Icons.check_circle_rounded,
                            color: BestColors.jade,
                            size: 26,
                          )
                        : started
                            ? SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  value: saved.fraction,
                                  strokeWidth: 2.6,
                                ),
                              )
                            : Icon(
                                Icons.radio_button_unchecked,
                                size: 21,
                                color: theme.colorScheme.outlineVariant,
                              ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        unit.displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
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
                const SizedBox(width: 6),
                if (canDownload)
                  _DownloadControl(
                    unit: unit,
                    download: download,
                    onDownload: onDownload,
                    onPause: onPause,
                    onResume: onResume,
                  ),
                const SizedBox(width: 4),
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(BestRadius.sm),
                  ),
                  child: Text(
                    shortNumber(unit.number),
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
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

class _DownloadControl extends StatelessWidget {
  const _DownloadControl({
    required this.unit,
    required this.download,
    required this.onDownload,
    required this.onPause,
    required this.onResume,
  });

  final MediaUnit unit;
  final DownloadTask? download;
  final VoidCallback onDownload;
  final VoidCallback? onPause;
  final VoidCallback? onResume;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final task = download;

    if (task == null) {
      return IconButton(
        tooltip: unit.kind == UnitKind.episode
            ? l10n.downloadEpisode
            : l10n.downloadChapter,
        visualDensity: VisualDensity.compact,
        onPressed: onDownload,
        icon: const Icon(Icons.download_outlined, size: 20),
      );
    }
    if (task.isFinished) {
      return Tooltip(
        message: l10n.downloadDone,
        child: const Padding(
          padding: EdgeInsets.all(12),
          child: Icon(
            Icons.download_done_rounded,
            color: BestColors.jade,
            size: 20,
          ),
        ),
      );
    }
    if (task.isFailed) {
      return IconButton(
        tooltip: l10n.downloadRetry,
        visualDensity: VisualDensity.compact,
        onPressed: onResume,
        icon: Icon(
          Icons.refresh_rounded,
          size: 20,
          color: Theme.of(context).colorScheme.error,
        ),
      );
    }
    if (task.isPaused) {
      return IconButton(
        tooltip: l10n.downloadResume,
        visualDensity: VisualDensity.compact,
        onPressed: onResume,
        icon: const Icon(Icons.play_arrow_rounded, size: 22),
      );
    }
    return IconButton(
      tooltip: l10n.downloadPause,
      visualDensity: VisualDensity.compact,
      onPressed: onPause,
      icon: SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          value: task.progress,
          strokeWidth: 2.2,
        ),
      ),
    );
  }
}

/// The person's own plan and lists.
///
/// It reads the stored row, not the provider argument, so a tap shows up
/// immediately without re-fetching the work from its source.
class _ShelfPlan extends ConsumerWidget {
  const _ShelfPlan({required this.media});

  final Media media;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final stored = ref.watch(mediaByIdProvider(media.id)).value ?? media;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.shelfPlan.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (stored.tags.isNotEmpty)
              Text(
                l10n.listsTitle,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final state in const [
              ReadingState.reading,
              ReadingState.planned,
              ReadingState.paused,
            ])
              ChoiceChip(
                avatar: Icon(_stateIcon(state), size: 15),
                label: Text(stateLabel(l10n, state)),
                selected: stored.state == state,
                onSelected: (selected) => setReadingState(
                  context,
                  ref,
                  stored,
                  selected ? state : ReadingState.none,
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final tag in stored.tags)
              InputChip(
                label: Text(tag),
                visualDensity: VisualDensity.compact,
                onDeleted: () => removeTag(ref, stored, tag),
              ),
            ActionChip(
              avatar: const Icon(Icons.add, size: 15),
              label: Text(l10n.listAdd),
              onPressed: () => _addList(context, ref, stored),
            ),
          ],
        ),
      ],
    );
  }

  static IconData _stateIcon(ReadingState state) => switch (state) {
        ReadingState.reading => Icons.menu_book_rounded,
        ReadingState.planned => Icons.bookmark_outline_rounded,
        ReadingState.paused => Icons.pause_circle_outline_rounded,
        ReadingState.none => Icons.remove,
      };

  static Future<void> _addList(
    BuildContext context,
    WidgetRef ref,
    Media media,
  ) async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.listName),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(hintText: l10n.listAdd),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(l10n.listAdd),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty) return;
    await addTag(ref, media, name);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.listAdded(name.trim()))));
  }
}
