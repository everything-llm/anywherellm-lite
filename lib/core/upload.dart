// Sending a file to the server: what a file to send is, and which files the server reads.

import 'ports.dart';
import 'server_models.dart';

/// A file to send, with the [meta] to keep with it. The UI wraps whatever the file picker or a
/// drop gave it. [read] throws [UnreadableFile] for something that cannot be read, such as a
/// folder.
class UploadFile {
  const UploadFile({
    required this.name,
    required this.read,
    this.meta = const DocMeta(),
  });

  final String name;
  final Future<List<int>> Function() read;
  final DocMeta meta;

  UploadFile withMeta(DocMeta meta) =>
      UploadFile(name: name, read: read, meta: meta);
}

/// Why a dropped or picked file could not be read, in the system's words.
class UnreadableFile implements Exception {
  const UnreadableFile(this.message);
  final String message;

  @override
  String toString() => message;
}

/// `.md` for `notes.MD`, or empty for a name with no extension, such as `Makefile` or
/// `.bashrc`.
String extensionOf(String name) {
  final dot = name.lastIndexOf('.');
  return dot <= 0 ? '' : name.substring(dot).toLowerCase();
}

final _extension = RegExp(r'^\.(?=[0-9]*[A-Z])[A-Z0-9]+$');

/// The file type on a file's tile: the extension of [name] in capitals, four letters at most, or
/// `FILE` when it has none or what follows the last dot is not one, as in `notes.v2-final` or
/// `Version 2.0`.
String sourceExt(String name) {
  final extension = extensionOf(name).toUpperCase();
  if (!_extension.hasMatch(extension)) return 'FILE';
  return extension.length > 5
      ? extension.substring(1, 5)
      : extension.substring(1);
}

/// Why the server will not read [name], or null. Null [accepted] means the server has not said,
/// so it decides.
String? extensionProblem(String name, Set<String>? accepted) {
  final extension = extensionOf(name);
  if (accepted == null || accepted.contains(extension)) return null;
  return extension.isEmpty
      ? 'the file has no extension, so the server cannot tell what it is'
      : 'the server does not read $extension files';
}

/// What [sendEach] made: the documents the server made, and each file it could not add with why.
typedef Sent = ({List<DocEntry> made, List<(String name, String why)> refused});

/// Sends each of [picked] in turn into the library [folder], or the server's default one when it
/// is null, and keeps going past a file that cannot be added. [accepted] are the extensions the
/// server reads, or null to let it decide. [onSending] hears each file's name as it goes.
/// Stops before reading or sending another file when [shouldContinue] returns false.
Future<Sent> sendEach(
  AnythingLlmApi api,
  List<UploadFile> picked, {
  Set<String>? accepted,
  String? folder,
  void Function(String name)? onSending,
  bool Function()? shouldContinue,
}) async {
  final made = <DocEntry>[];
  final refused = <(String, String)>[];
  for (final file in picked) {
    if (shouldContinue?.call() == false) break;
    onSending?.call(file.name);
    try {
      final wrongType = extensionProblem(file.name, accepted);
      if (wrongType != null) throw ApiException(wrongType);
      final bytes = await file.read();
      if (shouldContinue?.call() == false) break;
      made.addAll(
        await api.upload(file.name, bytes, meta: file.meta, folder: folder),
      );
    } on Exception catch (error) {
      if (error is! ApiException && error is! UnreadableFile) rethrow;
      refused.add((file.name, '$error'));
    }
  }
  return (made: made, refused: refused);
}

/// Why [text] is not a web address the server can read in, or null.
String? linkProblem(String text) {
  final uri = Uri.tryParse(text.trim());
  if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
    return 'a link starts with https:// or http://';
  }
  if (uri.host.isEmpty) return 'the link has no site in it';
  return null;
}
