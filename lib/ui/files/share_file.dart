import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

/// Hands the file [name], holding [bytes], to the system's share sheet: Android's, where
/// another app takes it.
Future<void> shareBytes(String name, List<int> bytes) async {
  await SharePlus.instance.share(
    ShareParams(
      files: [
        XFile.fromData(
          bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
          name: name,
        ),
      ],
      fileNameOverrides: [name],
    ),
  );
}
