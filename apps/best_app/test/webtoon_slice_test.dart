import 'package:best_app/src/ocr/ocr_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('webtoon slice keeps its source aspect ratio and file path', () {
    final slice = WebtoonSlice.fromMap({
      'index': 1,
      'top': 2048,
      'width': 800,
      'height': 409,
      'filePath': '/tmp/slice_1.jpg',
    });

    expect(slice.index, 1);
    expect(slice.top, 2048);
    expect(slice.width, 800);
    expect(slice.height, 409);
    expect(slice.filePath, '/tmp/slice_1.jpg');
    expect(slice.aspectRatio, closeTo(800 / 409, 0.0001));
  });

  test('webtoon slice tolerates missing fields', () {
    final slice = WebtoonSlice.fromMap(const {});

    expect(slice.index, 0);
    expect(slice.filePath, isEmpty);
    expect(slice.aspectRatio, 1);
  });
}
