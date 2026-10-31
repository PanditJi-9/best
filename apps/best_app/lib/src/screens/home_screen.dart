import 'package:best_data/best_data.dart';
import 'package:best_domain/best_domain.dart';
import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../actions.dart';
import '../l10n/generated/app_localizations.dart';
import '../labels.dart';
import '../navigation.dart';
import '../progress_label.dart';
import '../providers.dart';

/// The front door.
///
/// A fresh install has no library, so Home cannot be "your stuff": it is one
/// editorial spotlight, the resume rail, a ranked trending row and the sample
/// films that make the player reachable in two taps. Once a library exists the
/// resume rail moves to the top of the screen, because returning to a story is
/// the most common reason to open the app at all.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  static const BrowseKey _guideKey = (
    sourceId: DemoSource.sourceId,
    query: '',
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final guide = ref.watch(browseProvider(_guideKey));
    final continuing =
        ref.watch(continueProvider).value ?? const <ContinueEntry>[];
    final shelf = ref.watch(libraryProvider).value ?? const <LibraryEntry>[];
    final works = guide.value ?? const <Media>[];
    final featured = works.isEmpty ? null : works.first;
    final trending = works.length <= 1 ? const <Media>[] : works.sublist(1);
    final samples = works.where((media) => media.kind.isWatching).toList();

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(browseProvider(_guideKey));
          ref.invalidate(continueProvider);
          ref.invalidate(libraryProvider);
          try {
            await ref.read(browseProvider(_guideKey).future);
          } catch (_) {
            // The error state is rendered inline.
          }
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                child: Row(
                  children: [
                    Expanded(
                        child: BestWordmark(
                            tagline: l10n.tagline, label: l10n.appName)),
                    IconButton.filledTonal(
                      tooltip: l10n.searchAll,
                      onPressed: () => context.go(Routes.browse),
                      icon: const Icon(Icons.search, size: 22),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                child: _SearchPrompt(
                  label: l10n.searchAll,
                  onTap: () => context.go(Routes.browse),
                ),
              ),
            ),
            if (guide.isLoading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 80),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if (guide.hasError)
              SliverToBoxAdapter(
                child: EmptyState(
                  icon: Icons.cloud_off_outlined,
                  title: l10n.sourceError,
                  body: '${guide.error}',
                  action: FilledButton.icon(
                    onPressed: () => ref.invalidate(browseProvider(_guideKey)),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: Text(l10n.retry),
                  ),
                ),
              )
            else if (featured != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
                  child: SpotlightCard(
                    title: featured.displayTitle,
                    nativeTitle: featured.nativeTitle,
                    badge: kindLabel(l10n, featured.kind),
                    meta: _spotlightMeta(l10n, featured),
                    coverUrl: featured.coverUrl,
                    actionLabel: featured.kind.isReading
                        ? l10n.startReading
                        : l10n.startWatching,
                    actionIcon: featured.kind.isReading
                        ? Icons.menu_book_rounded
                        : Icons.play_arrow_rounded,
                    onOpen: () => openSeries(context, ref, featured),
                  ),
                ),
              ),
            if (continuing.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: SectionHeader(
                    title: l10n.continueTitle,
                    actionLabel: l10n.seeAll,
                    onAction: () => context.go(Routes.library),
                  ),
                ),
              ),
            if (continuing.isNotEmpty)
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 172,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: continuing.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: BestSpace.md),
                    itemBuilder: (context, index) {
                      final entry = continuing[index];
                      return ContinueCard(
                        title: entry.media.displayTitle,
                        subtitle: entry.unit.displayTitle,
                        coverUrl: entry.media.coverUrl,
                        progress: entry.progress.fraction,
                        progressLabel: continueProgressLabel(l10n, entry),
                        isVideo: entry.media.kind.isWatching,
                        onOpen: () =>
                            openUnit(context, ref, entry.media, entry.unit),
                      );
                    },
                  ),
                ),
              ),
            if (trending.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: SectionHeader(
                    title: l10n.trendingTitle,
                    actionLabel: l10n.seeAll,
                    onAction: () => context.go(Routes.browse),
                  ),
                ),
              ),
            if (trending.isNotEmpty)
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 266,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: trending.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: BestSpace.md),
                    itemBuilder: (context, index) {
                      final media = trending[index];
                      return SizedBox(
                        width: 130,
                        child: MediaCard(
                          title: media.displayTitle,
                          subtitle: kindLabel(l10n, media.kind),
                          coverUrl: media.coverUrl,
                          badge: kindLabel(l10n, media.kind),
                          rank: index + 1,
                          onTap: () => openSeries(context, ref, media),
                        ),
                      );
                    },
                  ),
                ),
              ),
            if (samples.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                  child: SectionHeader(title: l10n.samplesTitle),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    l10n.samplesBody,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 150,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    itemCount: samples.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: BestSpace.md),
                    itemBuilder: (context, index) {
                      final media = samples[index];
                      return _SampleCard(
                        title: media.displayTitle,
                        badge: l10n.sampleFilmBadge,
                        coverUrl: media.coverUrl,
                        onTap: () => openSeries(context, ref, media),
                      );
                    },
                  ),
                ),
              ),
            ],
            if (shelf.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Container(
                    padding: const EdgeInsets.all(BestSpace.xl),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(BestRadius.lg),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const BestMark(size: 38),
                        const SizedBox(height: BestSpace.md),
                        Text(
                          l10n.libraryWaiting,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: BestSpace.xs),
                        Text(
                          l10n.libraryWaitingBody,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.55,
                          ),
                        ),
                        const SizedBox(height: BestSpace.lg),
                        FilledButton.icon(
                          onPressed: () => openGuide(context, ref),
                          icon:
                              const Icon(Icons.auto_stories_outlined, size: 18),
                          label: Text(l10n.openGuide),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }

  static String _spotlightMeta(AppLocalizations l10n, Media media) {
    final parts = <String>[
      if (media.year != null) '${media.year}',
      statusLabel(l10n, media.status),
      if (media.author != null && media.author!.trim().isNotEmpty)
        media.author!,
    ];
    return parts.join('  ·  ');
  }
}

class _SearchPrompt extends StatelessWidget {
  const _SearchPrompt({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(BestRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(BestRadius.md),
        child: Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: BestSpace.lg),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(BestRadius.md),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Row(
            children: [
              Icon(
                Icons.search,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: BestSpace.md),
              Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SampleCard extends StatelessWidget {
  const _SampleCard({
    required this.title,
    required this.badge,
    required this.onTap,
    this.coverUrl,
  });

  final String title;
  final String badge;
  final String? coverUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: title,
      child: SizedBox(
        width: 270,
        child: Material(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(BestRadius.lg),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Stack(
              fit: StackFit.expand,
              children: [
                BestCover(title: title, url: coverUrl, radius: 0),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x22000000), Color(0xE607080B)],
                    ),
                  ),
                ),
                PositionedDirectional(
                  top: BestSpace.md,
                  start: BestSpace.md,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(BestRadius.pill),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      child: Text(
                        badge,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
                PositionedDirectional(
                  start: BestSpace.lg,
                  end: BestSpace.lg,
                  bottom: BestSpace.lg,
                  child: Row(
                    children: [
                      DecoratedBox(
                        decoration: const BoxDecoration(
                          color: BestColors.jade,
                          shape: BoxShape.circle,
                        ),
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(
                            Icons.play_arrow_rounded,
                            color: BestColors.ink,
                            size: 22,
                          ),
                        ),
                      ),
                      const SizedBox(width: BestSpace.md),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
