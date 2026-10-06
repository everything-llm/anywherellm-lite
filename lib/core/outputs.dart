// What an answer made besides its text: files and images an agent generated.

/// A file or image an agent made with an answer. Its bytes come from the server by
/// [storageName], which the server gave it; [name] is what it is called for the person.
class GeneratedFile {
  const GeneratedFile({
    required this.type,
    required this.name,
    required this.storageName,
    this.size,
  });

  /// The server's kind of output, such as `imageGenerationCard` or `PdfFileDownload`.
  final String type;
  final String name;
  final String storageName;

  /// Its size in bytes, when the server gave one.
  final int? size;

  bool get isImage => type == 'imageGenerationCard';
}

/// The files in an answer's `outputs` list: each `{type, payload}` whose payload has a
/// `storageFilename` the server could have made, letters, digits, `_`, `.` and `-` only, so a
/// name can never reach outside the server's folder of generated files.
List<GeneratedFile> generatedFilesOf(Object? outputs) {
  if (outputs is! List) return const [];
  return [
    for (final output in outputs)
      if (output case {
        'type': final String type,
        'payload': final Map<String, dynamic> payload,
      })
        if (payload['storageFilename'] case final String storage
            when _storageName.hasMatch(storage))
          GeneratedFile(
            type: type,
            name: switch (payload['filename']) {
              final String name when name.trim().isNotEmpty => name.trim(),
              _ => storage,
            },
            storageName: storage,
            size: switch (payload['fileSize']) {
              final num size when size >= 0 => size.toInt(),
              _ => null,
            },
          ),
  ];
}

final _storageName = RegExp(r'^[\w.-]+$');

/// [bytes] in words: `812 B`, `14.2 KB` or `3.1 MB`.
String sizeText(int bytes) => switch (bytes) {
  < 1024 => '$bytes B',
  < 1024 * 1024 => '${(bytes / 1024).toStringAsFixed(1)} KB',
  _ => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB',
};
