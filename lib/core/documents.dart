import 'futures.dart';
import 'ports.dart';
import 'server_models.dart';

/// A document and the workspaces that hold it.
class DocumentView {
  const DocumentView({required this.doc, required this.holders});

  final DocEntry doc;
  final List<Workspace> holders;
}

/// The document at [path] (`folder/name`) and the workspaces that hold it.
///
/// Which workspaces hold a document is read from each workspace's own list, since the
/// documents list leaves `pinnedWorkspaces` empty. That costs one call per workspace.
Future<DocumentView> openDocument(AnythingLlmApi api, String path) async {
  final (folders, workspaces) = await both(
    api.documents(),
    api.workspaces().then(
      (summaries) => Future.wait([
        for (final summary in summaries) api.workspace(summary.slug),
      ]),
    ),
  );
  final doc = folders
      .expand((folder) => folder.docs)
      .where((doc) => doc.path == path)
      .firstOrNull;
  if (doc == null) {
    throw ApiException(
      'There is no document $path on the server.',
      status: 404,
    );
  }
  return DocumentView(
    doc: doc,
    holders: [
      for (final workspace in workspaces)
        if (workspace.documents.any((held) => held.path == path)) workspace,
    ],
  );
}
