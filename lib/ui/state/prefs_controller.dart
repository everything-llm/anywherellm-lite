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

  Future<void> setGroundedOnly(bool on) => _change(prefs.withGroundedOnly(on));

  Future<void> setOff(String slug, List<OffDoc> docs) =>
      _change(prefs.withOff(slug, docs));

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
