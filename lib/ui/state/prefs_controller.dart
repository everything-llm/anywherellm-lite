import 'package:flutter/foundation.dart';

import '../../core/ports.dart';
import '../../core/prefs.dart';
import 'notice.dart';

/// The app's preferences: read once at start, written on every change.
class PrefsController extends ChangeNotifier {
  PrefsController(this._store);

  final PrefsStore _store;

  Prefs prefs = const Prefs();

  /// Why the last change could not be saved. The change still holds for this run.
  Notice? problem;

  Future<void> load() async {
    prefs = await _store.load();
    notifyListeners();
  }

  Future<void> setOff(String slug, List<OffDoc> docs) =>
      _change(prefs.withOff(slug, docs));

  /// Arranges the workspaces as [slugs].
  Future<void> setWorkspaceOrder(List<String> slugs) =>
      _change(prefs.withOrder(slugs));

  /// Drops a deleted workspace from the arrangement.
  Future<void> forgetWorkspace(String slug) async {
    if (prefs.workspaceOrder.contains(slug)) {
      await _change(prefs.withoutWorkspace(slug));
    }
  }

  /// Keeps a workspace whose slug changed where it stands in the arrangement.
  Future<void> renameWorkspace(String from, String to) async {
    if (prefs.workspaceOrder.contains(from)) {
      await _change(prefs.withRenamedWorkspace(from, to));
    }
  }

  Future<void> setTheme(ThemePref theme) => _change(prefs.withTheme(theme));

  Future<void> setTextSize(TextSize size) => _change(prefs.withTextSize(size));

  /// Forgets the documents at [paths] wherever they were switched off, as when they are deleted.
  Future<void> forgetDocs(Iterable<String> paths) async {
    final next = prefs.withoutDocs(paths.toSet());
    if (next.encode() != prefs.encode()) await _change(next);
  }

  Future<void> _change(Prefs next) async {
    prefs = next;
    notifyListeners();
    final before = problem;
    try {
      await _store.save(next);
      problem = null;
    } on ApiException catch (error) {
      problem = Notice('Could not save your preferences', error.message);
    }
    if (problem != before) notifyListeners();
  }
}
