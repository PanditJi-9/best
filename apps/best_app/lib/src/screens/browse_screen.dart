import 'dart:async';

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
import 'source_settings_sheet.dart';

class BrowseScreen extends ConsumerStatefulWidget {
  const BrowseScreen({
    super.key,
    this.initialSourceId,
    this.initialQuery = '',
  });

  final String? initialSourceId;
  final String initialQuery;

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
  void initState() {
    super.initState();
    _sourceId = widget.initialSourceId;
    if (widget.initialQuery.isNotEmpty) {
      _search.text = widget.initialQuery;
      _query = widget.initialQuery;
      _searchTerm = widget.initialQuery.trim();
    }
  }

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
          title: l10n.nothingHere,
          body: l10n.menuDirectoryBody,
          action: FilledButton.icon(
            onPressed: () => context.push(Routes.sources),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: Text(l10n.directoryTitle),
          ),
        ),
      );
    }

    // `null` means "all sources": the default view is the merged catalogue of
    // everything installed, and typing searches all of it at once.
    final source = _sourceId == null ? null : registry.byId(_sourceId!);
    final AsyncValue<List<Media>> results;
    if (source == null) {
      results = _searchTerm.isEmpty
          ? ref.watch(discoverProvider).whenData((feed) => feed.works)
          : ref.watch(searchAllProvider(_searchTerm));
    } else {
      results = ref.watch(
        browseProvider((sourceId: source.id, query: _searchTerm)),
      );
    }

    Future<void> reload() async {
      if (source == null) {
        if (_searchTerm.isEmpty) {
          ref.invalidate(discoverProvider);
          try {
            await ref.read(discoverProvider.future);
          } catch (_) {
            // The error state is rendered inline.
          }
        } else {
          ref.invalidate(searchAllProvider(_searchTerm));
          try {
            await ref.read(searchAllProvider(_searchTerm).future);
          } catch (_) {
            // The error state is rendered inline.
          }
        }
        return;
      }
      final key = (sourceId: source.id, query: _searchTerm);
      ref.invalidate(browseProvider(key));
      try {
        await ref.read(browseProvider(key).future);
      } catch (_) {
        // The error state is rendered inline.
      }
    }

    final extension = source is ExtensionSourceAdapter ? source : null;

    Future<void> openSettings() async {
      if (extension == null) return;
      final changed = await showSourceSettings(
        context,
        host: extension.host,
        info: extension.info,
      );
      if (changed) await reload();
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              child: PageMasthead(
                title: l10n.browseTitle,
                subtitle: l10n.browseSubtitle(sources.length),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const BackButton(),
                    if (extension != null)
                      Semantics(
                        label: l10n.sourceSettings,
                        button: true,
                        child: IconButton(
                            tooltip: l10n.sourceSettings,
                            onPressed: openSettings,
                            icon: const Icon(Icons.tune_rounded)),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: sources.length + 2,
                separatorBuilder: (context, index) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _SourcePill(
                      label: l10n.allSources,
                      selected: source == null,
                      onTap: () => setState(() => _sourceId = null),
                    );
                  }
                  if (index == sources.length + 1) {
                    return ActionChip(
                      avatar: const Icon(Icons.add_rounded, size: 17),
                      label: Text(l10n.directoryTitle),
                      onPressed: () => context.push(Routes.sources),
                    );
                  }
                  final candidate = sources[index - 1];
                  return _SourcePill(
                    label: candidate.name,
                    selected: candidate.id == source?.id,
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
                  hintText: source == null
                      ? l10n.searchAll
                      : l10n.searchSource(source.name),
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
                loading: () => const CustomScrollView(
                  physics: NeverScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(child: SizedBox(height: 10)),
                    SliverPosterGridSkeleton(),
                  ],
                ),
                error: (error, stack) => EmptyState(
                  icon: Icons.cloud_off_outlined,
                  title: l10n.sourceError,
                  body: extension == null
                      ? '$error'
                      : '${l10n.sourceSettingsHint}\n\n$error',
                  action: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FilledButton.icon(
                        onPressed: reload,
                        icon: const Icon(Icons.refresh, size: 18),
                        label: Text(l10n.retry),
                      ),
                      if (extension != null) ...[
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: openSettings,
                          icon: const Icon(Icons.tune_rounded, size: 18),
                          label: Text(l10n.sourceSettings),
                        ),
                      ],
                    ],
                  ),
                ),
                data: (works) {
                  if (works.isEmpty) {
                    return EmptyState(
                      icon: Icons.travel_explore_outlined,
                      eyebrow: (source?.name ?? l10n.sources).toUpperCase(),
                      title: _searchTerm.isNotEmpty
                          ? l10n.searchNoMatch(_searchTerm)
                          : l10n.nothingHere,
                      body: _searchTerm.isNotEmpty
                          ? l10n.searchNoMatchBody
                          : l10n.nothingHereBody,
                      action: _searchTerm.isEmpty
                          ? null
                          : OutlinedButton.icon(
                              onPressed: _clear,
                              icon: const Icon(Icons.close_rounded, size: 18),
                              label: Text(l10n.cancel),
                            ),
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
                            letterSpacing: BestType.tracking(context, 0.3),
                          ),
                        ),
                      ),
                      Expanded(
                        child: _BrowseGrid(
                          works: works,
                          onOpen: (media) => openSeries(context, ref, media),
                          onRefresh: reload,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
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
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Tooltip(
        message: label,
        child: Material(
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
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.public_rounded,
                    size: 15,
                    color: selected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 7),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 164),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight:
                            selected ? FontWeight.w800 : FontWeight.w600,
                        color: selected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = (width / 170).floor().clamp(2, 6).toInt();
        final tileWidth = (width - 40 - (columns - 1) * 12) / columns;

        return RefreshIndicator(
          onRefresh: onRefresh,
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
            physics: const AlwaysScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              mainAxisExtent: tileWidth * 1.5 + 66,
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
      },
    );
  }
}
