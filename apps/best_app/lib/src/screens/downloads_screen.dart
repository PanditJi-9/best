import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: Text(
              l10n.downloadsTitle,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -1,
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                child: EmptyState(
                  icon: Icons.download_for_offline_outlined,
                  title: l10n.downloadsEmptyTitle,
                  body: l10n.downloadsEmptyBody,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
