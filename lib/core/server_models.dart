// What the AnythingLLM API answers. Field names follow its responses; every field is read
// defensively, since the server's answers do not always match its own schema.

import 'dart:typed_data';

import 'chat.dart';
import 'json.dart';
import 'outputs.dart';

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

/// [value] as a whole number when it is one or a number as text, or else null.
int? _asInt(Object? value) => switch (value) {
  final num n => n.toInt(),
  final String s => int.tryParse(s.trim()),
  _ => null,
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

  /// This workspace under the name [name].
  Workspace withName(String name) => Workspace(
    slug: slug,
    name: name,
    threads: threads,
    documents: documents,
    prompt: prompt,
    settings: settings,
  );

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

/// One workspace setting: its type, the bounds of a number, and the only values text may take,
/// when it has a fixed set.
class SettingSpec {
  const SettingSpec(this.type, {this.min = 0, this.max, this.choices});

  final SettingType type;
  final num min;
  final num? max;
  final List<String>? choices;
}

/// The workspace settings Files shows, in the order it shows them. Each may be null on the
/// server, which means the system default.
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
  'chatMode': SettingSpec(
    SettingType.text,
    choices: ['automatic', 'chat', 'query'],
  ),
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
    SettingType.integer => _asInt(value),
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

/// A file sent with a question: its name, and for a picture, its bytes.
class SentFile {
  /// A file known by its [name] alone, such as a document.
  SentFile(this.name);

  /// A picture whose [bytes] are at hand, as when it was just sent.
  SentFile.picture(this.name, Uint8List bytes) : _bytes = bytes;

  SentFile._saved(this.name, this._dataUrl);

  /// An entry of a history message's `attachments`, or null when it has no name. A picture keeps
  /// its `contentString` data URL, decoded the first time [picture] is read, so reading a history
  /// for anything else costs nothing.
  static SentFile? fromJson(Map<String, dynamic> json) {
    final name = _known(json, 'name');
    if (name == null) return null;
    return _text(json, 'mime').startsWith('image/')
        ? SentFile._saved(name, _text(json, 'contentString'))
        : SentFile(name);
  }

  final String name;
  Uint8List? _bytes;

  /// A history picture's data URL until [picture] decodes it, so the text is not kept beside
  /// the bytes.
  String? _dataUrl;

  /// The picture's bytes, or null for any other file and for a data URL that is not a base64
  /// image.
  Uint8List? get picture {
    if (_dataUrl case final dataUrl?) {
      _dataUrl = null;
      _bytes = _decode(dataUrl);
    }
    return _bytes;
  }

  static Uint8List? _decode(String dataUrl) {
    try {
      final data = UriData.parse(dataUrl);
      return data.isBase64 && data.mimeType.startsWith('image/')
          ? data.contentAsBytes()
          : null;
    } on FormatException {
      return null;
    }
  }
}

/// One turn of a chat, as the server keeps it.
class ChatMessage {
  const ChatMessage({
    required this.role,
    required this.text,
    this.citations = const [],
    this.attachments = const [],
    this.files = const [],
    this.metrics,
    this.chatId,
  });

  /// An entry of a chat's `history`.
  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    role: json['role'] == 'user' ? Role.user : Role.assistant,
    text: switch (json['content']) {
      final String text => text,
      _ => '',
    },
    citations: citationsOf(json['sources']),
    attachments: [
      for (final attachment in jsonObjects(json['attachments']))
        ?SentFile.fromJson(attachment),
    ],
    files: generatedFilesOf(json['outputs']),
    metrics: metricsOf(json['metrics']),
    chatId: switch (json['chatId']) {
      final int id => id,
      _ => null,
    },
  );

  final Role role;
  final String text;

  /// The files sent with the message.
  final List<SentFile> attachments;

  /// What the answer drew on, each once, in the server's order.
  final List<Citation> citations;

  /// What an agent made with the answer.
  final List<GeneratedFile> files;

  /// How the answer ran, when the server measured it.
  final AnswerMetrics? metrics;

  /// The server's id for the exchange; a question and its answer share it.
  final int? chatId;
}

/// A passage of a document an answer read: its [text], and how close it was to the question,
/// [score] from 0 to 1, when the server said.
class Passage {
  const Passage(this.text, {this.score});

  final String text;
  final double? score;
}

/// A source an answer drew on: a document by its [title], with the [passages] the answer read
/// from it, or a web page an agent read, which also has its [url].
class Citation {
  const Citation(this.title, {this.url, this.passages = const []});

  final String title;
  final Uri? url;

  /// Closest first, those with a score before those without.
  final List<Passage> passages;
}

