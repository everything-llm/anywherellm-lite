import 'package:everything/core/connection.dart';
import 'package:everything/core/ports.dart';

/// An [AnythingLlmApi] for widget tests. Set [verifyError] to make [verify] fail.
class FakeAnythingLlm implements AnythingLlmApi {
  /// Every connection [verify] was given, in order.
  final List<Connection> verified = [];
  Object? verifyError;

  @override
  Future<void> verify(Connection connection) async {
    verified.add(connection);
    if (verifyError != null) throw verifyError!;
  }
}

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
