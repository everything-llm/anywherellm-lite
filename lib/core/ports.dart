import 'connection.dart';
import 'models.dart';
import 'server_models.dart';

export 'errors.dart';

/// The AnythingLLM server, as the UI sees it. Every method throws [ApiException] on failure.
/// Every method but [verify] uses the connection in use, and throws [NotConfigured] when there
/// is none.
abstract interface class AnythingLlmApi {
  /// Asks the server whether [connection] opens it. Takes the connection as an argument so
  /// Settings can test one before it is saved.
  Future<void> verify(Connection connection);

  /// Every workspace, without its documents.
  Future<List<Workspace>> workspaces();

  /// One workspace with its documents. A missing one is an [ApiException] with status 404.
  Future<Workspace> workspace(String slug);

  /// Every document, by folder.
  Future<List<DocFolder>> documents();

  /// The file extensions the server can read in, lower case with the dot: `.md`.
  Future<Set<String>> acceptedExtensions();

  /// Sends [bytes] as the file [name] into [folder], or the server's default folder, and
  /// returns the documents the server made of it. Attaches them to no workspace.
  Future<List<DocEntry>> upload(String name, List<int> bytes, {String? folder});
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

/// The nils libraries and inbox, as the UI sees them. Every method throws [ApiException] on
/// failure.
abstract interface class NilsApi {
  Future<Overview> overview();
  Future<List<ResearchEntry>> research();
  Future<ResearchDoc> researchDoc(String path);
  Future<List<SkillMeta>> skills();
  Future<SkillDoc> skillDoc(String name);
  Future<List<String>> inbox();

  /// Stages [bytes] as [name]. nils may rename it, so read the inbox for what was staged.
  Future<void> upload(String name, List<int> bytes);
}
