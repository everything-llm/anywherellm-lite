// Sending a file to the server: what a file to send is, and which files the server reads.

/// A file to send. The UI wraps whatever the file picker or a drop gave it. [read] throws
/// [UnreadableFile] for something that cannot be read, such as a folder.
class UploadFile {
  const UploadFile({required this.name, required this.read});

  final String name;
  final Future<List<int>> Function() read;
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

/// The file type on a file's tile: its extension in capitals, four letters at most, or `FILE`.
String sourceExt(String name) {
  final extension = extensionOf(name).toUpperCase();
  if (extension.isEmpty) return 'FILE';
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
