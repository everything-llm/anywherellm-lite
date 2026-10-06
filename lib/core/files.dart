// The server's data as one folder tree: what each node is, and the text a file node shows.
//
// The tree is a view. Every node is made from what the server answered; nothing in it is stored.

import 'dart:convert';

import 'chat.dart';
import 'errors.dart';
import 'server_models.dart';

/// What a node says about who owns it and whether it can be changed.
enum NodeBadge {
  /// Read from the server and written back through its API.
  none,

  /// Shown, but the API offers no way to change it.
  readOnly,

  /// Exists, but is never read: secrets and keys.
  locked,
}

enum NodeKind {
  root,
  workspaces,
  workspace,
  prompt,
  settings,
  docs,
  docLink,
  chats,
  chatLog,
  library,
  libraryFolder,
  libraryDoc,
  systemFolder,
  models,
  locked;

  bool get isFolder => switch (this) {
    root ||
    workspaces ||
    workspace ||
    docs ||
    chats ||
    library ||
    libraryFolder ||
    systemFolder => true,
    _ => false,
  };

  /// Whether the node's text can be edited and saved.
  bool get editable => this == prompt || this == settings;

  NodeBadge get badge => switch (this) {
    chatLog || models => NodeBadge.readOnly,
    locked => NodeBadge.locked,
    _ => NodeBadge.none,
  };
}

/// The tree path of library folder or document [ref].
String libraryPath(String ref) => '/library/$ref';

/// The tree path of workspace [slug]'s docs folder.
String docsPath(String slug) => '/workspaces/$slug/docs';

/// The tree path of workspace [slug]'s link to library document [ref].
String docLinkPath(String slug, String ref) => '${docsPath(slug)}/$ref';

/// Every folder path above [path], outermost first.
Iterable<String> ancestorsOf(String path) sync* {
  for (
    var cut = path.indexOf('/', 1);
    cut > 0;
    cut = path.indexOf('/', cut + 1)
  ) {
    yield path.substring(0, cut);
  }
}

/// One node of the tree. [path] is unique and stable across reloads; [name] is what is shown.
class FileNode {
  const FileNode({
    required this.path,
    required this.name,
    required this.kind,
    this.children = const [],
    this.slug,
    this.ref,
    this.pinned = false,
  });

  final String path;
  final String name;
  final NodeKind kind;
  final List<FileNode> children;

  /// A document link whose whole text is always in its workspace's context.
  final bool pinned;

  NodeBadge get badge => kind.badge;

  /// The workspace the node belongs to, when it belongs to one.
  final String? slug;

  /// What the node points at: a thread slug for a chat, a `folder/name.json` path for a
  /// document, a folder name for a library folder.
  final String? ref;
}

/// The whole tree. A workspace's prompt, settings and documents appear once its [details] are
/// read; its chats come from [threadsOf]. The library appears once [library] is read.
FileNode buildTree({
  required List<Workspace> workspaces,
  required List<Thread> Function(String slug) threadsOf,
  required Map<String, Workspace> details,
  required List<LibraryFolder>? library,
}) => FileNode(
  path: '/',
  name: '/',
  kind: NodeKind.root,
  children: [
    FileNode(
      path: '/workspaces',
      name: 'workspaces',
      kind: NodeKind.workspaces,
      children: [
        for (final w in workspaces)
          _workspace(w, threadsOf(w.slug), details[w.slug]),
      ],
    ),
    FileNode(
      path: '/library',
      name: 'library',
      kind: NodeKind.library,
      children: [
        for (final folder in library ?? const <LibraryFolder>[])
          FileNode(
            path: libraryPath(folder.name),
            name: folder.name,
            kind: NodeKind.libraryFolder,
            ref: folder.name,
            children: [
              for (final file in folder.files)
                FileNode(
                  path: libraryPath(file.path),
                  name: file.title,
                  kind: NodeKind.libraryDoc,
                  ref: file.path,
                ),
            ],
          ),
      ],
    ),
    const FileNode(
      path: '/settings',
      name: 'settings',
      kind: NodeKind.systemFolder,
      children: [
        FileNode(
          path: '/settings/models.json',
          name: 'models.json',
          kind: NodeKind.models,
        ),
      ],
    ),
    const FileNode(path: '/.env', name: '.env', kind: NodeKind.locked),
    const FileNode(path: '/keys', name: 'keys', kind: NodeKind.locked),
  ],
);

