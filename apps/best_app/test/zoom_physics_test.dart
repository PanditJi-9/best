import 'package:best_app/src/reader/zoom_physics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('rubber band', () {
    test('keeps nothing without an overshoot', () {
      expect(rubberBand(0, 100), 0.0);
      expect(rubberBand(-5, 100), 0.0);
    });

    test('moves about 0.55 of the finger right at the edge', () {
      expect(rubberBand(0.01, 100) / 0.01, closeTo(0.55, 0.01));
    });

    test('each extra pixel past the edge moves the content less', () {
      final first = rubberBand(10, 100) - rubberBand(0, 100);
      final second = rubberBand(20, 100) - rubberBand(10, 100);
      expect(second, lessThan(first));
    });

    test('never reaches the viewport extent', () {
      expect(rubberBand(1000, 100), lessThan(100));
    });
  });

  group('elastic scale', () {
    test('leaves scales inside the limits alone', () {
      expect(elasticScale(1.5, min: 0.5, max: 4), 1.5);
      expect(elasticScale(0.5, min: 0.5, max: 4), 0.5);
      expect(elasticScale(4.0, min: 0.5, max: 4), 4.0);
    });

    test('stretches past the lower limit with resistance', () {
      expect(elasticScale(0.1, min: 0.5, max: 4), closeTo(0.3472, 0.0005));
    });

    test('stretches past the upper limit with resistance', () {
      expect(elasticScale(8, min: 0.5, max: 4), closeTo(5.4194, 0.0005));
    });
  });

  group('pan rubber band', () {
    test('keeps offsets inside the zoomed range', () {
      expect(rubberPan(-50, 100, 2), -50.0);
      expect(rubberPan(0, 100, 2), 0.0);
    });

    test('resists past the leading edge', () {
      expect(rubberPan(30, 100, 2), closeTo(14.163, 0.001));
    });

    test('resists past the trailing edge', () {
      expect(rubberPan(-130, 100, 2), closeTo(-114.163, 0.001));
    });
  });
}
