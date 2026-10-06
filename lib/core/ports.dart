import 'chat.dart';
import 'commands.dart';
import 'connection.dart';
import 'prefs.dart';
import 'server_models.dart';

export 'errors.dart';

/// The AnythingLLM server, as the UI sees it. Every method throws [ApiException] on failure.
/// Every method but [verify] uses the connection in use, and throws [NotConfigured] when there
/// is none.
abstract interface class AnythingLlmApi {
  /// Asks the server whether [connection] opens it. Takes the connection as an argument so
  /// Settings can test one before it is saved.
  Future<void> verify(Connection connection);

  /// Every workspace with its named threads, without its documents.
  Future<List<Workspace>> workspaces();

  /// One workspace with its documents. A missing one is an [ApiException] with status 404.
  Future<Workspace> workspace(String slug);

  Future<Workspace> createWorkspace(String name);

  /// Renames the workspace and returns it as the server now has it.
  Future<Workspace> renameWorkspace(String slug, String name);

  /// Deletes the workspace with its chats. Its documents stay in the library.
  Future<void> deleteWorkspace(String slug);

  /// A new chat named [newChatName].
  Future<Thread> createThread(String slug);

  Future<void> renameThread(String slug, String thread, String name);

  Future<void> deleteThread(String slug, String thread);

  /// The chat's turns, oldest first.
  Future<List<ChatMessage>> history(String slug, String thread);

  /// Asks [message] in the chat, with [attachments] for this message only, and streams the
  /// answer. The stream fails with [ApiException]. Cancelling the subscription stops the answer.
  Stream<ChatEvent> streamChat(
    String slug,
    String thread,
    String message, {
    required ChatMode mode,
    List<Attachment> attachments = const [],
  });

  /// Clears the chat's history, so the model no longer sees its turns and history no longer
  /// lists them.
  Future<void> resetChat(String slug, String thread);

  /// The server's slash-command presets. They are read outside the developer API, which
  /// answers only while the server has no password; otherwise this fails.
  Future<List<SlashCommand>> slashCommands();

  /// Embeds the documents at [adds] in the workspace and drops those at [deletes], by
  /// `folder/name.json` path.
  Future<void> updateEmbeddings(
    String slug, {
    List<String> adds = const [],
    List<String> deletes = const [],
  });

  /// The file extensions the server can read in, lower case with the dot: `.md`.
  Future<Set<String>> acceptedExtensions();

  /// Sends [bytes] as the file [name] into library [folder], or the server's default folder
  /// when it is null, and returns the documents the server made of it. Attaches them to no
  /// workspace.
  Future<List<DocEntry>> upload(String name, List<int> bytes, {String? folder});

  /// Has the server read in the web page at [url] and returns the documents it made. Attaches
  /// them to no workspace.
  Future<List<DocEntry>> uploadLink(String url);

  /// Saves [text] as a document called [title] and returns the documents the server made.
  /// Attaches them to no workspace.
  Future<List<DocEntry>> uploadText(String title, String text);

  /// Writes the workspace columns in [fields], such as `openAiPrompt` or `topN`, and leaves the
  /// rest as they are.
  Future<void> updateWorkspace(String slug, Map<String, Object?> fields);

  /// Pins the document at [path] in the workspace, so its whole text is always in context, or
  /// unpins it.
  Future<void> pinDocument(String slug, String path, {required bool pinned});

  /// The library's folders and the documents in each.
  Future<List<LibraryFolder>> libraryFolders();

  /// The library document at [path], `folder/name.json`.
  Future<DocBody> document(String path);

  Future<void> createFolder(String name);

  /// Deletes the library folder [name] and the documents in it, which takes them out of every
  /// workspace too.
  Future<void> removeFolder(String name);

  /// Moves each library document from its first path to its second.
  Future<void> moveDocuments(List<(String from, String to)> moves);

  /// Deletes the library documents at [paths], which takes them out of every workspace too.
  Future<void> removeDocuments(List<String> paths);

  /// The server's settings, with every secret replaced by whether it is set.
  Future<Map<String, Object?>> systemSettings();
}

/// Where the connection is kept between runs.
abstract interface class SettingsStore {
  /// The saved connection, or null when none is saved. Throws [ApiException] when the store
  /// cannot be read.
  Future<Connection?> load();

  /// Throws [ApiException] when the store cannot be written.
  Future<void> save(Connection connection);

  Future<void> clear();
}

/// Where [Prefs] are kept between runs.
abstract interface class PrefsStore {
  /// The saved prefs, or the defaults when none are saved or they cannot be read.
  Future<Prefs> load();

  /// Throws [ApiException] when the prefs cannot be written.
  Future<void> save(Prefs prefs);
}
