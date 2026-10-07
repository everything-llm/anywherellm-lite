import '../core/ports.dart';
import '../core/prefs.dart';

/// Stands in for the browser's [PrefsStore] outside a browser, where `main.dart` never builds it.
class BrowserPrefsStore implements PrefsStore {
  @override
  Future<Prefs> load() => throw UnsupportedError('Only in a browser.');

  @override
  Future<void> save(Prefs prefs) =>
      throw UnsupportedError('Only in a browser.');
}
