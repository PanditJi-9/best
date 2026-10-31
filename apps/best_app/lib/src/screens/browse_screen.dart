import 'dart:async';

import 'package:best_domain/best_domain.dart';
import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../actions.dart';
import '../l10n/generated/app_localizations.dart';
import '../labels.dart';
import '../providers.dart';

class BrowseScreen extends ConsumerStatefulWidget {
  const BrowseScreen({super.key});

  @override
  ConsumerState<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends ConsumerState<BrowseScreen> {
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;
  String _query = '';
  String _searchTerm = '';
  String? _sourceId;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String value) {
    setState(() => _query = value);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 320), () {
      if (mounted) setState(() => _searchTerm = value.trim());
    });
  }

  void _clear() {
    _search.clear();
    _debounce?.cancel();
    setState(() {
      _query = '';
      _searchTerm = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final registry = ref.watch(sourceRegistryProvider);
    final sources = registry.all;

    if (sources.isEmpty) {
      return Scaffold(
        body: EmptyState(
          icon: Icons.extension_off_outlined,
          title: l10n.sourceError,
          body: l10n.nothingHereBody,
        ),
      );
    }

    final sourceId = _sourceId ?? sources.first.id;
    final source = registry.byId(sourceId) ?? sources.first;
    final key = (sourceId: source.id, query: _searchTerm);
    final results = ref.watch(browseProvider(key));

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.browseTitle,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1.2,
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        l10n.browseSubtitle(sources.length),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const BestMark(size: 34),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: sources.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final candidate = sources[index];
                return _SourcePill(
                  label: candidate.name,
                  selected: candidate.id == source.id,
                  onTap: () => setState(() => _sourceId = candidate.id),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onChanged: _onSearch,
              onSubmitted: (value) {
                _debounce?.cancel();
                setState(() => _searchTerm = value.trim());
              },
              decoration: InputDecoration(
                hintText: l10n.searchSource(source.name),
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
          const SizedBox(height: 8),
          Expanded(
            child: results.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => EmptyState(
                icon: Icons.cloud_off_outlined,
                title: l10n.sourceError,
                body: '$error',
                action: FilledButton.icon(
                  onPressed: () => ref.invalidate(browseProvider(key)),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(l10n.retry),
                ),
              ),
              data: (works) {
                if (works.isEmpty) {
                  return EmptyState(
                    icon: Icons.travel_explore_outlined,
                    eyebrow: source.name.toUpperCase(),
                    title: l10n.nothingHere,
                    body: l10n.nothingHereBody,
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 4, 22, 2),
                      child: Text(
                        l10n.resultCount(works.length),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    Expanded(
                      child: _BrowseGrid(
                        works: works,
                        onOpen: (media) => openSeries(context, ref, media),
                        onRefresh: () async {
                          ref.invalidate(browseProvider(key));
                          try {
                            await ref.read(browseProvider(key).future);
                          } catch (_) {
                            // The error state is rendered above.
                          }
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SourcePill extends StatelessWidget {
  const _SourcePill({
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
    return Material(
      color: selected
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(BestRadius.pill),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(BestRadius.pill),
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary.withValues(alpha: 0.55)
                  : theme.colorScheme.outlineVariant,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? Icons.check_circle_rounded : Icons.public_rounded,
                size: 15,
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 7),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrowseGrid extends StatelessWidget {
  const _BrowseGrid({
    required this.works,
    required this.onOpen,
    required this.onRefresh,
  });

  final List<Media> works;
  final void Function(Media media) onOpen;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final columns = (width / 170).floor().clamp(2, 6);
    final tileWidth = (width - 40 - (columns - 1) * 14) / columns;

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
        physics: const AlwaysScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisSpacing: 22,
          crossAxisSpacing: 14,
          mainAxisExtent: tileWidth * 1.5 + 82,
        ),
        itemCount: works.length,
        itemBuilder: (context, index) {
          final media = works[index];
          return MediaCard(
            title: media.displayTitle,
            subtitle: media.author?.trim().isNotEmpty == true
                ? media.author!
                : kindLabel(l10n, media.kind),
            coverUrl: media.coverUrl,
            badge: kindLabel(l10n, media.kind),
            onTap: () => onOpen(media),
          );
        },
      ),
    );
  }
}
