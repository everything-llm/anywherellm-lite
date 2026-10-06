import 'dart:async';

import 'package:anywherellm/core/chat.dart';
import 'package:anywherellm/core/connection.dart';
import 'package:anywherellm/core/ports.dart';
import 'package:anywherellm/core/server_models.dart';

/// A connection for tests that need a server set up.
const sampleConnection = Connection(baseUrl: 'https://h:3001', apiKey: 'K1');

/// A workspace on the fake server: its chats and the documents embedded in it.
class FakeWorkspace {
  FakeWorkspace(
    this.slug,
    this.name, {
    List<Thread>? threads,
    List<WorkspaceDoc>? docs,
    this.prompt,
    Map<String, Object?>? settings,
  }) : threads = threads ?? [],
       docs = docs ?? [],
       settings = settings ?? {...defaultSettings};

  final String slug;
  final String name;
  final List<Thread> threads;
  final List<WorkspaceDoc> docs;
  String? prompt;

  /// The workspace's columns from [workspaceSettingSpecs].
  final Map<String, Object?> settings;

  static const defaultSettings = <String, Object?>{
    'openAiTemp': 0.7,
    'openAiHistory': 20,
    'topN': 4,
    'similarityThreshold': 0.25,
    'chatProvider': null,
    'chatModel': null,
    'agentProvider': null,
    'agentModel': null,
    'vectorSearchMode': 'default',
    'queryRefusalResponse': null,
    'chatMode': 'automatic',
  };
}

/// An [AnythingLlmApi] for widget tests that keeps its workspaces in memory. Put an error in
/// [errors] under a method's name to make it fail, or a completer in [gates] to hold it until the
/// test completes it. Every call but [verify] is recorded in [calls] as `name` or `name:arg`.
///
/// [streamChat] answers with [answer] and [cited], or, when [hold] is set, with whatever the
/// test adds to the controller [chat] makes.
class FakeAnythingLlm implements AnythingLlmApi {
  final List<Connection> verified = [];
  Object? verifyError;

  List<FakeWorkspace> spaces = [];
  final Map<String, List<ChatMessage>> histories = {};

  /// Every document the server holds, by path, embedded or not.
  final Map<String, WorkspaceDoc> library = {};

  /// Library folders made with [createFolder], which show even while empty.
  final Set<String> folders = {};

  /// What [systemSettings] answers.
  Map<String, Object?> system = const {
    'LLMProvider': 'ollama',
    'OllamaLLMModelPref': 'qwen3:8b',
    'EmbeddingEngine': 'native',
    'VectorDB': 'lancedb',
  };
  Set<String> acceptedValue = {'.md', '.txt', '.pdf'};

  String answer = 'Here is what your sources say.';
  List<String> cited = const [];
  bool hold = false;
  StreamController<ChatEvent>? chat;

  /// The mode of every message asked, in order.
  final List<ChatMode> modes = [];

  final List<String> calls = [];
  final Map<String, Object> errors = {};
  final Map<String, Completer<void>> gates = {};
  var _made = 0;

  Future<T> _run<T>(String name, T Function() value, [String? arg]) async {
    calls.add(arg == null ? name : '$name:$arg');
    await gates[name]?.future;
    final error = errors[name];
    if (error != null) throw error;
    return value();
  }

  FakeWorkspace _space(String slug) => spaces.firstWhere(
    (w) => w.slug == slug,
    orElse: () =>
        throw ApiException('There is no workspace $slug.', status: 404),
  );

  @override
  Future<void> verify(Connection connection) async {
    verified.add(connection);
    if (verifyError != null) throw verifyError!;
  }

  @override
  Future<List<Workspace>> workspaces() => _run(
    'workspaces',
    () => [
      for (final w in spaces)
        Workspace(slug: w.slug, name: w.name, threads: [...w.threads]),
    ],
  );

  @override
  Future<Workspace> workspace(String slug) => _run('workspace', () {
    final w = _space(slug);
    return Workspace(
      slug: w.slug,
      name: w.name,
      documents: [...w.docs],
      prompt: w.prompt,
      settings: WorkspaceSettings({...w.settings}),
    );
  }, slug);

  @override
  Future<Workspace> createWorkspace(String name) => _run('createWorkspace', () {
    final made = FakeWorkspace(name.toLowerCase().replaceAll(' ', '-'), name);
    spaces.add(made);
    return Workspace(slug: made.slug, name: made.name);
  }, name);

  @override
  Future<Thread> createThread(String slug) => _run('createThread', () {
    final made = Thread(slug: 'th-${++_made}', name: newChatName);
    _space(slug).threads.add(made);
    return made;
  }, slug);

  @override
  Future<void> renameThread(String slug, String thread, String name) =>
      _run('renameThread', () {
        final list = _space(slug).threads;
        final at = list.indexWhere((t) => t.slug == thread);
        list[at] = Thread(slug: thread, name: name);
      }, '$thread:$name');

  @override
  Future<void> deleteThread(String slug, String thread) => _run(
    'deleteThread',
    () => _space(slug).threads.removeWhere((t) => t.slug == thread),
    thread,
  );

  @override
  Future<List<ChatMessage>> history(String slug, String thread) =>
      _run('history', () => histories[thread] ?? const [], thread);

