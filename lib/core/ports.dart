import 'dart:typed_data';

import 'chat.dart';
import 'chat_log.dart';
import 'commands.dart';
import 'connection.dart';
import 'embeds.dart';
import 'prefs.dart';
import 'schedule.dart';
import 'server_models.dart';

export 'errors.dart';

/// How a server signs in to its web UI: not at all, with one password, or with a user name and
/// password, which the app does not do.
enum ServerAuth { none, password, multiUser }

/// A running answer found again: see [AnythingLlmApi.rejoinChat].
typedef RejoinedAnswer = ({String? question, Stream<ChatEvent> events});

/// The AnythingLLM server, as the UI sees it. Every method throws [ApiException] on failure.
/// Every method but [verify] uses the connection in use, and throws [NotConfigured] when there
/// is none.
abstract interface class AnythingLlmApi {
  /// Asks the server whether [connection] opens it. Takes the connection as an argument so
  /// Settings can test one before it is saved.
  Future<void> verify(Connection connection);

  /// How the server at [connection] signs in to its web UI, which its own routes outside the
  /// developer API take instead of the key.
  Future<ServerAuth> serverAuth(Connection connection);

  /// Signs in to the server with [connection]'s password, so a wrong one fails here and not on
  /// the first call that needs it. A refused password is an [ApiException] with status 403.
  Future<void> signIn(Connection connection);

  /// The developer key named `AnywhereLLM` on the server at [baseUrl], made when it has none,
  /// signed in with [password] when the server has one. A server with several users refuses it
  /// with 401, as does a server with a password when [password] is null.
  Future<String> issueKey(String baseUrl, {String? password});

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

  /// [on] sends it to that server rather than the one in use, as when the server in use has
  /// just changed and a delete was still waiting to be undone.
  Future<void> deleteThread(String slug, String thread, {Connection? on});

  /// The chat's turns, oldest first.
  Future<List<ChatMessage>> history(String slug, String thread);

  /// Asks [message] in the chat, with [attachments] for this message only, and streams the
  /// answer in the workspace's own chat mode. The stream fails with [ApiException]. Cancelling
  /// the subscription lets go of the answer: a server that keeps answers going without the app
  /// finishes it and saves it to the chat, and any other stops it.
  Stream<ChatEvent> streamChat(
    String slug,
    String thread,
    String message, {
    List<Attachment> attachments = const [],
  });

  /// The answer a server that keeps answers going without the app is still writing in the chat,
  /// which the app did not start in this run: its [question], when the server says it, and its
  /// [events] from the start. Cancelling the subscription lets go of it, and [stopChat] stops it.
  /// Null when there is no such answer, the server has no such relay, or it cannot be asked: a
  /// chat never fails to open for this.
  Future<RejoinedAnswer?> rejoinChat(String slug, String thread);

  /// The answers the server that keeps answers going without the app ran to their end, in the
  /// 7 days it keeps them. Empty when the server has no such relay or it cannot be asked.
  Future<List<RelayRun>> finishedRuns();

  /// Every answer the server that keeps answers going without the app holds, running, finished,
  /// failed or stopped, in the 7 days it keeps them, oldest first. Fails with [ApiException],
  /// saying so, when the server has no such relay.
  Future<List<RelayRun>> relayRuns();

  /// Stops the relay's run [id], whichever chat it answers in. Does nothing for a run that has
  /// ended.
  Future<void> cancelRun(String id);

  /// The jobs AnythingLLM runs on a schedule. It takes the server's web login, as the presets
  /// do: on a server with a password it needs one saved.
  Future<List<ScheduledJob>> scheduledJobs();

  /// Stops the answer [streamChat] is running in the chat, on a server that keeps answers going
  /// without the app. Does nothing when there is none. Call it before cancelling the
  /// subscription.
  Future<void> stopChat(String slug, String thread);

  /// Clears the chat's history, so the model no longer sees its turns and history no longer
  /// lists them.
  Future<void> resetChat(String slug, String thread);

  /// The server's slash-command presets. They are read outside the developer API, with the
  /// server's password when it has one; without it this fails with status 401.
  Future<List<SlashCommand>> slashCommands();

  /// Deletes the chat's exchanges from [chatId] on, that one included, so a question asked again
  /// replaces them. Needs the server's password when it has one.
  Future<void> dropFrom(String slug, String thread, int chatId);

  /// Marks the answer [chatId] good or bad, or neither when [good] is null. Needs the server's
  /// password when it has one.
  Future<void> setFeedback(String slug, int chatId, bool? good);

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
  /// when it is null, with the details in [meta], and returns the documents the server made of
  /// it. Attaches them to no workspace.
  Future<List<DocEntry>> upload(
    String name,
    List<int> bytes, {
    String? folder,
    DocMeta meta = const DocMeta(),
  });

  /// Has the server read in the web page at [url], with the details in [meta], and returns the
  /// documents it made. Attaches them to no workspace.
  Future<List<DocEntry>> uploadLink(
    String url, {
    DocMeta meta = const DocMeta(),
  });

  /// Saves [text] as a document called [title], whatever title [meta] holds, with the rest of
  /// [meta], and returns the documents the server made. Attaches them to no workspace.
  Future<List<DocEntry>> uploadText(
    String title,
    String text, {
    DocMeta meta = const DocMeta(),
  });

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

  /// The passages of workspace [slug]'s documents that [query] finds, closest first, with the
  /// workspace's own number and threshold, as an answer would get them.
  Future<List<SearchHit>> searchDocs(String slug, String query);

  /// Every chat on the server, in [format], as the file's bytes.
  Future<List<int>> exportChats(ChatExport format);

  /// Page [page] of every chat the server recorded, newest first, [ChatLog.pageSize] a page.
  Future<ChatLog> workspaceChats({int page = 0});

  /// Whether the server in use has the everythingllm relay, which keeps an answer running after
  /// the app lets go of it. The answer is kept for the server, unless [again] asks afresh.
  Future<bool> relayFound({bool again = false});

  /// The bytes of a file or image an agent made, by the [storageName] the server gave it.
  Future<List<int>> generatedFile(String storageName);

  /// The image at [url], from an answer, as it is drawn: one frame for a plain image, and each
  /// new frame of a live one, which the server keeps pushing until it ends the response. Sent
  /// without the key, the password or a login token. Cancelling closes the connection.
  Stream<Uint8List> answerImage(Uri url);

  /// The server's settings, with every secret replaced by whether it is set.
  Future<Map<String, Object?>> systemSettings();

  /// Writes [changes] to the server's settings, each as text. Throws [ApiException] when the
  /// server refuses one or leaves one unwritten; those before it may be written already.
  Future<void> updateSystem(Map<String, String> changes);

  /// How many vectors the server's vector database holds, across every workspace.
  Future<int> vectorCount();

  /// The server's chat embeds.
  Future<List<Embed>> embeds();

  /// Makes a chat embed, and returns its uuid.
  Future<String> createEmbed(NewEmbed embed);

  /// Changes embed [uuid]: whether it is on, and the mode it answers in.
  Future<void> updateEmbed(String uuid, {bool? enabled, EmbedMode? mode});

  Future<void> deleteEmbed(String uuid);

  /// The chats embed [uuid] has held, in the server's order.
  Future<List<EmbedChat>> embedChats(String uuid);
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
