import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/ports.dart';
import '../../core/push.dart';
import '../push/pusher.dart';
import 'apps_controller.dart';
import 'chat_controller.dart';
import 'settings_controller.dart';
import 'shell_controller.dart';

enum PushStatus { waiting, on, unavailable, failed }

/// Where one [PushSource]'s notifications stand, and why, in words, when they do not arrive.
class PushState {
  const PushState(this.status, [this.why]);

  final PushStatus status;
  final String? why;
}

/// Push notifications on this device, from AnythingLLM's scheduled jobs and from the apps
/// server's apps. They are on while the [Pusher] has a distributor. Each source registers with
/// its server's key whenever the server in use, its password or the apps server changes, and at
/// every start, and sends the endpoint the distributor answers to its server. A tapped
/// notification, these or the app's own that an answer is ready, opens Upcoming, its app or its
/// chat.
class PushController extends ChangeNotifier {
  PushController(
    this._pusher,
    this._llm,
    this._appsApi,
    this._settings,
    this._chat,
    this._apps,
    this._shell,
  ) {
    _settings.addListener(_changed);
    _chat.addListener(_changed);
    _apps.addListener(_changed);
    _eventsSeen = _pusher.events.listen(_event);
    _tapsSeen = _pusher.taps.listen(_open);
  }

  final Pusher _pusher;
  final AnythingLlmApi _llm;
  final AppsApi _appsApi;
  final SettingsController _settings;
  final ChatController _chat;
  final AppsController _apps;
  final ShellController _shell;
  late final StreamSubscription<PushEvent> _eventsSeen;
  late final StreamSubscription<PushTarget> _tapsSeen;

  /// Whether notifications are on: null until [load] asks the distributor.
  bool? on;

  /// The distributors to choose among, while more than one is installed and none is the
  /// device's default.
  List<String>? choices;

  /// Why notifications could not be turned on.
  String? problem;

  /// Each source's state while [on].
  final states = <PushSource, PushState>{};

  /// What each source last registered for: its server, and for [PushSource.server] whether the
  /// app is signed in, or for [PushSource.apps] whether the apps server is there.
  final _seen = <PushSource, Object>{};

  /// The endpoint the distributor last gave [PushSource.apps], which turning off unsubscribes.
  String? _appsEndpoint;

  Future<void> load() async {
    on = await _pusher.distributor() != null;
    notifyListeners();
    _changed();
  }

  /// What [source] registers for, compared by value; the password alone does not change it.
  Object? _keyOf(PushSource source) {
    final server = _settings.connection?.withPassword(null);
    if (server == null) return null;
    return switch (source) {
      PushSource.server => (server, _chat.signedIn, _settings.auth),
      PushSource.apps => (server, _apps.available),
    };
  }

  void _changed() {
    if (on != true) return;
    for (final source in PushSource.values) {
      final key = _keyOf(source);
      if (key == _seen[source]) continue;
      if (key == null) {
        _seen.remove(source);
        _set(
          source,
          const PushState(PushStatus.unavailable, 'Connect to a server first.'),
        );
        continue;
      }
      _seen[source] = key;
      unawaited(_register(source, key));
    }
  }

  void _set(PushSource source, PushState state) {
    states[source] = state;
    notifyListeners();
  }

  /// Why [source] cannot push from the server in use, or null when it can.
  Future<PushState?> _blocked(PushSource source) async {
    switch (source) {
      case PushSource.server:
        if (_chat.signedIn) return null;
        return switch (_settings.auth) {
          null => const PushState(PushStatus.waiting),
          ServerAuth.multiUser => const PushState(
            PushStatus.unavailable,
            'A server with several users does not send this app notifications.',
          ),
          _ => const PushState(
            PushStatus.unavailable,
            'Needs the server password. Add it on the Connection page.',
          ),
        };
      case PushSource.apps:
        return switch (_apps.available) {
          null => const PushState(PushStatus.waiting),
          false => const PushState(
            PushStatus.unavailable,
            'No apps server runs beside this server.',
          ),
          true when !await _appsApi.canPush() => const PushState(
            PushStatus.unavailable,
            'This apps server cannot send notifications. Update it.',
          ),
          true => null,
        };
    }
  }

