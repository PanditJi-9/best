import 'dart:async';

import 'package:best_domain/best_domain.dart';
import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../actions.dart';
import '../labels.dart';
import '../l10n/generated/app_localizations.dart';
import '../meta/meta_labels.dart';
import '../meta/meta_models.dart';
import '../meta/meta_providers.dart';
import '../meta/meta_widgets.dart';
import '../navigation.dart';
import '../providers.dart';

/// One field for everything Best knows about a title.
///
/// It reads your own shelf first, because the work you already follow is the
/// likeliest answer, then the three catalogues that publish titles, then hands
/// the same words to your installed sources. The query is debounced, because
/// each provider is somebody else's server. Results keep their provider's name
/// and colour; an AniList entry and a MAL entry for the same anime are never
/// stacked twice.
class MetaSearchScreen extends ConsumerStatefulWidget {
  const MetaSearchScreen({super.key, this.initialQuery});

  /// Lets a genre or a shared link land directly on its results instead of an
  /// empty field the person has to retype.
  final String? initialQuery;

  @override
  ConsumerState<MetaSearchScreen> createState() => _MetaSearchScreenState();
}

class _MetaSearchScreenState extends ConsumerState<MetaSearchScreen> {
  static const List<String> _examples = [
    'Frieren',
    'Solo Leveling',
    'One Piece',
    'Vagabond',
  ];

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  Timer? _debounce;
  String _query = '';

  @override
  void initState() {
    super.initState();
    final initial = widget.initialQuery?.trim() ?? '';
    if (initial.isNotEmpty) {
      _query = initial;
      _controller.text = initial;
      _controller.selection = TextSelection.collapsed(offset: initial.length);
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 420), () {
      if (!mounted) return;
      final next = value.trim();
      if (next == _query) return;
      setState(() => _query = next);
    });
  }

  void _submit(String value) {
    _debounce?.cancel();
    final next = value.trim();
    if (next == _query) return;
    setState(() => _query = next);
  }

  void _useExample(String value) {
    _controller.text = value;
    _controller.selection = TextSelection.collapsed(offset: value.length);
    _submit(value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final ready = _query.length >= 2;
    final async = ready ? ref.watch(metaSearchProvider(_query)) : null;
    // The shelf answers from the local database, so it is watched even while
    // the catalogues are still on the wire.
    final shelf = ready ? ref.watch(librarySearchProvider(_query)) : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.searchEverything),
        titleSpacing: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              textInputAction: TextInputAction.search,
              onChanged: _onChanged,
              onSubmitted: _submit,
              style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13.5),
              decoration: InputDecoration(
                hintText: l10n.metaSearchHint,
                hintStyle: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: MaterialLocalizations.of(
                          context,
                        ).deleteButtonTooltip,
                        onPressed: () {
                          _controller.clear();
                          _debounce?.cancel();
                          setState(() => _query = '');
                          _focus.requestFocus();
                        },
                        icon: const Icon(Icons.close_rounded, size: 18),
                      ),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerLow,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(BestRadius.md),
                  borderSide: BorderSide(
                    color: theme.colorScheme.outlineVariant,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(BestRadius.md),
                  borderSide: BorderSide(
                    color: theme.colorScheme.outlineVariant,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(BestRadius.md),
                  borderSide: BorderSide(
                    color: theme.colorScheme.primary,
                    width: 1.4,
                  ),
                ),
              ),
            ),
          ),
          if (ready)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: () {
                    _focus.unfocus();
                    context.push(Routes.browseQuery(_query));
                  },
                  icon: const Icon(Icons.travel_explore_rounded, size: 20),
                  label: Text(
                    l10n.searchInSources(_query),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          Expanded(
            child: !ready
                ? _SearchStart(
                    l10n: l10n,
                    examples: _examples,
                    onExample: _useExample,
                  )
                : _SearchResults(
                    catalogues: async!,
                    shelf: shelf!,
                    l10n: l10n,
                    onRetry: () =>
                        ref.read(metaRefreshProvider.notifier).bump(),
                    onRetryShelf: () =>
                        ref.invalidate(librarySearchProvider(_query)),
                    onOpen: (work) =>
                        context.push(Routes.metaWork(work.source, work.id)),
                    onOpenShelf: (entry) =>
                        openSeries(context, ref, entry.media),
                  ),
          ),
        ],
      ),
    );
  }
}

class _SearchStart extends StatelessWidget {
  const _SearchStart({
    required this.l10n,
    required this.examples,
    required this.onExample,
  });