  @override
  Stream<ChatEvent> streamChat(
    String slug,
    String thread,
    String message, {
    required ChatMode mode,
  }) {
    calls.add('streamChat:$thread:$message');
    modes.add(mode);
    final error = errors['streamChat'];
    if (error != null) return Stream.error(error);
    if (hold) {
      chat = StreamController<ChatEvent>();
      return chat!.stream;
    }
    return Stream.fromIterable([TextChunk(answer), ChatDone(cited)]);
  }

  @override
  Future<void> updateEmbeddings(
    String slug, {
    List<String> adds = const [],
    List<String> deletes = const [],
  }) => _run('updateEmbeddings', () {
    final docs = _space(slug).docs;
    docs.removeWhere((d) => deletes.contains(d.path));
    for (final path in adds) {
      if (!docs.any((d) => d.path == path)) docs.add(library[path]!);
    }
  }, '+${adds.join(',')}-${deletes.join(',')}');

  @override
  Future<Set<String>> acceptedExtensions() =>
      _run('acceptedExtensions', () => acceptedValue);

  /// Files the server reads in as `<folder>/<name>.json`, `custom-documents` by default.
  @override
  Future<List<DocEntry>> upload(
    String name,
    List<int> bytes, {
    String? folder,
  }) => _run('upload', () {
    final doc = DocEntry(
      folder: folder ?? 'custom-documents',
      name: '$name.json',
    );
    library[doc.path] = WorkspaceDoc(
      path: doc.path,
      title: name,
      words: bytes.length,
    );
    return [doc];
  }, folder == null ? name : '$folder/$name');

  @override
  Future<void> updateWorkspace(String slug, Map<String, Object?> fields) =>
      _run('updateWorkspace', () {
        final w = _space(slug);
        for (final MapEntry(:key, :value) in fields.entries) {
          if (key == 'openAiPrompt') {
            w.prompt = value as String?;
          } else {
            w.settings[key] = value;
          }
        }
      }, slug);

  @override
  Future<void> pinDocument(String slug, String path, {required bool pinned}) =>
      _run('pinDocument', () {
        final docs = _space(slug).docs;
        final at = docs.indexWhere((d) => d.path == path);
        final doc = docs[at];
        docs[at] = WorkspaceDoc(
          path: doc.path,
          title: doc.title,
          words: doc.words,
          pinned: pinned,
        );
      }, '$path:$pinned');

  @override
  Future<List<LibraryFolder>> libraryFolders() => _run('libraryFolders', () {
    final byFolder = <String, List<LibraryFile>>{
      for (final folder in folders) folder: [],
    };
    for (final doc in library.values) {
      final folder = docFolder(doc.path);
      (byFolder[folder] ??= []).add(
        LibraryFile(folder: folder, name: docName(doc.path), title: doc.title),
      );
    }
    return [
      for (final MapEntry(:key, :value) in byFolder.entries)
        LibraryFolder(name: key, files: value),
    ];
  });

  @override
  Future<DocBody> document(String path) => _run('document', () {
    final doc = library[path];
    if (doc == null) throw ApiException('There is no document $path.');
    return DocBody(
      title: doc.title,
      text: 'The text of ${doc.title}.',
      details: {'docAuthor': 'Ada'},
    );
  }, path);

  @override
  Future<void> createFolder(String name) =>
      _run('createFolder', () => folders.add(name), name);

  /// Moves documents that no workspace uses, as the server does, and leaves the others.
  @override
  Future<void> moveDocuments(List<(String, String)> moves) =>
      _run('moveDocuments', () {
        for (final (from, to) in moves) {
          if (spaces.any((w) => w.docs.any((d) => d.path == from))) continue;
          final doc = library.remove(from)!;
          library[to] = WorkspaceDoc(
            path: to,
            title: doc.title,
            words: doc.words,
          );
        }
      }, [for (final (from, to) in moves) '$from>$to'].join(','));

  @override
  Future<void> removeDocuments(List<String> paths) =>
      _run('removeDocuments', () {
        for (final path in paths) {
          library.remove(path);
          for (final w in spaces) {
            w.docs.removeWhere((d) => d.path == path);
          }
        }
      }, paths.join(','));

  @override
  Future<Map<String, Object?>> systemSettings() =>
      _run('systemSettings', () => system);
}

/// A document in the server's library, ready to embed or put in a workspace.
WorkspaceDoc libraryDoc(FakeAnythingLlm llm, String title, {int? words = 120}) {
  final doc = WorkspaceDoc(
    path: 'custom-documents/$title.json',
    title: title,
    words: words,
  );
  llm.library[doc.path] = doc;
  return doc;
}

/// A server with the mockup's workspaces: Q3 planning with two chats and two files, and an empty
/// Household.
FakeAnythingLlm planningServer() {
  final llm = FakeAnythingLlm();
  llm.spaces = [
    FakeWorkspace(
      'q3',
      'Q3 planning',
      threads: [
        const Thread(slug: 'priorities', name: 'Quarter priorities'),
        const Thread(slug: 'budget', name: 'Budget questions'),
      ],
      docs: [
        libraryDoc(llm, 'Q3 roadmap.pdf'),
        libraryDoc(llm, 'Customer interviews.docx'),
      ],
    ),
    FakeWorkspace('household', 'Household'),
  ];
  llm.histories['budget'] = const [
    ChatMessage(role: Role.user, text: 'What is the budget?'),
    ChatMessage(
      role: Role.assistant,
      text: 'About 40k.',
      citations: ['Q3 roadmap.pdf'],
    ),
  ];
  return llm;
}
