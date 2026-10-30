import 'dart:async';
import 'dart:typed_data';

import 'package:anywherellm/core/chat.dart';
import 'package:anywherellm/core/connection.dart';
import 'package:anywherellm/core/outputs.dart';
import 'package:anywherellm/core/ports.dart';
import 'package:anywherellm/core/server_models.dart';
import 'package:anywherellm/core/users.dart';

import 'fake_calls.dart';

/// A connection for tests that need a server set up.
const sampleConnection = Connection(baseUrl: 'https://h:3001', apiKey: 'K1');

/// A workspace on the fake server: its chats and the documents embedded in it.
class FakeWorkspace {
  FakeWorkspace(
    this.slug,
    this.name, {
    this.id,
    List<Thread>? threads,
    List<WorkspaceDoc>? docs,
    this.prompt,
    Map<String, Object?>? settings,
  }) : threads = threads ?? [],
       docs = docs ?? [],
       settings = settings ?? {...defaultSettings};

  String slug;
  String name;

  /// The server's number for it, which [FakeAnythingLlm.members] is keyed by.
  final int? id;
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

/// An [AnythingLlmApi] for widget tests that keeps its workspaces in memory. It records and
/// steers its calls as [FakeCalls] does, but for [verify], which goes in [verified] and fails
/// with [verifyError].
///
/// [streamChat] answers with [answer] and [cited], or, when [hold] is set, with whatever the
/// test adds to the controller [chat] makes, which [chats] also keeps by thread.
class FakeAnythingLlm with FakeCalls implements AnythingLlmApi {
  final List<Connection> verified = [];
  Object? verifyError;

  /// The id [streamChat]'s next answer is given, counting up.
  int nextChatId = 100;

  List<FakeWorkspace> spaces = [];

  /// The workspaces whose read leaves out their settings, as a server may.
  final Set<String> noSettings = {};

  /// Each chat's history, by thread, and a workspace's Main chat's by its [mainChatOf].
  final Map<String, List<ChatMessage>> histories = {};

  /// Adds [question] and its [answer] to [thread]'s history as exchange [chatId], as the server
  /// saves an answer.
  void saveExchange(
    String thread,
    String question,
    String answer, {
    int chatId = 100,
  }) => histories[thread] = [
    ...?histories[thread],
    ChatMessage(role: Role.user, text: question, chatId: chatId),
    ChatMessage(role: Role.assistant, text: answer, chatId: chatId),
  ];

  /// Every document the server holds, by path, embedded or not.
  final Map<String, LibraryDoc> library = {};

  /// The library's folders, in the order [library] lists them; a document's folder not named
  /// here follows them.
  final List<String> folders = ['custom-documents'];

  /// What [systemSettings] answers.
  Map<String, Object?> system = const {
    'LLMProvider': 'ollama',
    'OllamaLLMModelPref': 'qwen3:8b',
    'EmbeddingEngine': 'native',
    'VectorDB': 'lancedb',
  };

  /// What [vectorCount] answers.
  int vectors = 796;

  String answer = 'Here is what your sources say.';
  List<String> cited = const [];

  /// The files an agent made, which [streamChat] sends with the answer.
  List<GeneratedFile> made = const [];

  /// How [streamChat]'s answer ran.
  AnswerMetrics? measured;

  /// What [generatedFile] answers, by storage name. Any other name is not found.
  final Map<String, List<int>> generated = {};

  /// What [answerImage] answers, by address. Any other address is not found.
  final Map<Uri, List<int>> images = {};

  bool hold = false;
  StreamController<ChatEvent>? chat;

  /// Each held answer's controller, by thread or [mainChatOf]: the last one when a chat asked
  /// twice.
  final Map<String, StreamController<ChatEvent>> chats = {};

  /// The status lines [streamChat] sends before the answer, as an agent does.
  List<String> agentStatus = const [];

  /// The files sent with the last message asked.
  List<Attachment> lastAttachments = const [];

  /// The mode the last message asked was sent in, or null for the workspace's own.
  ChatMode? lastMode;

  /// The details each added document was given, by path.
  final Map<String, DocMeta> metaOf = {};

  /// The slug [renameWorkspace] gives the workspace, when set. The server keeps it otherwise.
  String? renamedSlug;

  /// Whether the server has several users, which [multiUser] answers.
  bool several = false;

  /// What [users] answers on a server with [several] users.
  List<ServerUser> people = const [];

  /// The users each workspace lists, by [FakeWorkspace.id]; [workspaceUsers] answers none for
  /// one not here.
  final Map<int, List<WorkspaceMember>> members = {};

  /// The user each chat was made as by [createThread], by its slug, null for none.
  final Map<String, int?> madeAs = {};

  /// The user the last message asked was sent as, or null for none.
  int? lastUserId;

