import 'package:best_app/src/l10n/generated/app_localizations.dart';
import 'package:best_app/src/providers.dart';
import 'package:best_app/src/screens/manage_sources_screen.dart';
import 'package:best_domain/best_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Source implements SourceAdapter {
  const _Source(this.id, this.name);

  @override
  final String id;
  @override
  final String name;
  @override
  String get language => 'all';

  @override
  Future<List<Media>> popular({int page = 1}) async => const [];

  @override
  Future<List<Media>> search(String query, {int page = 1}) async => const [];

  @override
  Future<Media> details(Media media) async => media;

  @override
  Future<List<MediaUnit>> units(Media media) async => const [];

  @override
  Future<List<MediaResource>> resources(MediaUnit unit) async => const [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SharedPreferences> pump(
    WidgetTester tester,
    List<SourceAdapter> sources,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          preferencesProvider.overrideWithValue(preferences),
          sourceRegistryProvider
              .overrideWithValue(SourceRegistry.fixed(sources)),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(
            colorSchemeSeed: Colors.indigo,
            useMaterial3: true,
          ),
          home: const ManageSourcesScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return preferences;
  }

  testWidgets('hiding a source persists and the last one cannot be hidden',
      (tester) async {
    final preferences = await pump(tester, const [
      _Source('alpha', 'Alpha scans'),
      _Source('beta', 'Beta scans'),
    ]);

    expect(find.text('Alpha scans'), findsOneWidget);
    expect(find.text('Beta scans'), findsOneWidget);

    Future<void> toggle(String id) async {
      await tester.tap(find.descendant(
        of: find.byKey(ValueKey('manage-source-$id')),
        matching: find.byType(Switch),
      ));
      await tester.pumpAndSettle();
    }

    await toggle('alpha');
    expect(preferences.getStringList('hidden_sources_v1'), ['alpha']);

    await toggle('beta');
    expect(preferences.getStringList('hidden_sources_v1'), ['alpha']);
    expect(find.text('Keep at least one source visible.'), findsOneWidget);

    // Showing it again clears the stored choice.
    await toggle('alpha');
    expect(preferences.getStringList('hidden_sources_v1'), isEmpty);
  });
}
