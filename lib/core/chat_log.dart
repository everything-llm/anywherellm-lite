// The chats the server has recorded across every workspace, as its admin list gives them.

import 'server_models.dart';

/// One exchange the server recorded: the question, where and when it was asked.
class LoggedChat {
  const LoggedChat({required this.workspace, required this.question, this.at});

  factory LoggedChat.fromJson(Map<String, dynamic> json) => LoggedChat(
    workspace: switch (json['workspace']) {
      {'name': final String name} => name,
      _ => '',
    },
    question: switch (json['prompt']) {
      final String prompt => prompt,
      _ => '',
    },
    at: switch (json['createdAt']) {
      final String at => DateTime.tryParse(at),
      _ => null,
    },
  );

  /// The workspace's name, or empty when it has since been deleted.
  final String workspace;
  final String question;
  final DateTime? at;
}

/// One page of [LoggedChat]s, newest first, and whether the server has more after it.
class ChatLog {
  const ChatLog(this.chats, {required this.more});

  /// Reads the `{chats, hasPages}` the server answers.
  factory ChatLog.fromJson(Object? json) => ChatLog([
    if (json is Map)
      for (final chat in jsonObjects(json['chats'])) LoggedChat.fromJson(chat),
  ], more: json is Map && json['hasPages'] == true);

  /// How many chats the server gives a page.
  static const pageSize = 20;

  final List<LoggedChat> chats;
  final bool more;
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// When [at] was, said briefly against [now], both local: `Today 10:42`, `Yesterday`, `3 Oct`,
/// or `3 Oct 2025` in another year.
String sentText(DateTime at, DateTime now) {
  final day = DateTime(at.year, at.month, at.day);
  final today = DateTime(now.year, now.month, now.day);
  String two(int n) => n.toString().padLeft(2, '0');
  if (day == today) return 'Today ${two(at.hour)}:${two(at.minute)}';
  if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
  final date = '${at.day} ${_months[at.month - 1]}';
  return at.year == now.year ? date : '$date ${at.year}';
}