  /// What [exportChats] answers.
  List<int> exported =
      'id,workspace,prompt,response\n1,Q3 planning,Hi,Hello\n'.codeUnits;

  var _made = 0;

  FakeWorkspace _space(String slug) => spaces.firstWhere(
    (w) => w.slug == slug,
    orElse: () =>
        throw ApiException('There is no workspace $slug.', status: 404),
  );

  @override
  Future<void> verify(Connection connection) async {
    verified.add(connection);
    await gates['verify']?.future;
    if (verifyError != null) throw verifyError!;
  }

  @override
  Future<List<Workspace>> workspaces() => record(
    'workspaces',
    () => [
      for (final w in spaces)
        Workspace(
          slug: w.slug,
          name: w.name,
          id: w.id,
          threads: [...w.threads],
        ),
    ],
  );

  @override
  Future<Workspace> workspace(String slug) => record('workspace', () {
    final w = _space(slug);
    return Workspace(
      slug: w.slug,
      name: w.name,
      documents: [...w.docs],
      prompt: w.prompt,
      settings: noSettings.contains(slug)
          ? null
          : WorkspaceSettings({...w.settings}),
    );
  }, slug);

  @override
  Future<Workspace> createWorkspace(String name, {String? prompt}) =>
      record('createWorkspace', () {
        final made = FakeWorkspace(
          name.toLowerCase().replaceAll(' ', '-'),
          name,
          prompt: prompt,
        );
        spaces.add(made);
        return Workspace(slug: made.slug, name: made.name);
      }, name);

  @override
  Future<Workspace> renameWorkspace(String slug, String name) =>
      record('renameWorkspace', () {
        final w = _space(slug)
          ..name = name
          ..slug = renamedSlug ?? slug;
        return Workspace(slug: w.slug, name: w.name);
      }, '$slug:$name');

  @override
  Future<void> deleteWorkspace(String slug) => record('deleteWorkspace', () {
    _space(slug);
    spaces.removeWhere((w) => w.slug == slug);
  }, slug);

  @override
  Future<Thread> createThread(String slug, {int? userId}) =>
      record('createThread', () {
        final made = Thread(slug: 'th-${++_made}', name: newChatName);
        _space(slug).threads.add(made);
        madeAs[made.slug] = userId;
        return made;
      }, slug);

  @override
  Future<void> renameThread(String slug, String thread, String name) =>
      record('renameThread', () {
        final list = _space(slug).threads;
        final at = list.indexWhere((t) => t.slug == thread);
        list[at] = Thread(slug: thread, name: name);
      }, '$thread:$name');

  /// The server each delete was sent to by name, when it was not the one in use.
  final deletedOn = <String, Connection>{};

  @override
  Future<void> deleteThread(String slug, String thread, {Connection? on}) =>
      record('deleteThread', () {
        if (on != null) deletedOn[thread] = on;
        _space(slug).threads.removeWhere((t) => t.slug == thread);
      }, thread);

  /// What chat [thread] of workspace [slug] is kept and recorded under: the thread, or for a
  /// null [thread] the workspace's [mainChatOf]. Main chat is never asked for by that key as a
  /// thread, since the server knows no such thread.
  String _chatOf(String slug, String? thread) {
    if (isMainChat(thread)) {
      throw StateError(
        'Main chat goes to the server as no thread, not $thread.',
      );
    }
    return thread ?? mainChatOf(slug);
  }

  @override
  Future<void> resetChat(String slug, String? thread) {
    final chat = _chatOf(slug, thread);
    return record('resetChat', () => histories.remove(chat), chat);
  }

  @override
  Future<List<ChatMessage>> history(String slug, String? thread) {
    final chat = _chatOf(slug, thread);
    return record('history', () => histories[chat] ?? const [], chat);
  }

  @override
  Stream<ChatEvent> streamChat(
    String slug,
    String? thread,
    String message, {
    List<Attachment> attachments = const [],
    ChatMode? mode,
    int? userId,
  }) {
    final key = _chatOf(slug, thread);
    calls.add('streamChat:$key:$message');
    lastAttachments = attachments;
    lastMode = mode;
    lastUserId = userId;
    final error = errors['streamChat'];
    if (error != null) return Stream.error(error);
    if (hold) {
      chat = chats[key] = StreamController<ChatEvent>();
      return chat!.stream;
    }
    final id = nextChatId++;
    return Stream.fromIterable([
      for (final line in agentStatus) StatusChunk(line),
      TextChunk(answer),
      ChatDone(
        [for (final title in cited) Citation(title)],
        files: made,
        metrics: measured,
        chatId: id,
      ),
    ]);
  }

