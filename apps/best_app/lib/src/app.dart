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
  bool _authenticated = false;
  bool _authenticating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkUpdates();
      _checkAppUpdate();
      _checkBiometrics();
    });
    _updates = Timer.periodic(const Duration(hours: 6), (_) => _checkUpdates());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed) {
      _checkUpdates();
      _checkAppUpdate();
      _checkBiometrics();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (ref.read(settingsProvider).biometricLockEnabled) {
        setState(() => _authenticated = false);
      }
    }
  }

  Future<void> _checkBiometrics() async {
    final enabled = ref.read(settingsProvider).biometricLockEnabled;
    if (!enabled || _authenticated || _authenticating) return;

    _authenticating = true;
    try {
      final client = ref.read(biometricClientProvider);
      final ok = await client.authenticate(
        title: 'فتح تطبيق Best',
        subtitle: 'استخدم البصمة أو رمز القفل للوصول إلى مكتبتك',
      );
      if (mounted && ok) {
        setState(() => _authenticated = true);
      }
    } finally {
      _authenticating = false;
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

    final locked = settings.biometricLockEnabled && !_authenticated;

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
      builder: (context, child) {
        if (!locked) return child ?? const SizedBox.shrink();
        return _BiometricLockScreen(onUnlock: _checkBiometrics);
      },
    );
  }
}

class _BiometricLockScreen extends StatelessWidget {
  const _BiometricLockScreen({required this.onUnlock});

  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: BestColors.jade.withValues(alpha: 0.15),
                  border: Border.all(
                    color: BestColors.jade.withValues(alpha: 0.4),
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.fingerprint_rounded,
                  size: 48,
                  color: BestColors.jade,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'تطبيق Best مقفل',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'مكتبتك وسجل قراءتك محمية بواسطة القفل البيومتري',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: BestColors.jade,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: onUnlock,
                icon: const Icon(Icons.lock_open_rounded, size: 20),
                label: const Text(
                  'إلغاء القفل الآن',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
