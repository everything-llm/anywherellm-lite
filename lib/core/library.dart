import 'chat.dart' show attachmentMime, documentMime;
import 'json.dart';
import 'outputs.dart';
import 'server_models.dart' show jsonObjects;

/// An app the agent made in a workspace, as the toolkit's Library lists it: its [title], the
/// root-relative [page] it is served at, the [workspace] it belongs to and the one line, [change],
/// that says what changed in it last, and when ([changed]). Never what the app holds now.
class LibraryApp {
  const LibraryApp({
    required this.title,
    required this.page,
    this.workspace,
    this.workspaceSlug,
    this.changed,
    this.change = '',
  });

  /// An app as the toolkit lists it, or null without a title or a page that starts at the root.
  static LibraryApp? fromJson(Map<String, dynamic> json) {
    final title = json['title'];
    final page = json['page'];
    if (title is! String || title.isEmpty) return null;
    if (page is! String || !page.startsWith('/')) return null;
    return LibraryApp(
      title: title,
      page: page,
      workspace: textOrNull(json['workspace']),
      workspaceSlug: textOrNull(json['workspaceSlug']),
      changed: timeOrNull(json['changed']),
      change: textOrNull(json['change']) ?? '',
    );
  }

  final String title;
  final String page;
  final String? workspace;
  final String? workspaceSlug;
  final DateTime? changed;
  final String change;

  /// Whether the app belongs to the workspace [slug].
  bool isIn(String? slug) => _isIn(slug, workspaceSlug, workspace);
}

/// A file the agent made, as the toolkit's Library lists it: the [file] to read from the server,
/// the [workspace] it was made in and when ([created]).
class LibraryFile {
  const LibraryFile({
    required this.file,
    this.workspace,
    this.workspaceSlug,
    this.created,
  });

  /// A file as the toolkit lists it, or null without a name the server's folder of generated
  /// files could hold. Without a `type`, a picture's name makes it an image.
  static LibraryFile? fromJson(Map<String, dynamic> json) {
    final storage = json['storageFilename'];
    final name = json['name'];
    final file = generatedFilesOf([
      {
        'type': switch (json['type']) {
          final String type when type.isNotEmpty => type,
          _ when storage is String && attachmentMime(storage) != documentMime =>
            'imageGenerationCard',
          _ => 'file',
        },
        'payload': {
          'filename': name,
          'storageFilename': storage,
          'fileSize': json['size'],
        },
      },
    ]).firstOrNull;
    if (file == null) return null;
    return LibraryFile(
      file: file,
      workspace: textOrNull(json['workspace']),
      workspaceSlug: textOrNull(json['workspaceSlug']),
      created: timeOrNull(json['createdAt']),
    );
  }

  final GeneratedFile file;
  final String? workspace;
  final String? workspaceSlug;
  final DateTime? created;

  /// Whether the file was made in the workspace [slug].
  bool isIn(String? slug) => _isIn(slug, workspaceSlug, workspace);
}

/// Whether what the toolkit placed in [workspaceSlug], or in [workspace] where it gave no slug,
/// is in the workspace [slug].
bool _isIn(String? slug, String? workspaceSlug, String? workspace) =>
    slug != null && (workspaceSlug ?? workspace) == slug;

/// What the toolkit's Library holds: the apps and the files.
class LibraryContents {
  const LibraryContents({this.apps = const [], this.files = const []});

  final List<LibraryApp> apps;
  final List<LibraryFile> files;
}

/// The Library in a toolkit's answer: `apps` and `files` objects, each kept when it is whole.
LibraryContents libraryOf(Object? json) => json is! Map
    ? const LibraryContents()
    : LibraryContents(
        apps: [
          for (final app in jsonObjects(json['apps']))
            ?LibraryApp.fromJson(app),
        ],
        files: [
          for (final file in jsonObjects(json['files']))
            ?LibraryFile.fromJson(file),
        ],
      );
