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

/// A boolean field, which the server sometimes sends as `0`/`1` or `"true"`.
bool _bool(Map<String, dynamic> json, String key) => switch (json[key]) {
  final bool value => value,
  final num value => value != 0,
  final String value => value.trim() == 'true',
  _ => false,
};

/// The objects in a list field; anything else is skipped.
List<Map<String, dynamic>> jsonObjects(Object? value) => [
  for (final item in value is List ? value : const [])
    if (item is Map<String, dynamic>) item,
];

/// The folder of a `folder/name.json` document path, or empty when it has none.
String docFolder(String path) {
  final cut = path.lastIndexOf('/');
  return cut < 0 ? '' : path.substring(0, cut);
}

/// The file name of a `folder/name.json` document path.
String docName(String path) => path.substring(path.lastIndexOf('/') + 1);

class Workspace {
  const Workspace({
    required this.slug,
    required this.name,
    this.threads = const [],
    this.documents = const [],
    this.prompt,
    this.settings,
  });

  factory Workspace.fromJson(Map<String, dynamic> json) {
    final slug = _text(json, 'slug');
    final prompt = json['openAiPrompt'];
    return Workspace(
      slug: slug,
      name: _known(json, 'name') ?? slug,
      prompt: prompt is String ? prompt : null,
      settings: WorkspaceSettings.fromJson(json),
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

  /// The workspace's own system prompt, or null when it has none and the default applies.
  final String? prompt;

  /// The answer settings, or null when the answer did not carry them.
  final WorkspaceSettings? settings;
}

/// How a setting's value is written: a whole number, any number, or text.
enum SettingType { integer, number, text }

/// One workspace setting: its type, the bounds of a number, and whether this app writes it.
class SettingSpec {
  const SettingSpec(this.type, {this.min = 0, this.max, this.writable = true});

  final SettingType type;
  final num min;
  final num? max;
  final bool writable;
}

/// The workspace settings Files shows, in the order it shows them. Each may be null on the
/// server, which means the system default. `chatMode` is never written: the app sends the answer
/// mode with each message.
const workspaceSettingSpecs = {
  'openAiTemp': SettingSpec(SettingType.number),
  'openAiHistory': SettingSpec(SettingType.integer),
  'topN': SettingSpec(SettingType.integer, min: 1),
  'similarityThreshold': SettingSpec(SettingType.number, max: 1),
  'chatProvider': SettingSpec(SettingType.text),
  'chatModel': SettingSpec(SettingType.text),
  'agentProvider': SettingSpec(SettingType.text),
  'agentModel': SettingSpec(SettingType.text),
  'vectorSearchMode': SettingSpec(SettingType.text),
  'queryRefusalResponse': SettingSpec(SettingType.text),
  'chatMode': SettingSpec(SettingType.text, writable: false),
};

/// A workspace's answer settings, by the server's column names in [workspaceSettingSpecs].
class WorkspaceSettings {
  const WorkspaceSettings(this.values);

  /// The settings in a workspace's JSON, or null when it holds none of them, as the list call.
  static WorkspaceSettings? fromJson(Map<String, dynamic> json) {
    if (!workspaceSettingSpecs.keys.any(json.containsKey)) return null;
    return WorkspaceSettings({
      for (final MapEntry(:key, value: spec) in workspaceSettingSpecs.entries)
        key: _setting(json[key], spec.type),
    });
  }

  /// Every key of [workspaceSettingSpecs], each a value of its type or null.
  final Map<String, Object?> values;

  static Object? _setting(Object? value, SettingType type) => switch (type) {
    SettingType.integer => switch (value) {
      final num n => n.toInt(),
      final String s => int.tryParse(s.trim()),
      _ => null,
    },
    SettingType.number => switch (value) {
      final num n => n,
      final String s => num.tryParse(s.trim()),
      _ => null,
    },
    SettingType.text => value is String ? value : null,
  };
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
  const WorkspaceDoc({
    required this.path,
    required this.title,
    this.words,
    this.pinned = false,
    this.watched = false,
  });

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
          docName(path),
      words: metadata == null ? null : _int(metadata, 'wordCount'),
      pinned: _bool(json, 'pinned'),
      watched: _bool(json, 'watched'),
    );
  }

  /// `folder/name.json`, the same as [DocEntry.path].
  final String path;
  final String title;
  final int? words;

  /// Whether its whole text is always in the workspace's context.
  final bool pinned;

  /// Whether the server re-reads it from its source.
  final bool watched;

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
      folder: docFolder(location),
      name: _known(json, 'name') ?? docName(location),
    );
  }

  final String folder;

  /// The stored file's name, such as `notes.md-1f2e.json`.
  final String name;

  /// `folder/name`: how a workspace names it.
  String get path => '$folder/$name';
}

/// A folder of the server's document library, the shared pool workspaces take documents from.
class LibraryFolder {
  const LibraryFolder({required this.name, this.files = const []});

  /// A folder entry of the `localFiles` tree; entries that are not files are skipped.
  factory LibraryFolder.fromJson(Map<String, dynamic> json) {
    final name = _text(json, 'name');
    return LibraryFolder(
      name: name,
      files: [
        for (final item in jsonObjects(json['items']))
          if (item['type'] == 'file') LibraryFile.fromJson(name, item),
      ],
    );
  }

  final String name;
  final List<LibraryFile> files;
}

/// A document in the library, as the server parsed it from an upload.
class LibraryFile {
  const LibraryFile({
    required this.folder,
    required this.name,
    required this.title,
  });

  factory LibraryFile.fromJson(String folder, Map<String, dynamic> json) {
    final name = _text(json, 'name');
    return LibraryFile(
      folder: folder,
      name: name,
      title: _known(json, 'title') ?? name,
    );
  }

  final String folder;

  /// The stored file's name, such as `notes.md-1f2e.json`.
  final String name;
  final String title;

  /// `folder/name`: how a workspace names it, the same as [WorkspaceDoc.path].
  String get path => '$folder/$name';
}

/// The folders of a `localFiles` tree, whose root is the `documents` folder itself.
List<LibraryFolder> libraryOf(Object? localFiles) => [
  if (localFiles is Map<String, dynamic>)
    for (final item in jsonObjects(localFiles['items']))
      if (item['type'] == 'folder') LibraryFolder.fromJson(item),
];

/// The document fields Files shows, in order, with their labels.
const docDetailLabels = {
  'docAuthor': 'Author',
  'description': 'Description',
  'docSource': 'Source',
  'chunkSource': 'Read from',
  'published': 'Published',
  'wordCount': 'Words',
  'token_count_estimate': 'Tokens (estimate)',
  'url': 'Address',
};

/// One library document as the server describes it on its own: its details and, when the server
/// sends it, its text.
class DocBody {
  const DocBody({required this.title, this.text, this.details = const {}});

  factory DocBody.fromJson(Map<String, dynamic> json) {
    final text = json['pageContent'];
    return DocBody(
      title: _known(json, 'title') ?? _text(json, 'name'),
      text: text is String ? text : null,
      details: {
        for (final key in docDetailLabels.keys) key: ?_known(json, key),
      },
    );
  }

  final String title;

  /// The parsed text, or null when the server left it out.
  final String? text;

  /// The known keys of [docDetailLabels], in its order.
  final Map<String, String> details;
}
