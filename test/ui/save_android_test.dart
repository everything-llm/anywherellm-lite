import 'dart:typed_data';

import 'package:anywherellm/ui/files/save_android.dart';
import 'package:file_picker_platform_interface/file_picker_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

/// A save dialog that answers [place] for whatever is saved.
class _Picker extends FilePickerPlatform {
  _Picker(this.place);

  final Uri? place;

  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async => place;
}

Future<String?> saved(Uri? place) {
  FilePickerPlatform.instance = _Picker(place);
  return saveWithPicker('notes.txt', () async => [1, 2, 3]);
}

void main() {
  test('names where a document went, as its id says', () async {
    expect(
      await saved(
        Uri.parse(
          'content://com.android.externalstorage.documents/document/'
          'primary%3ADownload%2Fnotes.txt',
        ),
      ),
      'primary:Download/notes.txt',
    );
  });

  test('a name with a percent sign in it is named whole', () async {
    expect(
      await saved(
        Uri.parse(
          'content://com.android.externalstorage.documents/document/'
          'primary%3ADownload%2F100%25%20done.txt',
        ),
      ),
      'primary:Download/100% done.txt',
    );
  });

  test('a cancelled dialog saves nothing', () async {
    expect(await saved(null), isNull);
  });
}
