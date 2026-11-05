import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/generated/app_localizations.dart';
import '../meta/meta_models.dart';
import '../meta/meta_providers.dart';
import '../meta/meta_widgets.dart';
import '../navigation.dart';

Future<void> _reload(WidgetRef ref, MetaListKind kind) async {
  ref.read(metaRefreshProvider.notifier).bump();
  try {
    await ref.read(metaListProvider(kind).future);
  } catch (_) {
    // The error state is rendered by the body.
  }
}

/// The full version of one home rail: thirty ranked works from one catalogue.
///
/// The rank on each row is the provider's own order, not a re-ranking. That is
/// why the header names the community before it names the list.
class MetaListScreen extends ConsumerWidget {
  const MetaListScreen({super.key, required this.kind});

  final MetaListKind kind;

  String _title(AppLocalizations l10n) => switch (kind) {
        MetaListKind.anilistTrending => l10n.metaTrending,
        MetaListKind.anilistTop => l10n.metaTopAnime,
        MetaListKind.anilistAiring => l10n.metaAiring,
        MetaListKind.malTop => l10n.metaMalTop,
        MetaListKind.hwaTop => l10n.metaHwaTop,
      };

  String _subtitle(AppLocalizations l10n) => switch (kind) {
        MetaListKind.anilistTrending => l10n.metaTrendingSub,
        MetaListKind.anilistTop => l10n.metaTrendingSub,
        MetaListKind.anilistAiring => l10n.metaAiringSub,
        MetaListKind.malTop => l10n.metaMalTopSub,
        MetaListKind.hwaTop => l10n.metaHwaTopSub,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(metaListProvider(kind));
    final source = kind.source;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        surfaceTintColor: Colors.transparent,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _title(l10n),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            Text(
              _subtitle(l10n),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w400,
                  ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 14),
            child: Center(child: MetaSourceChip(source: source)),
          ),
        ],
      ),
      body: async.when(
        loading: () => const _ListLoading(),
        error: (error, stack) => _ListError(
          l10n: l10n,
          message: error.toString(),
          onRetry: () => ref.read(metaRefreshProvider.notifier).bump(),
        ),
        data: (works) {
          if (works.isEmpty) {
            return RefreshIndicator(
              onRefresh: () => _reload(ref, kind),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                children: [
                  EmptyState(
                    icon: Icons.inbox_outlined,
                    title: l10n.metaNoResults,
                    body: l10n.metaSourceUnavailableBody,
                    action: FilledButton.icon(
                      onPressed: () =>
                          ref.read(metaRefreshProvider.notifier).bump(),
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: Text(l10n.retry),
                    ),
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () => _reload(ref, kind),
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(top: 6, bottom: 28),
              itemCount: works.length,
              separatorBuilder: (context, index) => Divider(
                height: 1,
                indent: 66,
                endIndent: 20,
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              itemBuilder: (context, index) {
                final work = works[index];
                return MetaRankRow(
                  work: work,
                  rank: index + 1,
                  onTap: () => context.push(
                    Routes.metaWork(work.source, work.id),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _ListLoading extends StatelessWidget {
  const _ListLoading();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      itemCount: 8,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) => Container(
        height: 62,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(BestRadius.md),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
      ),
    );
  }
}

class _ListError extends StatelessWidget {
  const _ListError({
    required this.l10n,
    required this.message,
    required this.onRetry,
  });

  final AppLocalizations l10n;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: EmptyState(
          icon: Icons.cloud_off_rounded,
          title: l10n.metaError,
          body: message,
          action: FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(l10n.retry),
          ),
        ),
      ),
    );
  }
}
