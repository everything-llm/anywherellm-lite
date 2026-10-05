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
    this.threads = const [],
    this.documents = const [],
  });

  factory Workspace.fromJson(Map<String, dynamic> json) {
    final slug = _text(json, 'slug');
    return Workspace(
      slug: slug,
      name: _known(json, 'name') ?? slug,
      threads: [
        for (final thread in jsonObjects(json['threads']))
          Thread.fromJson(thread),
      ],
      documents: [
        for (final doc in jsonObjects(json['documents']))
          WorkspaceDoc.fromJson(doc),
      ],
    );
  }

  final String slug;
  final String name;

  /// Named only when every workspace is read at once: the server leaves the names out when it
  /// answers for one.
  final List<Thread> threads;

  /// Only filled when the workspace was read on its own.
  final List<WorkspaceDoc> documents;
}

/// One chat in a workspace. The server calls it a thread.
class Thread {
  const Thread({required this.slug, required this.name});

  factory Thread.fromJson(Map<String, dynamic> json) =>
      Thread(slug: _text(json, 'slug'), name: _known(json, 'name') ?? 'Chat');

  final String slug;
  final String name;
}

enum Role { user, assistant }

/// One turn of a chat, as the server keeps it.
class ChatMessage {
  const ChatMessage({
    required this.role,
    required this.text,
    this.citations = const [],
  });

  /// An entry of a chat's `history`.
  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    role: json['role'] == 'user' ? Role.user : Role.assistant,
    text: switch (json['content']) {
      final String text => text,
      _ => '',
    },
    citations: citationsOf(json['sources']),
  );

  final Role role;
  final String text;

  /// The titles of the documents the answer drew on, each once, in the server's order.
  final List<String> citations;
}

/// The document titles in a `sources` list, each once.
List<String> citationsOf(Object? sources) =>
    {for (final source in jsonObjects(sources)) ?_known(source, 'title')}
        .toList();

/// A document a workspace holds.
class WorkspaceDoc {
  const WorkspaceDoc({required this.path, required this.title, this.words});

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
      words: metadata == null ? null : _int(metadata, 'wordCount'),
    );
  }

  /// `folder/name.json`, the same as [DocEntry.path].
  final String path;
  final String title;
  final int? words;

  static Map<String, dynamic>? _decode(String text) {
    try {
      final value = jsonDecode(text);
      return value is Map<String, dynamic> ? value : null;
    } on FormatException {
      return null;
    }
  }
}

/// A document the server made of an upload.
class DocEntry {
  const DocEntry({required this.folder, required this.name});

  /// An upload's result, whose `location` names the folder.
  factory DocEntry.fromJson(Map<String, dynamic> json) {
    final location = _text(json, 'location');
    return DocEntry(
      folder: _parent(location),
      name: _known(json, 'name') ?? _base(location),
    );
  }

  final String folder;

  /// The stored file's name, such as `notes.md-1f2e.json`.
  final String name;

  /// `folder/name`: how a workspace names it.
  String get path => '$folder/$name';
}
