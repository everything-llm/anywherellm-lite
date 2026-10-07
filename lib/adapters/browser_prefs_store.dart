import 'package:web/web.dart' as web;

import '../core/ports.dart';
import '../core/prefs.dart';

/// [PrefsStore] in the browser's local storage for this page's origin, as one JSON entry. Holds
/// nothing secret: the key is kept by [KeyringSettingsStore].
class BrowserPrefsStore implements PrefsStore {
  static const _entry = 'anywherellm.prefs';

  @override
  Future<Prefs> load() async {
    try {
      final stored = web.window.localStorage.getItem(_entry);
      return stored == null ? const Prefs() : Prefs.decode(stored);
    } on Object {
      return const Prefs();
    }
  }

  @override
  Future<void> save(Prefs prefs) async {
    try {
      web.window.localStorage.setItem(_entry, prefs.encode());
    } on Object {
      throw const ApiException(
        'Could not save the app\'s preferences in the browser\'s storage.',
      );
    }
  }
}
