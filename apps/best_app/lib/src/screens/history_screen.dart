import 'package:best_domain/best_domain.dart';
import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../actions.dart';
import '../l10n/generated/app_localizations.dart';
import '../labels.dart';
import '../navigation.dart';
import '../providers.dart';

/// Everything you have read, newest first, in one place.
///
/// Two lists answer two questions: the works you opened and left, and the
/// chapters you are partway through. Both are grouped by day, and each row says
/// what matters for coming back to it: the chapter, the page and the time.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

enum _HistoryTab { recent, continueReading }

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  _HistoryTab _tab = _HistoryTab.recent;
  bool _searching = false;
  String _query = '';

  Future<void> _refresh() async {
    ref.invalidate(historyContinueProvider);
    ref.invalidate(recentProvider);
    try {
      await Future.wait([
        ref.read(historyContinueProvider.future),
        ref.read(recentProvider.future),
      ]);
    } catch (_) {
      // Rendered inline.
    }
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) _query = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final query = _query.trim();
    final works = (ref.watch(recentProvider).value ?? const <Media>[])
        .where((media) => _matches(media.displayTitle, query))
        .toList(growable: false);
    final entries = (ref.watch(historyContinueProvider).value ??
            const <ContinueEntry>[])
        .where((entry) => _matches(entry.media.displayTitle, query))
        .toList(growable: false);
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.historyTitle,
                        style: BestType.pageTitle(context),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.historySubtitle,
                        style: BestType.body(context),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: l10n.historySearch,
                  onPressed: _toggleSearch,
                  icon: Icon(
                    _searching ? Icons.close_rounded : Icons.search_rounded,
                  ),
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: BestMotion.fast,
            alignment: Alignment.topCenter,
            child: _searching
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: TextField(
                      autofocus: true,
                      onChanged: (value) => setState(() => _query = value),
                      decoration: InputDecoration(
                        hintText: l10n.historySearch,
                        prefixIcon: const Icon(Icons.search_rounded),
                        isDense: true,
                        filled: true,
                        fillColor: theme.colorScheme.surfaceContainerLow,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(BestRadius.pill),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
            child: _Segments(
              selected: _tab,
              onSelected: (tab) => setState(() => _tab = tab),
            ),
          ),
          Expanded(
            child: switch (_tab) {
              _HistoryTab.continueReading => _ContinueList(
                  entries: entries,
                  query: query,
                  onRefresh: _refresh,
                ),
              _HistoryTab.recent => _RecentList(
                  works: works,
                  query: query,
                  onRefresh: _refresh,
                ),
            },
          ),
        ],
      ),
    );
  }
}

bool _matches(String title, String query) =>
    query.isEmpty ||
    SearchText.normalize(title).contains(SearchText.normalize(query));

/// Whole calendar days between [epochMillis] and [now]. UTC midnights keep the
/// count exact across daylight-saving changes.
int _daysAgo(int epochMillis, DateTime now) {
  final date = DateTime.fromMillisecondsSinceEpoch(epochMillis);
  return DateTime.utc(now.year, now.month, now.day)
      .difference(DateTime.utc(date.year, date.month, date.day))
      .inDays;
}

String _dayLabel(AppLocalizations l10n, int daysAgo, int epochMillis) {
  if (daysAgo <= 0) return l10n.historyToday;
  if (daysAgo == 1) return l10n.historyYesterday;
  if (daysAgo < 30) return l10n.historyDaysAgo(daysAgo);
  return shortDate(epochMillis);
}

/// Rows under one header per calendar day. The input is already newest first,
/// so every day is a single run of rows.
List<Widget> _dayRows<T>({
  required AppLocalizations l10n,
  required List<T> items,
  required int Function(T item) millisOf,
  required Widget Function(T item) rowOf,
}) {
  final now = DateTime.now();
  final children = <Widget>[];
  String? shown;
  for (final item in items) {
    final millis = millisOf(item);
    final label = _dayLabel(l10n, _daysAgo(millis, now), millis);
    if (label.isNotEmpty && label != shown) {
      shown = label;
      children.add(_DayHeader(label: label));
    }
    children.add(rowOf(item));
  }
  return children;
}

Widget _searchEmpty(AppLocalizations l10n, String query) => EmptyState(
      icon: Icons.search_off_rounded,
      title: l10n.searchNoMatch(query),
      body: l10n.searchNoMatchBody,
    );

/// Removes the work from the recently opened list only. Progress is untouched,
/// so a work you are still reading stays under "continue".
Future<void> _forget(BuildContext context, WidgetRef ref, Media media) async {
  final l10n = AppLocalizations.of(context);
  await ref.read(repositoryProvider).forgetOpened(media.id);
  if (!context.mounted) return;
  ref.invalidate(recentProvider);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(l10n.historyRemoved)),
  );
}

class _Segments extends StatelessWidget {
  const _Segments({required this.selected, required this.onSelected});

