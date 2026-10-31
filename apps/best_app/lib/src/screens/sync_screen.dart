import 'package:best_data/best_data.dart';
import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/generated/app_localizations.dart';
import '../providers.dart';

/// One encrypted file on the person's own server.
///
/// The screen is a form, a passphrase, and two buttons, because that is the
/// whole feature: there is no account to create and no Best server to trust.
/// The passphrase is kept in memory only, so leaving the screen forgets it.
class SyncScreen extends ConsumerStatefulWidget {
  const SyncScreen({super.key});

  @override
  ConsumerState<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends ConsumerState<SyncScreen> {
  late final TextEditingController _url;
  late final TextEditingController _user;
  late final TextEditingController _password;
  final TextEditingController _passphrase = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _status;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(syncSettingsProvider);
    _url = TextEditingController(text: settings.url);
    _user = TextEditingController(text: settings.username);
    _password = TextEditingController(text: settings.password);
  }

  @override
  void dispose() {
    _url.dispose();
    _user.dispose();
    _password.dispose();
    _passphrase.dispose();
    super.dispose();
  }

  SyncSettings get _settings => SyncSettings(
        url: _url.text,
        username: _user.text,
        password: _password.text,
      );

  void _persist() => ref.read(syncSettingsProvider.notifier).save(_settings);

  Future<void> _upload() async {
    final l10n = AppLocalizations.of(context);
    await _run((controller) async {
      final result = await controller.upload(_passphrase.text);
      return l10n.syncUploaded(
        result.works,
        result.units,
        result.sources,
      );
    });
  }

  Future<void> _download() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.syncConfirmTitle),
        content: Text(l10n.syncConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.syncDownload),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run((controller) async {
      final result = await controller.download(_passphrase.text);
      return l10n.syncDownloaded(
        result.works,
        result.units,
        result.sources,
      );
    });
  }

  /// Saves the form, then runs one operation. Every failure is a sentence in
  /// the form, not a snackbar that disappears before it is read.
  Future<void> _run(
    Future<String> Function(SyncController controller) action,
  ) async {
    if (_busy) return;
    _persist();
    setState(() {
      _busy = true;
      _error = null;
      _status = null;
    });
    try {
      final message = await action(ref.read(syncControllerProvider));
      if (!mounted) return;
      setState(() => _status = message);
    } on SyncException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } on BackupException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.syncTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(BestRadius.lg),
              border: Border.all(color: theme.colorScheme.outlineVariant),
              color: theme.colorScheme.surfaceContainerLow,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.lock_outline_rounded, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n.syncBody,
                    style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: l10n.syncUrl,
              hintText: l10n.syncUrlHint,
              helperMaxLines: 2,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _user,
            autocorrect: false,
            decoration: InputDecoration(labelText: l10n.syncUser),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(labelText: l10n.syncPassword),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passphrase,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: l10n.syncPassphrase,
              helperText: l10n.syncPassphraseNote,
              helperMaxLines: 2,
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _busy ? null : _upload,
            icon: const Icon(Icons.cloud_upload_outlined, size: 19),
            label: Text(l10n.syncUpload),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _busy ? null : _download,
            icon: const Icon(Icons.cloud_download_outlined, size: 19),
            label: Text(l10n.syncDownload),
          ),
          if (_busy) ...[
            const SizedBox(height: 18),
            const Center(child: CircularProgressIndicator()),
          ],
          if (_status != null) ...[
            const SizedBox(height: 18),
            _Note(
              icon: Icons.check_circle_outline_rounded,
              color: BestColors.jade,
              text: _status!,
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 18),
            _Note(
              icon: Icons.error_outline_rounded,
              color: theme.colorScheme.error,
              text: _error!,
            ),
          ],
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(BestRadius.md),
        color: color.withValues(alpha: 0.10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}