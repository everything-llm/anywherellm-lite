import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker_platform_interface/file_picker_platform_interface.dart';

/// A picked file holding [bytes].
final class Picked extends PlatformFile {
  Picked(this.name, [List<int> bytes = const [1]])
    : bytes = Uint8List.fromList(bytes);

  @override
  final String name;
  final Uint8List bytes;

  @override
  Uri get uri => Uri.file('/picked/$name');

  @override
  XFile get xFile => XFile.fromData(bytes, path: name, length: bytes.length);

  @override
  int? lengthSync() => bytes.length;

  @override
  Future<int?> length() async => bytes.length;

  @override
  Future<Uint8List> readAsBytes() async => bytes;

  @override
  Stream<Uint8List> readAsByteStream() => Stream.value(bytes);
}

/// A file picker that picks [files], once [picked] completes when it is given.
class FakePicker extends FilePickerPlatform {
  FakePicker(this.files, {this.picked});

  List<PlatformFile> files;
  final Future<void>? picked;

  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    await picked;
    return files;
  }
}
