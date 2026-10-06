// Slash commands: the server's presets, which it expands itself, and the one built-in, /reset.

import 'errors.dart';

/// A command a message can start with. The server swaps [command] for [prompt] when the message
/// is asked.
class SlashCommand {
  const SlashCommand({
    required this.command,
    required this.prompt,
    this.description = '',
  });

  /// A preset as `GET /api/system/slash-command-presets` lists it, or null when it has no
  /// command.
  static SlashCommand? fromJson(Map<String, dynamic> json) {
    final command = json['command'];
    if (command is! String || !command.startsWith('/')) return null;
    final prompt = json['prompt'];
    final description = json['description'];
    return SlashCommand(
      command: command,
      prompt: prompt is String ? prompt : '',
      description: description is String ? description : '',
    );
  }

  /// Starts with a slash: `/deep-research`.
  final String command;
  final String prompt;
  final String description;
}

/// The built-in command that clears a chat's history. The developer API takes it as a flag, not
/// as text.
const resetCommand = SlashCommand(
  command: '/reset',
  prompt: '/reset',
  description: 'Clear the chat history and begin a new chat',
);

/// [resetCommand] and then [presets], leaving out a preset named like a built-in, which the
/// server never runs.
List<SlashCommand> withBuiltIns(List<SlashCommand> presets) => [
  resetCommand,
  for (final p in presets)
    if (p.command.toLowerCase() != resetCommand.command) p,
];

/// The commands to offer while [draft] is being typed: those that start with it, when it is a
/// slash and the start of one word. Empty otherwise.
List<SlashCommand> commandsFor(String draft, List<SlashCommand> commands) {
  if (!draft.startsWith('/') || draft.contains(_space)) return const [];
  final typed = draft.toLowerCase();
  return [
    for (final c in commands)
      if (c.command.toLowerCase().startsWith(typed)) c,
  ];
}

final _space = RegExp(r'\s');

/// Why the server's presets could not be listed, from the [error] reading them failed with. A
/// 401 or 403 means the server has a password, since the list takes the web UI's session.
String whyNoPresets(ApiException error) =>
    error.status == 401 || error.status == 403
    ? 'This server has a password, so its own commands can\'t be listed here. One typed in full still runs.'
    : 'The server\'s own commands could not be listed. One typed in full still runs.';

/// [message] with each preset swapped for its prompt where it starts the message or follows a
/// space and is not the start of a longer command, as the server does.
String expandPresets(String message, List<SlashCommand> presets) {
  var expanded = message;
  for (final p in presets) {
    final pattern = RegExp(
      '(^|\\s)(${RegExp.escape(p.command)})(?![a-z0-9_-])',
    );
    expanded = expanded.replaceAllMapped(pattern, (m) => '${m[1]}${p.prompt}');
  }
  return expanded;
}

final _reset = RegExp(r'^/reset(?![a-z0-9_-])', caseSensitive: false);

/// Whether [message] asks to clear the chat: it starts with `/reset`, or with a preset whose
/// prompt does.
bool resetsChat(String message, List<SlashCommand> presets) =>
    _reset.hasMatch(expandPresets(message.trim(), presets).trimLeft());
