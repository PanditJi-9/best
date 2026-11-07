import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../extension_host.dart';
import '../l10n/generated/app_localizations.dart';
import '../providers.dart';

/// Lists APK bundles, not thousands of duplicated language rows. Only visible
/// tiles build/load icons; searching the index makes no requests to the sites.
class SourceDirectoryScreen extends ConsumerStatefulWidget {
  const SourceDirectoryScreen({super.key, this.initialKind = 'all'});

  /// Opens already narrowed to the half of the catalogue the reader is in.
  final String initialKind;

  @override
  ConsumerState<SourceDirectoryScreen> createState() => _SourceDirectoryState();
}

class _SourceDirectoryState extends ConsumerState<SourceDirectoryScreen> {
  final _search = TextEditingController();
  final _busy = <String>{};
  final _confirming = <String>{};
  final _errors = <String, String>{};
  final _trusted = <String>{};
  late String _kind = widget.initialKind;
  String _status = 'all';
  String _language = '*';
  bool _adult = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(extensionDirectoryProvider);
    ref.invalidate(extensionCatalogProvider);
    await ref.read(extensionDirectoryProvider.future);
  }

  Future<void> _activate(ExtensionEntry entry) async {
    final l10n = AppLocalizations.of(context);
    final host = ref.read(extensionHostProvider);
    if (!host.isAvailable) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.directoryAndroidOnly)));
      return;
    }
    if (_busy.contains(entry.packageName) ||
        _confirming.contains(entry.packageName)) {
      return;
    }
    _confirming.add(entry.packageName);
    try {
      final preferences = ref.read(preferencesProvider);
      final trusted = {
        ..._trusted,
        ...?preferences?.getStringList('extension_trusted_publishers_v1')
      };
      if (!trusted.contains(entry.repositoryUrl)) {
        final accepted = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l10n.directoryTrustTitle),
            content: SingleChildScrollView(
                child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l10n.directoryTrustBody),
                const SizedBox(height: BestSpace.md),
                Text(entry.repositoryUrl,
                    style: Theme.of(context).textTheme.bodySmall)
              ],
            )),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(l10n.cancel)),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(l10n.directoryTrust))
            ],
          ),
        );
        if (accepted != true || !mounted) return;
        _trusted.add(entry.repositoryUrl);
        try {
          await preferences?.setStringList('extension_trusted_publishers_v1',
              {...trusted, entry.repositoryUrl}.toList());
        } catch (_) {/* Session trust remains. */}
      }
      if (!mounted) return;
      setState(() => _busy.add(entry.packageName));
      final result = await ref.read(extensionInstallerProvider).activate(entry);
      if (!mounted) return;
      setState(() {
        _errors.remove(entry.packageName);
        if (result != entry.packageName) {
          _errors[entry.packageName] = l10n.directoryActivationFailed;
        }
      });
      ref.invalidate(extensionCatalogProvider);
    } catch (error) {
      if (mounted) setState(() => _errors[entry.packageName] = '$error');
    } finally {
      _confirming.remove(entry.packageName);
      if (mounted) setState(() => _busy.remove(entry.packageName));
    }
  }

  Future<void> _remove(ExtensionEntry entry) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: Text(l10n.directoryRemove),
                content: Text(l10n.directoryRemoveBody),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(l10n.cancel)),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(l10n.directoryRemove))
                ]));
    if (confirmed != true || !mounted || _busy.contains(entry.packageName)) {
      return;
    }
    setState(() => _busy.add(entry.packageName));
    try {
      final removed =
          await ref.read(extensionInstallerProvider).remove(entry.packageName);
      if (!mounted) return;
      setState(() {
        _errors.remove(entry.packageName);
        if (!removed) _errors[entry.packageName] = l10n.directoryRemoveFailed;
      });
      ref.invalidate(extensionCatalogProvider);
    } catch (error) {
      if (mounted) setState(() => _errors[entry.packageName] = '$error');
    } finally {
      if (mounted) setState(() => _busy.remove(entry.packageName));
    }
  }

  void _details(ExtensionEntry entry) {
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) => DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.6,
              builder: (context, scroll) => ListView(
                  controller: scroll,
                  padding: const EdgeInsets.all(BestSpace.lg),
                  children: [
                    Text(entry.name,
                        style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: BestSpace.md),
                    SelectableText(
                        '${entry.packageName}\nv${entry.version} · ${entry.versionCode}\n${entry.repositoryUrl}'),
                    const Divider(height: BestSpace.xl),
                    Text(l10n.directoryIntro),
                    for (final site in entry.sources)
                      ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                              '${site.name} · ${site.language.toUpperCase()}'),
                          subtitle: SelectableText(site.homeUrl)),
                  ]),
            ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final directory = ref.watch(extensionDirectoryProvider);
    final catalog = ref.watch(extensionCatalogProvider);
    final inventory = catalog.value ?? const ExtensionCatalog.empty();
    final installed = {
      for (final item in inventory.installed) item.packageName: item
    };
    final problems = {
      for (final problem in inventory.problems) problem.name: problem.message
    };
    final loaded = inventory.sources.map((s) => s.packageName).toSet();
    final updates = ref.watch(extensionUpdatesProvider);
    final updateErrors = updates.value?.errors ?? const <String, String>{};

    return Scaffold(
      appBar: AppBar(title: Text(l10n.directoryTitle), actions: [
        IconButton(
            tooltip: l10n.retry,
            onPressed: directory.isLoading ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded)),
        IconButton(
            tooltip: l10n.extensionsUpdate,
            onPressed: updates.isLoading
                ? null
                : () => ref
                    .read(extensionUpdatesProvider.notifier)
                    .check(force: true),
            icon: const Icon(Icons.system_update_alt_rounded)),
      ]),
      body: RefreshIndicator(
          onRefresh: _refresh,
          child: CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                  child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    BestSpace.lg, BestSpace.sm, BestSpace.lg, 0),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          directory.value == null
                              ? l10n.extensionsTitle
                              : l10n.directoryCounts(
                                  directory.value!.entries.length,
                                  directory.value!.sourceCount),
                          style: theme.textTheme.titleMedium),
                      const SizedBox(height: BestSpace.sm),
                      Text(l10n.directoryIntro,
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                      if (directory.value?.cached == true)
                        _Notice(text: l10n.directoryCached),
                      if (directory.value?.errors.isNotEmpty == true)
                        _Notice(text: l10n.directoryPartial),
                      if (catalog.hasError) _Notice(text: '${catalog.error}'),
                      if (updates.isLoading)
                        _Notice(text: l10n.directoryUpdating),
                      if (updates.hasError || updateErrors.isNotEmpty)
                        _Notice(text: l10n.directoryUpdateFailed),
                      if (updates.value?.checked == true &&
                          updateErrors.isEmpty)
                        _Notice(
                            text: l10n
                                .directoryUpdateDone(updates.value!.updated)),
                      const SizedBox(height: BestSpace.md),
                      TextField(
                          key: const ValueKey('directory-search'),
                          controller: _search,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                              hintText: l10n.directorySearch,
                              prefixIcon: const Icon(Icons.search_rounded),
                              suffixIcon: _search.text.isEmpty
                                  ? null
                                  : IconButton(
                                      tooltip: l10n.cancel,
                                      onPressed: () => setState(_search.clear),
                                      icon: const Icon(Icons.close_rounded)))),
                      const SizedBox(height: BestSpace.sm),
                    ]),
              )),
              SliverToBoxAdapter(
                  child: SizedBox(
                      height: 52,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(
                            horizontal: BestSpace.lg),
                        children: [
                          for (final item in [
                            ('all', l10n.allSources),
                            ('manga', l10n.kindManga),
                            ('anime', l10n.kindAnime)
                          ])
                            Padding(
                                padding: const EdgeInsetsDirectional.only(
                                    end: BestSpace.sm),
                                child: ChoiceChip(
                                    label: Text(item.$2),
                                    selected: _kind == item.$1,
                                    onSelected: (_) =>
                                        setState(() => _kind = item.$1))),
                          FilterChip(
                              label: Text(l10n.directoryInstalled),
                              selected: _status == 'installed',
                              onSelected: (selected) => setState(() =>
                                  _status = selected ? 'installed' : 'all')),
                          const SizedBox(width: BestSpace.sm),
                          FilterChip(
                              label: Text(l10n.directoryUpdates),
                              selected: _status == 'updates',
                              onSelected: (selected) => setState(() =>
                                  _status = selected ? 'updates' : 'all')),
                        ],
                      ))),
              if (directory.value != null)
                SliverToBoxAdapter(
                    child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: BestSpace.lg),
                  child: Column(children: [
                    DropdownButtonFormField<String>(
                        key: ValueKey(_language),
                        initialValue: _language,
                        isExpanded: true,
                        decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.translate_rounded)),
                        items: [
                          DropdownMenuItem(
                              value: '*',
                              child: Text(l10n.directoryAllLanguages)),
                          for (final lang in ({
                            if (_language != '*') _language,
                            ...directory.value!.entries
                                .expand((e) => e.languages),
                          }.toList()
                            ..sort()))
                            DropdownMenuItem(
                                value: lang, child: Text(lang.toUpperCase()))
                        ],
                        onChanged: (value) =>
                            setState(() => _language = value ?? '*')),
                    SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(l10n.directoryAdult,
                            style: theme.textTheme.bodySmall),
                        value: _adult,
                        onChanged: (value) => setState(() => _adult = value)),
                  ]),
                )),
              ...directory.when(
                loading: () => [
                  const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(child: CircularProgressIndicator()))
                ],
                error: (error, stack) => [
                  SliverFillRemaining(
                      hasScrollBody: false,
                      child: EmptyState(
                          icon: Icons.cloud_off_outlined,
                          title: l10n.sourceError,
                          body: '$error',
                          action: FilledButton(
                              onPressed: _refresh, child: Text(l10n.retry))))
                ],
                data: (index) {
                  final entries = <ExtensionEntry>[
                    ...index.entries,
                    // A retired/incompatible APK remains visible and removable.
                    for (final item in installed.values)
                      if (!index.entries
                          .any((e) => e.packageName == item.packageName))
                        ExtensionEntry(
                            name: item.packageName.split('.').last,
                            packageName: item.packageName,
                            apkUrl: '',
                            language: 'all',
                            version: item.versionName,
                            versionCode: item.versionCode,
                            nsfw: false,
                            kind: item.kind),
                  ]
                      .where((e) =>
                          (_kind == 'all' || e.kind == _kind) &&
                          (_adult ||
                              !e.nsfw ||
                              installed.containsKey(e.packageName)) &&
                          (_language == '*' ||
                              e.languages.contains(_language)) &&
                          e.matches(_search.text) &&
                          (_status != 'installed' ||
                              installed.containsKey(e.packageName)) &&
                          (_status != 'updates' ||
                              (installed.containsKey(e.packageName) &&
                                  e.versionCode >
                                      installed[e.packageName]!.versionCode)))
                      .toList();
                  if (entries.isEmpty) {
                    return [
                      SliverFillRemaining(
                          hasScrollBody: false,
                          child: EmptyState(
                              icon: Icons.travel_explore_rounded,
                              title: l10n.directoryEmpty,
                              body: l10n.directoryEmptyBody))
                    ];
                  }
                  return <Widget>[
                    SliverToBoxAdapter(
                        child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: BestSpace.lg,
                                vertical: BestSpace.sm),
                            child: Text(l10n.resultCount(entries.length),
                                style: theme.textTheme.labelSmall))),
                    SliverList.builder(
                        itemCount: entries.length,
                        itemBuilder: (context, position) {
                          final entry = entries[position];
                          final item = installed[entry.packageName];
                          final error = _errors[entry.packageName] ??
                              problems[entry.packageName] ??
                              updateErrors[entry.packageName];
                          return _ExtensionTile(
                              entry: entry,
                              installed: item,
                              busy: _busy.contains(entry.packageName) ||
                                  updates.isLoading,
                              error: error,
                              loaded: loaded.contains(entry.packageName),
                              onActivate: catalog.isLoading
                                  ? null
                                  : () => _activate(entry),
                              onRemove: () => _remove(entry),
                              onDetails: () => _details(entry));
                        }),
                    const SliverToBoxAdapter(
                        child: SizedBox(height: BestSpace.xl)),
                  ];
                },
              ),
            ],
          )),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(top: BestSpace.sm),
      child: Text(text,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.primary)));
}

