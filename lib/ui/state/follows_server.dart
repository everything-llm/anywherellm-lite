import 'package:flutter/foundation.dart';

import '../../core/connection.dart';
import 'settings_controller.dart';

/// A controller whose state is about the server in use. [followServer] starts it listening to
/// the settings: when another server is in use, [leavingServer] runs while what it holds is
/// still about the one before, and then [serverChanged], to start afresh. A call that took
/// [here] before it was sent tells by it, once answered, whether its answer is still about the
/// server in use.
mixin FollowsServer on ChangeNotifier {
  late final SettingsController _settings;
  Object? _key;
  Connection? _server;

  /// Counts the times [serverKey] changed, so an answer from before tells even after it came back.
  int _changes = 0;

  /// The server the state is about.
  Connection? get server => _server;

  /// What the state follows, whose change starts it afresh: the connection in use, compared as
  /// a connection.
  @protected
  Object? get serverKey => _settings.connection;

  /// Starts following the server [settings] put in use.
  @protected
  void followServer(SettingsController settings) {
    _settings = settings;
    _server = settings.connection;
    _key = serverKey;
    settings.addListener(_settingsChanged);
  }

  /// The server in use now, for a call to check its answer against.
  ServerAt get here => ServerAt._(this);

  /// Runs as another server is about to be in use, while [server] is still the one before.
  @protected
  void leavingServer() {}

  /// Starts afresh on [server], now in use in place of [was].
  @protected
  void serverChanged(Connection? was);

  void _settingsChanged() {
    final key = serverKey;
    if (key == _key) return;
    leavingServer();
    final was = _server;
    _key = key;
    _server = _settings.connection;
    _changes++;
    serverChanged(was);
  }

  @override
  void dispose() {
    _settings.removeListener(_settingsChanged);
    super.dispose();
  }
}

/// The server a [FollowsServer] was on when a call was sent, to tell once it is answered
/// whether its answer is still about the server in use.
final class ServerAt {
  ServerAt._(this._owner) : server = _owner._server, _changes = _owner._changes;

  final FollowsServer _owner;

  /// The server in use when this was taken.
  final Connection? server;
  final int _changes;

  /// Whether [server] is the server in use, compared as a connection: one put in use again after
  /// another counts.
  bool get current => _owner._server == server;

  /// Whether what the controller follows has not changed since, not even and back again.
  bool get unchanged => _owner._changes == _changes;
}
