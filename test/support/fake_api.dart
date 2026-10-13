import 'dart:async';
import 'dart:typed_data';

import 'package:anywherellm/core/chat.dart';
import 'package:anywherellm/core/chat_log.dart';
import 'package:anywherellm/core/connection.dart';
import 'package:anywherellm/core/embeds.dart';
import 'package:anywherellm/core/outputs.dart';
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

  String slug;
  String name;
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
/// test adds to the controller [chat] makes, which [chats] also keeps by thread.
class FakeAnythingLlm implements AnythingLlmApi {
  final List<Connection> verified = [];
  Object? verifyError;

  /// The id [streamChat]'s next answer is given, counting up.
  int nextChatId = 100;

  List<FakeWorkspace> spaces = [];
  final Map<String, List<ChatMessage>> histories = {};

  /// Every document the server holds, by path, embedded or not.
  final Map<String, WorkspaceDoc> library = {};

  /// The library documents, by path, whose text `document` leaves out, as the server may.
  final Set<String> textless = {};

  /// What [systemSettings] answers.
  Map<String, Object?> system = const {
    'LLMProvider': 'ollama',
    'OllamaLLMModelPref': 'qwen3:8b',
    'EmbeddingEngine': 'native',
    'VectorDB': 'lancedb',
  };

  /// The server's chat embeds.
  List<Embed> embedList = [];

  /// The chats each embed has held, by uuid.
  final Map<String, List<EmbedChat>> embedChatsOf = {};

  /// What [vectorCount] answers.
  int vectors = 796;
  Set<String> acceptedValue = {'.md', '.txt', '.pdf'};

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

  /// Each held answer's controller, by thread: the last one when a chat asked twice.
  final Map<String, StreamController<ChatEvent>> chats = {};

  /// The status lines [streamChat] sends before the answer, as an agent does.
  List<String> agentStatus = const [];

  /// The files sent with the last message asked.
  List<Attachment> lastAttachments = const [];

  /// The details each added document was given, by path.
  final Map<String, DocMeta> metaOf = {};

  /// The slug [renameWorkspace] gives the workspace, when set. The server keeps it otherwise.
  String? renamedSlug;

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
  Future<Workspace> createWorkspace(String name, {String? prompt}) =>
      _run('createWorkspace', () {
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
      _run('renameWorkspace', () {
        final w = _space(slug)
          ..name = name
          ..slug = renamedSlug ?? slug;
        return Workspace(slug: w.slug, name: w.name);
      }, '$slug:$name');

  @override
  Future<void> deleteWorkspace(String slug) => _run('deleteWorkspace', () {
    _space(slug);
    spaces.removeWhere((w) => w.slug == slug);
  }, slug);

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

  /// The server each delete was sent to by name, when it was not the one in use.
  final deletedOn = <String, Connection>{};

  @override
  Future<void> deleteThread(String slug, String thread, {Connection? on}) =>
      _run('deleteThread', () {
        if (on != null) deletedOn[thread] = on;
        _space(slug).threads.removeWhere((t) => t.slug == thread);
      }, thread);

  @override
  Future<List<ChatMessage>> history(String slug, String thread) =>
      _run('history', () => histories[thread] ?? const [], thread);

  @override
  Stream<ChatEvent> streamChat(
    String slug,
    String thread,
    String message, {
    List<Attachment> attachments = const [],
  }) {
    calls.add('streamChat:$thread:$message');
    lastAttachments = attachments;
    final error = errors['streamChat'];
    if (error != null) return Stream.error(error);
    if (hold) {
      chat = chats[thread] = StreamController<ChatEvent>();
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
    DocMeta meta = const DocMeta(),
  }) => _run('upload', () {
    final doc = DocEntry(folder: 'custom-documents', name: '$name.json');
    _keep(doc, name, meta, words: bytes.length, web: false);
    return [doc];
  }, name);

  /// A page the server reads in as `custom-documents/url-<host>.json`.
  @override
  Future<List<DocEntry>> uploadLink(
    String url, {
    DocMeta meta = const DocMeta(),
  }) => _run('uploadLink', () {
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
  }) => _run('uploadText', () {
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
  }) {
    metaOf[doc.path] = meta;
    library[doc.path] = WorkspaceDoc(
      path: doc.path,
      title: meta.title.trim().isEmpty ? title : meta.title.trim(),
      words: words,
      web: web,
    );
  }

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
  Future<DocBody> document(String path) => _run('document', () {
    final doc = library[path];
    if (doc == null) throw ApiException('There is no document $path.');
    return DocBody(
      title: doc.title,
      text: textless.contains(path) ? null : 'The text of ${doc.title}.',
    );
  }, path);

  @override
  Future<List<SearchHit>> searchDocs(String slug, String query) => _run(
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

  /// What [exportChats] answers, for any format.
  String exported = '{"prompt":"hi"}';

  @override
  Future<List<int>> exportChats(ChatExport format) =>
      _run('exportChats', () => exported.codeUnits, format.name);

  /// What [workspaceChats] pages through, newest first.
  List<LoggedChat> chatLog = [];

  @override
  Future<ChatLog> workspaceChats({int page = 0}) => _run('workspaceChats', () {
    const size = ChatLog.pageSize;
    final start = page * size;
    return ChatLog(
      chatLog.skip(start).take(size).toList(),
      more: chatLog.length > start + size,
    );
  }, '$page');

  /// Writes each change into [system]; a secret, which the server reports only as set, becomes
  /// true.
  @override
  Future<void> updateSystem(Map<String, String> changes) =>
      _run('updateSystem', () {
        system = {
          ...system,
          for (final MapEntry(:key, :value) in changes.entries)
            key: system[key] is bool ? true : value,
        };
      }, changes.keys.join(','));

  @override
  Future<List<Embed>> embeds() => _run('embeds', () => [...embedList]);

  /// Makes the embed with a uuid counting up, for the workspace whose slug it was given.
  @override
  Future<String> createEmbed(NewEmbed embed) => _run('createEmbed', () {
    final uuid = 'embed-${embedList.length + 1}';
    embedList = [
      ...embedList,
      Embed(
        uuid: uuid,
        workspace: spaces.firstWhere((w) => w.slug == embed.workspaceSlug).name,
        mode: embed.mode,
        enabled: true,
      ),
    ];
    return uuid;
  }, embed.workspaceSlug);

  @override
  Future<void> updateEmbed(String uuid, {bool? enabled, EmbedMode? mode}) =>
      _run('updateEmbed', () {
        embedList = [
          for (final e in embedList)
            e.uuid == uuid
                ? Embed(
                    uuid: uuid,
                    workspace: e.workspace,
                    mode: mode ?? e.mode,
                    enabled: enabled ?? e.enabled,
                    chats: e.chats,
                  )
                : e,
        ];
      }, uuid);

  @override
  Future<void> deleteEmbed(String uuid) => _run('deleteEmbed', () {
    embedList = [
      for (final e in embedList)
        if (e.uuid != uuid) e,
    ];
  }, uuid);

  @override
  Future<List<EmbedChat>> embedChats(String uuid) =>
      _run('embedChats', () => embedChatsOf[uuid] ?? const [], uuid);

  @override
  Future<int> vectorCount() => _run('vectorCount', () => vectors);

  @override
  Future<Uint8List> answerImage(Uri url) => _run('answerImage', () {
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
      _run('generatedFile', () {
        final bytes = generated[storageName];
        if (bytes == null) throw const ApiException('File not found');
        return bytes;
      }, storageName);

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
