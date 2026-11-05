import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child, {TextDirection direction = TextDirection.ltr}) {
  return MaterialApp(
    theme: bestTheme(Brightness.dark),
    home: Directionality(
      textDirection: direction,
      child: Scaffold(body: child),
    ),
  );
}

void main() {
  group('theme', () {
    test('no text role sets letter spacing (it breaks Arabic joining)', () {
      for (final brightness in Brightness.values) {
        final text = bestTheme(brightness).textTheme;
        final styles = <TextStyle?>[
          text.displayLarge,
          text.displayMedium,
          text.displaySmall,
          text.headlineLarge,
          text.headlineMedium,
          text.headlineSmall,
          text.titleLarge,
          text.titleMedium,
          text.titleSmall,
          text.bodyLarge,
          text.bodyMedium,
          text.bodySmall,
          text.labelLarge,
          text.labelMedium,
          text.labelSmall,
        ];
        for (final style in styles) {
          expect(style?.letterSpacing ?? 0, 0);
        }
      }
    });
  });

  group('SectionHeader', () {
    testWidgets('shows the title and fires the action', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(
        SectionHeader(
          title: 'Discover',
          actionLabel: 'See all',
          onAction: () => taps++,
        ),
      ));
      expect(find.text('Discover'), findsOneWidget);
      await tester.tap(find.text('See all'));
      expect(taps, 1);
    });

    testWidgets('renders in RTL without overflow', (tester) async {
      await tester.pumpWidget(_host(
        const SectionHeader(title: 'اكتشف', index: '2'),
        direction: TextDirection.rtl,
      ));
      expect(find.text('اكتشف'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('EmptyState', () {
    testWidgets('shows title, body and action', (tester) async {
      await tester.pumpWidget(_host(
        EmptyState(
          icon: Icons.inbox_outlined,
          title: 'Nothing here',
          body: 'Add something first.',
          action: FilledButton(onPressed: () {}, child: const Text('Add')),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Nothing here'), findsOneWidget);
      expect(find.text('Add something first.'), findsOneWidget);
      expect(find.text('Add'), findsOneWidget);
    });
  });

  group('BestCover', () {
    testWidgets('without artwork shows the first glyph of the title',
        (tester) async {
      await tester.pumpWidget(_host(
        const SizedBox(
          width: 100,
          height: 150,
          child: BestCover(title: 'Blue Echo'),
        ),
      ));
      expect(find.text('B'), findsOneWidget);
    });
  });

  group('BestTapScale', () {
    testWidgets('still delivers taps', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(
        Center(
          child: BestTapScale(
            onTap: () => taps++,
            child: const SizedBox(width: 120, height: 120),
          ),
        ),
      ));
      await tester.tap(find.byType(BestTapScale));
      await tester.pump(const Duration(milliseconds: 300));
      expect(taps, 1);
    });
  });

  group('BestReveal', () {
    testWidgets('ends fully visible and leaves no pending timers',
        (tester) async {
      await tester.pumpWidget(_host(
        const BestReveal(
          delay: Duration(milliseconds: 120),
          child: Text('Revealed'),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Revealed'), findsOneWidget);
      final opacity = tester.widget<Opacity>(
        find.descendant(
          of: find.byType(BestReveal),
          matching: find.byType(Opacity),
        ),
      );
      expect(opacity.opacity, 1);
    });
  });

  group('skeletons', () {
    testWidgets('poster rail builds at phone width without overflow',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_host(const PosterRailSkeleton()));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(PosterSkeleton), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('row list builds without overflow', (tester) async {
      await tester.pumpWidget(_host(
        const SingleChildScrollView(child: RowListSkeleton(count: 3)),
      ));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(RowSkeleton), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    });
  });
}