  @override
  Future<void> updateEmbeddings(
    String slug, {
    List<String> adds = const [],
    List<String> deletes = const [],
  }) => record('updateEmbeddings', () {
    final docs = _space(slug).docs;
    docs.removeWhere((d) => deletes.contains(d.path));
    for (final path in adds) {
      if (!docs.any((d) => d.path == path)) docs.add(embedded(library[path]!));
    }
  }, '+${adds.join(',')}-${deletes.join(',')}');

  /// Each folder of [folders], then any other a document is in, with its documents in the order
  /// they were added.
  @override
  Future<List<LibraryFolder>> libraryFolders() => record('libraryFolders', () {
    final names = {
      ...folders,
      for (final path in library.keys) docFolder(path),
    };
    return [
      for (final name in names)
        LibraryFolder(name, [
          for (final doc in library.values)
            if (docFolder(doc.path) == name) doc,
        ]),
    ];
  });

  @override
  Future<void> createFolder(String name) => record('createFolder', () {
    if (folders.contains(name)) {
      throw const ApiException('Folder by that name already exists');
    }
    folders.add(name);
  }, name);

  /// Leaves every document where it is when a workspace uses one of them, as the server leaves
  /// that one.
  @override
  Future<void> moveDocuments(List<({String from, String to})> moves) =>
      record('moveDocuments', () {
        final used = {
          for (final w in spaces)
            for (final d in w.docs) d.path,
        };
        if (moves.any((m) => used.contains(m.from))) {
          throw const ApiException(movedNot);
        }
        for (final (:from, :to) in moves) {
          final doc = library.remove(from)!;
          library[to] = LibraryDoc(
            path: to,
            title: doc.title,
            words: doc.words,
            web: doc.web,
            link: doc.link,
            fileName: doc.fileName,
            published: doc.published,
          );
          if (!folders.contains(docFolder(to))) folders.add(docFolder(to));
        }
      }, [for (final m in moves) '${m.from}>${m.to}'].join(','));

  @override
  Future<void> deleteDocuments(List<String> paths) =>
      record('deleteDocuments', () {
        library.removeWhere((path, _) => paths.contains(path));
        for (final w in spaces) {
          w.docs.removeWhere((d) => paths.contains(d.path));
        }
      }, paths.join(','));

  @override
  Future<void> pinDocument(String slug, String path, {required bool pinned}) =>
      record('pinDocument', () {
        final docs = _space(slug).docs;
        final at = docs.indexWhere((d) => d.path == path);
        if (at < 0) {
          throw const ApiException(
            'This workspace does not use the document.',
            status: 404,
          );
        }
        final doc = docs[at];
        docs[at] = WorkspaceDoc(
          path: doc.path,
          title: doc.title,
          words: doc.words,
          web: doc.web,
          pinned: pinned,
        );
      }, '$slug:$path:$pinned');

  /// What [acceptedExtensions] answers: some of the types stock AnythingLLM reads.
  Set<String> accepted = {'.md', '.txt', '.pdf', '.html', '.docx', '.csv'};

  @override
  Future<Set<String>> acceptedExtensions() =>
      record('acceptedExtensions', () => accepted);

  /// Files the server reads in as `<folder>/<name>.json`, `custom-documents` by default; the
  /// call is recorded as `upload:<name>`, or `upload:<folder>/<name>` into a folder named.
  @override
  Future<List<DocEntry>> upload(
    String name,
    List<int> bytes, {
    DocMeta meta = const DocMeta(),
    String? folder,
  }) => record('upload', () {
    final doc = DocEntry(
      folder: folder ?? 'custom-documents',
      name: '$name.json',
    );
    if (!folders.contains(doc.folder)) folders.add(doc.folder);
    _keep(doc, name, meta, words: bytes.length, web: false, file: name);
    return [doc];
  }, folder == null ? name : '$folder/$name');

  /// A page the server reads in as `custom-documents/url-<host>.json`.
  @override
  Future<List<DocEntry>> uploadLink(
    String url, {
    DocMeta meta = const DocMeta(),
  }) => record('uploadLink', () {
    final host = Uri.parse(url).host;
    final doc = DocEntry(folder: 'custom-documents', name: 'url-$host.json');
    _keep(doc, host, meta, words: 1, web: true);
    return [doc];
  }, url);

  /// Text the server saves as `custom-documents/raw-<title>.json`.
  @override
  Future<List<DocEntry>> uploadText(
    String title,
    String text, {
    DocMeta meta = const DocMeta(),
  }) => record('uploadText', () {
    final doc = DocEntry(folder: 'custom-documents', name: 'raw-$title.json');
    _keep(
      doc,
      title,
      DocMeta(
        title: title,
        author: meta.author,
        description: meta.description,
        source: meta.source,
      ),
      words: text.split(' ').length,
      web: false,
    );
    return [doc];
  }, title);

