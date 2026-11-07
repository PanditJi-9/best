import 'dart:async';

import 'package:best_domain/best_domain.dart';
import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/generated/app_localizations.dart';
import '../labels.dart';
import '../navigation.dart';
import '../providers.dart';
import '../widgets/source_avatar.dart';

/// Home shows one catalogue at a time, so a long list of chips becomes noise.
/// This screen is where a reader decides which sources take part in that strip.
/// Hiding never uninstalls and never touches the shelf or downloads.
class ManageSourcesScreen extends ConsumerStatefulWidget {
  const ManageSourcesScreen({super.key});

  @override
  ConsumerState<ManageSourcesScreen> createState() =>
      _ManageSourcesScreenState();
}

class _ManageSourcesScreenState extends ConsumerState<ManageSourcesScreen> {
  /// Source ids with an explicit test in flight. The test uses the same
  /// popular() call Home uses, so a green result is evidence about the path a
  /// reader actually takes, not a separate health-check endpoint.
  final Set<String> _testing = <String>{};

  Future<void> _toggle(SourceAdapter source, bool visible) async {
    final l10n = AppLocalizations.of(context);
    final all = ref.read(sourceRegistryProvider).all;
    final accepted = await ref
        .read(sourceVisibilityProvider.notifier)
        .setVisible(source.id, visible, allIds: all.map((entry) => entry.id));
    if (!accepted) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.sourcesKeepOne)));
      }
      return;
    }
    if (visible || !mounted) return;

    // The hidden source may be the one Home remembered. Move the remembered
    // choice to a source that is still visible so reopening Home is coherent.
    final scope = ref.read(homeScopeProvider);
    if (scope.sourceId != source.id) return;
    final hidden = ref.read(sourceVisibilityProvider);
    for (final candidate in all) {
      if (candidate.id == source.id || hidden.contains(candidate.id)) continue;
      ref.read(homeScopeProvider.notifier).selectSource(candidate.id);
      return;
    }
  }

  Future<void> _test(SourceAdapter source) async {
    if (!_testing.add(source.id)) return;
    setState(() {});
    final started = Stopwatch()..start();
    try {
      await source.popular().timeout(const Duration(seconds: 15));
      started.stop();
      if (!mounted) return;
      ref.read(sourceHealthProvider.notifier).recordSuccess(
            source.id,
            started.elapsed,
          );
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.sourceTestSuccess(source.name, started.elapsedMilliseconds),
          ),
        ),
      );
    } on TimeoutException {
      started.stop();
      if (!mounted) return;
      ref.read(sourceHealthProvider.notifier).recordFailure(
            source.id,
            TimeoutException('No answer in 15s'),
          );
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.sourceTestTimeout(source.name))),
      );
    } catch (error) {
      started.stop();
      if (!mounted) return;
      ref.read(sourceHealthProvider.notifier).recordFailure(source.id, error);
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.sourceTestFailed(source.name, _shortError(error)),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _testing.remove(source.id));
    }
  }

  static String _shortError(Object error) {
    final first = error.toString().split('\n').first.trim();
    if (first.isEmpty) return 'Unknown error';
    return first.length > 120 ? '${first.substring(0, 117)}…' : first;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final all = ref.watch(sourceRegistryProvider).all;
    final hidden = ref.watch(sourceVisibilityProvider);
    final health = ref.watch(sourceHealthProvider);
    final current = ref.watch(homeScopeProvider).sourceId;
    final reading = <SourceAdapter>[];
    final watching = <SourceAdapter>[];
    for (final source in all) {
      if (homeKindOf(source) == HomeKind.watching) {
        watching.add(source);
      } else {
        reading.add(source);
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.sourcesManage),
        actions: [
          IconButton(
            tooltip: l10n.homeAddSources,
            onPressed: () => context.push(Routes.sources),
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: all.isEmpty
          ? EmptyState(
              icon: Icons.extension_outlined,
              title: l10n.mangaNoSourcesTitle,
              body: l10n.mangaNoSourcesBody,
              action: FilledButton.icon(
                onPressed: () => context.push(Routes.sources),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(l10n.homeAddSources),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                BestLayout.gutter,
                BestSpace.sm,
                BestLayout.gutter,
                BestSpace.xxl,
              ),
              children: [
                Container(
                  padding: const EdgeInsets.all(BestSpace.lg),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(BestRadius.lg),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.tune_rounded,
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: BestSpace.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.sourcesManageBody,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: BestSpace.sm),
                            Text(
                              l10n.sourcesManageHint,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                height: 1.45,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (reading.isNotEmpty) ...[
                  _SectionLabel(label: l10n.kindManga),
                  for (final source in reading)
                    _SourceRow(
                      source: source,
                      visible: !hidden.contains(source.id),
                      current: source.id == current,
                      health: health[source.id],
                      testing: _testing.contains(source.id),
                      onTest: () => _test(source),
                      onChanged: (value) => _toggle(source, value),
                    ),
                ],
                if (watching.isNotEmpty) ...[
                  _SectionLabel(label: l10n.kindAnime),
                  for (final source in watching)
                    _SourceRow(
                      source: source,
                      visible: !hidden.contains(source.id),
                      current: source.id == current,
                      health: health[source.id],
                      testing: _testing.contains(source.id),
                      onTest: () => _test(source),
                      onChanged: (value) => _toggle(source, value),
                    ),
                ],
              ],
            ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        BestSpace.xs,
        BestSpace.lg,
        BestSpace.xs,
        BestSpace.xs,
      ),
      child: Text(
        label,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({
    required this.source,
    required this.visible,
    required this.current,
    required this.health,
    required this.testing,
    required this.onTest,
    required this.onChanged,
  });

  final SourceAdapter source;
  final bool visible;
  final bool current;
  final SourceHealth? health;
  final bool testing;
  final VoidCallback onTest;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final details = [
      homeKindOf(source) == HomeKind.watching ? l10n.kindAnime : l10n.kindManga,
      if (source.language.trim().isNotEmpty) source.language.toUpperCase(),
    ].join(' · ');
    final statusColor = switch (health) {
      null => theme.colorScheme.outline,
      final h when !h.tested => theme.colorScheme.outline,
      final h when h.failed => theme.colorScheme.error,
      final h when h.slow => BestColors.gold,
      _ => BestColors.jade,
    };
    final error = health?.lastError;
    return Padding(
      padding: const EdgeInsets.only(bottom: BestSpace.xs),
      child: Material(
        color: theme.colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BestRadius.lg),
          side: BorderSide(
            color: current
                ? theme.colorScheme.primary.withValues(alpha: 0.55)
                : theme.colorScheme.outlineVariant,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              key: ValueKey('manage-source-${source.id}'),
              value: visible,
              onChanged: onChanged,
              secondary: SourceAvatar(source: source, size: 38),
              title: Row(
                children: [
                  Flexible(
                    child: Text(
                      source.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: autoTextDirection(
                        source.name,
                        Directionality.of(context),
                      ),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (current) ...[
                    const SizedBox(width: BestSpace.sm),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(BestRadius.pill),
                      ),
                      child: Text(
                        l10n.sourcesCurrent,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              subtitle: Text(
                details,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                BestSpace.lg,
                0,
                BestSpace.sm,
                BestSpace.sm,
              ),
              child: Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: statusColor,
                    ),
                  ),
                  const SizedBox(width: BestSpace.xs),
                  Expanded(
                    child: Text(
                      _healthLabel(l10n, health),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: health?.failed == true
                            ? theme.colorScheme.error
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: testing ? null : onTest,
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      minimumSize: const Size(0, 28),
                      padding: const EdgeInsets.symmetric(
                        horizontal: BestSpace.sm,
                      ),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      testing ? l10n.sourceTesting : l10n.sourceTest,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (health?.failed == true && error != null && error.isNotEmpty)
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  BestSpace.lg,
                  0,
                  BestSpace.lg,
                  BestSpace.sm,
                ),
                child: Text(
                  error,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: autoTextDirection(
                    error,
                    Directionality.of(context),
                  ),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.error,
                    fontSize: 10,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _healthLabel(AppLocalizations l10n, SourceHealth? health) {
    if (health == null || !health.tested) return l10n.sourceHealthUnknown;
    if (health.failed) {
      return l10n.sourceHealthFailed(shortDateTime(health.lastFailureAt));
    }
    if (health.slow) {
      return l10n.sourceHealthSlow(_latency(health.lastLatencyMs));
    }
    return l10n.sourceHealthOk(shortDateTime(health.lastSuccessAt));
  }

  static String _latency(int milliseconds) {
    if (milliseconds >= 1000) {
      return '${(milliseconds / 1000).toStringAsFixed(1)} s';
    }
    return '$milliseconds ms';
  }
}
