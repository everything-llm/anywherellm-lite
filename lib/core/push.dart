import 'dart:convert';

import 'apps.dart';

/// Where a notification comes from. Each is its own UnifiedPush instance, registered with that
/// server's own VAPID key, since a distributor may tie an endpoint to one sender.
enum PushSource {
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

  /// The browser's JSON, which the apps server takes.
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

/// An app, opened in its sheet.
class AppTarget extends PushTarget {
  const AppTarget(this.app);

  final AppRef app;

  @override
  bool operator ==(Object other) => other is AppTarget && other.app == app;

  @override
  int get hashCode => app.hashCode;
}

/// A chat, opened full screen.
class ChatTarget extends PushTarget {
  const ChatTarget(this.slug, this.thread);

  final String slug;
  final String thread;

  @override
  bool operator ==(Object other) =>
      other is ChatTarget && other.slug == slug && other.thread == thread;

  @override
  int get hashCode => Object.hash(slug, thread);
}

/// The Android channel of the app's own notifications that an answer is ready, beside each
/// [PushSource]'s.
const answersChannel = 'answers';

/// What tapping a notification opens: [payload] is what it was drawn from, `{title, body,
/// data}`, on the channel [channel]. An app's opens the app its `data` names by `workspace` and
/// `app`; an answer's opens the chat its `data` names by `workspace` and `thread`; anything else
/// opens nothing.
PushTarget? tapTargetOf(String channel, String payload) {
  Object? json;
  try {
    json = jsonDecode(payload);
  } on FormatException {
    json = null;
  }
  final data = json is Map ? json['data'] : null;
  return switch ((channel, data)) {
    (final apps, {'workspace': final String workspace, 'app': final String app})
        when apps == PushSource.apps.instance =>
      switch (appRefNamed(workspace, app)) {
        final ref? => AppTarget(ref),
        null => null,
      },
    (
      answersChannel,
      {'workspace': final String slug, 'thread': final String thread},
    )
        when slug.isNotEmpty && thread.isNotEmpty =>
      ChatTarget(slug, thread),
    _ => null,
  };
}

/// The payload of the notification that the answer in chat [thread] of workspace [slug] is
/// ready, which [tapTargetOf] reads back.
String answerReadyPayload({
  required String title,
  required String body,
  required String slug,
  required String thread,
}) => jsonEncode({
  'title': title,
  'body': body,
  'data': {'workspace': slug, 'thread': thread},
});

/// What a UnifiedPush distributor is called, from its Android package name.
String distributorName(String package) => switch (package) {
  'io.heckel.ntfy' => 'ntfy',
  'org.unifiedpush.distributor.sunup' => 'Sunup',
  'org.unifiedpush.distributor.nextpush' => 'NextPush',
  'org.unifiedpush.distributor.fcm' => 'FCM Distributor',
  _ => package,
};
