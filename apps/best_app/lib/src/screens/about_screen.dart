import 'dart:async';

import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/generated/app_localizations.dart';
import '../labels.dart';
import '../updates.dart';

/// Version, release notes and the project links.
///
/// Best ships as an APK outside any store, so this screen is the only place a
/// reader can see which build they run and whether a newer signed build
/// exists. The check is a plain read of GitHub's public release feed.
class AboutScreen extends ConsumerStatefulWidget {
  const AboutScreen({super.key});

  @override
  ConsumerState<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends ConsumerState<AboutScreen> {
  @override
  void initState() {
    super.initState();
    // Opening the screen is a request to know. The controller still throttles
    // itself, so this does not spend the GitHub budget on every visit.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // `isLoading` is true while the notifier's own build future is still
      // resolving, which is exactly when this callback runs. The controller
      // de-duplicates concurrent checks, so asking here is safe and is what
      // makes opening About actually fetch the feed.
      final status = ref.read(updateProvider);
      if (status.value == null && !status.hasError) {
        unawaited(ref.read(updateProvider.notifier).check());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final build = ref.watch(appBuildProvider).value;
    final version = build == null ? '—' : '${build.version} (${build.build})';

    return Scaffold(
      appBar: AppBar(title: Text(l10n.aboutTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          const SizedBox(height: 8),
          Center(
            child: Column(
              children: [
                const BestMark(size: 76),
                const SizedBox(height: 14),
                Text(
                  l10n.appName,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: BestType.tracking(context, -1),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.tagline,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    letterSpacing: BestType.tracking(context, 0.4),
                  ),
                ),
                const SizedBox(height: 10),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(BestRadius.pill),
                    border: Border.all(
                      color: theme.colorScheme.primary.withValues(alpha: 0.28),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    child: Text(
                      l10n.aboutVersionLine(
                        build?.version ?? '—',
                        build?.build ?? '—',
                      ),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          const _UpdateCard(),
          const SizedBox(height: 20),
          Text(
            l10n.aboutUpdatesBody,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.65,
            ),
          ),
          const SizedBox(height: 22),
          _LinksCard(version: version),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.aboutLocalNote,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _UpdateCard extends ConsumerWidget {
  const _UpdateCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final update = ref.watch(updateProvider);
    final status = update.value;
    final release = status?.release;
    final available = status?.available == true;
    final busy = update.isLoading;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(BestRadius.lg),
        border: Border.all(
          color: available
              ? theme.colorScheme.primary.withValues(alpha: 0.55)
              : theme.colorScheme.outlineVariant,
        ),
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [
            (available ? theme.colorScheme.primary : BestColors.brass)
                .withValues(alpha: available ? 0.16 : 0.07),
            theme.colorScheme.surfaceContainerLow,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                available
                    ? Icons.system_update_alt_rounded
                    : update.hasError
                        ? Icons.cloud_off_outlined
                        : Icons.verified_outlined,
                size: 22,
                color: available
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  available
                      ? l10n.updateAvailable(release!.version)
                      : update.hasError
                          ? l10n.updateCheckFailed
                          : status == null
                              ? l10n.checkUpdates
                              : l10n.updateUpToDate,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (busy)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          if (update.hasError) ...[
            const SizedBox(height: 8),
            Text(
              _failureText(l10n, update.error!),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ],
          if (available && release!.notes.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(height: 1, color: theme.colorScheme.outlineVariant),
            const SizedBox(height: 12),
            Text(
              l10n.releaseNotes,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
                letterSpacing: BestType.tracking(context, 0.6),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              release.notes,
              style: theme.textTheme.bodySmall?.copyWith(height: 1.6),
            ),
            if (release.publishedAt != null) ...[
              const SizedBox(height: 8),
              Text(
                l10n.publishedOn(
                  shortDate(release.publishedAt!.millisecondsSinceEpoch),
                ),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
          if (available && release!.notes.isEmpty) ...[
            const SizedBox(height: 6),
            Text(
              l10n.releaseNotesEmpty,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 16),
          // Wrap, not Row: Arabic button labels are long and the About card
          // also has to fit a 320 dp phone without clipping a verb.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (available)
                FilledButton.icon(
                  onPressed: () => _open(
                    context,
                    release.apkUrl ?? release.pageUrl,
                  ),
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: Text(
                    release!.apkUrl == null
                        ? l10n.openReleasePage
                        : l10n.downloadUpdate,
                  ),
                ),
              TextButton.icon(
                onPressed: busy
                    ? null
                    : () => ref.read(updateProvider.notifier).check(
                          force: true,
                        ),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(
                  busy ? l10n.checkingUpdates : l10n.checkUpdates,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _failureText(AppLocalizations l10n, Object error) {
  final failure = error is UpdateException ? error.failure : null;
  return switch (failure) {
    UpdateFailure.network => l10n.updateNetwork,
    UpdateFailure.rateLimited => l10n.updateRateLimited,
    UpdateFailure.notFound => l10n.updateNotFound,
    UpdateFailure.malformed => l10n.updateMalformed,
    UpdateFailure.server => l10n.updateServer,
    null => l10n.updateCheckFailed,
  };
}

class _LinksCard extends StatelessWidget {
  const _LinksCard({required this.version});

  final String version;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BestRadius.lg),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          _LinkRow(
            icon: Icons.code_rounded,
            title: l10n.viewSource,
            onTap: () => _open(context, bestRepositoryUrl),
          ),
          const Divider(height: 1, indent: 52),
          _LinkRow(
            icon: Icons.new_releases_outlined,
            title: l10n.openReleasePage,
            onTap: () => _open(context, bestReleasesUrl),
          ),
          const Divider(height: 1, indent: 52),
          _LinkRow(
            icon: Icons.description_outlined,
            title: l10n.aboutLicenses,
            onTap: () => showLicensePage(
              context: context,
              applicationName: l10n.appName,
              applicationVersion: version,
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 15, 10, 15),
        child: Row(
          children: [
            Icon(icon, size: 19, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Icon(
              Icons.open_in_new_rounded,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _open(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = AppLocalizations.of(context);
  var opened = false;
  try {
    opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    opened = false;
  }
  if (!opened) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.linkFailed)));
  }
}
