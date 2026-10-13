import 'dart:async';

import 'package:anywherellm/core/push.dart';
import 'package:anywherellm/ui/push/pusher.dart';

/// A UnifiedPush distributor kept in memory. [installed] are the distributors on the device,
/// [byDefault] the one it uses without asking; [register] answers an endpoint for the source at
/// once unless [refuse] says, in words, why it fails.
class FakePusher implements Pusher {
  FakePusher({
    this.installed = const ['io.heckel.ntfy'],
    this.byDefault = 'io.heckel.ntfy',
  });

  List<String> installed;
  String? byDefault;
  String? using;
  bool allowed = true;
  String? refuse;

  /// Every register and unregister, as `register:<instance>:<vapid>`.
  final calls = <String>[];
  final _events = StreamController<PushEvent>();
  final _taps = StreamController<PushTarget>();

  static PushSubscription endpointOf(PushSource source) => PushSubscription(
    'https://ntfy.sh/up-${source.instance}?up=1',
    p256dh: 'BKey-${source.instance}',
    auth: 'Auth',
  );

  @override
  Future<String?> distributor() async => using;

  @override
  Future<List<String>> distributors() async => installed;

  @override
  Future<bool> useDefault() async {
    using ??= byDefault;
    return using != null;
  }

  @override
  Future<void> choose(String distributor) async => using = distributor;

  @override
  Future<bool> askPermission() async => allowed;

  @override
  Future<void> register(PushSource source, String vapid) async {
    calls.add('register:${source.instance}:$vapid');
    _events.add(
      refuse == null
          ? PushEndpointEvent(source, endpointOf(source))
          : PushRefusedEvent(source, refuse!),
    );
  }

  @override
  Future<void> unregister(PushSource source) async {
    calls.add('unregister:${source.instance}');
    using = null;
  }

  /// The distributor stops pushing to [source].
  void drop(PushSource source) => _events.add(PushDroppedEvent(source));

  /// A notification is tapped.
  void tap(PushTarget target) => _taps.add(target);

  @override
  Stream<PushEvent> get events => _events.stream;

  @override
  Stream<PushTarget> get taps => _taps.stream;
}