  Future<void> _register(PushSource source, Object key) async {
    final blocked = await _blocked(source);
    if (_seen[source] != key) return;
    if (blocked != null) return _set(source, blocked);
    _set(source, const PushState(PushStatus.waiting));
    try {
      final vapid = await switch (source) {
        PushSource.server => _llm.pushKey(),
        PushSource.apps => _appsApi.pushKey(),
      };
      if (_seen[source] != key) return;
      await _pusher.register(source, vapid);
    } on ApiException catch (error) {
      if (_seen[source] == key) {
        _set(source, PushState(PushStatus.failed, error.message));
      }
    }
  }

  Future<void> _event(PushEvent event) async {
    final source = event.source;
    if (on != true) return;
    switch (event) {
      case PushEndpointEvent(:final subscription):
        if (source == PushSource.apps) _appsEndpoint = subscription.endpoint;
        // An endpoint for a source that cannot push now, as one replayed from before, waits.
        final key = _seen[source];
        if (key == null || states[source]?.status == PushStatus.unavailable) {
          return;
        }
        try {
          await switch (source) {
            PushSource.server => _llm.subscribePush(subscription),
            PushSource.apps => _appsApi.subscribePush(subscription),
          };
          if (_seen[source] == key) {
            _set(source, const PushState(PushStatus.on));
          }
        } on ApiException catch (error) {
          if (_seen[source] == key) {
            _set(source, PushState(PushStatus.failed, error.message));
          }
        }
      case PushRefusedEvent(:final why):
        _set(source, PushState(PushStatus.failed, why));
      case PushDroppedEvent():
        if (source == PushSource.apps) _appsEndpoint = null;
        _set(
          source,
          const PushState(
            PushStatus.failed,
            'The distributor stopped sending these. Turn notifications off and on again.',
          ),
        );
    }
  }

  /// Turns notifications on with the device's distributor, or offers [choices] when there are
  /// several and none is the default.
  Future<void> turnOn() async {
    problem = null;
    choices = null;
    notifyListeners();
    if (!await _pusher.askPermission()) {
      problem = 'Android does not let this app show notifications. Allow them in its settings.';
      return notifyListeners();
    }
    if (await _pusher.distributor() == null && !await _pusher.useDefault()) {
      final found = await _pusher.distributors();
      if (found.isEmpty) {
        problem = 'Install a UnifiedPush distributor, such as ntfy, then turn notifications on.';
        return notifyListeners();
      }
      if (found.length > 1) {
        choices = found;
        return notifyListeners();
      }
      await _pusher.choose(found.single);
    }
    _started();
  }

  /// Turns notifications on with [distributor], one of [choices].
  Future<void> choose(String distributor) async {
    choices = null;
    await _pusher.choose(distributor);
    _started();
  }

  void _started() {
    on = true;
    _seen.clear();
    states.clear();
    notifyListeners();
    _changed();
  }

  /// Stops every source's pushes. The apps server forgets the device; AnythingLLM has no way to,
  /// and finds the endpoint gone.
  Future<void> turnOff() async {
    final apps = _appsEndpoint;
    on = false;
    choices = null;
    problem = null;
    _seen.clear();
    states.clear();
    _appsEndpoint = null;
    notifyListeners();
    if (apps != null && _apps.available == true) {
      try {
        await _appsApi.unsubscribePush(apps);
      } on ApiException {
        // The distributor drops the endpoint below, which the apps server then forgets itself.
      }
    }
    await Future.wait([
      for (final source in PushSource.values) _pusher.unregister(source),
    ]);
  }

  void _open(PushTarget target) {
    switch (target) {
      case UpcomingTarget():
        _shell.showTab(HomeTab.chats);
        _shell.openUpcoming();
      case AppTarget(:final app):
        _shell.openApp(app);
      case ChatTarget(:final slug, :final thread):
        _shell.showTab(HomeTab.chats);
        unawaited(_chat.select(slug, thread: thread));
        _shell.openChat();
    }
  }

  @override
  void dispose() {
    unawaited(_eventsSeen.cancel());
    unawaited(_tapsSeen.cancel());
    _settings.removeListener(_changed);
    _chat.removeListener(_changed);
    _apps.removeListener(_changed);
    super.dispose();
  }
}
