import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'navigation.dart';
import 'screens/browse_screen.dart';
import 'screens/downloads_screen.dart';
import 'screens/library_screen.dart';
import 'screens/reader_screen.dart';
import 'screens/series_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/shell_screen.dart';
import 'screens/watch_screen.dart';

/// A router belongs to one app instance. `BestApp` builds it once and keeps it
/// across theme and locale rebuilds, so changing a setting never throws away
/// the navigation stack; a new app instance (a test, a second window) starts
/// at the shelf instead of inheriting another instance's location.
GoRouter buildRouter() => GoRouter(
      initialLocation: Routes.library,
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) =>
              ShellScreen(navigationShell: navigationShell),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: Routes.library,
                  builder: (context, state) => const LibraryScreen(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: Routes.browse,
                  builder: (context, state) => const BrowseScreen(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: Routes.downloads,
                  builder: (context, state) => const DownloadsScreen(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: Routes.settings,
                  builder: (context, state) => const SettingsScreen(),
                ),
              ],
            ),
          ],
        ),
        GoRoute(
          path: '/series',
          builder: (context, state) {
            final query = state.uri.queryParameters;
            return SeriesScreen(
              sourceId: query['source'] ?? '',
              url: query['url'] ?? '',
            );
          },
        ),
        GoRoute(
          path: '/read',
          builder: (context, state) {
            final query = state.uri.queryParameters;
            return ReaderScreen(
              sourceId: query['source'] ?? '',
              url: query['url'] ?? '',
              unitUrl: query['unit'] ?? '',
            );
          },
        ),
        GoRoute(
          path: '/watch',
          builder: (context, state) {
            final query = state.uri.queryParameters;
            return WatchScreen(
              sourceId: query['source'] ?? '',
              url: query['url'] ?? '',
              unitUrl: query['unit'] ?? '',
            );
          },
        ),
      ],
      errorBuilder: (context, state) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              state.error?.toString() ?? 'Not found',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
