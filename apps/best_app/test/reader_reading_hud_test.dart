import 'package:best_app/src/widgets/reader_reading_hud.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('reading HUD reveals and then leaves the artwork alone', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: ReaderReadingHud(
            chapterTitle: 'Chapter 7',
            pageLabel: 'Page 12 of 48',
            visible: true,
          ),
        ),
      ),
    );
    await tester.pump();

    final label = tester.widget<Text>(
      find.byKey(const ValueKey('reader-hud-label')),
    );
    expect(label.textSpan?.toPlainText(), contains('Chapter 7'));
    expect(find.text('Page 12 of 48'), findsOneWidget);
    expect(_opacity(tester), 1);

    await tester.pump(const Duration(milliseconds: 2400));
    await tester.pump();

    expect(_opacity(tester), 0);
  });

  testWidgets('reading HUD stays hidden in paged mode', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ReaderReadingHud(
            chapterTitle: 'Chapter 7',
            pageLabel: 'Page 12 of 48',
            visible: false,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(_opacity(tester), 0);
  });
}

double _opacity(WidgetTester tester) {
  return tester
      .widget<AnimatedOpacity>(find.byKey(const ValueKey('reader-reading-hud')))
      .opacity;
}
