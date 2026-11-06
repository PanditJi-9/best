import 'dart:async';

import 'package:best_data/best_data.dart';
import 'package:best_domain/best_domain.dart';
import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/generated/app_localizations.dart';
import '../labels.dart';
import '../navigation.dart';
import '../providers.dart';

/// Moving a work to another source without losing the person's place.
///
/// The old row is read from storage, not from a live source: a work usually
/// moves *because* its source died. The candidate is fetched from the target
/// source, its chapters are matched by number (never by position), and only
/// then is anything written.
class MigrateScreen extends ConsumerStatefulWidget {
  const MigrateScreen({super.key, required this.mediaId});

  final String mediaId;

  @override
  ConsumerState<MigrateScreen> createState() => _MigrateScreenState();
}

class _MigrateScreenState extends ConsumerState<MigrateScreen> {
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;
  String _query = '';
  String _sourceId = '*';
  String? _busyId;
  bool _seeded = false;

  /// The search box starts with the old title, but the title arrives with the
  /// stored row: writing the controller during build would rebuild the field
  /// mid-layout, so the seed waits one frame. It deliberately does not search:
  /// opening the screen must not fire a request at every installed source.
  void _seed(SeriesData old) {
    if (_seeded) return;
    _seeded = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _search.text = old.media.displayTitle;
      setState(() {});
    });
  }

  void _submit() {
    _debounce?.cancel();
    setState(() => _query = _search.text.trim());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 320), () {
      if (!mounted) return;
      setState(() => _query = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final local = ref.watch(localWorkProvider(widget.mediaId));

    return Scaffold(
      appBar: AppBar(title: Text(l10n.migrateTitle)),
      body: local.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => EmptyState(
          icon: Icons.error_outline,
          title: l10n.migrateFailed,
          body: '$error',
          action: FilledButton(
            onPressed: () => ref.invalidate(localWorkProvider(widget.mediaId)),
            child: Text(l10n.retry),
          ),
        ),
        data: (old) {
          _seed(old);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: Text(
                  l10n.migrateBody,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: Row(
                  children: [
                    SizedBox(
                      width: 52,
                      height: 76,
                      child: BestCover(
                        title: old.media.displayTitle,
                        url: old.media.coverUrl,
                        radius: BestRadius.sm,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            old.media.displayTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: BestType.cardTitle(context),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            l10n.unitCount(old.units.length),
                            style: BestType.meta(context),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: TextField(
                  controller: _search,
                  textInputAction: TextInputAction.search,
                  onChanged: _onSearch,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    hintText: l10n.migrateSearchSources,
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () {
                                  _search.clear();
                                  _debounce?.cancel();
                                  setState(() => _query = '');
                                },
                              ),
                              IconButton(
                                tooltip: l10n.migrateSearchSources,
                                icon: const Icon(Icons.arrow_forward_rounded,
                                    size: 18),
                                onPressed: _submit,
                              ),
                            ],
                          ),
                  ),
                ),
              ),
              _SourcePicker(
                selected: _sourceId,
                onChanged: (value) => setState(() => _sourceId = value),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _Results(
                  key: ValueKey('$_sourceId|$_query'),
                  sourceId: _sourceId,
                  query: _query,
                  busyId: _busyId,
                  onPick: (candidate) => _prepareAndConfirm(old, candidate),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _prepareAndConfirm(SeriesData old, Media candidate) async {
    final l10n = AppLocalizations.of(context);
    final registry = ref.read(sourceRegistryProvider);
    final source = registry.byId(candidate.ref.sourceId);
    if (source == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.migrateFailed)));
      return;
    }
    setState(() => _busyId = candidate.id);
    try {
      var target = candidate;
      try {
        target = await source.details(candidate);
      } catch (_) {
        // The search row already carries a title and cover; chapters are the
        // only thing this screen truly needs from the target.
      }
      final units = await source.units(target);
      final plan = MigrationPlan.between(old.units, units);
      if (!mounted) return;
      setState(() => _busyId = null);
      await _showPlan(old: old, target: target, units: units, plan: plan);
    } catch (error) {
      if (!mounted) return;
      setState(() => _busyId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${l10n.migrateFailed}: $error')),
      );
    }
  }

  Future<void> _showPlan({
    required SeriesData old,
    required Media target,
    required List<MediaUnit> units,
    required MigrationPlan plan,
  }) async {
    final l10n = AppLocalizations.of(context);
    var keepOld = false;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          final theme = Theme.of(context);
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    target.displayTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: BestType.sectionTitle(context),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    [
                      registryName(target.ref.sourceId),
                      if (target.author != null && target.author!.isNotEmpty)
                        target.author!,
                      kindLabel(l10n, target.kind),
                    ].join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (plan.isEmpty)
                    Text(
                      l10n.migrateNoChapters,
                      style: theme.textTheme.bodyMedium,
                    )
                  else
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(BestRadius.md),
                        border:
                            Border.all(color: theme.colorScheme.outlineVariant),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.swap_horiz_rounded,
                            color: BestColors.jade,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '${plan.pairs.length} / ${plan.totalOld} '
                              '${l10n.migrateMatched}',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 10),
                  Text(
                    l10n.migrateDownloadsNote,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: keepOld,
                    onChanged: (value) =>
                        setSheetState(() => keepOld = value ?? false),
                    title: Text(l10n.migrateKeepOld),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: Text(l10n.cancel),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: Text(l10n.migrateConfirm),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (confirmed != true || !mounted) return;
    await _migrate(
      old: old,
      target: target,
      units: units,
      plan: plan,
      keepOld: keepOld,
    );
  }

  Future<void> _migrate({
    required SeriesData old,
    required Media target,
    required List<MediaUnit> units,
    required MigrationPlan plan,
    required bool keepOld,
  }) async {
    final l10n = AppLocalizations.of(context);
    final repository = ref.read(repositoryProvider);
    setState(() => _busyId = target.id);
    try {
      // The target and its chapters must exist before the progress rows point
      // at them, otherwise a chapter id would reference nothing.
      await repository.saveMedia(target);
      await repository.saveUnits(units);
      await repository.migrateMedia(
        fromMediaId: old.media.id,
        target: target,
        carriedProgress: plan.carryProgress(old.progress),
        removeOldFromLibrary: !keepOld,
      );
      ref.invalidate(libraryProvider);
      ref.invalidate(continueProvider);
      ref.invalidate(resumeProvider);
      ref.invalidate(seriesProvider(
        (sourceId: target.ref.sourceId, url: target.ref.url),
      ));
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.migrateDone)));
      context.pushReplacement(Routes.seriesOf(target));
    } catch (error) {
      if (!mounted) return;
      setState(() => _busyId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${l10n.migrateFailed}: $error')),
      );
    }
  }

  /// The source's display name, falling back to its id when the adapter is gone.
  String registryName(String sourceId) {
    final source = ref.read(sourceRegistryProvider).byId(sourceId);
    return source?.name ?? sourceId;
  }
}