/// The sources in a `sources` list, each once: a web page once per address, and a source with
/// no address once per title, holding each passage of it the list has. A web page's address is
/// its `chunkSource` after `link://`, as `link://https://example.com/page`; a document has
/// none. A passage's `text` starts with a `<document_metadata>` block, which is dropped, and
/// its `score` is kept only from 0 to 1.
List<Citation> citationsOf(Object? sources) {
  if (sources is! List || sources.isEmpty) return const [];
  // Each title's passages, filled as the list is read; a page's stays empty.
  final cited = <(String, Uri?, List<Passage>)>[];
  final byTitle = <String, List<Passage>>{};
  final pages = <Uri>{};
  final pageTitles = <String>{};
  for (final source in jsonObjects(sources)) {
    final title = _known(source, 'title');
    if (title == null) continue;
    final link = _linkOf(source['chunkSource']);
    final page = link == null ? null : Uri.tryParse(link);
    if (page != null && isWebAddress(page)) {
      if (pages.add(page)) {
        pageTitles.add(title);
        cited.add((title, page, const []));
      }
      continue;
    }
    if (pageTitles.contains(title)) continue;
    final passages = byTitle.putIfAbsent(title, () {
      final passages = <Passage>[];
      cited.add((title, null, passages));
      return passages;
    });
    final text = source['text'] is String
        ? (source['text'] as String).replaceFirst(_metadataBlock, '').trim()
        : '';
    if (text.isEmpty) continue;
    passages.add(
      Passage(
        text,
        score: switch (source['score']) {
          final num n when n >= 0 && n <= 1 => n.toDouble(),
          _ => null,
        },
      ),
    );
  }
  return [
    for (final (title, url, passages) in cited)
      Citation(title, url: url, passages: _closestFirst(passages)),
  ];
}

/// [passages] with a score, highest first, then those without, each in the order given.
List<Passage> _closestFirst(List<Passage> passages) {
  final scored = [
    for (final p in passages)
      if (p.score != null) p,
  ];
  // List.sort is not stable, so ties keep their order through their index.
  final order = {for (final (i, p) in scored.indexed) p: i};
  scored.sort((a, b) {
    final by = b.score!.compareTo(a.score!);
    return by != 0 ? by : order[a]!.compareTo(order[b]!);
  });
  return List.unmodifiable([
    ...scored,
    for (final p in passages)
      if (p.score == null) p,
  ]);
}

/// The address a document was read from, after the `link://` of its [chunkSource], or null for
/// one that was not read from a link.
String? _linkOf(Object? chunkSource) =>
    chunkSource is String && chunkSource.startsWith('link://')
    ? chunkSource.substring('link://'.length)
    : null;

/// A document a workspace holds.
class WorkspaceDoc {
  const WorkspaceDoc({
    required this.path,
    required this.title,
    this.words,
    this.web,
  });

  /// The `metadata` field is the document's own JSON as a string. Its `chunkSource` is
  /// `link://<url>` for a web page and empty for any other document.
  factory WorkspaceDoc.fromJson(Map<String, dynamic> json) {
    final path = _text(json, 'docpath');
    final metadata = switch (json['metadata']) {
      final String text => switch (jsonOrNull(text)) {
        final Map<String, dynamic> map => map,
        _ => null,
      },
      _ => null,
    };
    return WorkspaceDoc(
      path: path,
      title:
          (metadata == null ? null : _known(metadata, 'title')) ??
          _known(json, 'filename') ??
          docName(path),
      words: _asInt(metadata?['wordCount']),
      web: switch (metadata?['chunkSource']) {
        final String source => _linkOf(source) != null,
        _ => null,
      },
    );
  }

  /// `folder/name.json`, the same as [DocEntry.path].
  final String path;
  final String title;
  final int? words;

  /// Whether it is a web page, or null when its metadata does not say.
  final bool? web;
}

/// The details the server keeps with a document, given when it is added. An empty field is left
/// for the server to fill.
class DocMeta {
  const DocMeta({
    this.title = '',
    this.author = '',
    this.description = '',
    this.source = '',
  });

  final String title;
  final String author;
  final String description;
  final String source;

  bool get isEmpty => toJson().isEmpty;

  /// The fields that are not blank, trimmed, under the server's `metadata` keys.
  Map<String, String> toJson() => {
    for (final (key, value) in [
      ('title', title),
      ('docAuthor', author),
      ('description', description),
      ('docSource', source),
    ])
      if (value.trim().isNotEmpty) key: value.trim(),
  };
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

/// One library document as the server describes it on its own: its title and, when the server
/// sends it, its text.
class DocBody {
  const DocBody({required this.title, this.text});

  factory DocBody.fromJson(Map<String, dynamic> json) {
    final text = json['pageContent'];
    return DocBody(
      title: _known(json, 'title') ?? _text(json, 'name'),
      text: text is String ? text : null,
    );
  }

  final String title;

  /// The parsed text, or null when the server left it out.
  final String? text;
}

final _metadataBlock = RegExp(
  r'^\s*<document_metadata>[\s\S]*?</document_metadata>\s*',
);

/// A passage of a workspace's documents that a question finds, as an answer would get it.
class SearchHit {
  const SearchHit({
    required this.title,
    required this.text,
    required this.score,
  });

  /// The `metadata` holds the document's title; [score] is from 0 to 1, higher is closer. The
  /// server starts each passage's `text` with a `<document_metadata>` block, which is dropped.
  factory SearchHit.fromJson(Map<String, dynamic> json) {
    final metadata = json['metadata'];
    final score = json['score'];
    return SearchHit(
      title:
          (metadata is Map<String, dynamic>
              ? _known(metadata, 'title')
              : null) ??
          'Untitled',
      text: json['text'] is String
          ? (json['text'] as String).replaceFirst(_metadataBlock, '')
          : '',
      score: score is num ? score.toDouble() : 0,
    );
  }

  final String title;
  final String text;
  final double score;
}
