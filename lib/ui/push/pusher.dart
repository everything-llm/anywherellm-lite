import '../../core/push.dart';

/// What the distributor said about a [PushSource]'s registration.
sealed class PushEvent {
  const PushEvent(this.source);

  final PushSource source;
}

/// The address the source's server pushes to, with the keys it encrypts for.
class PushEndpointEvent extends PushEvent {
  const PushEndpointEvent(super.source, this.subscription);

  final PushSubscription subscription;
}

/// The distributor could not register the source, and [why], in words.
class PushRefusedEvent extends PushEvent {
  const PushRefusedEvent(super.source, this.why);

  final String why;
}

/// The distributor stopped pushing to the source, as when it was uninstalled or reset.
class PushDroppedEvent extends PushEvent {
  const PushDroppedEvent(super.source);
}

/// The device's push notifications: a UnifiedPush distributor, which the servers push to, and
/// the notifications Android shows for each push, which the app does not draw itself.
abstract interface class Pusher {
  /// The distributor in use, by its package name, or null while none is: notifications are on
  /// exactly while one is.
  Future<String?> distributor();

  /// The distributors installed, by package name.
  Future<List<String>> distributors();

  /// Uses the saved distributor, or else the device's default one; false when there is none
  /// to use without asking which.
  Future<bool> useDefault();

  /// Uses [distributor] from now on.
  Future<void> choose(String distributor);

  /// Asks Android to let the app show notifications, where it asks; false when refused.
  Future<bool> askPermission();

  /// Asks the distributor for [source]'s endpoint, tied to [vapid], its server's public key.
  /// The answer comes as a [PushEvent].
  Future<void> register(PushSource source, String vapid);

  /// Stops [source]'s pushes. The last one stopped lets go of the distributor.
  Future<void> unregister(PushSource source);

  /// The distributor's answers, buffered until listened to.
  Stream<PushEvent> get events;

  /// What each notification tapped opens, the one that started the app first; buffered until
  /// listened to.
  Stream<PushTarget> get taps;
}