  final AppLocalizations l10n;
  final List<String> examples;
  final ValueChanged<String> onExample;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
      children: [
        Icon(
          Icons.travel_explore_rounded,
          size: 52,
          color: theme.colorScheme.primary.withValues(alpha: 0.55),
        ),
        const SizedBox(height: 16),
        Text(
          l10n.searchEverythingBody,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          l10n.metaSearchStartBody,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 11.5,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 22),
        Text(
          l10n.metaTryExamples,
          textAlign: TextAlign.center,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 10.5,
            letterSpacing: BestType.tracking(context, 0.4),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 9),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final example in examples)
              ActionChip(
                onPressed: () => onExample(example),
                label: Text(example, style: const TextStyle(fontSize: 11)),
                visualDensity: VisualDensity.compact,
                side: BorderSide(color: theme.colorScheme.outlineVariant),
                backgroundColor: theme.colorScheme.surfaceContainerLow,
              ),
          ],
        ),
        const SizedBox(height: 26),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final source in const [
              MetaSource.anilist,
              MetaSource.myAnimeList,
              MetaSource.hwa,
            ]) ...[
              MetaSourceChip(source: source, compact: true),
              const SizedBox(width: 5),
            ],
          ],
        ),
      ],
    );
  }
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({
    required this.catalogues,
    required this.shelf,
    required this.l10n,
    required this.onRetry,
    required this.onRetryShelf,
    required this.onOpen,
    required this.onOpenShelf,
  });

  final AsyncValue<MetaSearchResults> catalogues;
  final AsyncValue<List<LibraryEntry>> shelf;
  final AppLocalizations l10n;
  final VoidCallback onRetry;
  final VoidCallback onRetryShelf;
  final ValueChanged<MetaWork> onOpen;
  final ValueChanged<LibraryEntry> onOpenShelf;

  @override
  Widget build(BuildContext context) {
    final results = catalogues.value;
    final entries = shelf.value ?? const <LibraryEntry>[];
    return RefreshIndicator(
      onRefresh: () async {
        onRetry();
        onRetryShelf();
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 28),
        children: [
          if (shelf.isLoading) const LinearProgressIndicator(),
          if (shelf.hasError)
            _SearchError(
              title: l10n.searchOnShelf,
              l10n: l10n,
              message: shelf.error.toString(),
              onRetry: onRetryShelf,
            ),
          if (entries.isNotEmpty) ...[
            _ResultSectionHeader(
              title: l10n.searchOnShelf,
              count: entries.length,
            ),
            for (final entry in entries)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: WorkCard(
                  density: WorkCardDensity.row,
                  title: entry.media.displayTitle,
                  coverUrl: entry.media.coverUrl,
                  subtitle:
                      '${entry.completedUnits}/${entry.totalUnits} · '
                      '${kindLabel(l10n, entry.media.kind)}',
                  onTap: () => onOpenShelf(entry),
                ),
              ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 8),
            child: Text(
              l10n.searchInCatalogues,
              style: BestType.sectionTitle(context),
            ),
          ),
          if (catalogues.isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              child: LinearProgressIndicator(),
            ),
          if (catalogues.hasError)
            _SearchError(
              l10n: l10n,
              message: catalogues.error.toString(),
              onRetry: onRetry,
            ),
          if (results != null) ...[
            MetaSourceNotice(
              failures: results.failures,
              retryLabel: l10n.retry,
              onRetry: onRetry,
            ),
            if (results.anime.isNotEmpty) ...[
              _ResultSectionHeader(
                source: MetaSource.anilist,
                title: l10n.metaAnimeResults,
                count: results.anime.length,
              ),
              for (final work in results.anime)
                _ResultRow(work: work, onTap: () => onOpen(work)),
            ],
            if (results.manhwa.isNotEmpty) ...[
              _ResultSectionHeader(
                source: MetaSource.hwa,
                title: l10n.metaManhwaResults,
                count: results.manhwa.length,
              ),
              for (final work in results.manhwa)
                _ResultRow(work: work, onTap: () => onOpen(work)),
            ],
            if (results.isEmpty && !catalogues.isLoading)
              Padding(
                padding: const EdgeInsets.all(18),
                child: EmptyState(
                  icon: Icons.search_off_rounded,
                  title: l10n.metaNoResults,
                  body: l10n.metaNoResultsBody,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _ResultSectionHeader extends StatelessWidget {
  const _ResultSectionHeader({
    this.source,
    required this.title,
    required this.count,
  });

  final MetaSource? source;
  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
      child: Row(
        children: [
          if (source != null) ...[
            MetaSourceDot(source: source!),
            const SizedBox(width: 7),
          ],
          Flexible(
            child: Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 10.5,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.work, required this.onTap});

  final MetaWork work;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final facts = <String>[];
    final format = metaFormatLabel(work.format);
    if (format.isNotEmpty) facts.add(format);
    if (work.episodes != null) {
      facts.add('${work.episodes} ${l10n.metaEpShort}');
    }
    if (work.chapters != null) {
      facts.add('${work.chapters} ${l10n.metaChShort}');
    }
    if (work.year != null) facts.add('${work.year}');
    if (facts.isEmpty && work.genres.isNotEmpty) {
      facts.add(work.genres.take(2).join(' · '));
    }

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 52,
              height: 78,
              child: BestCover(
                title: work.displayTitle,
                url: work.coverUrl,
                radius: BestRadius.sm,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    work.displayTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                  if (work.nativeTitle != null &&
                      work.nativeTitle!.trim().isNotEmpty &&
                      work.nativeTitle != work.displayTitle) ...[
                    const SizedBox(height: 1),
                    Text(
                      work.nativeTitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 10,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    facts.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 7,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      MetaSourceChip(source: work.source, compact: true),
                      MetaScore(score: work.score, source: work.scoreSource),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Padding(
              padding: const EdgeInsets.only(top: 26),
              child: Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchError extends StatelessWidget {
  const _SearchError({
    this.title,
    required this.l10n,
    required this.message,
    required this.onRetry,
  });

  final AppLocalizations l10n;
  final String? title;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: EmptyState(
          icon: Icons.cloud_off_rounded,
          title: title ?? l10n.metaError,
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
