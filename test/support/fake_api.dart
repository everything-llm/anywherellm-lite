import 'package:everything/core/connection.dart';
import 'package:everything/core/ports.dart';
import 'package:everything/core/server_models.dart';

/// A connection for tests that need a server set up.
const sampleConnection = Connection(baseUrl: 'https://h:3001', apiKey: 'K1');

/// An [AnythingLlmApi] for widget tests. Set the fields to change what it answers, and put an
/// error in [errors] under a method's name to make it fail. Every call but [verify] is recorded
/// in [calls] as `name` or `name:arg`.
class FakeAnythingLlm implements AnythingLlmApi {
  /// Every connection [verify] was given, in order.
  final List<Connection> verified = [];
  Object? verifyError;

  /// Each workspace's full answer, documents included. [workspaces] answers without them.
  List<Workspace> workspacesValue = [];
  List<DocFolder> foldersValue = [];
  Set<String> acceptedValue = {'.md', '.txt', '.pdf'};

  final List<String> calls = [];
  final Map<String, Object> errors = {};

  Future<T> _run<T>(String name, T Function() value, [String? arg]) async {
    calls.add(arg == null ? name : '$name:$arg');
    final error = errors[name];
    if (error != null) throw error;
    return value();
  }

  @override
  Future<void> verify(Connection connection) async {
    verified.add(connection);
    if (verifyError != null) throw verifyError!;
  }

  @override
  Future<List<Workspace>> workspaces() => _run(
    'workspaces',
    () => [
      for (final w in workspacesValue)
        Workspace(
          slug: w.slug,
          name: w.name,
          chatModel: w.chatModel,
          threads: w.threads,
        ),
    ],
  );

  @override
  Future<Workspace> workspace(String slug) => _run(
    'workspace',
    () => workspacesValue.firstWhere(
      (w) => w.slug == slug,
      orElse: () =>
          throw ApiException('There is no workspace $slug.', status: 404),
    ),
    slug,
  );

  @override
  Future<List<DocFolder>> documents() => _run('documents', () => foldersValue);

  @override
  Future<Set<String>> acceptedExtensions() =>
      _run('acceptedExtensions', () => acceptedValue);

  /// Files the server reads into [folder], as a document titled by [name].
  @override
  Future<List<DocEntry>> upload(
    String name,
    List<int> bytes, {
    String? folder,
  }) => _run('upload', () {
    final doc = DocEntry(
      folder: folder ?? 'custom-documents',
      name: '$name-1.json',
      title: name,
    );
    foldersValue = [
      for (final f in foldersValue)
        f.name == doc.folder
            ? DocFolder(name: f.name, docs: [...f.docs, doc])
            : f,
      if (!foldersValue.any((f) => f.name == doc.folder))
        DocFolder(name: doc.folder, docs: [doc]),
    ];
    return [doc];
  }, '$name:${folder ?? ''}');
}

DocEntry sampleDoc(
  String folder,
  String title, {
  String? description,
  int? words = 120,
}) => DocEntry(
  folder: folder,
  name: '$title.md-0001.json',
  title: title,
  description: description ?? 'About $title',
  source: 'a text file uploaded by the user.',
  published: '10/5/2026, 11:48:20 AM',
  words: words,
);

/// The document a [documentServer] holds in one of its two workspaces.
final heldDoc = sampleDoc('claude', 'agents');

/// A server with [heldDoc] in its `claude` folder, held by the workspace `research` and not by
/// `other`.
FakeAnythingLlm documentServer() => FakeAnythingLlm()
  ..foldersValue = [
    DocFolder(name: 'claude', docs: [heldDoc]),
  ]
  ..workspacesValue = [
    Workspace(
      slug: 'research',
      name: 'Research',
      documents: [WorkspaceDoc(path: heldDoc.path, title: heldDoc.title)],
    ),
    const Workspace(slug: 'other', name: 'Other'),
  ];
