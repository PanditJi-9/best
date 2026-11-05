import 'dart:async';

import 'package:best_data/best_data.dart';
import 'package:best_domain/best_domain.dart';
import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../actions.dart';
import '../extension_host.dart';
import '../l10n/generated/app_localizations.dart';
import '../labels.dart';
import '../navigation.dart';
import '../providers.dart';

/// The source-first manga shelf.
///
/// Hikari's front page is a list of the sites you brought; this is that idea
/// with a search box that can either stay inside one source or fan out over
/// all of them. A source tile opens the existing catalogue browser, so there
/// is exactly one place that knows how to page a source.
class MangaScreen extends ConsumerStatefulWidget {
  const MangaScreen({super.key});

  @override
  ConsumerState<MangaScreen> createState() => _MangaScreenState();
}

class _MangaScreenState extends ConsumerState<MangaScreen> {
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;
  String _query = '';
  String _term = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String value) {
    setState(() => _query = value);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 340), () {
      if (mounted) setState(() => _term = value.trim());
    });
  }

  void _clear() {
    _search.clear();
    _debounce?.cancel();
    setState(() {
      _query = '';
      _term = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final sources = ref
        .watch(sourceRegistryProvider)
        .all
        .where((source) => source.id != DemoSource.sourceId)
        .toList();
    final results = _term.isEmpty ? null : ref.watch(searchAllProvider(_term));

    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              child: PageMasthead(
                index: "02",
                title: l10n.mangaTitle,
                subtitle: l10n.browseSubtitle(sources.length),
                trailing: IconButton(
                  tooltip: l10n.mangaDirectory,
                  onPressed: () => context.push(Routes.sources),
                  icon: const Icon(Icons.extension_outlined),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              child: TextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                onChanged: _onSearch,
                onSubmitted: (value) {
                  _debounce?.cancel();
                  setState(() => _term = value.trim());
                },
                decoration: InputDecoration(
                  hintText: l10n.mangaSearchHint,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: _clear,
                        ),
                ),
              ),
            ),
          ),
          if (results == null) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: SectionHeader(
                  index: "01",
                  title: l10n.mangaSourcesTitle,
                  trailing: sources.isEmpty
                      ? null
                      : Text(
                          l10n.sourcesReady(sources.length),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: Text(
                  l10n.mangaSourcesBody,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ),
            ),
            if (sources.isEmpty)
              SliverToBoxAdapter(
                child: EmptyState(
                  icon: Icons.extension_off_outlined,
                  eyebrow: l10n.mangaTitle.toUpperCase(),
                  title: l10n.mangaNoSourcesTitle,
                  body: l10n.mangaNoSourcesBody,
                  action: FilledButton.icon(
                    onPressed: () => context.push(Routes.sources),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: Text(l10n.mangaDirectory),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                sliver: SliverList.separated(
                  itemCount: sources.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: BestSpace.sm),
                  itemBuilder: (context, index) {
                    final source = sources[index];
                    return _SourceTile(
                      source: source,
                      onTap: () => context.push(
                        Routes.browseSource(source.id),
                      ),
                    );
                  },
                ),
              ),
          ] else
            ..._searchSlivers(context, l10n, results),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  List<Widget> _searchSlivers(
    BuildContext context,
    AppLocalizations l10n,
    AsyncValue<List<Media>> results,
  ) {
    final theme = Theme.of(context);
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SectionHeader(
            index: "01",
            title: l10n.searchAll,
            trailing: Text(
              l10n.sourcesReady(
                ref
                    .watch(sourceRegistryProvider)
                    .all
                    .where((source) => source.id != DemoSource.sourceId)
                    .length,
              ),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
      ...switch (results) {
        AsyncValue(hasError: true, :final error) => [
            SliverToBoxAdapter(
              child: EmptyState(
                icon: Icons.cloud_off_outlined,
                title: l10n.sourceError,
                body: '$error',
                action: FilledButton.icon(
                  onPressed: () => ref.invalidate(searchAllProvider(_term)),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(l10n.retry),
                ),
              ),
            ),
          ],
        AsyncValue(isLoading: true, value: null) => const [
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 80),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
          ],
        AsyncValue(:final value?) when value.isEmpty => [
            SliverToBoxAdapter(
              child: EmptyState(
                icon: Icons.search_off_outlined,
                title: l10n.mangaNoResults,
                body: l10n.searchAll,
              ),
            ),
          ],
        AsyncValue(:final value?) => [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 180,
                  mainAxisSpacing: BestSpace.lg,
                  crossAxisSpacing: BestSpace.md,
                  childAspectRatio: 0.48,
                ),
                itemCount: value.length,
                itemBuilder: (context, index) {
                  final media = value[index];
                  return MediaCard(
                    title: media.displayTitle,
                    subtitle: kindLabel(l10n, media.kind),
                    coverUrl: media.coverUrl,
                    badge: kindLabel(l10n, media.kind),
                    rating: media.rating,
                    onTap: () => openSeries(context, ref, media),
                  );
                },
              ),
            ),
          ],
        _ => const [],
      },
    ];
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({required this.source, required this.onTap});

  final SourceAdapter source;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final extension = source is ExtensionSourceAdapter
        ? (source as ExtensionSourceAdapter).info
        : null;
    final isAnime = extension?.isAnime ?? false;
    final isServer = source.id.startsWith('suwayomi:');
    final isPack = source.id.startsWith('pack:');
    final badge = isAnime
        ? l10n.mangaAnimeBadge
        : isServer
            ? 'Server'
            : isPack
                ? 'Pack'
                : l10n.mangaMangaBadge;
    final language = source.language.isEmpty || source.language == 'all'
        ? null
        : source.language.toUpperCase();
    final latest = extension?.supportsLatest ?? false;

    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(BestRadius.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(BestSpace.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(BestRadius.md),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(BestRadius.sm),
                  border: Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.34),
                  ),
                ),
                child: Text(
                  source.name.trim().isEmpty
                      ? '?'
                      : source.name.trim().characters.first.toUpperCase(),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontFamily: BestFonts.display,
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: BestSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      source.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontFamily: BestFonts.display,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        badge,
                        if (language != null) language,
                        if (latest) 'Latest',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        letterSpacing: BestType.tracking(context, 0.2),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
