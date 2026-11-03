import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';

import '../extension_host.dart';
import '../l10n/generated/app_localizations.dart';

/// Shows the settings an extension declares for one of its sources.
///
/// A community extension owns its own mirror list, image quality, login and
/// content filters. Without these controls the app can only use the first
/// domain the extension was built with, and a blocked domain looks like a
/// broken source. Returns `true` when a value was written.
Future<bool> showSourceSettings(
  BuildContext context, {
  required ExtensionHost host,
  required ExtensionSourceInfo info,
}) async {
  final changed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.66,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scroll) => _SourceSettingsSheet(
        host: host,
        info: info,
        scroll: scroll,
      ),
    ),
  );
  return changed ?? false;
}

class _SourceSettingsSheet extends StatefulWidget {
  const _SourceSettingsSheet({
    required this.host,
    required this.info,
    required this.scroll,
  });

  final ExtensionHost host;
  final ExtensionSourceInfo info;
  final ScrollController scroll;

  @override
  State<_SourceSettingsSheet> createState() => _SourceSettingsSheetState();
}

class _SourceSettingsSheetState extends State<_SourceSettingsSheet> {
  late Future<List<SourceSetting>> _future;
  List<SourceSetting> _settings = const [];
  bool _changed = false;
  bool _saving = false;
  bool _failed = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<SourceSetting>> _load() async {
    final settings = await widget.host.settings(widget.info.sourceId);
    if (mounted) setState(() => _settings = settings);
    return settings;
  }

  Future<void> _write(SourceSetting setting, String value) async {
    if (_saving) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _saving = true);
    final accepted = await widget.host.setSetting(
      widget.info.sourceId,
      setting.key,
      value,
    );
    if (!mounted) return;
    // The confirmation belongs inside the sheet: a snackbar would be covered
    // by the sheet itself, where the reader could never see it.
    setState(() {
      _saving = false;
      _failed = !accepted;
      _status = accepted ? l10n.sourceSettingsSaved : l10n.sourceSettingsFailed;
      if (accepted) {
        _changed = true;
        _settings = [
          for (final item in _settings)
            if (item.key == setting.key) _replaced(item, value) else item,
        ];
      }
    });
  }

  /// A copy of [setting] with the new value, keeping its label lookup intact.
  SourceSetting _replaced(SourceSetting setting, String value) {
    return SourceSetting(
      key: setting.key,
      type: setting.type,
      title: setting.title,
      summary: setting.summary,
      value: value,
      entries: setting.entries,
      entryValues: setting.entryValues,
      values: value.split('\u001f'),
    );
  }

  Future<void> _pick(SourceSetting setting) async {
    final l10n = AppLocalizations.of(context);
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(setting.title),
        children: [
          for (var index = 0; index < setting.entries.length; index++)
            ListTile(
              title: Text(setting.entries[index]),
              leading: Icon(
                setting.entryValues[index] == setting.value
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: setting.entryValues[index] == setting.value
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
              onTap: () => Navigator.pop(context, setting.entryValues[index]),
            ),
          Padding(
            padding:
                const EdgeInsets.fromLTRB(BestSpace.lg, 0, BestSpace.sm, 0),
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.cancel),
              ),
            ),
          ),
        ],
      ),
    );
    if (selected != null) await _write(setting, selected);
  }

  Future<void> _editText(SourceSetting setting) async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(text: setting.value);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(setting.title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: setting.summary.isEmpty ? null : setting.summary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(l10n.save),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null) await _write(setting, value);
  }

  Future<void> _pickMany(SourceSetting setting) async {
    final l10n = AppLocalizations.of(context);
    final chosen = setting.values.toSet();
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(setting.title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var index = 0; index < setting.entries.length; index++)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(setting.entries[index]),
                    value: chosen.contains(setting.entryValues[index]),
                    onChanged: (value) => setDialogState(() {
                      if (value == true) {
                        chosen.add(setting.entryValues[index]);
                      } else {
                        chosen.remove(setting.entryValues[index]);
                      }
                    }),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, chosen),
              child: Text(l10n.save),
            ),
          ],
        ),
      ),
    );
    if (result != null) {
      await _write(setting, result.join(SourceSettingSeparator.value));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            BestSpace.lg,
            BestSpace.sm,
            BestSpace.sm,
            0,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.info.name,
                        style: theme.textTheme.headlineSmall),
                    Text(
                      widget.info.packageName,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Semantics(
                label: MaterialLocalizations.of(context).closeButtonTooltip,
                button: true,
                child: IconButton(
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  onPressed: () => Navigator.pop(context, _changed),
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: BestSpace.xl),
        if (_status != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
                BestSpace.lg, 0, BestSpace.lg, BestSpace.sm),
            child: Row(
              children: [
                Icon(
                  _failed ? Icons.error_outline : Icons.check_circle_outline,
                  size: 16,
                  color: _failed
                      ? theme.colorScheme.error
                      : theme.colorScheme.primary,
                ),
                const SizedBox(width: BestSpace.sm),
                Expanded(
                  child: Text(
                    _status!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: _failed
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: FutureBuilder<List<SourceSetting>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(BestSpace.xl),
                    child:
                        Text('${snapshot.error}', textAlign: TextAlign.center),
                  ),
                );
              }
              if (_settings.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(BestSpace.xl),
                    child: Text(
                      l10n.sourceSettingsEmpty,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                );
              }
              return ListView(
                controller: widget.scroll,
                padding: const EdgeInsets.fromLTRB(
                    BestSpace.lg, 0, BestSpace.lg, BestSpace.xxl),
                children: [
                  Text(
                    l10n.sourceSettingsHint,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: BestSpace.sm),
                  for (final setting in _settings) _tile(setting),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _tile(SourceSetting setting) {
    if (setting.isSwitch) {
      return SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(setting.title),
        subtitle: setting.summary.isEmpty ? null : Text(setting.summary),
        value: setting.value == 'true',
        onChanged: _saving
            ? null
            : (value) => _write(setting, value ? 'true' : 'false'),
      );
    }
    // A list's own summary is the entry it points at, so read the current
    // value instead of the summary captured when the sheet opened.
    final label = setting.isList || setting.isMulti
        ? setting.selectedLabel
        : setting.summary;
    final subtitle = label.isEmpty ? null : label;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(setting.title),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: _saving
          ? null
          : () {
              if (setting.isList) {
                _pick(setting);
              } else if (setting.isMulti) {
                _pickMany(setting);
              } else if (setting.isText) {
                _editText(setting);
              }
            },
    );
  }
}

/// The separator the host uses for multi-select values.
abstract final class SourceSettingSeparator {
  static const String value = '\u001f';
}
