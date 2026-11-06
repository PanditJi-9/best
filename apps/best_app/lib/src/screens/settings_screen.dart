import 'dart:ui' as ui;

import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/generated/app_localizations.dart';
import '../navigation.dart';
import '../labels.dart';
import '../extension_host.dart';
import '../providers.dart';
import '../updates.dart';

/// Settings is the "your copy of Best" screen: identity and numbers first, then
/// three compact groups. Choices are segmented instead of three stacked rows so
/// the whole page fits on one phone screen without scrolling past the fold.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider);
    final works = ref.watch(libraryProvider).value?.length ?? 0;
    final downloads = ref.watch(downloadsProvider).value ?? const [];
    final offline = downloads.where((task) => task.isFinished).length;
    final sources = ref.watch(sourceRegistryProvider).all;
    final packs = ref.watch(sourcePacksProvider);
    final extensions = ref.watch(extensionCatalogProvider).value ??
        const ExtensionCatalog.empty();
    final update = ref.watch(updateProvider);
    final build = ref.watch(appBuildProvider).value;
    final installed =
        build == null ? null : '${build.version} (${build.build})';
    final updateSummary = update.isLoading
        ? l10n.checkingUpdates
        : update.value?.available == true
            ? l10n.updateAvailable(update.value!.latestVersion)
            : update.hasError
                ? l10n.updateCheckFailed
                : installed == null
                    ? l10n.checkUpdates
                    : '${l10n.versionLabel} $installed';

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
          children: [
            PageMasthead(
              index: "09",
              title: l10n.settingsTitle,
              subtitle: l10n.settingsSubtitle,
            ),
            const SizedBox(height: 20),
            _ProfileCard(
              works: works,
              offline: offline,
              sources: sources.length,
            ),
            _Group(
              title: l10n.language,
              icon: Icons.translate_rounded,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: _Segmented<String?>(
                  selected: settings.languageCode,
                  options: [
                    _SegmentOption(
                      value: null,
                      icon: Icons.brightness_auto_outlined,
                      label: l10n.languageSystem,
                    ),
                    _SegmentOption(
                      value: 'en',
                      icon: Icons.text_fields_rounded,
                      label: l10n.english,
                    ),
                    _SegmentOption(
                      value: 'ar',
                      icon: Icons.language_rounded,
                      label: l10n.arabic,
                    ),
                  ],
                  onSelect: (code) =>
                      ref.read(settingsProvider.notifier).setLanguage(code),
                ),
              ),
            ),
            _Group(
              title: l10n.appearance,
              icon: Icons.palette_outlined,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: _Segmented<ThemeMode>(
                  selected: settings.themeMode,
                  options: [
                    for (final mode in ThemeMode.values)
                      _SegmentOption(
                        value: mode,
                        icon: switch (mode) {
                          ThemeMode.system => Icons.brightness_auto_outlined,
                          ThemeMode.light => Icons.light_mode_outlined,
                          ThemeMode.dark => Icons.dark_mode_outlined,
                        },
                        label: themeLabel(l10n, mode),
                      ),
                  ],
                  onSelect: (mode) =>
                      ref.read(settingsProvider.notifier).setThemeMode(mode),
                ),
              ),
            ),
            _Group(
              title: l10n.readingGroup,
              icon: Icons.menu_book_outlined,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Segmented<ReaderMode>(
                      selected: settings.readerMode,
                      options: [
                        _SegmentOption(
                          value: ReaderMode.paged,
                          icon: Icons.auto_stories_outlined,
                          label: l10n.readerModePaged,
                        ),
                        _SegmentOption(
                          value: ReaderMode.vertical,
                          icon: Icons.view_stream_outlined,
                          label: l10n.readerModeVertical,
                        ),
                      ],
                      onSelect: (mode) => ref
                          .read(settingsProvider.notifier)
                          .setReaderMode(mode),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      l10n.readerModeBody,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.55,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    SwitchListTile.adaptive(
                      value: settings.ocrTranslationEnabled,
                      onChanged: (bool value) => ref
                          .read(settingsProvider.notifier)
                          .setOcrTranslationEnabled(value),
                      secondary: const Icon(Icons.translate_rounded, size: 19),
                      title: Text(
                        l10n.readerOcrTitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        l10n.readerOcrBody,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      contentPadding: const EdgeInsetsDirectional.only(
                        start: 2,
                        end: 2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _Group(
              title: l10n.offlineGroup,
              icon: Icons.cloud_download_outlined,
              child: Column(
                children: [
                  SwitchListTile.adaptive(
                    value: settings.wifiOnly,
                    onChanged: (value) =>
                        ref.read(settingsProvider.notifier).setWifiOnly(value),
                    secondary: const Icon(Icons.wifi_rounded, size: 19),
                    title: Text(
                      l10n.wifiOnlyTitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      l10n.wifiOnlyBody,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    contentPadding: const EdgeInsetsDirectional.only(
                      start: 14,
                      end: 8,
                    ),
                  ),
                  const Divider(height: 1, indent: 52),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.storage_rounded,
                              size: 19,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                l10n.storageCapTitle,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _Segmented<int>(
                          selected: settings.storageCapGb,
                          options: [
                            _SegmentOption(
                              value: 0,
                              icon: Icons.all_inclusive_rounded,
                              label: l10n.storageCapOff,
                            ),
                            for (final gb in const [1, 2, 5])
                              _SegmentOption(
                                value: gb,
                                icon: Icons.sd_storage_outlined,
                                label: '$gb GB',
                              ),
                          ],
                          onSelect: (value) => ref
                              .read(settingsProvider.notifier)
                              .setStorageCapGb(value),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _Group(
              title: l10n.dataGroup,
              icon: Icons.shield_moon_outlined,
              child: Column(
                children: [
                  _LinkTile(
                    icon: Icons.insights_outlined,
                    title: l10n.statsTitle,
                    subtitle: l10n.statsSubtitle,
                    onTap: () => context.push(Routes.stats),
                  ),
                  const Divider(height: 1, indent: 52),
                  _LinkTile(
                    icon: Icons.settings_backup_restore,
                    title: l10n.backupTitle,
                    subtitle: l10n.backupShort,
                    onTap: () => context.push(Routes.backup),
                  ),
                  const Divider(height: 1, indent: 52),
                  _LinkTile(
                    icon: Icons.sync_rounded,
                    title: l10n.syncTitle,
                    subtitle: l10n.syncShort,
                    onTap: () => context.push(Routes.sync),
                  ),
                ],
              ),
            ),
            _Group(
              title: 'الأمان والخصوصية',
              icon: Icons.security_rounded,
              child: Column(
                children: [
                  SwitchListTile.adaptive(
                    value: settings.biometricLockEnabled,
                    onChanged: (bool value) async {
                      if (value) {
                        final client = ref.read(biometricClientProvider);
                        final ok = await client.authenticate(
                          title: 'تفعيل القفل بالبصمة',
                          subtitle: 'أكّد هويتك لتفعيل القفل البيومتري',
                        );
                        if (!ok) return;
                      }
                      ref
                          .read(settingsProvider.notifier)
                          .setBiometricLockEnabled(value);
                    },
                    secondary: const Icon(Icons.fingerprint_rounded, size: 19),
                    title: Text(
                      'قفل التطبيق بالبصمة',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      'طلب بصمة الإصبع أو رمز قفل الجهاز عند فتح التطبيق لحماية مكتبتك وسجل قراءتك',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    contentPadding: const EdgeInsetsDirectional.only(
                      start: 14,
                      end: 8,
                    ),
                  ),
                ],
              ),
            ),
            _Group(
              title: l10n.extensionsTitle,
              icon: Icons.extension_outlined,
              child: Column(
                children: [
                  _LinkTile(
                    icon: Icons.inventory_2_outlined,
                    title: l10n.directoryTitle,
                    subtitle: l10n.extensionsHint,
                    onTap: () => context.push(Routes.sources),
                  ),
                  const Divider(height: 1, indent: 52),
                  SwitchListTile(
                    title: Text(l10n.directoryAutoUpdates),
                    subtitle: Text(l10n.directoryAutoUpdatesBody),
                    value: ref.watch(extensionAutoUpdatesProvider),
                    onChanged: ref
                        .read(extensionAutoUpdatesProvider.notifier)
                        .setEnabled,
                  ),
                  const Divider(height: 1, indent: 52),
                  _LinkTile(
                    icon: Icons.system_update_alt_rounded,
                    title: ref.watch(extensionUpdatesProvider).isLoading
                        ? l10n.directoryUpdating
                        : l10n.extensionsUpdate,
                    onTap: ref.watch(extensionUpdatesProvider).isLoading
                        ? null
                        : () => _updateExtensions(context, ref),
                  ),
                  if (extensions.problems.isNotEmpty) ...[
                    const Divider(height: 1, indent: 52),
                    _LinkTile(
                      icon: Icons.warning_amber_rounded,
                      title: l10n.extensionsFailed(extensions.problems.length),
                      subtitle: extensions.problems.first.message,
                      onTap: () => _showProblems(context, extensions),
                    ),
                  ],
                ],
              ),
            ),
            _Group(
              title: l10n.suwayomiTitle,
              icon: Icons.dns_outlined,
              child: Column(
                children: [
                  _LinkTile(
                    icon: Icons.link_rounded,
                    title: settings.suwayomiUrl ?? l10n.suwayomiNone,
                    subtitle: l10n.suwayomiShort,
                    onTap: () => _openServer(context, ref),
                  ),
                  if (settings.suwayomiUrl != null) ...[
                    const Divider(height: 1, indent: 52),
                    _LinkTile(
                      icon: Icons.link_off_rounded,
                      title: l10n.suwayomiDisconnect,
                      onTap: () {
                        ref
                            .read(settingsProvider.notifier)
                            .setSuwayomiUrl(null);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(l10n.suwayomiRemoved)),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
            _Group(
              title: l10n.sourcePacks,
              icon: Icons.extension_outlined,
              child: Column(
                children: [
                  const _PackTile(
                    icon: Icons.auto_stories_outlined,
                    label: 'MangaDex',
                    builtIn: true,
                  ),
                  const _PackTile(
                    icon: Icons.menu_book_outlined,
                    label: 'Best Guide',
                    builtIn: true,
                  ),
                  for (final pack in packs)
                    _PackTile(
                      icon: Icons.extension_outlined,
                      label: pack.name,
                      detail: pack.language,
                      onRemove: () {
                        ref.read(sourcePacksProvider.notifier).remove(pack.id);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(l10n.sourcePackRemoved)),
                        );
                      },
                    ),
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: SizedBox(
                      width: double.infinity,
                      child: TextButton.icon(
                        onPressed: () => _openAddPack(context, ref),
                        icon: const Icon(Icons.add_link_rounded, size: 19),
                        label: Text(l10n.addSourcePack),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 44),
                          backgroundColor: theme.colorScheme.primary.withValues(
                            alpha: 0.08,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(BestRadius.md),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _Group(
              title: l10n.aboutUpdatesGroup,
              icon: Icons.info_outline_rounded,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const BestMark(size: 44),
                            const SizedBox(width: BestSpace.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l10n.appName,
                                    style:
                                        theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w900,
                                      letterSpacing:
                                          BestType.tracking(context, -0.3),
                                    ),
                                  ),
                                  Text(
                                    l10n.tagline,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.verified_outlined,
                              size: 20,
                              color: theme.colorScheme.primary,
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text(
                          l10n.aboutBody,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.65,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, indent: 52),
                  _LinkTile(
                    icon: update.value?.available == true
                        ? Icons.system_update_alt_rounded
                        : Icons.info_outline_rounded,
                    title: l10n.aboutTitle,
                    subtitle: updateSummary,
                    onTap: () => context.push(Routes.about),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Center(
              child: Text(
                '${l10n.appName} · ${l10n.tagline}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.7,
                  ),
                  letterSpacing: BestType.tracking(context, 0.4),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Checks numeric upstream versions for the user's activated extensions only.
Future<void> _updateExtensions(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  await ref.read(extensionUpdatesProvider.notifier).check(force: true);
  if (!context.mounted) return;
  messenger.showSnackBar(
    SnackBar(
        content: Text(ref.read(extensionUpdatesProvider).hasError ||
                ref.read(extensionUpdatesProvider).value?.errors.isNotEmpty ==
                    true
            ? l10n.directoryUpdateFailed
            : l10n.directoryUpdateDone(
                ref.read(extensionUpdatesProvider).value?.updated ?? 0))),
  );
}

void _showProblems(BuildContext context, ExtensionCatalog catalog) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(AppLocalizations.of(context).extensionsTitle),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final problem in catalog.problems)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text('${problem.name}\n${problem.message}'),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(AppLocalizations.of(context).cancel),
        ),
      ],
    ),
  );
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.works,
    required this.offline,
    required this.sources,
  });

  final int works;
  final int offline;
  final int sources;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [
            theme.colorScheme.primary.withValues(alpha: 0.20),
            BestColors.gold.withValues(alpha: 0.08),
            theme.colorScheme.surfaceContainerLow,
          ],
        ),
        borderRadius: BorderRadius.circular(BestRadius.lg),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.30),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const BestMark(size: 54),
              const SizedBox(width: BestSpace.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.appName,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: BestType.tracking(context, -1),
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.tagline,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        letterSpacing: BestType.tracking(context, 0.3),
                      ),
                    ),
                  ],
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(BestRadius.pill),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  child: Text(
                    l10n.profileReader,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w800,
                      letterSpacing: BestType.tracking(context, 0.4),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(height: 1, color: theme.colorScheme.outlineVariant),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _ProfileStat(value: '$works', label: l10n.statsWorks),
              ),
              _Divider(),
              Expanded(
                child: _ProfileStat(
                  value: '$offline',
                  label: l10n.statsDownloads,
                ),
              ),
              _Divider(),
              Expanded(
                child: _ProfileStat(
                  value: '$sources',
                  label: l10n.sources,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 26,
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }
}

class _ProfileStat extends StatelessWidget {
  const _ProfileStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w900,
            fontFeatures: const [ui.FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 4, bottom: 9),
            child: Row(
              children: [
                Icon(icon, size: 15, color: theme.colorScheme.primary),
                const SizedBox(width: 7),
                Text(
                  title,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                    letterSpacing: BestType.tracking(context, 0.7),
                  ),
                ),
              ],
            ),
          ),
          Material(
            color: theme.colorScheme.surfaceContainerLow,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(BestRadius.lg),
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _SegmentOption<T> {
  const _SegmentOption({
    required this.value,
    required this.icon,
    required this.label,
  });

  final T value;
  final IconData icon;
  final String label;
}

class _Segmented<T> extends StatelessWidget {
  const _Segmented({
    required this.options,
    required this.selected,
    required this.onSelect,
  });

  final List<_SegmentOption<T>> options;
  final T selected;
  final ValueChanged<T> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(BestRadius.pill),
      ),
      child: Row(
        children: [
          for (final option in options)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: _Segment(
                  option: option,
                  selected: option.value == selected,
                  onTap: () => onSelect(option.value),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Segment<T> extends StatelessWidget {
  const _Segment({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final _SegmentOption<T> option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = selected
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurfaceVariant;
    return Material(
      color: selected ? theme.colorScheme.primary : Colors.transparent,
      borderRadius: BorderRadius.circular(BestRadius.pill),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(option.icon, size: 15, color: foreground),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  option.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: foreground,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _openServer(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = AppLocalizations.of(context);
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => const _ServerDialog(),
  );
  if (!(saved ?? false)) return;

  final url = ref.read(settingsProvider).suwayomiUrl;
  if (url == null) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.suwayomiRemoved)));
    return;
  }

  // A wrong address otherwise looks exactly like a working one until the reader
  // opens Browse, so ask the server once and say what happened.
  messenger.showSnackBar(
    SnackBar(
      content: Text(l10n.suwayomiChecking),
      duration: const Duration(seconds: 40),
    ),
  );

  var ready = 0;
  var answered = false;
  final client = ref.read(suwayomiClientProvider);
  if (client != null) {
    try {
      final sources = await client.sources();
      ready = sources.where((source) => !source.nsfw).length;
      answered = true;
    } catch (_) {
      // An unreachable server is a normal answer here, not a crash.
    }
  }
  if (!context.mounted) return;

  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        answered ? l10n.suwayomiConnected(ready) : l10n.suwayomiUnreachable,
      ),
    ),
  );
  // The source list may have arrived after the first build; ask for a refresh.
  ref.invalidate(suwayomiSourcesProvider);
}

Future<void> _openAddPack(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = AppLocalizations.of(context);
  final added = await showDialog<bool>(
    context: context,
    builder: (_) => const _AddPackDialog(),
  );
  if (added ?? false) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.sourcePackAdded)));
  }
}

class _PackTile extends StatelessWidget {
  const _PackTile({
    required this.icon,
    required this.label,
    this.detail,
    this.builtIn = false,
    this.onRemove,
  });

  final IconData icon;
  final String label;
  final String? detail;
  final bool builtIn;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(BestRadius.sm),
            ),
            child: Icon(
              icon,
              size: 19,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: BestSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (detail != null && detail!.trim().isNotEmpty)
                  Text(
                    detail!.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      letterSpacing: BestType.tracking(context, 0.6),
                    ),
                  ),
              ],
            ),
          ),
          if (builtIn)
            DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(BestRadius.pill),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 4,
                ),
                child: Text(
                  l10n.builtIn,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          if (onRemove != null)
            IconButton(
              onPressed: onRemove,
              icon: const Icon(Icons.delete_outline, size: 20),
              tooltip: l10n.delete,
            ),
        ],
      ),
    );
  }
}

