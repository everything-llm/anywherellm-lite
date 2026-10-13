import 'package:anywherellm/core/connection.dart';
import 'package:anywherellm/core/ports.dart';
import 'package:anywherellm/core/prefs.dart';

/// A [SettingsStore] that keeps its connection in memory. Set [loadError] or [saveError] to make
/// the keyring fail.
class FakeSettingsStore implements SettingsStore {
  FakeSettingsStore([this.saved]);

  Connection? saved;

  /// Where the saved connection's companions run, as saved with it.
  Map<String, Uri> savedCompanions = const {};
  ApiException? loadError;
  ApiException? saveError;

  @override
  Future<Pairing?> load() async {
    if (loadError != null) throw loadError!;
    return switch (saved) {
      final saved? => Pairing(saved, savedCompanions),
      null => null,
    };
  }

  @override
  Future<void> save(Pairing pairing) async {
    if (saveError != null) throw saveError!;
    saved = pairing.connection;
    savedCompanions = pairing.companions;
  }

  @override
  Future<void> clear() async {
    if (saveError != null) throw saveError!;
    saved = null;
    savedCompanions = const {};
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
