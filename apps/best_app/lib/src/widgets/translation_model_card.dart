import 'dart:async';

import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/generated/app_localizations.dart';
import '../providers.dart';

/// Makes the offline promise visible instead of hiding a one-time model
/// download behind the first translated page. Online translation keeps working
/// while this card downloads both ML Kit language models.
class TranslationModelCard extends ConsumerStatefulWidget {
  const TranslationModelCard({super.key, this.compact = false});

  final bool compact;

  @override
  ConsumerState<TranslationModelCard> createState() =>
      _TranslationModelCardState();
}

class _TranslationModelCardState extends ConsumerState<TranslationModelCard> {
  bool? _ready;
  bool _busy = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final ready = await ref
        .read(translationModelClientProvider)
        .isModelDownloaded();
    if (!mounted) return;
    setState(() => _ready = ready);
  }

  Future<void> _download() async {
    setState(() {
      _busy = true;
      _failed = false;
    });
    final ready = await ref
        .read(translationModelClientProvider)
        .downloadModel(force: true);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _ready = ready;
      _failed = !ready;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final ready = _ready;
    final title = ready == true
        ? l10n.translationOfflineReady
        : l10n.translationOfflineTitle;
    final body = ready == true
        ? l10n.translationOfflineReadyBody
        : l10n.translationOfflineBody;

    return Container(
      margin: EdgeInsets.only(top: widget.compact ? 2 : 8),
      padding: EdgeInsets.all(widget.compact ? 10 : 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(BestRadius.md),
        border: Border.all(
          color: ready == true
              ? BestColors.jade.withValues(alpha: 0.45)
              : theme.colorScheme.outlineVariant,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ready == true
                ? Icons.offline_bolt_rounded
                : Icons.cloud_download_outlined,
            size: widget.compact ? 18 : 22,
            color: ready == true ? BestColors.jade : BestColors.emberSoft,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: ready == true ? BestColors.jade : null,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                if (ready == false) ...[
                  const SizedBox(height: 4),
                  Text(
                    l10n.translationOfflineSize,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 10.5,
                    ),
                  ),
                ],
                if (_failed) ...[
                  const SizedBox(height: 4),
                  Text(
                    l10n.translationOfflineFailed,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                      height: 1.35,
                    ),
                  ),
                ],
                if (_busy) ...[
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: const LinearProgressIndicator(minHeight: 2),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    l10n.translationOfflineDownloading,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (ready == null)
            const Padding(
              padding: EdgeInsetsDirectional.only(start: 8, top: 2),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (ready == false)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 8),
              child: OutlinedButton(
                onPressed: _busy ? null : _download,
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  textStyle: const TextStyle(fontSize: 11),
                ),
                child: Text(l10n.translationOfflineDownload),
              ),
            ),
        ],
      ),
    );
  }
}
