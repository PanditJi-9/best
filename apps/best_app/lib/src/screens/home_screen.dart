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
    final theme = Theme.of(context);
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

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          children: [
            Row(children: [
              const BestMark(size: 42),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(l10n.appName, style: BestType.pageTitle(context)),
                    const SizedBox(height: 4),
                    Text(l10n.homeSubtitle, style: BestType.meta(context)),
                  ])),
              IconButton(
                  tooltip: l10n.newsTitle,
                  onPressed: () => context.push(Routes.news),
                  icon: const Icon(Icons.notifications_none_rounded)),
            ]),
            const SizedBox(height: 22),
            Material(
              color: theme.colorScheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(BestRadius.lg),
                  side: BorderSide(color: theme.colorScheme.outlineVariant)),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: const ValueKey('home-unified-search'),
                onTap: () => context.push(Routes.metaSearch),
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(children: [
                      Icon(Icons.search_rounded,
                          color: theme.colorScheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Text(l10n.searchEverything,
                              style: theme.textTheme.bodyMedium)),
                      const Icon(Icons.arrow_forward_rounded, size: 18),
                    ])),
              ),
            ),
            const UpdateBanner(),
            const SizedBox(height: 20),
            if (slots.isNotEmpty)
              ReadingCard(
                  slot: slots.first,
                  prominent: true,
                  onOpen: () => openUnit(
                      context, ref, slots.first.media, slots.first.unit))
            else if (continuing.isLoading)
              const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: LinearProgressIndicator())
            else if (continuing.hasError)
              _Prompt(
                  title: l10n.sourceError,
                  body: l10n.retry,
                  label: l10n.retry,
                  icon: Icons.refresh_rounded,
                  onTap: () => ref.invalidate(resumeProvider))
            else
              _Prompt(
                  title: l10n.homeCaughtUpTitle,
                  body: l10n.homeCaughtUpBody,
                  label: sources.isEmpty ? l10n.openGuide : l10n.openLibrary,
                  icon: Icons.auto_stories_outlined,
                  onTap: sources.isEmpty
                      ? () => openGuide(context, ref)
                      : () => context.go(Routes.library)),
            _Heading(
                title: l10n.mangaSourcesTitle,
                action: l10n.seeAll,
                onTap: () => context.push(Routes.manga)),
            if (sources.isEmpty)
              _Prompt(
                  title: l10n.mangaNoSourcesTitle,
                  body: l10n.mangaNoSourcesBody,
                  label: l10n.homeAddSources,
                  icon: Icons.extension_outlined,
                  onTap: () => context.push(Routes.sources))
            else
              SizedBox(
                  height: 52,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: sources.length + 1,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: 8),
                    itemBuilder: (context, index) => index == sources.length
                        ? OutlinedButton.icon(
                            onPressed: () => context.push(Routes.sources),
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: Text(l10n.homeAddSources))
                        : OutlinedButton.icon(
                            onPressed: () => context
                                .push(Routes.browseSource(sources[index].id)),
                            icon: const Icon(Icons.public_rounded, size: 18),
                            label: Text(sources[index].name)),
                  )),
            _Heading(
                title: l10n.discoverTitle,
                action: l10n.navDatabase,
                onTap: () => context.go(Routes.database)),
            SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
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
                            label: Text(kind == null
                                ? l10n.filterAll
                                : kindLabel(l10n, kind)),
                            selected: _kind == kind,
                            onSelected: (_) => setState(() => _kind = kind),
                          )),
                  ],
                )),
            const SizedBox(height: 12),
            if (latest.isNotEmpty) ...[
              Text(l10n.homeNewFromSources,
                  style: BestType.sectionTitle(context)),
              const SizedBox(height: 12),
              _Works(works: latest, onOpen: (m) => openSeries(context, ref, m)),
            ],
            if (picks.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(l10n.homeForYou, style: BestType.sectionTitle(context)),
              if (recommendations.value?.personalised == true)
                Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                        l10n.forYouBecause(
                            recommendations.value!.genres.join(' · ')),
                        style: BestType.body(context))),
              const SizedBox(height: 12),
              _Works(works: picks, onOpen: (m) => openSeries(context, ref, m)),
            ],
            if (latest.isEmpty && picks.isEmpty)
              if (sources.isNotEmpty &&
                  (feed.isLoading || recommendations.isLoading))
                const Padding(
                    padding: EdgeInsets.all(24),
                    child: LinearProgressIndicator())
              else
                _Prompt(
                    title:
                        feed.hasError ? l10n.sourceError : l10n.homeNothingKind,
                    body: l10n.homeDiscoveryBody,
                    label: feed.hasError ? l10n.retry : l10n.navDatabase,
                    icon: Icons.travel_explore_rounded,
                    onTap: feed.hasError
                        ? _refresh
                        : () => context.go(Routes.database)),
          ],
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(
      {required this.title, required this.action, required this.onTap});
  final String title;
  final String action;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 6),
        child: Row(children: [
          Expanded(child: Text(title, style: BestType.sectionTitle(context))),
          TextButton(onPressed: onTap, child: Text(action)),
        ]),
      );
}

class _Prompt extends StatelessWidget {
  const _Prompt(
      {required this.title,
      required this.body,
      required this.label,
      required this.icon,
      required this.onTap});
  final String title;
  final String body;
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(BestRadius.lg),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: BestType.sectionTitle(context)),
          const SizedBox(height: 8),
          Text(body, style: BestType.body(context)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
              onPressed: onTap, icon: Icon(icon, size: 18), label: Text(label)),
        ]),
      );
}

class _Works extends StatelessWidget {
  const _Works({required this.works, required this.onOpen});
  final List<Media> works;
  final ValueChanged<Media> onOpen;
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
        height: 242,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: works.length,
          separatorBuilder: (context, index) => const SizedBox(width: 14),
          itemBuilder: (context, index) => SizedBox(
              width: 118,
              child: WorkCard(
                  title: works[index].displayTitle,
                  subtitle: kindLabel(l10n, works[index].kind),
                  coverUrl: works[index].coverUrl,
                  onTap: () => onOpen(works[index]))),
        ));
  }
}
