import 'package:best_app/src/imports/document_picker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const picker = DocumentPickerClient();
  test('known oversized files are rejected before reading', () async {
    var read = false;
    final document = PickedDocument(name: 'large.srt', length: 100,
      openRead: () { read = true; return Stream.value([1]); });
    await expectLater(picker.readBounded(document, maximumBytes: 10),
        throwsFormatException);
    expect(read, isFalse);
  });
  test('unknown-size streams are still bounded', () async {
    final document = PickedDocument(name: 'unknown.srt',
      openRead: () => Stream.fromIterable([[1, 2, 3], [4, 5, 6]]));
    await expectLater(picker.readBounded(document, maximumBytes: 4),
        throwsFormatException);
  });
}
