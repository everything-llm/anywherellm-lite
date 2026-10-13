import 'dart:convert';

import 'apps.dart';

/// Where a notification comes from. Each is its own UnifiedPush instance, registered with that
/// server's own VAPID key, since a distributor may tie an endpoint to one sender.
enum PushSource {
  /// AnythingLLM itself, which pushes when a scheduled job ends.
  server('anythingllm', 'Scheduled jobs'),

  /// anythingllm-apps-v2, which pushes an app's `notify`.
  apps('apps', 'Apps');

  const PushSource(this.instance, this.label);

  /// The UnifiedPush instance, and the Android notification channel.
  final String instance;

  /// The channel's name in Android's settings, and the row's on the Notifications page. Android
  /// draws a notification with no Flutter engine, so `PushNotes.kt` keeps its own copy of each.
  final String label;

  static PushSource? ofInstance(String instance) =>
      values.where((source) => source.instance == instance).firstOrNull;
}

/// A device's Web Push subscription (RFC 8030): where a server posts, and the keys it encrypts
/// for (RFC 8291), base64url.
class PushSubscription {
  const PushSubscription(
    this.endpoint, {
    required this.p256dh,
    required this.auth,
  });

  final String endpoint;
  final String p256dh;
  final String auth;

  /// The browser's JSON, which AnythingLLM and the apps server both take.
  Map<String, Object?> toJson() => {
    'endpoint': endpoint,
    'keys': {'p256dh': p256dh, 'auth': auth},
  };

  @override
  bool operator ==(Object other) =>
      other is PushSubscription &&
      other.endpoint == endpoint &&
      other.p256dh == p256dh &&
      other.auth == auth;

  @override
  int get hashCode => Object.hash(endpoint, p256dh, auth);

  /// The endpoint is a capability: anyone who knows it can push to this device.
  @override
  String toString() => 'PushSubscription(endpoint hidden)';
}

/// What tapping a notification opens.
sealed class PushTarget {
  const PushTarget();
}

/// The Upcoming page, where the scheduled jobs are listed.
class UpcomingTarget extends PushTarget {
  const UpcomingTarget();

  @override
  bool operator ==(Object other) => other is UpcomingTarget;

  @override
  int get hashCode => (UpcomingTarget).hashCode;
}

/// An app, opened in its sheet.
class AppTarget extends PushTarget {
  const AppTarget(this.app);

  final AppRef app;

  @override
  bool operator ==(Object other) => other is AppTarget && other.app == app;

  @override
  int get hashCode => app.hashCode;
}

/// What tapping the notification for [payload], a push from [source], opens. Both servers push
/// `{title, body, data}`, the shape of AnythingLLM's scheduled-job pushes: a scheduled job's
/// opens Upcoming, and an app's opens the app its `data` names by `workspace` and `app`, or
/// nothing when it names none. Android draws the notification itself from the same payload.
PushTarget? pushTargetOf(String payload, PushSource source) {
  if (source == PushSource.server) return const UpcomingTarget();
  final Object? json;
  try {
    json = jsonDecode(payload);
  } on FormatException {
    return null;
  }
  if (json case {
    'data': {'workspace': final String workspace, 'app': final String app},
  }) {
    return switch (appRefNamed(workspace, app)) {
      final ref? => AppTarget(ref),
      null => null,
    };
  }
  return null;
}

/// What a UnifiedPush distributor is called, from its Android package name.
String distributorName(String package) => switch (package) {
  'io.heckel.ntfy' => 'ntfy',
  'org.unifiedpush.distributor.sunup' => 'Sunup',
  'org.unifiedpush.distributor.nextpush' => 'NextPush',
  'org.unifiedpush.distributor.fcm' => 'FCM Distributor',
  _ => package,
};