class _SourcePicker extends ConsumerWidget {
  const _SourcePicker({required this.selected, required this.onChanged});

  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final registry = ref.watch(sourceRegistryProvider);
    final sources = registry.all
        .where((source) => source.id != DemoSource.sourceId)
        .toList(growable: false);
    // A source removed since the last visit must not leave the picker stuck on
    // a value that no longer has an item.
    final value = selected == '*' || sources.any((s) => s.id == selected)
        ? selected
        : '*';

    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          ChoiceChip(
            label: Text(l10n.migrateAllSources),
            selected: value == '*',
            onSelected: (_) => onChanged('*'),
          ),
          for (final source in sources) ...[
            const SizedBox(width: 8),
            ChoiceChip(
              label: Text(source.name),
              selected: value == source.id,
              onSelected: (_) => onChanged(source.id),
            ),
          ],
        ],
      ),
    );
  }
}

class _Results extends ConsumerWidget {
  const _Results({
    super.key,
    required this.sourceId,
    required this.query,
    required this.busyId,
    required this.onPick,
  });

  final String sourceId;
  final String query;
  final String? busyId;
  final ValueChanged<Media> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    if (query.trim().isEmpty) {
      return EmptyState(
        icon: Icons.travel_explore_rounded,
        title: l10n.migrateSearchSources,
        body: l10n.migrateHint,
      );
    }
    final results =
        ref.watch(migrationSearchProvider((sourceId: sourceId, query: query)));
    final registry = ref.watch(sourceRegistryProvider);

    return results.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => EmptyState(
        icon: Icons.error_outline,
        title: l10n.sourceError,
        body: '$error',
        action: FilledButton(
          onPressed: () => ref.invalidate(
            migrationSearchProvider((sourceId: sourceId, query: query)),
          ),
          child: Text(l10n.retry),
        ),
      ),
      data: (works) {
        if (works.isEmpty) {
          return EmptyState(
            icon: Icons.search_off_rounded,
            title: l10n.migrateNoResults,
            body: l10n.migrateNoResultsBody,
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          itemCount: works.length,
          itemBuilder: (context, index) {
            final work = works[index];
            final source = registry.byId(work.ref.sourceId);
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: WorkCard(
                density: WorkCardDensity.row,
                title: work.displayTitle,
                subtitle: [
                  source?.name ?? work.ref.sourceId,
                  if (work.year != null) '${work.year}',
                  if (work.author != null && work.author!.isNotEmpty)
                    work.author!,
                ].join(' · '),
                coverUrl: work.coverUrl,
                badge: kindLabel(l10n, work.kind),
                trailing: busyId == work.id
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      )
                    : const Icon(Icons.chevron_right_rounded, size: 20),
                onTap: busyId == null ? () => onPick(work) : null,
              ),
            );
          },
        );
      },
    );
  }
}
