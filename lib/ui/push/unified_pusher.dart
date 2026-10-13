import 'dart:async';

import 'package:flutter/services.dart';
import 'package:unifiedpush_android/unifiedpush_android.dart';
import 'package:unifiedpush_platform_interface/data/failed_reason.dart';
import 'package:unifiedpush_platform_interface/data/push_endpoint.dart';
import 'package:unifiedpush_platform_interface/unifiedpush_platform_interface.dart';

import '../../core/push.dart';
import 'pusher.dart';

/// The [Pusher] over UnifiedPush's Android connector. The app's own `PushEvents` service shows
/// each push as a notification itself, with no Flutter engine, so one arrives while the app is
/// closed; it hands the distributor's other answers to the connector's Flutter plugin, which
/// buffers them until [UnifiedPushPlatform.initializeCallback]. `MainActivity` asks for the
/// notification permission and hands each tapped notification over the `anywherellm/push`
/// channel.
class UnifiedPusher implements Pusher {
  UnifiedPusher() {
    _ready = _start();
  }

  static const _native = MethodChannel('anywherellm/push');

  late final Future<void> _ready;
  final _events = StreamController<PushEvent>();
  final _taps = StreamController<PushTarget>();

  UnifiedPushPlatform get _up => UnifiedPushPlatform.instance;

  Future<void> _start() async {
    // The app depends on the Android implementation alone, so it registers it itself.
    if (_up is! UnifiedPushAndroid) UnifiedPushAndroid.registerWith();
    _native.setMethodCallHandler((call) async {
      if (call.method == 'tap') _tapped(call.arguments);
    });
    await _up.initializeCallback(
      onNewEndpoint: _endpoint,
      onRegistrationFailed: (reason, instance) {
        final source = PushSource.ofInstance(instance);
        if (source != null) {
          _events.add(PushRefusedEvent(source, _refused(reason)));
        }
      },
      onUnregistered: (instance) {
        final source = PushSource.ofInstance(instance);
        if (source != null) _events.add(PushDroppedEvent(source));
      },
      // PushEvents shows every push; none reaches Dart.
      onMessage: (_, _) {},
    );
    _tapped(await _native.invokeMethod<Object?>('launchTap'));
  }

  void _endpoint(PushEndpoint endpoint, String instance) {
    final source = PushSource.ofInstance(instance);
    final keys = endpoint.pubKeySet;
    // A server can only encrypt for a device that sent its keys.
    if (source == null || keys == null) return;
    _events.add(
      PushEndpointEvent(
        source,
        PushSubscription(endpoint.url, p256dh: keys.pubKey, auth: keys.auth),
      ),
    );
  }

  static String _refused(FailedReason reason) => switch (reason) {
    FailedReason.network =>
      'The distributor could not reach its server. Try again later.',
    FailedReason.actionRequired =>
      'Open the distributor app: it needs you to finish setting it up.',
    FailedReason.vapidRequired =>
      'The distributor wants a server key it was not given.',
    FailedReason.internalError =>
      'The distributor could not register this app.',
  };

  /// A tapped notification, as `MainActivity` hands it over: its source's instance and the
  /// push's payload as text.
  void _tapped(Object? tap) {
    if (tap is! Map) return;
    final source = PushSource.ofInstance('${tap['instance']}');
    final payload = tap['payload'];
    if (source == null || payload is! String) return;
    if (pushTargetOf(payload, source) case final target?) _taps.add(target);
  }

  @override
  Future<String?> distributor() async {
    await _ready;
    return _up.getDistributor();
  }

  @override
  Future<List<String>> distributors() async {
    await _ready;
    return _up.getDistributors(const []);
  }

  @override
  Future<bool> useDefault() async {
    await _ready;
    return _up.tryUseCurrentOrDefaultDistributor();
  }

  @override
  Future<void> choose(String distributor) async {
    await _ready;
    await _up.saveDistributor(distributor);
  }

  @override
  Future<bool> askPermission() async {
    await _ready;
    return await _native.invokeMethod<bool>('askPermission') ?? false;
  }

  @override
  Future<void> register(PushSource source, String vapid) async {
    await _ready;
    await _up.register(source.instance, const [], null, vapid);
  }

  @override
  Future<void> unregister(PushSource source) async {
    await _ready;
    await _up.unregister(source.instance);
  }

  @override
  Stream<PushEvent> get events => _events.stream;

  @override
  Stream<PushTarget> get taps => _taps.stream;
}
