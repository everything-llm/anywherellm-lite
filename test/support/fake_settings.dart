import 'package:everything/core/connection.dart';
import 'package:everything/core/ports.dart';
import 'package:everything/core/prefs.dart';

/// A [SettingsStore] that keeps its connection in memory. Set [loadError] or [saveError] to make
/// the keyring fail.
class FakeSettingsStore implements SettingsStore {
  FakeSettingsStore([this.saved]);

  Connection? saved;
  ApiException? loadError;
  ApiException? saveError;

  @override
  Future<Connection?> load() async {
    if (loadError != null) throw loadError!;
    return saved;
  }

  @override
  Future<void> save(Connection connection) async {
    if (saveError != null) throw saveError!;
    saved = connection;
  }

  @override
  Future<void> clear() async {
    if (saveError != null) throw saveError!;
    saved = null;
  }
}

/// A [PrefsStore] in memory. Set [saveError] to make saving fail.
class FakePrefsStore implements PrefsStore {
  FakePrefsStore([this.saved = const Prefs()]);

  Prefs saved;
  ApiException? saveError;

  @override
  Future<Prefs> load() async => saved;

  @override
  Future<void> save(Prefs prefs) async {
    if (saveError != null) throw saveError!;
    saved = prefs;
  }
}
