import 'dart:convert';

/// A chat, opened full screen.
class ChatTarget {
  const ChatTarget(this.slug, this.thread);

  final String slug;
  final String thread;

  @override
  bool operator ==(Object other) =>
      other is ChatTarget && other.slug == slug && other.thread == thread;

  @override
  int get hashCode => Object.hash(slug, thread);
}

/// The chat a tapped notification opens: [payload] is what it was drawn from, `{title, body,
/// data}`, and its `data` names the chat by `workspace` and `thread`. Anything else opens
/// nothing.
ChatTarget? chatTargetOf(String payload) {
  Object? json;
  try {
    json = jsonDecode(payload);
  } on FormatException {
    json = null;
  }
  final data = json is Map ? json['data'] : null;
  return switch (data) {
    {'workspace': final String slug, 'thread': final String thread}
        when slug.isNotEmpty && thread.isNotEmpty =>
      ChatTarget(slug, thread),
    _ => null,
  };
}

/// The payload of the notification that the answer in chat [thread] of workspace [slug] is
/// ready, which [chatTargetOf] reads back.
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