class _AddPackDialog extends ConsumerStatefulWidget {
  const _AddPackDialog();

  @override
  ConsumerState<_AddPackDialog> createState() => _AddPackDialogState();
}

class _ServerDialog extends ConsumerStatefulWidget {
  const _ServerDialog();

  @override
  ConsumerState<_ServerDialog> createState() => _ServerDialogState();
}

class _ServerDialogState extends ConsumerState<_ServerDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: ref.read(settingsProvider).suwayomiUrl ?? '',
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final raw = _controller.text.trim();
    if (raw.isEmpty) {
      ref.read(settingsProvider.notifier).setSuwayomiUrl(null);
      Navigator.of(context).pop(true);
      return;
    }
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      setState(() => _error = AppLocalizations.of(context).suwayomiInvalid);
      return;
    }
    ref.read(settingsProvider.notifier).setSuwayomiUrl(raw);
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(l10n.suwayomiTitle),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.suwayomiBody,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              autocorrect: false,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                hintText: l10n.suwayomiHint,
                errorText: _error,
                errorMaxLines: 3,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.save)),
      ],
    );
  }
}

class _AddPackDialogState extends ConsumerState<_AddPackDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final error = ref.read(sourcePacksProvider.notifier).add(_controller.text);
    if (error == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() => _error = error);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(l10n.addSourcePack),
      content: SizedBox(
        width: 420,
        // The editor and validation error can outgrow the dialog, especially
        // with the keyboard open. Keep the actions outside the scrolling body.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.sourcePacksBody,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _controller,
                minLines: 6,
                maxLines: 12,
                autocorrect: false,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                decoration: InputDecoration(
                  hintText: l10n.sourcePackHint,
                  errorText: _error,
                  errorMaxLines: 3,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.add)),
      ],
    );
  }
}

/// A row that opens another screen. Settings groups mix controls and links, and
/// a link that looks like a control is a small betrayal, so it gets its own
/// shape: icon, two lines, a chevron.
class _LinkTile extends StatelessWidget {
  const _LinkTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String title;

  /// Omitted when the row is self-explanatory, e.g. a plain action.
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        child: Row(
          children: [
            Icon(icon, size: 19, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
