import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// The [FileSaver] the app uses on Android: the system's own save dialog, through the storage
/// access framework. The dialog takes the bytes with it, so the file is fetched before it opens;
/// cancelling it saves nothing. Returns where the file went, as the person would name it.
Future<String?> saveWithPicker(
  String suggestedName,
  Future<List<int>?> Function() bytes,
) async {
  final data = await bytes();
  if (data == null) return null;
  final place = await FilePicker.saveFile(
    fileName: suggestedName,
    bytes: data is Uint8List ? data : Uint8List.fromList(data),
  );
  if (place == null) return null;
  return switch (place.scheme) {
    'file' => place.toFilePath(),
    // A document's id, such as `primary:Download/notes.txt`, already decoded: a name with `%`
    // in it would not survive a second decoding.
    _ when place.pathSegments.isNotEmpty => place.pathSegments.last,
    _ => suggestedName,
  };
}