  /// Puts [doc] in the library, titled by [meta] or else [title], and records [meta]. A [web]
  /// page is one the server read from a link.
  void _keep(
    DocEntry doc,
    String title,
    DocMeta meta, {
    required int words,
    required bool web,
    String? file,
  }) {
    metaOf[doc.path] = meta;
    library[doc.path] = LibraryDoc(
      path: doc.path,
      title: meta.title.trim().isEmpty ? title : meta.title.trim(),
      words: words,
      web: web,
      link: web ? 'https://$title' : null,
      fileName: file,
    );
  }

  @override
  Future<void> updateWorkspace(String slug, Map<String, Object?> fields) =>
      record('updateWorkspace', () {
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
  Future<List<SearchHit>> searchDocs(String slug, String query) => record(
    'searchDocs',
    () {
      final words = query.toLowerCase().split(' ').toSet();
      return [
        for (final (i, d) in _space(slug).docs.indexed)
          if (d.title.toLowerCase().split(RegExp(r'[ .]')).any(words.contains))
            SearchHit(
              title: d.title,
              text: 'A passage of ${d.title}.',
              score: 0.9 - i / 10,
            ),
      ];
    },
    '$slug:$query',
  );

  /// Writes each change into [system]; a secret, which the server reports only as set, becomes
  /// true.
  @override
  Future<void> updateSystem(Map<String, String> changes) =>
      record('updateSystem', () {
        system = {
          ...system,
          for (final MapEntry(:key, :value) in changes.entries)
            key: system[key] is bool ? true : value,
        };
      }, changes.keys.join(','));

  @override
  Future<int> vectorCount() => record('vectorCount', () => vectors);

  @override
  Future<Uint8List> answerImage(Uri url) => record('answerImage', () {
    final bytes = images[url];
    if (bytes == null) {
      throw const ApiException(
        'The image could not be read: the server answered 404.',
      );
    }
    return Uint8List.fromList(bytes);
  }, url.toString());

  @override
  Future<List<int>> generatedFile(String storageName) =>
      record('generatedFile', () {
        final bytes = generated[storageName];
        if (bytes == null) throw const ApiException('File not found');
        return bytes;
      }, storageName);

  @override
  Future<Map<String, Object?>> systemSettings() =>
      record('systemSettings', () => system);

  @override
  Future<bool> multiUser() => record('multiUser', () => several);

  /// A single-user server refuses, as the server answers HTTP 401.
  @override
  Future<List<ServerUser>> users() => record('users', () {
    if (!several) {
      throw const ApiException('The server rejected the key.', status: 401);
    }
    return people;
  });

  @override
  Future<List<WorkspaceMember>> workspaceUsers(int workspaceId) => record(
    'workspaceUsers',
    () => members[workspaceId] ?? const [],
    '$workspaceId',
  );

  @override
  Future<List<int>> exportChats() => record('exportChats', () => exported);
}

/// Why the fake leaves a document a workspace uses where it is, as the server does.
const movedNot = 'A workspace uses it.';

/// A document in the server's library, in [folder], as a workspace holds it once embedded,
/// ready to put in a workspace's docs.
WorkspaceDoc libraryDoc(
  FakeAnythingLlm llm,
  String title, {
  int? words = 120,
  String folder = 'custom-documents',
  String? published,
}) {
  final doc = LibraryDoc(
    path: '$folder/$title.json',
    title: title,
    words: words,
    fileName: title,
    published: published,
  );
  llm.library[doc.path] = doc;
  if (!llm.folders.contains(folder)) llm.folders.add(folder);
  return embedded(doc);
}

/// [doc] as a workspace holds it once embedded.
WorkspaceDoc embedded(LibraryDoc doc) => WorkspaceDoc(
  path: doc.path,
  title: doc.title,
  words: doc.words,
  web: doc.web,
);

/// A server with the mockup's workspaces: Q3 planning with two chats and two files, and an empty
/// Household.
/// [planningServer] with [answer] as the last answer in the chat it opens on.
FakeAnythingLlm answering(String answer, {List<Citation> cited = const []}) {
  final llm = planningServer();
  llm.histories['budget'] = [
    const ChatMessage(role: Role.user, text: 'Where?'),
    ChatMessage(role: Role.assistant, text: answer, citations: cited),
  ];
  return llm;
}

/// [planningServer] with the budget chat's one exchange asked with [attachments].
FakeAnythingLlm askedWithFiles(List<String> attachments) {
  final llm = planningServer();
  llm.histories['budget'] = [
    ChatMessage(
      role: Role.user,
      text: 'What is the budget?',
      attachments: [for (final name in attachments) SentFile(name)],
    ),
    const ChatMessage(role: Role.assistant, text: 'About 40k.'),
  ];
  return llm;
}

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
      citations: [Citation('Q3 roadmap.pdf')],
    ),
  ];
  return llm;
}
