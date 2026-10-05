import 'package:flutter/foundation.dart';

import '../../core/connection.dart';
import '../../core/futures.dart';
import '../../core/ports.dart';
import '../../core/server_models.dart';
import '../../core/upload.dart';
import 'notice.dart';

/// Sending files to the server: what it reads, which folder they go in, and what came of them.
/// Everything it knows is about the server in [_holder]; a new server starts it afresh.
class UploadController extends ChangeNotifier {
  UploadController(this._api, this._holder);

  final AnythingLlmApi _api;
  final ConnectionHolder _holder;

  /// The connection the fields below describe.
  Connection? _server;

  /// The extensions the server reads, or null when it has not said. Then the server decides.
  Set<String>? accepted;

  /// The folders on the server, for the folder choice. Always holds [folder].
  List<String> folders = const [defaultFolder];

  /// Where the next files go.
  String folder = defaultFolder;

  /// The documents made by the uploads so far, newest first.
  List<DocEntry> uploaded = const [];

  /// The file being sent now, or null.
  String? sending;

  Notice? _unreadable;
  final List<Notice> _refused = [];

  /// Why the server's file types or folders could not be read, then why the last files could
  /// not be sent.
  List<Notice> get problems => [?_unreadable, ..._refused];

  /// Asks the server what it reads and which folders it has. On a different server than last
  /// time, first forgets what was known of the old one.
  Future<void> refresh() async {
    if (_holder.current != _server) {
      _server = _holder.current;
      accepted = null;
      folder = defaultFolder;
      folders = const [defaultFolder];
      uploaded = const [];
      _refused.clear();
    }
    try {
      final (types, found) = await both(
        _api.acceptedExtensions(),
        _api.documents(),
      );
      accepted = types;
      folders = {defaultFolder, for (final f in found) f.name, folder}.toList();
      _unreadable = null;
    } on ApiException catch (error) {
      _unreadable = Notice(
        'Could not ask the server what it reads',
        error.message,
      );
    }
    notifyListeners();
  }

  void choose(String folder) {
    if (folder == this.folder) return;
    this.folder = folder;
    notifyListeners();
  }

  void report(String title, String text) {
    _refused.add(Notice(title, text));
    notifyListeners();
  }

  /// Sends each file in turn. Each one that cannot be sent says why, and the rest still go.
  Future<void> upload(List<UploadFile> files) async {
    if (files.isEmpty) return;
    _refused.clear();
    for (final file in files) {
      sending = file.name;
      notifyListeners();
      void refused(String why) =>
          _refused.add(Notice('Could not upload ${file.name}', why));
      try {
        final wrongType = extensionProblem(file.name, accepted);
        if (wrongType != null) throw ApiException(wrongType);
        final made = await _api.upload(
          file.name,
          await file.read(),
          folder: folder,
        );
        uploaded = [...made, ...uploaded];
      } on ApiException catch (error) {
        refused(error.message);
      } on UnreadableFile catch (error) {
        refused(error.message);
      }
    }
    sending = null;
    notifyListeners();
  }
}
