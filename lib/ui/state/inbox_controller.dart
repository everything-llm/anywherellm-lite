import 'package:flutter/foundation.dart';

import '../../core/copy.dart';
import '../../core/ports.dart';
import 'overview_controller.dart';

/// A file to stage. The UI wraps whatever the file picker or a drop gave it. [length] and
/// [read] throw [UnreadableFile] for something that cannot be read, such as a folder.
class UploadFile {
  const UploadFile({
    required this.name,
    required this.length,
    required this.read,
  });

  final String name;
  final Future<int> Function() length;
  final Future<List<int>> Function() read;
}

/// Why a dropped or picked file could not be read, in the system's words.
class UnreadableFile implements Exception {
  const UnreadableFile(this.message);
  final String message;

  @override
  String toString() => message;
}

/// A problem to show on the Inbox page.
class Notice {
  const Notice(this.title, this.text);
  final String title;
  final String text;
}

/// The files staged for adding, and staging more.
class InboxController extends ChangeNotifier {
  InboxController(this._api, this._overview);

  final NilsApi _api;

  /// Where nils's size limit is read, each time a file is staged.
  final OverviewController _overview;

  List<String> staged = const [];

  Notice? _unreadable;
  final List<Notice> _refused = [];

  /// Why the inbox could not be read, then why the last files could not be staged.
  List<Notice> get problems => [?_unreadable, ..._refused];

  Future<void> refresh() async {
    try {
      staged = await _api.inbox();
      _unreadable = null;
    } on ApiException catch (error) {
      _unreadable = Notice('Could not read the inbox', error.message);
    }
    notifyListeners();
  }

  void report(String title, String text) {
    _refused.add(Notice(title, text));
    notifyListeners();
  }

  /// Stages each file in turn. Each one that cannot be staged says why, and the rest still go.
  Future<void> upload(List<UploadFile> files) async {
    if (files.isEmpty) return;
    _refused.clear();
    notifyListeners();
    for (final file in files) {
      void refused(String why) =>
          _refused.add(Notice('Could not stage ${file.name}', why));
      try {
        final tooBig = uploadProblem(await file.length(), _overview.limits);
        if (tooBig != null) throw ApiException(tooBig);
        await _api.upload(file.name, await file.read());
      } on ApiException catch (error) {
        refused(error.message);
      } on UnreadableFile catch (error) {
        refused(error.message);
      }
    }
    await refresh();
  }
}
