import 'package:best_domain/best_domain.dart';
import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../actions.dart';
import '../l10n/generated/app_localizations.dart';
import '../labels.dart';
import '../navigation.dart';
import '../news.dart';
import '../providers.dart';

/// The newsroom.
///
/// Three honest feeds: release notes written by hand, chapters the sources
/// actually returned as latest, and the state of the extension market. No
/// editorial articles are invented to fill the page.
class NewsScreen extends ConsumerWidget {
  const NewsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context);
    final feed = ref.watch(discoverProvider);
    final latest = feed.value?.latest ?? const <Media>[];
    final publishers = ref.watch(publishersProvider);
    final market = publishers.value;

    return Scaffold(
      appBar: AppBar(),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(discoverProvider);
          ref.invalidate(publishersProvider);
          try {
            await ref.read(discoverProvider.future);
          } catch (_) {
            // Rendered inline.
          }
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            PageMasthead(
              title: l10n.newsTitle,
              subtitle: l10n.newsSubtitle,
            ),
            const SizedBox(height: BestSpace.lg),
            SectionHeader(
              title: l10n.newsReleases,
            ),
            const SizedBox(height: BestSpace.md),
            for (final note in kReleaseNotes) ...[
              _ReleaseCard(note: note, locale: locale),
              const SizedBox(height: BestSpace.md),
            ],
            const SizedBox(height: BestSpace.md),
            SectionHeader(
              title: l10n.newsChapters,
            ),
            const SizedBox(height: BestSpace.md),
            if (latest.isEmpty)
              Text(
                feed.isLoading ? '…' : l10n.newsChaptersEmpty,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              for (final media in latest.take(8)) ...[
                _ChapterRow(
                  media: media,
                  source: _sourceName(ref, media),
                  onTap: () => openSeries(context, ref, media),
                ),
                const SizedBox(height: BestSpace.sm),
              ],
            const SizedBox(height: BestSpace.lg),
            SectionHeader(
              title: l10n.newsMarket,
            ),
            const SizedBox(height: BestSpace.md),
            _MarketCard(
              market: market,
              onOpen: () => context.push(Routes.sources),
            ),
          ],
        ),
      ),
    );
  }
}

String _sourceName(WidgetRef ref, Media media) {
  final source = ref.watch(sourceRegistryProvider).byId(media.ref.sourceId);
  return source?.name ?? media.ref.sourceId;
}

class _ReleaseCard extends StatelessWidget {
  const _ReleaseCard({required this.note, required this.locale});

  final ReleaseNote note;
  final Locale locale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(BestSpace.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(BestRadius.md),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'v${note.version}',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontFamily: BestFonts.display,
                  fontWeight: FontWeight.w800,
                  color: BestColors.brass,
                ),
              ),
              const SizedBox(width: BestSpace.sm),
              Text(
                note.date,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: BestSpace.md),
          for (var index = 0; index < note.lines.length; index++) ...[
            if (index > 0) const SizedBox(height: BestSpace.md),
            Text(
              note.lines[index].title.of(locale),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              note.lines[index].body.of(locale),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ChapterRow extends StatelessWidget {
  const _ChapterRow({
    required this.media,
    required this.source,
    required this.onTap,
  });

  final Media media;
  final String source;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(BestRadius.sm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(BestSpace.sm),
          child: Row(
            children: [
              SizedBox(
                width: 40,
                height: 56,
                child: BestCover(
                  title: media.displayTitle,
                  url: media.coverUrl,
                  radius: BestRadius.sm,
                ),
              ),
              const SizedBox(width: BestSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      media.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontFamily: BestFonts.display,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$source · ${kindLabel(l10n, media.kind)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
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

class _MarketCard extends StatelessWidget {
  const _MarketCard({required this.market, required this.onOpen});

  final Publishers? market;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final publishers = market?.items.length ?? 0;
    return Container(
      padding: const EdgeInsets.all(BestSpace.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(BestRadius.md),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.storefront_outlined,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.newsMarket,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontFamily: BestFonts.display,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (market?.cached == true)
                Text(
                  l10n.newsMarketCached,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(height: BestSpace.md),
          Text(
            l10n.newsMarketBody(
              market?.extensions ?? 0,
              market?.sources ?? 0,
              publishers,
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: BestSpace.md),
          OutlinedButton.icon(
            onPressed: onOpen,
            icon: const Icon(Icons.extension_outlined, size: 18),
            label: Text(l10n.newsOpenDirectory),
          ),
        ],
      ),
    );
  }
}
