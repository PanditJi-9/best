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
import '../providers.dart';
import '../reading_card.dart';
import '../update_banner.dart';

/// A personal front door. Local actions precede every network-backed shelf.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  MediaKind? _kind;

  bool _matches(Media media) => switch (_kind) {
        null => true,
        MediaKind.manga =>
          media.kind == MediaKind.manga || media.kind == MediaKind.webtoon,
        MediaKind.drama =>
          media.kind == MediaKind.drama || media.kind == MediaKind.film,
        _ => media.kind == _kind,
      };

  Future<void> _refresh() async {
    ref.invalidate(resumeProvider);
    ref.invalidate(discoverProvider);
    ref.invalidate(rankingsProvider);
    ref.invalidate(recommendationsProvider);
    try {
      await ref.read(discoverProvider.future);
    } catch (_) {
      // Discovery has its own retry state; local actions stay available.
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final continuing = ref.watch(resumeProvider);
    final slots = continuing.value ?? const <ResumeSlot>[];
    final feed = ref.watch(discoverProvider);
    final recommendations = ref.watch(recommendationsProvider);
    final sources = ref
        .watch(sourceRegistryProvider)
        .all
        .where((s) => s.id != DemoSource.sourceId)
        .toList(growable: false);
    // A catalogue recommendation is useful here only when its source is
    // available. The independent Database remains the place for all metadata.
    bool available(Media m) => sources.any((s) => s.id == m.ref.sourceId);
    final latest = (feed.value?.latest ?? const <Media>[])
        .where(available)
        .where(_matches)
        .take(12)
        .toList();
    final picks =
        (recommendations.value?.works ?? feed.value?.works ?? const <Media>[])
            .where(available)
            .where(_matches)
            .take(12)
            .toList();

    final discoverLoading = sources.isNotEmpty &&
        (feed.isLoading || recommendations.isLoading);

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          // Rails bleed to the screen edge and carry the gutter themselves;
          // everything else is wrapped in `_inset`.
          padding: const EdgeInsets.only(top: 16, bottom: 28),
          children: [
            _inset(
              Row(children: [
                Expanded(
                  child: BestWordmark(
                    markSize: 40,
                    label: l10n.appName,
                    tagline: l10n.homeSubtitle,
                  ),
                ),
                const SizedBox(width: BestSpace.sm),
                IconButton.filledTonal(
                  tooltip: l10n.newsTitle,
                  onPressed: () => context.push(Routes.news),
                  icon: const Icon(Icons.notifications_none_rounded),
                ),
              ]),
            ),
            const SizedBox(height: 20),
            _inset(
              _SearchEntry(
                label: l10n.searchEverything,
                onTap: () => context.push(Routes.metaSearch),
              ),
            ),
            // The banner carries its own gutter.
            const UpdateBanner(),
            const SizedBox(height: 20),
            if (slots.isNotEmpty)
              _inset(
                BestReveal(
                  child: ReadingCard(
                    slot: slots.first,
                    prominent: true,
                    onOpen: () => openUnit(
                      context,
                      ref,
                      slots.first.media,
                      slots.first.unit,
                    ),
                  ),
                ),
              )
            else if (continuing.isLoading)
              _inset(const BestPulse(child: HeroSkeleton(height: 252)))
            else if (continuing.hasError)
              _inset(
                _Prompt(
                  title: l10n.sourceError,
                  body: l10n.retry,
                  label: l10n.retry,
                  icon: Icons.refresh_rounded,
                  onTap: () => ref.invalidate(resumeProvider),
                ),
              )
            else
              _inset(
                _Prompt(
                  title: l10n.homeCaughtUpTitle,
                  body: l10n.homeCaughtUpBody,
                  label: sources.isEmpty ? l10n.openGuide : l10n.openLibrary,
                  icon: Icons.auto_stories_outlined,
                  onTap: sources.isEmpty
                      ? () => openGuide(context, ref)
                      : () => context.go(Routes.library),
                ),
              ),
            _inset(
              _Heading(
                title: l10n.mangaSourcesTitle,
                action: l10n.seeAll,
                onTap: () => context.push(Routes.manga),
              ),
            ),
            if (sources.isEmpty)
              _inset(
                _Prompt(
                  title: l10n.mangaNoSourcesTitle,
                  body: l10n.mangaNoSourcesBody,
                  label: l10n.homeAddSources,
                  icon: Icons.extension_outlined,
                  onTap: () => context.push(Routes.sources),
                ),
              )
            else
              SizedBox(
                height: 48,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: BestLayout.gutter),
                  itemCount: sources.length + 1,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: BestSpace.sm),
                  itemBuilder: (context, index) => index == sources.length
                      ? ActionChip(
                          avatar: const Icon(Icons.add_rounded, size: 17),
                          label: Text(l10n.homeAddSources),
                          onPressed: () => context.push(Routes.sources),
                        )
                      : ActionChip(
                          avatar: const Icon(Icons.public_rounded, size: 17),
                          label: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 160),
                            child: Text(
                              sources[index].name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          onPressed: () => context.push(
                            Routes.browseSource(sources[index].id),
                          ),
                        ),
                ),
              ),
            _inset(
              _Heading(
                title: l10n.discoverTitle,
                action: l10n.navDatabase,
                onTap: () => context.go(Routes.database),
              ),
            ),
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: BestLayout.gutter),
                children: [
                  for (final kind in <MediaKind?>[
                    null,
                    MediaKind.manga,
                    MediaKind.manhwa,
                    MediaKind.anime,
                    MediaKind.drama,
                  ])
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: ChoiceChip(
                        label: Text(
                          kind == null
                              ? l10n.filterAll
                              : kindLabel(l10n, kind),
                        ),
                        selected: _kind == kind,
                        onSelected: (_) => setState(() => _kind = kind),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (latest.isNotEmpty) ...[
              _inset(
                Text(
                  l10n.homeNewFromSources,
                  style: BestType.sectionTitle(context),
                ),
              ),
              const SizedBox(height: 12),
              BestReveal(
                child: _Works(
                  works: latest,
                  onOpen: (m) => openSeries(context, ref, m),
                ),
              ),
            ],
            if (picks.isNotEmpty) ...[
              const SizedBox(height: 16),
              _inset(
                Text(l10n.homeForYou, style: BestType.sectionTitle(context)),
              ),
              if (recommendations.value?.personalised == true)
                _inset(
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      l10n.forYouBecause(
                        recommendations.value!.genres.join(' · '),
                      ),
                      style: BestType.body(context),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              BestReveal(
                child: _Works(
                  works: picks,
                  onOpen: (m) => openSeries(context, ref, m),
                ),
              ),
            ],
            if (latest.isEmpty && picks.isEmpty)
              if (discoverLoading)
                const PosterRailSkeleton()
              else
                _inset(
                  _Prompt(
                    title:
                        feed.hasError ? l10n.sourceError : l10n.homeNothingKind,
                    body: l10n.homeDiscoveryBody,
                    label: feed.hasError ? l10n.retry : l10n.navDatabase,
                    icon: Icons.travel_explore_rounded,
                    onTap: feed.hasError
                        ? _refresh
                        : () => context.go(Routes.database),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

/// Wraps a non-rail child in the page gutter.
Widget _inset(Widget child) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: BestLayout.gutter),
      child: child,
    );

/// The one search entry on Home. It looks like a field but opens the unified
/// search screen, so it is a button with a 52 dp target, not a `TextField`.
class _SearchEntry extends StatelessWidget {
  const _SearchEntry({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BestRadius.lg),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const ValueKey('home-unified-search'),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 54),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: BestSpace.lg),
            child: Row(children: [
              Icon(Icons.search_rounded, color: theme.colorScheme.primary),
              const SizedBox(width: BestSpace.md),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Icon(
                Icons.arrow_forward_rounded,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading({
    required this.title,
    required this.action,
    required this.onTap,
  });

  final String title;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SectionHeader(
        title: title,
        actionLabel: action,
        onAction: onTap,
      );
}

class _Prompt extends StatelessWidget {
  const _Prompt({
    required this.title,
    required this.body,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String body;
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(BestSpace.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(BestRadius.xl),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(BestRadius.md),
            ),
            child: Icon(icon, size: 22, color: primary),
          ),
          const SizedBox(width: BestSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: BestType.sectionTitle(context)),
                const SizedBox(height: BestSpace.xs + 2),
                Text(body, style: BestType.body(context)),
                const SizedBox(height: BestSpace.md),
                OutlinedButton(
                  onPressed: onTap,
                  child: Text(label),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Works extends StatelessWidget {
  const _Works({
    required this.works,
    required this.onOpen,
  });

  final List<Media> works;
  final ValueChanged<Media> onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final cardWidth = (screenWidth * 0.36).clamp(132.0, 162.0).toDouble();

    return SizedBox(
      height: cardWidth * 1.5 + 84,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: BestLayout.gutter),
        itemCount: works.length,
        separatorBuilder: (context, index) =>
            const SizedBox(width: BestSpace.md),
        itemBuilder: (context, index) => SizedBox(
          width: cardWidth,
          child: WorkCard(
            title: works[index].displayTitle,
            subtitle: kindLabel(l10n, works[index].kind),
            coverUrl: works[index].coverUrl,
            onTap: () => onOpen(works[index]),
          ),
        ),
      ),
    );
  }
}
