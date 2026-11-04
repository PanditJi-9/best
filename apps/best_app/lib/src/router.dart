import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'navigation.dart';
import 'meta/meta_models.dart';
import 'screens/about_screen.dart';
import 'screens/backup_screen.dart';
import 'screens/browse_screen.dart';
import 'screens/contributors_screen.dart';
import 'screens/database_screen.dart';
import 'screens/discover_screen.dart';
import 'screens/downloads_screen.dart';
import 'screens/history_screen.dart';
import 'screens/home_screen.dart';
import 'screens/library_screen.dart';
import 'screens/menu_screen.dart';
import 'screens/manga_screen.dart';
import 'screens/meta_detail_screen.dart';
import 'screens/meta_list_screen.dart';
import 'screens/meta_search_screen.dart';
import 'screens/news_screen.dart';
import 'screens/reader_screen.dart';
import 'screens/series_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/shell_screen.dart';
import 'screens/source_directory_screen.dart';
import 'screens/stats_screen.dart';
import 'screens/sync_screen.dart';
import 'screens/top_rated_screen.dart';
import 'screens/watch_screen.dart';

/// A router belongs to one app instance. `BestApp` builds it once and keeps it
/// across theme and locale rebuilds, so changing a setting never throws away
/// the navigation stack; a new app instance (a test, a second window) starts
/// at the shelf instead of inheriting another instance's location.
GoRouter buildRouter() => GoRouter(
      initialLocation: Routes.home,
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) =>
              ShellScreen(navigationShell: navigationShell),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: Routes.home,
                  builder: (context, state) => const HomeScreen(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: Routes.database,
                  builder: (context, state) => const DatabaseScreen(),
                ),
              ],
            ),
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
                  path: Routes.downloads,
                  builder: (context, state) => const DownloadsScreen(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: Routes.menu,
                  builder: (context, state) => const MenuScreen(),
                ),
              ],
            ),
          ],
        ),
        GoRoute(
          path: Routes.manga,
          builder: (context, state) => const MangaScreen(),
        ),
        GoRoute(
          path: Routes.discover,
          builder: (context, state) => const DiscoverScreen(),
        ),
        GoRoute(
          path: Routes.metaSearch,
          builder: (context, state) => const MetaSearchScreen(),
        ),
        GoRoute(
          path: '/meta/work',
          builder: (context, state) {
            final query = state.uri.queryParameters;
            MetaSource? source;
            for (final value in MetaSource.values) {
              if (value.name == query['source']) {
                source = value;
                break;
              }
            }
            if (source == null || (query['id'] ?? '').isEmpty) {
              return const MetaSearchScreen();
            }
            return MetaDetailScreen(source: source, id: query['id']!);
          },
        ),
        GoRoute(
          path: '/meta/list',
          builder: (context, state) {
            final query = state.uri.queryParameters;
            MetaListKind? kind;
            for (final value in MetaListKind.values) {
              if (value.name == query['kind']) {
                kind = value;
                break;
              }
            }
            return MetaListScreen(kind: kind ?? MetaListKind.anilistTrending);
          },
        ),
        GoRoute(
          path: Routes.history,
          builder: (context, state) => const HistoryScreen(),
        ),
        GoRoute(
          path: Routes.browse,
          builder: (context, state) {
            final query = state.uri.queryParameters;
            return BrowseScreen(
              initialSourceId: query['source'],
              initialQuery: query['q'] ?? '',
            );
          },
        ),
        GoRoute(
          path: Routes.settings,
          builder: (context, state) => const SettingsScreen(),
        ),
        GoRoute(
          path: Routes.about,
          builder: (context, state) => const AboutScreen(),
        ),
        GoRoute(
          path: Routes.topRated,
          builder: (context, state) => const TopRatedScreen(),
        ),
        GoRoute(
          path: Routes.news,
          builder: (context, state) => const NewsScreen(),
        ),
        GoRoute(
          path: Routes.contributors,
          builder: (context, state) => const ContributorsScreen(),
        ),
        GoRoute(
          path: Routes.sources,
          builder: (context, state) => const SourceDirectoryScreen(),
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
          path: Routes.stats,
          builder: (context, state) => const StatsScreen(),
        ),
        GoRoute(
          path: Routes.backup,
          builder: (context, state) => const BackupScreen(),
        ),
        GoRoute(
          path: Routes.sync,
          builder: (context, state) => const SyncScreen(),
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
