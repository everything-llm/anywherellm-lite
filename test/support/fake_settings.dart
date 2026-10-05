import 'package:everything/core/connection.dart';
import 'package:everything/core/ports.dart';

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
