// The workspaces' prompts, settings and documents as one folder tree, and the text a file node
// shows.
//
// The tree is a view. Every node is made from what the server answered; nothing in it is stored.

import 'dart:convert';

import 'errors.dart';
import 'server_models.dart';

enum NodeKind {
  root,
  workspaces,
  workspace,
  prompt,
  settings,
  docs,
  docLink;

  bool get isFolder => switch (this) {
    root || workspaces || workspace || docs => true,
    _ => false,
  };

  /// Whether the node's text can be edited and saved.
  bool get editable => this == prompt || this == settings;
}

/// The tree path of workspace [slug]'s docs folder.
String docsPath(String slug) => '/workspaces/$slug/docs';

/// The tree path of workspace [slug]'s link to library document [ref].
String docLinkPath(String slug, String ref) => '${docsPath(slug)}/$ref';

/// The tree path of workspace [slug]'s prompt.
String promptPath(String slug) => '/workspaces/$slug/PROMPT.md';

/// The tree path of workspace [slug]'s answer settings.
String settingsPath(String slug) => '/workspaces/$slug/settings.json';

/// The pages of the open workspace. Each shows a node of the tree under a plain name.
enum FilesSection {
  documents('Documents'),
  instructions('Instructions'),
  answers('Answer settings');

  const FilesSection(this.title);

  final String title;

  /// The tree path of what the section shows in workspace [slug].
  String pathIn(String slug) => switch (this) {
    documents => docsPath(slug),
    instructions => promptPath(slug),
    answers => settingsPath(slug),
  };
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

  /// The workspace the node belongs to, when it belongs to one.
  final String? slug;

  /// What the node points at: a `folder/name.json` path for a document.
  final String? ref;
}

/// The whole tree: each workspace, whose prompt, settings and documents appear once its
/// [details] are read.
FileNode buildTree({
  required List<Workspace> workspaces,
  required Map<String, Workspace> details,
}) => FileNode(
  path: '/',
  name: '/',
  kind: NodeKind.root,
  children: [
    FileNode(
      path: '/workspaces',
      name: 'workspaces',
      kind: NodeKind.workspaces,
      children: [for (final w in workspaces) _workspace(w, details[w.slug])],
    ),
  ],
);

FileNode _workspace(Workspace w, Workspace? detail) {
  final base = '/workspaces/${w.slug}';
  return FileNode(
    path: base,
    name: w.name,
    kind: NodeKind.workspace,
    slug: w.slug,
    children: [
      if (detail != null) ...[
        FileNode(
          path: promptPath(w.slug),
          name: 'PROMPT.md',
          kind: NodeKind.prompt,
          slug: w.slug,
        ),
        if (detail.settings != null)
          FileNode(
            path: settingsPath(w.slug),
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

final _notInFileName = RegExp(r'[\x00-\x1f/\\:*?"<>|]');

final _plainText = RegExp(r'\.(txt|md|markdown)$', caseSensitive: false);

/// The name a document called [title] is saved under by default: the title with any character a
/// file name cannot hold made `-`, ending in `.txt` unless it already names a plain-text file.
/// The saved file holds the text the server read, so `report.pdf` becomes `report.pdf.txt`.
String textFileName(String title) {
  final name = title.replaceAll(_notInFileName, '-').trim();
  if (name.isEmpty) return 'document.txt';
  return _plainText.hasMatch(name) ? name : '$name.txt';
}

const _indented = JsonEncoder.withIndent('  ');

/// [settings] as the JSON the answer settings are saved through.
String settingsText(WorkspaceSettings settings) =>
    '${_indented.convert(settings.values)}\n';

/// The settings in [text] that differ from [was], ready to write. Throws [ApiException] when the
/// text is not a JSON object, names a setting the app does not know, or gives one a value of the
/// wrong type or range.
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
    if (value == was.values[key]) continue;
    _check(key, spec, value);
    changed[key] = value;
  }
  return changed;
}

void _check(String key, SettingSpec spec, Object? value) {
  final choices = spec.choices;
  if (value == null && choices == null) return;
  if (spec.type == SettingType.text) {
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