  final _HistoryTab selected;
  final ValueChanged<_HistoryTab> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final options = <(_HistoryTab, String)>[
      (_HistoryTab.recent, l10n.historyRecent),
      (_HistoryTab.continueReading, l10n.historyContinue),
    ];
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: options.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final option = options[index];
          return _SegmentChip(
            label: option.$2,
            selected: option.$1 == selected,
            onTap: () => onSelected(option.$1),
          );
        },
      ),
    );
  }
}

class _SegmentChip extends StatelessWidget {
  const _SegmentChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(BestRadius.pill),
      child: AnimatedContainer(
        duration: BestMotion.fast,
        padding: const EdgeInsets.symmetric(horizontal: 15),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(BestRadius.pill),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
          ),
        ),
        child: Text(
          label,
          maxLines: 1,
          style: theme.textTheme.labelMedium?.copyWith(
            color: selected
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            fontSize: 11.5,
          ),
        ),
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
      child: Text(
        label,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// One work on one line of the list: cover, title, a detail line, an optional
/// progress bar, and a single action at the end.
class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    super.key,
    required this.media,
    required this.detail,
    required this.onTap,
    required this.trailing,
    this.progress,
  });

  final Media media;
  final String detail;
  final VoidCallback onTap;
  final Widget trailing;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fraction = progress;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 4, 8),
        child: Row(
          children: [
            SizedBox(
              width: 52,
              height: 76,
              child: BestCover(
                title: media.displayTitle,
                url: media.coverUrl,
                radius: BestRadius.sm,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    media.displayTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textDirection: autoTextDirection(
                      media.displayTitle,
                      Directionality.of(context),
                    ),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (fraction != null) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(BestRadius.pill),
                      child: BestProgressRule(
                        value: fraction,
                        track: theme.colorScheme.outlineVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }
}

class _EmptyList extends StatelessWidget {
  const _EmptyList({required this.onRefresh, required this.empty});

  final Future<void> Function() onRefresh;
  final Widget empty;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.sizeOf(context).height * 0.12),
          empty,
        ],
      ),
    );
  }
}

class _RecentList extends ConsumerWidget {
  const _RecentList({
    required this.works,
    required this.query,
    required this.onRefresh,
  });

  final List<Media> works;
  final String query;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    if (works.isEmpty) {
      return _EmptyList(
        onRefresh: onRefresh,
        empty: query.isNotEmpty
            ? _searchEmpty(l10n, query)
            : EmptyState(
                icon: Icons.history_toggle_off_rounded,
                title: l10n.historyEmptyTitle,
                body: l10n.historyRecentEmpty,
              ),
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        children: _dayRows<Media>(
          l10n: l10n,
          items: works,
          millisOf: (media) => media.lastOpenedAt,
          rowOf: (media) => _HistoryRow(
            key: ValueKey('history-${media.id}'),
            media: media,
            detail: [
              kindLabel(l10n, media.kind),
              shortTime(media.lastOpenedAt),
            ].where((part) => part.isNotEmpty).join(' · '),
            onTap: () => openSeries(context, ref, media),
            trailing: IconButton(
              tooltip: l10n.historyRemove,
              onPressed: () => _forget(context, ref, media),
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ),
        ),
      ),
    );
  }
}

class _ContinueList extends ConsumerWidget {
  const _ContinueList({
    required this.entries,
    required this.query,
    required this.onRefresh,
  });

  final List<ContinueEntry> entries;
  final String query;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    if (entries.isEmpty) {
      return _EmptyList(
        onRefresh: onRefresh,
        empty: query.isNotEmpty
            ? _searchEmpty(l10n, query)
            : EmptyState(
                icon: Icons.history_rounded,
                title: l10n.historyEmptyTitle,
                body: l10n.historyEmptyBody,
                action: FilledButton.icon(
                  onPressed: () => context.push(Routes.sources),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text(l10n.homeAddSources),
                ),
              ),
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        children: _dayRows<ContinueEntry>(
          l10n: l10n,
          items: entries,
          millisOf: (entry) => entry.progress.updatedAt,
          rowOf: (entry) {
            final media = entry.media;
            final total = entry.progress.total;
            final fraction = total <= 0
                ? (entry.progress.completed ? 1.0 : 0.0)
                : (entry.progress.position / total).clamp(0.0, 1.0).toDouble();
            return _HistoryRow(
              key: ValueKey('history-continue-${media.id}'),
              media: media,
              detail: [
                '${l10n.menuChaptersShort} ${shortNumber(entry.unit.number)}',
                if (total > 0)
                  l10n.pageOf(
                    (entry.progress.position + 1).clamp(1, total).toInt(),
                    total,
                  ),
                shortTime(entry.progress.updatedAt),
              ].where((part) => part.isNotEmpty).join(' · '),
              progress: fraction,
              onTap: () => openUnit(context, ref, media, entry.unit),
              trailing: IconButton(
                tooltip: l10n.continueReading,
                onPressed: () => openUnit(context, ref, media, entry.unit),
                icon: Icon(
                  Icons.play_arrow_rounded,
                  color: theme.colorScheme.primary,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