FileNode _workspace(Workspace w, List<Thread> threads, Workspace? detail) {
  final base = '/workspaces/${w.slug}';
  return FileNode(
    path: base,
    name: w.name,
    kind: NodeKind.workspace,
    slug: w.slug,
    children: [
      if (detail != null) ...[
        FileNode(
          path: '$base/PROMPT.md',
          name: 'PROMPT.md',
          kind: NodeKind.prompt,
          slug: w.slug,
        ),
        if (detail.settings != null)
          FileNode(
            path: '$base/settings.json',
            name: 'settings.json',
            kind: NodeKind.settings,
            slug: w.slug,
          ),
        FileNode(
          path: docsPath(w.slug),
          name: 'docs',
          kind: NodeKind.docs,
          slug: w.slug,
          children: [
            for (final doc in detail.documents)
              FileNode(
                path: docLinkPath(w.slug, doc.path),
                name: doc.title,
                kind: NodeKind.docLink,
                slug: w.slug,
                ref: doc.path,
                pinned: doc.pinned,
              ),
          ],
        ),
      ],
      FileNode(
        path: '$base/chats',
        name: 'chats',
        kind: NodeKind.chats,
        slug: w.slug,
        children: [
          for (final t in threads)
            FileNode(
              path: '$base/chats/${t.slug}',
              name: '${t.name}.md',
              kind: NodeKind.chatLog,
              slug: w.slug,
              ref: t.slug,
            ),
        ],
      ),
    ],
  );
}

/// The node at [path] under [root], or null when there is none.
FileNode? nodeAt(FileNode root, String path) {
  if (root.path == path) return root;
  for (final child in root.children) {
    if (path == child.path || path.startsWith('${child.path}/')) {
      final found = nodeAt(child, path);
      if (found != null) return found;
    }
  }
  return null;
}

/// A chat as Markdown: its name as the heading, then each turn with the sources it cited.
String chatMarkdown(String name, List<ChatMessage> turns) {
  final out = StringBuffer('# $name\n');
  for (final turn in turns) {
    out
      ..write('\n**${turn.role == Role.user ? 'You' : 'Answer'}**\n\n')
      ..write('${splitReasoning(turn.text).answer}\n');
    if (turn.citations.isNotEmpty) {
      final sources = [
        for (final c in turn.citations)
          c.url == null ? c.title : '[${c.title}](${c.url})',
      ];
      out.write('\nSources: ${sources.join(', ')}\n');
    }
  }
  return out.toString();
}

const _indented = JsonEncoder.withIndent('  ');

final _secretKey = RegExp('key|secret|token|password', caseSensitive: false);

/// [settings] as the JSON Files shows and edits.
String settingsText(WorkspaceSettings settings) =>
    '${_indented.convert(settings.values)}\n';

/// The settings in [text] that differ from [was], ready to write. Throws [ApiException] when the
/// text is not a JSON object, names a setting Files does not know, gives one a value of the
/// wrong type or range, or changes one this app never writes.
Map<String, Object?> parseSettings(String text, WorkspaceSettings was) {
  final Object? json;
  try {
    json = jsonDecode(text);
  } on FormatException catch (error) {
    throw ApiException('The settings are not valid JSON: ${error.message}');
  }
  if (json is! Map<String, dynamic>) {
    throw const ApiException('The settings must be one JSON object.');
  }
  final changed = <String, Object?>{};
  for (final MapEntry(:key, :value) in json.entries) {
    final spec = workspaceSettingSpecs[key];
    if (spec == null) throw ApiException('$key is not a workspace setting.');
    _check(key, spec, value);
    if (value == was.values[key]) continue;
    changed[key] = value;
  }
  return changed;
}

void _check(String key, SettingSpec spec, Object? value) {
  if (value == null) return;
  if (spec.type == SettingType.text) {
    final choices = spec.choices;
    if (value is String && (choices == null || choices.contains(value))) {
      return;
    }
    throw ApiException(
      choices == null
          ? '$key must be text or null.'
          : '$key must be one of ${choices.join(', ')}.',
    );
  }
  final whole = spec.type == SettingType.integer;
  final max = spec.max;
  if ((whole ? value is int : value is num) &&
      (value as num) >= spec.min &&
      (max == null || value <= max)) {
    return;
  }
  final range = max == null
      ? 'of at least ${spec.min}'
      : 'from ${spec.min} to $max';
  throw ApiException(
    '$key must be ${whole ? 'a whole number' : 'a number'} $range.',
  );
}

/// The provider and model names in the server's [settings], as JSON. Only keys that name a
/// provider, a model, an engine or the vector database are kept, and never one that names a key,
/// secret, token or password, whatever its value.
String modelsText(Map<String, Object?> settings) {
  bool shown(String key) =>
      !_secretKey.hasMatch(key) &&
      (key == 'VectorDB' ||
          key.endsWith('Provider') ||
          key.endsWith('ModelPref') ||
          key.endsWith('Engine'));
  final kept = {
    for (final key in settings.keys.toList()..sort())
      if (shown(key) && settings[key] is String) key: settings[key],
  };
  return '${_indented.convert(kept)}\n';
}
