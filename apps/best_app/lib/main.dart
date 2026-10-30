import 'package:best_data/best_data.dart';
import 'package:best_domain/best_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'src/app.dart';
import 'src/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // A failed database open must not become a white screen. The in-memory
  // repository keeps the app usable for the session; the next launch retries
  // SQLite. Nothing is silently written over a corrupt file.
  LibraryRepository repository;
  try {
    final database = await AppDatabase.open(
      factory: databaseFactory,
      path: p.join(await getDatabasesPath(), AppDatabase.fileName),
    );
    repository = SqfliteLibraryRepository(database.db);
  } catch (error, stack) {
    debugPrint(
      'Best: SQLite unavailable, using memory storage. $error\n$stack',
    );
    repository = MemoryLibraryRepository();
  }

  final preferences = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repository),
        preferencesProvider.overrideWithValue(preferences),
      ],
      child: const BestApp(),
    ),
  );
}