class _ExtensionTile extends StatelessWidget {
  const _ExtensionTile(
      {required this.entry,
      required this.installed,
      required this.busy,
      required this.error,
      required this.loaded,
      required this.onActivate,
      required this.onRemove,
      required this.onDetails});
  final ExtensionEntry entry;
  final InstalledExtension? installed;
  final bool busy;
  final bool loaded;
  final String? error;
  final VoidCallback? onActivate;
  final VoidCallback onRemove;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final newer =
        installed != null && entry.versionCode > installed!.versionCode;
    final status = entry.apkUrl.isEmpty
        ? l10n.directoryUnavailable
        : installed == null
            ? l10n.directoryUntested
            : loaded
                ? l10n.directoryLoaded
                : l10n.extensionsFailed(1);
    return Padding(
      key: ValueKey(entry.packageName),
      padding: const EdgeInsets.symmetric(horizontal: BestSpace.lg),
      child: Column(children: [
        Padding(
            padding: const EdgeInsets.symmetric(vertical: BestSpace.md),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                  width: 40,
                  height: 48,
                  child: entry.iconUrl == null
                      ? Icon(entry.kind == 'anime'
                          ? Icons.play_circle_outline_rounded
                          : Icons.menu_book_rounded)
                      : Image.network(entry.iconUrl!,
                          width: 40,
                          height: 40,
                          cacheWidth: 96,
                          errorBuilder: (_, error, stack) =>
                              const Icon(Icons.extension_outlined))),
              const SizedBox(width: BestSpace.md),
              Expanded(
                  child: InkWell(
                      onTap: onDetails,
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(entry.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall),
                            Text(
                                '${entry.kind == 'anime' ? l10n.kindAnime : l10n.kindManga} · ${entry.languages.join(', ').toUpperCase()} · v${entry.version}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant)),
                            if (newer)
                              Text(
                                  'v${installed!.versionName} → v${entry.version}',
                                  style: theme.textTheme.labelSmall),
                            Text(status,
                                style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant)),
                            if (entry.contentWarning != 'safe')
                              Text(
                                  entry.nsfw
                                      ? l10n.directoryNsfw
                                      : l10n.directoryMixed,
                                  style: theme.textTheme.labelSmall),
                            if (error != null)
                              Text(error!,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.error)),
                          ]))),
              const SizedBox(width: BestSpace.sm),
              if (busy)
                const SizedBox(
                    width: 48,
                    height: 48,
                    child: Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(strokeWidth: 2)))
              else if (installed == null || newer)
                Column(mainAxisSize: MainAxisSize.min, children: [
                  FilledButton(
                      onPressed: entry.apkUrl.isEmpty ? null : onActivate,
                      style: FilledButton.styleFrom(
                          minimumSize: const Size(76, 44),
                          padding: const EdgeInsets.symmetric(
                              horizontal: BestSpace.md)),
                      child: Text(newer
                          ? l10n.directoryUpdates
                          : l10n.directoryActivate)),
                  if (installed != null)
                    PopupMenuButton<String>(
                        tooltip: l10n.directoryDetails,
                        onSelected: (value) =>
                            value == 'remove' ? onRemove() : onDetails(),
                        itemBuilder: (_) => [
                              PopupMenuItem(
                                  value: 'details',
                                  child: Text(l10n.directoryDetails)),
                              PopupMenuItem(
                                  value: 'remove',
                                  child: Text(l10n.directoryRemove)),
                            ]),
                ])
              else
                PopupMenuButton<String>(
                    tooltip: l10n.directoryDetails,
                    onSelected: (value) =>
                        value == 'remove' ? onRemove() : onDetails(),
                    itemBuilder: (_) => [
                          PopupMenuItem(
                              value: 'details',
                              child: Text(l10n.directoryDetails)),
                          PopupMenuItem(
                              value: 'remove',
                              child: Text(l10n.directoryRemove))
                        ]),
            ])),
        const Divider(height: 1),
      ]),
    );
  }
}
