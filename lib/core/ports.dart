import 'dart:typed_data';

import 'chat.dart';
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

  /// Makes a workspace called [name], with [prompt] as its system prompt, or the server's
  /// default when it is null.
  Future<Workspace> createWorkspace(String name, {String? prompt});

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

  /// The chat's turns, oldest first. A null [thread], here and in [streamChat] and [resetChat],
  /// is the workspace's Main chat, which is in no thread.
  Future<List<ChatMessage>> history(String slug, String? thread);

  /// Asks [message] in the chat, with [attachments] for this message only, and streams the
  /// answer in [mode], or in the workspace's own chat mode when it is null. The stream fails
  /// with [ApiException]. Cancelling the subscription lets go of the answer, which stops it,
  /// though an agent may still finish it and save it to the chat.
  Stream<ChatEvent> streamChat(
    String slug,
    String? thread,
    String message, {
    List<Attachment> attachments = const [],
    ChatMode? mode,
  });

  /// Clears the chat's history: the model no longer sees its exchanges, and history no longer
  /// lists them. The server keeps the rows, and nothing here brings them back.
  Future<void> resetChat(String slug, String? thread);

  /// Embeds the documents at [adds] in the workspace and drops those at [deletes], by
  /// `folder/name.json` path.
  Future<void> updateEmbeddings(
    String slug, {
    List<String> adds = const [],
    List<String> deletes = const [],
  });

  /// The file extensions the server can read in, lower case with the dot: `.md`.
  Future<Set<String>> acceptedExtensions();

  /// Sends [bytes] as the file [name] into the server's default library folder, with the
  /// details in [meta], and returns the documents the server made of it. Attaches them to no
  /// workspace.
  Future<List<DocEntry>> upload(
    String name,
    List<int> bytes, {
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

  /// The passages of workspace [slug]'s documents that [query] finds, closest first, with the
  /// workspace's own number and threshold, as an answer would get them.
  Future<List<SearchHit>> searchDocs(String slug, String query);

  /// The bytes of a file or image an agent made, by the [storageName] the server gave it.
  Future<List<int>> generatedFile(String storageName);

  /// The bytes of the image at [url], from an answer. Sent without the key.
  Future<Uint8List> answerImage(Uri url);

  /// The server's settings, with every secret replaced by whether it is set.
  Future<Map<String, Object?>> systemSettings();

  /// Writes [changes] to the server's settings, each as text. Throws [ApiException] when the
  /// server refuses one or leaves one unwritten; those before it may be written already.
  Future<void> updateSystem(Map<String, String> changes);

  /// How many vectors the server's vector database holds, across every workspace.
  Future<int> vectorCount();
}

/// Where the connection is kept between runs.
abstract interface class SettingsStore {
  /// The saved connection, or null when none is saved. Throws [ApiException] when the store
  /// cannot be read.
  Future<Connection?> load();

  /// Throws [ApiException] when the store cannot be written.
  Future<void> save(Connection saved);

  Future<void> clear();
}

/// Where [Prefs] are kept between runs.
abstract interface class PrefsStore {
  /// The saved prefs, or the defaults when none are saved or they cannot be read.
  Future<Prefs> load();

  /// Throws [ApiException] when the prefs cannot be written.
  Future<void> save(Prefs prefs);
}
