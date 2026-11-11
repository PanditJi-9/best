import 'package:best_app/src/reader/vertical_strip.dart';
import 'package:flutter_test/flutter_test.dart';

double stripProgress({
  required int pageCount,
  required int index,
  required double leading,
  required double trailing,
  bool atStripEnd = false,
}) => verticalStripProgress(
  pageCount: pageCount,
  index: index,
  leading: leading,
  trailing: trailing,
  atStripEnd: atStripEnd,
);

void main() {
  group('auto-scroll speed', () {
    test('cycles 1x, 2x, 3x, 0.5x and back to 1x', () {
      expect(nextAutoScrollSpeed(1.0), 2.0);
      expect(nextAutoScrollSpeed(2.0), 3.0);
      expect(nextAutoScrollSpeed(3.0), 0.5);
      expect(nextAutoScrollSpeed(0.5), 1.0);
    });

    test('an unknown speed resets to 1x', () {
      expect(nextAutoScrollSpeed(7.0), 1.0);
    });

    test('badges only the speeds that differ from 1x', () {
      expect(autoScrollSpeedLabel(1.0), isNull);
      expect(autoScrollSpeedLabel(2.0), '×2');
      expect(autoScrollSpeedLabel(3.0), '×3');
      expect(autoScrollSpeedLabel(0.5), '×0.5');
    });
  });

  group('vertical strip progress', () {
    test('an empty strip reads zero', () {
      expect(
        stripProgress(pageCount: 0, index: 0, leading: 0.0, trailing: 1.0),
        0.0,
      );
    });

    test('a line halfway down page 0 of 4 reads one eighth', () {
      expect(
        stripProgress(pageCount: 4, index: 0, leading: 0.0, trailing: 1.0),
        closeTo(0.125, 1e-9),
      );
    });

    test('a tall page moves the bar by how far the line has crossed it', () {
      // Page 1 is three screens tall and the line sits halfway down it:
      // (1 + 0.5) / 4.
      expect(
        stripProgress(pageCount: 4, index: 1, leading: -1.0, trailing: 2.0),
        closeTo(0.375, 1e-9),
      );
    });

    test('a page whose top is still below the line counts as not started', () {
      expect(
        stripProgress(pageCount: 4, index: 2, leading: 0.8, trailing: 1.8),
        closeTo(0.5, 1e-9),
      );
    });

    test('the chapter-end card reads complete', () {
      expect(
        stripProgress(pageCount: 4, index: 4, leading: 0.2, trailing: 1.2),
        1.0,
      );
    });

    test('reaching the end of the strip reads complete', () {
      expect(
        stripProgress(
          pageCount: 4,
          index: 3,
          leading: 0.0,
          trailing: 1.0,
          atStripEnd: true,
        ),
        1.0,
      );
    });
  });

  group('strip end', () {
    test('is reached once the last item bottom edge is on screen', () {
      expect(
        isAtVerticalStripEnd(lastIndex: 3, itemCount: 4, trailing: 1.0),
        isTrue,
      );
      expect(
        isAtVerticalStripEnd(lastIndex: 3, itemCount: 4, trailing: 0.6),
        isTrue,
      );
    });

    test('tolerates float noise at the bottom edge', () {
      expect(
        isAtVerticalStripEnd(lastIndex: 3, itemCount: 4, trailing: 1.0005),
        isTrue,
      );
    });

    test('is not reached while the last item extends below the screen', () {
      expect(
        isAtVerticalStripEnd(lastIndex: 3, itemCount: 4, trailing: 1.4),
        isFalse,
      );
    });

    test('is not reached while later items are still unseen', () {
      expect(
        isAtVerticalStripEnd(lastIndex: 2, itemCount: 4, trailing: 0.9),
        isFalse,
      );
    });
  });
}
