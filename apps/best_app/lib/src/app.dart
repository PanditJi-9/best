import 'dart:async';

import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'l10n/generated/app_localizations.dart';
import 'providers.dart';
import 'router.dart';
import 'network.dart';
import 'updates.dart';

class BestApp extends ConsumerStatefulWidget {
  const BestApp({super.key});

  @override
  ConsumerState<BestApp> createState() => _BestAppState();
}

class _BestAppState extends ConsumerState<BestApp> with WidgetsBindingObserver {
  late final GoRouter _router = buildRouter();
  Timer? _updates;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkUpdates();
      _checkAppUpdate();
    });
    _updates = Timer.periodic(const Duration(hours: 6), (_) => _checkUpdates());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed) {
      _checkUpdates();
      _checkAppUpdate();
    }
  }

  /// The release check is a plain GitHub read, so it waits for a real
  /// connection and lets [UpdateController] enforce its six-hour gap. A
  /// platform without the connectivity plugin reports `unknown`; that is not
  /// enough evidence to spend the reader's data.
  void _checkAppUpdate() {
    if (!mounted) return;
    final network = ref.read(networkProvider).value;
    if (network != NetworkKind.wifi && network != NetworkKind.mobile) return;
    unawaited(ref.read(updateProvider.notifier).check());
  }

  void _checkUpdates() {
    if (!mounted || !_foreground || !ref.read(extensionAutoUpdatesProvider)) {
      return;
    }
    final network = ref.read(networkProvider).value;
    if (network == NetworkKind.none) return;
    if (ref.read(settingsProvider).wifiOnly && network != NetworkKind.wifi) {
      return;
    }
    unawaited(ref.read(extensionUpdatesProvider.notifier).check());
  }

  @override
  void dispose() {
    _updates?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    ref.listen(networkProvider, (previous, next) {
      if (next.value == NetworkKind.wifi && previous?.value != next.value) {
        _checkUpdates();
      }
      if ((next.value == NetworkKind.wifi ||
              next.value == NetworkKind.mobile) &&
          previous?.value != next.value) {
        _checkAppUpdate();
      }
    });
    ref.listen(extensionAutoUpdatesProvider, (previous, enabled) {
      if (enabled) _checkUpdates();
    });

    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appName,
      debugShowCheckedModeBanner: false,
      theme: bestTheme(Brightness.light),
      darkTheme: bestTheme(Brightness.dark),
      themeMode: settings.themeMode,
      locale:
          settings.languageCode == null ? null : Locale(settings.languageCode!),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      routerConfig: _router,
    );
  }
}
