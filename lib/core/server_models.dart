// What the AnythingLLM API answers. Field names follow its responses; every field is read
// defensively, since the server's answers do not always match its own schema.

import 'dart:convert';

/// A string or number field as text, trimmed, or empty when it is missing.
String _text(Map<String, dynamic> json, String key) => switch (json[key]) {
  final String value => value.trim(),
  final num value => '$value',
  _ => '',
};

/// A text field, or null when it is missing, empty or the server's own `Unknown` placeholder.
String? _known(Map<String, dynamic> json, String key) {
  final value = _text(json, key);
  return value.isEmpty || value == 'Unknown' ? null : value;
}

int? _int(Map<String, dynamic> json, String key) => switch (json[key]) {
  final num value => value.toInt(),
  final String value => int.tryParse(value.trim()),
  _ => null,
};

/// The objects in a list field; anything else is skipped.
List<Map<String, dynamic>> jsonObjects(Object? value) => [
  for (final item in value is List ? value : const [])
    if (item is Map<String, dynamic>) item,
];

/// [path] with its last `/` and what follows removed, or empty when it has none.
String _parent(String path) {
  final cut = path.lastIndexOf('/');
  return cut < 0 ? '' : path.substring(0, cut);
}

String _base(String path) => path.substring(path.lastIndexOf('/') + 1);

class Workspace {
  const Workspace({
    required this.slug,
    required this.name,
    this.chatModel,
    this.threads = 0,
    this.documents = const [],
  });

  factory Workspace.fromJson(Map<String, dynamic> json) {
    final slug = _text(json, 'slug');
    return Workspace(
      slug: slug,
      name: _known(json, 'name') ?? slug,
      chatModel: _known(json, 'chatModel'),
      threads: jsonObjects(json['threads']).length,
      documents: [
        for (final doc in jsonObjects(json['documents']))
          WorkspaceDoc.fromJson(doc),
      ],
    );
  }

  final String slug;
  final String name;

  /// Null when the workspace uses the server's default model.
  final String? chatModel;
  final int threads;

  /// Only filled when the workspace was read on its own.
  final List<WorkspaceDoc> documents;
}

/// A document a workspace holds.
class WorkspaceDoc {
  const WorkspaceDoc({required this.path, required this.title});

  /// The `metadata` field is the document's own JSON as a string.
  factory WorkspaceDoc.fromJson(Map<String, dynamic> json) {
    final path = _text(json, 'docpath');
    final metadata = switch (json['metadata']) {
      final String text => _decode(text),
      _ => null,
    };
    return WorkspaceDoc(
      path: path,
      title:
          (metadata == null ? null : _known(metadata, 'title')) ??
          _known(json, 'filename') ??
          _base(path),
    );
  }

  /// `folder/name.json`, the same as [DocEntry.path].
  final String path;
  final String title;

  static Map<String, dynamic>? _decode(String text) {
    try {
      final value = jsonDecode(text);
      return value is Map<String, dynamic> ? value : null;
    } on FormatException {
      return null;
    }
  }
}

/// A folder of documents on the server.
class DocFolder {
  const DocFolder({required this.name, required this.docs});

  factory DocFolder.fromJson(Map<String, dynamic> json) {
    final name = _text(json, 'name');
    return DocFolder(
      name: name,
      docs: [
        for (final item in jsonObjects(json['items']))
          if (item['type'] != 'folder') DocEntry.fromJson(item, folder: name),
      ],
    );
  }

  final String name;
  final List<DocEntry> docs;
}

/// A document the server has read in. The server keeps its text but its API does not return it.
class DocEntry {
  const DocEntry({
    required this.folder,
    required this.name,
    required this.title,
    this.description,
    this.author,
    this.source,
    this.published,
    this.words,
    this.tokens,
  });

  /// The folder is [folder] when the answer is a folder's listing, and comes from `location`
  /// when it is an upload's result.
  factory DocEntry.fromJson(Map<String, dynamic> json, {String? folder}) {
    final location = _text(json, 'location');
    final name = _known(json, 'name') ?? _base(location);
    return DocEntry(
      folder: folder ?? _parent(location),
      name: name,
      title: _known(json, 'title') ?? name,
      description: _known(json, 'description'),
      author: _known(json, 'docAuthor'),
      source: _known(json, 'docSource'),
      // A locale string such as "10/5/2026, 11:48:20 AM", not the epoch the schema promises.
      // Shown as the server wrote it.
      published: _known(json, 'published'),
      words: _int(json, 'wordCount'),
      tokens: _int(json, 'token_count_estimate'),
    );
  }

  final String folder;

  /// The stored file's name, such as `notes.md-1f2e.json`.
  final String name;
  final String title;
  final String? description;
  final String? author;
  final String? source;
  final String? published;
  final int? words;
  final int? tokens;

  /// `folder/name`: how a workspace names it, and the app's route to it.
  String get path => '$folder/$name';
}
