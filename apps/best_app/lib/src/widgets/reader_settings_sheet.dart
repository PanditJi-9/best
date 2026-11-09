import 'package:best_domain/best_domain.dart';
import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/generated/app_localizations.dart';
import '../providers.dart';
import 'reader_download_tile.dart';

/// Everything that changes how a chapter is read, in one place.
///
/// It is also the reader's toolkit: the page grid, bookmarks, chapter download,
/// chapter search and colour filter all start here, so the reading surface
/// itself stays free of a second toolbar.
class ReaderSettingsSheet extends ConsumerWidget {
  const ReaderSettingsSheet({
    super.key,
    required this.media,
    required this.unit,
    required this.onOpenChapters,
    required this.onOpenColorFilter,
    required this.onOpenPageGrid,
    required this.onOpenBookmarks,
  });

  final Media media;
  final MediaUnit unit;
  final VoidCallback onOpenChapters;
  final VoidCallback onOpenColorFilter;
  final VoidCallback onOpenPageGrid;
  final VoidCallback onOpenBookmarks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final settings = ref.watch(readerSettingsForProvider(media.id));
    final notifier = ref.read(readerSettingsControllerProvider(media.id));
    final remembersWork = ref.watch(
      readerProfilesProvider
          .select((profiles) => profiles.containsKey(media.id)),
    );
    final bookmarks =
        ref.watch(readerBookmarksProvider)[unit.id] ?? const <int>[];

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          BestSpace.xl,
          BestSpace.sm,
          BestSpace.xl,
          BestSpace.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.readerSettings,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontFamily: BestFontFamily.heading,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, size: 20),
                ),
              ],
            ),
            Text(
              l10n.readerSettingsBody,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            _section(theme, l10n.readerProfileTitle),
            Wrap(
              spacing: BestSpace.sm,
              runSpacing: BestSpace.sm,
              children: [
                _chip(
                  context,
                  label: l10n.readerProfileGlobal,
                  icon: Icons.public_rounded,
                  selected: !remembersWork,
                  onSelected: () => notifier.rememberForWork(false),
                ),
                _chip(
                  context,
                  label: l10n.readerProfileWork,
                  icon: Icons.auto_stories_outlined,
                  selected: remembersWork,
                  onSelected: () => notifier.rememberForWork(true),
                ),
              ],
            ),
            _hint(
              theme,
              remembersWork
                  ? l10n.readerProfileWorkBody
                  : l10n.readerProfileGlobalBody,
            ),
            if (remembersWork)
              Text(
                media.displayTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium,
              ),
            _section(theme, l10n.readerTools),
            Row(
              children: [
                Expanded(
                  child: _toolButton(
                    icon: Icons.grid_view_rounded,
                    label: l10n.readerPageGrid,
                    onPressed: () {
                      Navigator.of(context).pop();
                      onOpenPageGrid();
                    },
                  ),
                ),
                const SizedBox(width: BestSpace.sm),
                Expanded(
                  child: _toolButton(
                    icon: Icons.bookmark_border_rounded,
                    label: bookmarks.isEmpty
                        ? l10n.readerBookmarks
                        : '${l10n.readerBookmarks} · ${bookmarks.length}',
                    onPressed: () {
                      Navigator.of(context).pop();
                      onOpenBookmarks();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: BestSpace.sm),
            Row(
              children: [
                Expanded(
                  child: _toolButton(
                    icon: Icons.list_rounded,
                    label: l10n.chapters,
                    onPressed: () {
                      Navigator.of(context).pop();
                      onOpenChapters();
                    },
                  ),
                ),
                const SizedBox(width: BestSpace.sm),
                Expanded(
                  child: _toolButton(
                    icon: Icons.tune_rounded,
                    label: l10n.readerColorFilter,
                    onPressed: () {
                      Navigator.of(context).pop();
                      onOpenColorFilter();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: BestSpace.sm),
            ReaderDownloadTile(media: media, unit: unit),
            _section(theme, l10n.readerModeTitle),
            Wrap(
              spacing: BestSpace.sm,
              runSpacing: BestSpace.sm,
              children: [
                _chip(
                  context,
                  label: l10n.readerModePaged,
                  icon: Icons.auto_stories_outlined,
                  selected: settings.readerMode == ReaderMode.paged,
                  onSelected: () => notifier.setReaderMode(ReaderMode.paged),
                ),
                _chip(
                  context,
                  label: l10n.readerModeVertical,
                  icon: Icons.view_stream_outlined,
                  selected: settings.readerMode == ReaderMode.vertical,
                  onSelected: () => notifier.setReaderMode(ReaderMode.vertical),
                ),
              ],
            ),
            if (settings.readerMode == ReaderMode.paged) ...[
              _section(theme, l10n.readerDirection),
              Wrap(
                spacing: BestSpace.sm,
                runSpacing: BestSpace.sm,
                children: [
                  _chip(
                    context,
                    label: l10n.readerDirectionLtr,
                    icon: Icons.arrow_forward_rounded,
                    selected: settings.readerDirection == ReaderDirection.ltr,
                    onSelected: () =>
                        notifier.setReaderDirection(ReaderDirection.ltr),
                  ),
                  _chip(
                    context,
                    label: l10n.readerDirectionRtl,
                    icon: Icons.arrow_back_rounded,
                    selected: settings.readerDirection == ReaderDirection.rtl,
                    onSelected: () =>
                        notifier.setReaderDirection(ReaderDirection.rtl),
                  ),
                ],
              ),
              _hint(theme, l10n.readerDirectionBody),
              _section(theme, l10n.readerFit),
              Wrap(
                spacing: BestSpace.sm,
                runSpacing: BestSpace.sm,
                children: [
                  _chip(
                    context,
                    label: l10n.readerFitScreen,
                    icon: Icons.fit_screen_rounded,
                    selected: settings.readerFit == ReaderFit.screen,
                    onSelected: () => notifier.setReaderFit(ReaderFit.screen),
                  ),
                  _chip(
                    context,
                    label: l10n.readerFitWidth,
                    icon: Icons.width_full_rounded,
                    selected: settings.readerFit == ReaderFit.width,
                    onSelected: () => notifier.setReaderFit(ReaderFit.width),
                  ),
                  _chip(
                    context,
                    label: l10n.readerFitHeight,
                    icon: Icons.height_rounded,
                    selected: settings.readerFit == ReaderFit.height,
                    onSelected: () => notifier.setReaderFit(ReaderFit.height),
                  ),
                  _chip(
                    context,
                    label: l10n.readerFitOriginal,
                    icon: Icons.zoom_out_map_rounded,
                    selected: settings.readerFit == ReaderFit.original,
                    onSelected: () => notifier.setReaderFit(ReaderFit.original),
                  ),
                ],
              ),
              _hint(theme, l10n.readerFitBody),
              _section(theme, l10n.readerSpread),
              Wrap(
                spacing: BestSpace.sm,
                runSpacing: BestSpace.sm,
                children: [
                  _chip(
                    context,
                    label: l10n.readerSpreadSingle,
                    icon: Icons.crop_portrait_rounded,
                    selected:
                        settings.readerSpreadMode == ReaderSpreadMode.single,
                    onSelected: () =>
                        notifier.setReaderSpreadMode(ReaderSpreadMode.single),
                  ),
                  _chip(
                    context,
                    label: l10n.readerSpreadAdaptive,
                    icon: Icons.screen_rotation_rounded,
                    selected:
                        settings.readerSpreadMode == ReaderSpreadMode.adaptive,
                    onSelected: () =>
                        notifier.setReaderSpreadMode(ReaderSpreadMode.adaptive),
                  ),
                  _chip(
                    context,
                    label: l10n.readerSpreadDouble,
                    icon: Icons.menu_book_rounded,
                    selected: settings.readerSpreadMode ==
                        ReaderSpreadMode.doublePage,
                    onSelected: () => notifier
                        .setReaderSpreadMode(ReaderSpreadMode.doublePage),
                  ),
                ],
              ),
              _hint(theme, l10n.readerSpreadBody),
              if (settings.readerSpreadMode != ReaderSpreadMode.single)
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: settings.readerCoverAlone,
                  onChanged: notifier.setReaderCoverAlone,
                  title: Text(l10n.readerCoverAlone),
                  subtitle: Text(l10n.readerCoverAloneBody),
                ),
            ],
            _section(theme, l10n.readerBackground),
            Wrap(
              spacing: BestSpace.sm,
              runSpacing: BestSpace.sm,
              children: [
                for (final background in ReaderBackground.values)
                  _backgroundChip(
                    context,
                    label: _backgroundLabel(l10n, background),
                    color: _backgroundColor(background),
                    selected: settings.readerBackground == background,
                    onSelected: () => notifier.setReaderBackground(background),
                  ),
              ],
            ),
            if (settings.readerMode == ReaderMode.vertical) ...[
              _section(theme, l10n.readerWebtoonGap),
              Wrap(
                spacing: BestSpace.sm,
                runSpacing: BestSpace.sm,
                children: [
                  _chip(
                    context,
                    label: l10n.readerGapNone,
                    icon: Icons.compress_rounded,
                    selected: settings.readerWebtoonGap == 0,
                    onSelected: () => notifier.setReaderWebtoonGap(0),
                  ),
                  _chip(
                    context,
                    label: l10n.readerGapSmall,
                    icon: Icons.unfold_more_rounded,
                    selected: settings.readerWebtoonGap == 8,
                    onSelected: () => notifier.setReaderWebtoonGap(8),
                  ),
                  _chip(
                    context,
                    label: l10n.readerGapLarge,
                    icon: Icons.unfold_more_rounded,
                    selected: settings.readerWebtoonGap == 16,
                    onSelected: () => notifier.setReaderWebtoonGap(16),
                  ),
                ],
              ),
            ],
            const SizedBox(height: BestSpace.md),
            if (settings.readerMode == ReaderMode.paged)
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: settings.readerTapZones,
                onChanged: notifier.setReaderTapZones,
                secondary: const Icon(Icons.touch_app_outlined, size: 20),
                title: Text(
                  l10n.readerTapZones,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  l10n.readerTapZonesBody,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
              ),
            if (settings.readerMode == ReaderMode.paged &&
                settings.readerTapZones) ...[
              _section(theme, l10n.readerTapZoneSize),
              Wrap(
                spacing: BestSpace.sm,
                runSpacing: BestSpace.sm,
                children: [
                  for (final size in ReaderTapZoneSize.values)
                    _chip(
                      context,
                      label: switch (size) {
                        ReaderTapZoneSize.small => l10n.readerTapZoneSmall,
                        ReaderTapZoneSize.medium => l10n.readerTapZoneMedium,
                        ReaderTapZoneSize.large => l10n.readerTapZoneLarge,
                      },
                      icon: switch (size) {
                        ReaderTapZoneSize.small => Icons.compress_rounded,
                        ReaderTapZoneSize.medium => Icons.touch_app_outlined,
                        ReaderTapZoneSize.large => Icons.open_in_full_rounded,
                      },
                      selected: settings.readerTapZoneSize == size,
                      onSelected: () =>
                          notifier.setReaderTapZoneSize(size),
                    ),
                ],
              ),
              _hint(theme, l10n.readerTapZoneSizeBody),
            ],
            _section(theme, l10n.readerDeviceSettings),
            _hint(theme, l10n.readerDeviceSettingsBody),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: settings.readerKeepAwake,
              onChanged: notifier.setReaderKeepAwake,
              secondary: const Icon(Icons.light_mode_outlined, size: 20),
              title: Text(
                l10n.readerKeepAwake,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Text(
                l10n.readerKeepAwakeBody,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: settings.readerPreload,
              onChanged: notifier.setReaderPreload,
              secondary: const Icon(Icons.bolt_outlined, size: 20),
              title: Text(
                l10n.readerPreload,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Text(
                l10n.readerPreloadBody,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: settings.ocrTranslationEnabled,
              onChanged: notifier.setOcrTranslationEnabled,
              secondary: const Icon(Icons.translate_rounded, size: 20),
              title: Text(l10n.readerOcrTitle),
              subtitle: Text(l10n.readerOcrBody),
            ),
            const SizedBox(height: BestSpace.sm),
            DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(BestRadius.md),
              ),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(
                  horizontal: BestSpace.md,
                ),
                childrenPadding: const EdgeInsets.fromLTRB(
                  BestSpace.md,
                  0,
                  BestSpace.md,
                  BestSpace.md,
                ),
                leading: const Icon(Icons.tips_and_updates_outlined, size: 20),
                title: Text(
                  l10n.readerTips,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                children: [
                  _tip(
                    theme,
                    Icons.touch_app_outlined,
                    l10n.readerTipTap,
                  ),
                  _tip(
                    theme,
                    Icons.view_stream_outlined,
                    l10n.readerTipWebtoon,
                  ),
                  _tip(
                    theme,
                    Icons.zoom_out_map_rounded,
                    l10n.readerTipOriginal,
                  ),
                  _tip(
                    theme,
                    Icons.grid_view_rounded,
                    l10n.readerTipGrid,
                  ),
                  _tip(
                    theme,
                    Icons.keyboard_outlined,
                    l10n.readerTipKeyboard,
                  ),
                  _tip(
                    theme,
                    Icons.download_for_offline_outlined,
                    l10n.readerTipDownload,
                  ),
                  _tip(
                    theme,
                    Icons.skip_next_rounded,
                    l10n.readerTipChapterEdges,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 60),
        padding: const EdgeInsets.symmetric(
          horizontal: BestSpace.sm,
          vertical: 12,
        ),
      ),
      icon: Icon(icon, size: 18),
      label: Text(
        label,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _tip(ThemeData theme, IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: BestSpace.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: BestSpace.sm),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(ThemeData theme, String label) {
    return Padding(
      padding: const EdgeInsets.only(top: BestSpace.lg, bottom: BestSpace.sm),
      child: Text(
        label,
        style: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onSurface,
        ),
      ),
    );
  }

  Widget _hint(ThemeData theme, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: BestSpace.sm),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          height: 1.5,
        ),
      ),
    );
  }

  Widget _chip(
    BuildContext context, {
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onSelected,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return ChoiceChip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      selectedColor: scheme.primary.withValues(alpha: 0.16),
      side: BorderSide(
        color: selected
            ? scheme.primary.withValues(alpha: BestAlpha.borderStrong)
            : scheme.outlineVariant,
      ),
      onSelected: (_) => onSelected(),
    );
  }

  Widget _backgroundChip(
    BuildContext context, {
    required String label,
    required Color color,
    required bool selected,
    required VoidCallback onSelected,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return ChoiceChip(
      avatar: Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: scheme.outlineVariant),
        ),
      ),
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      selectedColor: scheme.primary.withValues(alpha: 0.16),
      side: BorderSide(
        color: selected
            ? scheme.primary.withValues(alpha: BestAlpha.borderStrong)
            : scheme.outlineVariant,
      ),
      onSelected: (_) => onSelected(),
    );
  }

  static String _backgroundLabel(
    AppLocalizations l10n,
    ReaderBackground background,
  ) {
    return switch (background) {
      ReaderBackground.black => l10n.readerBackgroundBlack,
      ReaderBackground.charcoal => l10n.readerBackgroundCharcoal,
      ReaderBackground.sepia => l10n.readerBackgroundSepia,
      ReaderBackground.white => l10n.readerBackgroundWhite,
    };
  }

  static Color _backgroundColor(ReaderBackground background) {
    return switch (background) {
      ReaderBackground.black => Colors.black,
      ReaderBackground.charcoal => const Color(0xFF1C1C1E),
      ReaderBackground.sepia => const Color(0xFFF2E6D0),
      ReaderBackground.white => Colors.white,
    };
  }
}
