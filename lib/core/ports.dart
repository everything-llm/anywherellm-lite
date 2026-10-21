import 'dart:typed_data';

import 'activity.dart';
import 'chat.dart';
import 'companion.dart';
import 'connection.dart';
import 'memory.dart';
import 'prefs.dart';
import 'schedule.dart';
import 'server_models.dart';
import 'skill_pages.dart';
import 'toolkit.dart';

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

  /// The chat's turns, oldest first.
  Future<List<ChatMessage>> history(String slug, String thread);

  /// Asks [message] in the chat, with [attachments] for this message only, and streams the
  /// answer in [mode], or in the workspace's own chat mode when it is null. The stream fails
  /// with [ApiException]. Cancelling the subscription lets go of the answer, which stops it,
  /// though an agent may still finish it and save it to the chat.
  Stream<ChatEvent> streamChat(
    String slug,
    String thread,
    String message, {
    List<Attachment> attachments = const [],
    ChatMode? mode,
  });

  /// Clears the chat's history: the model no longer sees its exchanges, and history no longer
  /// lists them. The server keeps the rows, and nothing here brings them back.
  Future<void> resetChat(String slug, String thread);

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

  /// The library document at [path], `folder/name.json`.
  Future<DocBody> document(String path);

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

/// A [Companion]: a server that may run beside AnythingLLM on its host and takes the same
/// developer key.
abstract interface class CompanionApi {
  /// Which companion this is.
  Companion get companion;

  /// The features the companion's `/health` offers beside the server in use, asked without the
  /// key, or null when it is not there. Remembered for the connection; [again] asks afresh.
  /// Never throws.
  Future<Set<String>?> features({bool again = false});
}

/// The toolkit, anythingllm-toolkit: AnythingLLM's saved memories and scheduled jobs, which
/// its developer API lacks, through the toolkit's bridge to its internal API, as the
/// [ToolkitFeature]s the bridge allows. Every method but [features] uses the
/// connection in use and throws [ApiException] on failure, [NotConfigured] when there is none.
abstract interface class ToolkitApi implements CompanionApi {
  /// Where the suite's Library and Vault pages are now. The paths are bearer capabilities: the
  /// caller opens one and keeps none. Fails with status 401 or 403 for a key the bridge does not
  /// take for this route.
  Future<SkillPages> pages();

  /// The jobs AnythingLLM runs on a schedule. Times are UTC.
  Future<List<ScheduledJob>> scheduledJobs();

  /// What the agent did, newest first: the events before the one named [before] when it is
  /// given, up to [limit].
  Future<ActivityEvents> activity({String? before, int limit = 50});

  /// The latest runs of job [id], newest first.
  Future<List<JobRun>> jobRuns(String id, {int limit = 5});

  /// Makes a job, switched on.
  Future<void> createJob(JobDraft draft);

  /// Replaces job [id]'s name, prompt and schedule with [draft]'s.
  Future<void> updateJob(String id, JobDraft draft);

  /// Switches job [id] on or off.
  Future<void> setJobEnabled(String id, bool enabled);

  Future<void> deleteJob(String id);

  /// Starts one run of job [id] at once, and answers without waiting for it. Fails when one is
  /// already running or waiting.
  Future<void> runJob(String id);

  /// Whether the server keeps saved memories, and saves them from chats itself.
  Future<MemorySwitches> memorySwitches();

  /// Turns saved memories, or the server saving them from chats, on or off; null leaves one as
  /// it is.
  Future<void> setMemorySwitches({bool? enabled, bool? learn});

  /// The saved memories workspace [slug]'s chats are shown. Fails with status 403 while the
  /// server keeps none.
  Future<SavedMemories> savedMemories(String slug);

  /// Saves [text] for every workspace when [global], else for workspace [slug]. A full list is
  /// an [ApiException] in the server's words.
  Future<SavedMemory> addMemory(
    String slug,
    String text, {
    required bool global,
  });

  Future<SavedMemory> editMemory(int id, String text);

  Future<void> deleteMemory(int id);

  /// Shows memory [id] in every workspace's chats, or, given [toWorkspace], in that workspace's
  /// only.
  Future<SavedMemory> moveMemory(int id, {String? toWorkspace});
}

/// Where the connection is kept between runs.
abstract interface class SettingsStore {
  /// The saved connection, with where its companions run when that was said, or null when none
  /// is saved. Throws [ApiException] when the store cannot be read.
  Future<Pairing?> load();

  /// Throws [ApiException] when the store cannot be written.
  Future<void> save(Pairing saved);

  Future<void> clear();
}

/// Where [Prefs] are kept between runs.
abstract interface class PrefsStore {
  /// The saved prefs, or the defaults when none are saved or they cannot be read.
  Future<Prefs> load();

  /// Throws [ApiException] when the prefs cannot be written.
  Future<void> save(Prefs prefs);
}
