import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

class PickedDocument {
  const PickedDocument({required this.name, required this.openRead, this.length});
  final String name;
  final int? length;
  final Stream<List<int>> Function() openRead;
}

/// The only entry point for user-selected external files. Reading is bounded
/// even when a document provider cannot report its size ahead of time.
class DocumentPickerClient {
  const DocumentPickerClient();

  Future<PickedDocument?> pick(List<String> extensions) async {
    final file = await FilePicker.pickFile(type: FileType.custom,
        allowedExtensions: extensions);
    if (file == null) return null;
    return PickedDocument(name: file.name, length: await file.length(),
        openRead: file.readAsByteStream);
  }

  Future<Uint8List> readBounded(PickedDocument document,
      {required int maximumBytes}) async {
    if ((document.length ?? 0) > maximumBytes) {
      throw const FormatException('The selected file is too large.');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in document.openRead()
        .timeout(const Duration(seconds: 30))) {
      if (bytes.length + chunk.length > maximumBytes) {
        throw const FormatException('The selected file is too large.');
      }
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }
}
