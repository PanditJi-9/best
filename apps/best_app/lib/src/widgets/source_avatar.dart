import 'package:best_data/best_data.dart';
import 'package:best_domain/best_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../extension_host.dart';
import '../providers.dart';

/// A site's real icon when it has one, a typographic monogram otherwise.
///
/// The anime side of the catalogue shipped text-only rows for months; an avatar
/// is the fastest way to tell seven sites apart. One widget is shared by the
/// Home strip, the source picker and Manage sources so an identity never
/// changes between screens.
class SourceAvatar extends ConsumerWidget {
  const SourceAvatar({super.key, required this.source, this.size = 40});

  final SourceAdapter source;
  final double size;

  String? _iconUrl(WidgetRef ref) {
    if (source is JsonSourceAdapter) {
      return (source as JsonSourceAdapter).pack.iconUrl;
    }
    if (source is SuwayomiSource) {
      return (source as SuwayomiSource).info.iconUrl;
    }
    if (source is ExtensionSourceAdapter) {
      final package = (source as ExtensionSourceAdapter).info.packageName;
      final entries =
          ref.watch(extensionDirectoryProvider).value?.entries ?? const [];
      for (final entry in entries) {
        if (entry.packageName == package &&
            entry.iconUrl != null &&
            entry.iconUrl!.isNotEmpty) {
          return entry.iconUrl;
        }
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final url = _iconUrl(ref);
    final initial = source.name.trim().isEmpty
        ? '?'
        : String.fromCharCode(source.name.trim().runes.first).toUpperCase();
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.14),
        shape: BoxShape.circle,
      ),
      child: Text(
        initial,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w900,
          fontSize: size * 0.42,
        ),
      ),
    );
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: url == null
            ? fallback
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stack) => fallback,
              ),
      ),
    );
  }
}
