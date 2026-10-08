// Chat embeds: a chat box for one workspace that a web page carries, and the chats it held.

import 'dart:convert';

/// The modes an embed answers in. The server takes only these two; an agent never runs in one.
enum EmbedMode {
  chat('Chat'),
  query('Query');

  const EmbedMode(this.label);
  final String label;

  static EmbedMode fromServer(Object? value) =>
      values.where((m) => m.name == value).firstOrNull ?? query;
}

/// A chat embed as the server lists it. The list leaves out its allowed sites and limits, so
/// they are set when it is made and not shown after.
class Embed {
  const Embed({
    required this.uuid,
    required this.workspace,
    required this.mode,
    required this.enabled,
    this.chats = 0,
  });

  factory Embed.fromJson(Map<String, dynamic> json) => Embed(
    uuid: switch (json['uuid']) {
      final String uuid => uuid,
      _ => '',
    },
    workspace: switch (json['workspace']) {
      {'name': final String name} => name,
      _ => 'A deleted workspace',
    },
    mode: EmbedMode.fromServer(json['chat_mode']),
    enabled: json['enabled'] == true,
    chats: switch (json['chat_count']) {
      final num n => n.toInt(),
      _ => 0,
    },
  );

  final String uuid;

  /// The name of the workspace it answers from.
  final String workspace;
  final EmbedMode mode;
  final bool enabled;

  /// How many chats it has held.
  final int chats;
}

/// What a new embed is made with. A null limit is none.
class NewEmbed {
  const NewEmbed({
    required this.workspaceSlug,
    this.mode = EmbedMode.query,
    this.sites = const [],
    this.chatsPerDay,
    this.chatsPerSession,
  });

  final String workspaceSlug;
  final EmbedMode mode;

  /// The sites the embed answers on, such as `example.com`; empty for any site.
  final List<String> sites;
  final int? chatsPerDay;
  final int? chatsPerSession;

  Map<String, Object?> toJson() => {
    'workspace_slug': workspaceSlug,
    'chat_mode': mode.name,
    if (sites.isNotEmpty) 'allowlist_domains': sites,
    'max_chats_per_day': ?chatsPerDay,
    'max_chats_per_session': ?chatsPerSession,
  };
}

/// [text] as the sites an embed answers on: split at commas, spaces and new lines, empty parts
/// dropped.
List<String> sitesOf(String text) => [
  for (final part in text.split(RegExp(r'[\s,]+')))
    if (part.isNotEmpty) part,
];

/// One question a visitor asked an embed, and its answer.
class EmbedChat {
  const EmbedChat({
    required this.session,
    required this.question,
    required this.answer,
    this.at,
  });

  /// The server keeps an answer as JSON holding its `text`, or as the text itself.
  factory EmbedChat.fromJson(Map<String, dynamic> json) {
    final response = json['response'];
    final decoded = response is String ? _jsonOrNull(response) : response;
    return EmbedChat(
      session: switch (json['session_id']) {
        final String id => id,
        _ => '',
      },
      question: switch (json['prompt']) {
        final String prompt => prompt,
        _ => '',
      },
      answer: switch (decoded) {
        {'text': final String text} => text,
        _ => response is String ? response : '',
      },
      at: switch (json['createdAt']) {
        final String at => DateTime.tryParse(at),
        _ => null,
      },
    );
  }

  /// The visitor's session, which ties their questions together.
  final String session;
  final String question;
  final String answer;
  final DateTime? at;
}

Object? _jsonOrNull(String text) {
  try {
    return jsonDecode(text);
  } on FormatException {
    return null;
  }
}

/// The HTML a web page carries to show [uuid]'s chat box, served by the server at [server].
String embedSnippet(Uri server, String uuid) {
  final base = server.replace(query: null, fragment: null);
  final origin = base.toString().replaceFirst(RegExp(r'[/?#]+$'), '');
  return '<script\n'
      '  data-embed-id="$uuid"\n'
      '  data-base-api-url="$origin/api/embed"\n'
      '  src="$origin/embed/anythingllm-chat-widget.min.js">\n'
      '</script>';
}
