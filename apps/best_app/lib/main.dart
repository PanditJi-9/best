import 'dart:async';

import 'package:best_data/best_data.dart';
import 'package:best_domain/best_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'src/app.dart';
import 'src/providers.dart';

/// Startup is the one place where a failure has no screen to explain itself, so
/// it is also the one place where every step has a fallback and the whole thing
/// runs inside a guarded zone.
void main() {
  var started = false;

  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        debugPrint('Best: framework error: ${details.exceptionAsString()}');
      };

      final repository = await _openRepository();
      final preferences = await _openPreferences();

      runApp(
        ProviderScope(
          overrides: [
            repositoryProvider.overrideWithValue(repository),
            preferencesProvider.overrideWithValue(preferences),
          ],
          child: const BestApp(),
        ),
      );
      started = true;
    },
    (error, stack) {
      debugPrint('Best: startup failed: $error\n$stack');
      // A late error must not replace a working app with a failure screen.
      if (!started) {
        runApp(StartupFailureApp(message: '$error'));
      }
    },
  );
}

/// A failed database open must not become a white screen. The in-memory
/// repository keeps the app usable for the session; the next launch retries
/// SQLite. Nothing is silently written over a corrupt file.
Future<LibraryRepository> _openRepository() async {
  try {
    final database = await AppDatabase.open(
      factory: databaseFactory,
      path: p.join(await getDatabasesPath(), AppDatabase.fileName),
    ).timeout(const Duration(seconds: 10));
    return SqfliteLibraryRepository(database.db);
  } catch (error, stack) {
    debugPrint('Best: SQLite unavailable, using memory. $error\n$stack');
    return MemoryLibraryRepository();
  }
}

/// Preferences are a convenience, never a prerequisite. If the platform store
/// is missing or corrupt, the app runs with session-only settings instead of
/// killing the launch.
Future<SharedPreferences?> _openPreferences() async {
  try {
    return await SharedPreferences.getInstance().timeout(
      const Duration(seconds: 5),
    );
  } catch (error, stack) {
    debugPrint('Best: preferences unavailable. $error\n$stack');
    return null;
  }
}

/// Shown only when the app could not reach its first frame. It is deliberately
/// independent of localization, theme and Riverpod: those may be the failure.
class StartupFailureApp extends StatelessWidget {
  const StartupFailureApp({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF17151A),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Best could not start',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Something failed before the first screen. The details below '
                  'can be copied into a bug report.',
                  style: TextStyle(
                    color: Color(0xFFB9B3C6),
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 18),
                Expanded(
                  child: SingleChildScrollView(
                    child: SelectableText(
                      message,
                      style: const TextStyle(
                        color: Color(0xFFF0A6A6),
                        fontFamily: 'monospace',
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
