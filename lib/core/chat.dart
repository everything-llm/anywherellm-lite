// Asking a workspace: what a streamed answer is made of, and how a chat gets its name.

import 'dart:typed_data';

import 'outputs.dart';
import 'server_models.dart';
import 'upload.dart';

/// A workspace's chat mode on the server, which every message in it answers in. Its [name] is
/// the server's value.
enum ChatMode {
  automatic(
    'Agent',
    'Answers from general knowledge, the switched-on files and tools such as web search.',
    'Files, knowledge and tools',
    'Can also search the web and use skills.',
  ),
  chat(
    'Chat',
    'Answers from general knowledge and the switched-on files, without tools.',
    'Files and general knowledge',
    'No tools: no web search or skills.',
  ),
  query(
    'Query',
    'Answers only from the switched-on files, and says so when they do not cover it.',
    'Files only',
    'Says so when the files do not cover it.',
  );

  const ChatMode(this.label, this.about, this.title, this.detail);

  /// The server's own name for the mode, as AnythingLLM's web UI shows it.
  final String label;

  /// What the mode answers from, in one sentence.
  final String about;

  /// What the mode answers from, as a choice in Sources.
  final String title;

  /// The line under [title].
  final String detail;

  /// The mode the server calls [value], or null for none it knows.
  static ChatMode? fromServer(Object? value) =>
      values.where((m) => m.name == value).firstOrNull;
}

/// What answers draw on in every [ChatMode], for when the mode is not known.
const everyModeDrawsOn = 'Answers draw on the switched-on files.';

/// What a new chat is called until its first message names it.
const newChatName = 'New chat';

/// A piece of a streamed answer.
sealed class ChatEvent {
  const ChatEvent();
}

/// More text of the answer.
class TextChunk extends ChatEvent {
  const TextChunk(this.text);
  final String text;
}

/// What the agent is doing now, such as running a tool. It is not part of the answer. [tool]
/// names the tool it calls, when the status is a [toolCall].
class StatusChunk extends ChatEvent {
  const StatusChunk(this.text, {this.tool});
  final String text;
  final String? tool;
}

/// The whole answer, which takes the place of the text streamed so far. An agent streams what it
/// writes before and between its tools, then sends its answer whole.
class WholeAnswer extends ChatEvent {
  const WholeAnswer(this.text);
  final String text;
}

/// An agent's status [thought] in plain words: `@agent: Using SearXNG…` loses its prefix, and
/// `@agent is executing `web-browsing` tool {…}` becomes `Running web-browsing`.
String agentStatus(String thought) {
  if (toolCall(thought) case final call?) return 'Running ${call.name}';
  final text = thought.trim().replaceFirst(_agentPrefix, '');
  return text.split('\n').first.trim();
}

/// A tool call an agent's status [thought] reports, as AnythingLLM words it when its provider
/// is verbose: ``@agent is executing `browser-act` tool {...}``, the tool's [name] and its
/// arguments, JSON as sent, in [args]; or null for any other thought.
({String name, String args})? toolCall(String thought) {
  final call = _toolCall.firstMatch(thought.trim());
  return call == null ? null : (name: call[1]!, args: call[2]!);
}

final _toolCall = RegExp(
  r'^@agent is executing `([^`]+)`(?: tool)?\s*([\s\S]*)$',
);
final _agentPrefix = RegExp(r'^@agent:?\s*');

/// The answer is complete. [citations] are what it drew on, [files] what an agent made with
/// it, and [metrics] how it ran.
class ChatDone extends ChatEvent {
  const ChatDone(
    this.citations, {
    this.files = const [],
    this.metrics,
    this.chatId,
  });
  final List<Citation> citations;
  final List<GeneratedFile> files;
  final AnswerMetrics? metrics;

  /// The server's id for the exchange, when it said.
  final int? chatId;
}

/// The address a link in an answer opens, or null for one the app will not open. Only web
/// pages and mail open; `javascript:`, `file:`, app schemes and relative paths do not.
Uri? openableLink(String href) {
  final uri = Uri.tryParse(href.trim());
  if (uri == null) return null;
  return switch (uri.scheme) {
    'http' || 'https' when uri.host.isNotEmpty => uri,
    'mailto' when uri.path.contains('@') => uri,
    _ => null,
  };
}

/// Whether an image at [uri] in an answer may load: only from [server]'s own host, on any port,
/// over https, or over http where the server itself is http and [allowHttp] lets it be. So an
/// answer cannot make the app fetch an address off that host.
bool loadableImage(Uri uri, Uri? server, {required bool allowHttp}) =>
    server != null &&
    uri.host == server.host &&
    (uri.scheme == 'https' ||
        (uri.scheme == 'http' && server.scheme == 'http' && allowHttp));

/// The failure an agent's [answer] reports in place of an answer, or null when it is an answer.
/// AnythingLLM's agent sends a model's failure as the answer's text, starting with
/// `The agent model failed to respond`, and stores it so.
String? modelFailure(String answer) {
  final text = answer.trim();
  return text.startsWith('The agent model failed to respond') ? text : null;
}

/// The name a chat takes from its first [message]: its first line, cut to 42 code points so an
/// emoji is never split.
String defaultTitle(String message) {
  final line = message.trim().split('\n').first.trim();
  if (line.isEmpty) return newChatName;
  final points = line.runes;
  if (points.length <= 42) return line;
  return '${String.fromCharCodes(points.take(41)).trimRight()}…';
}

/// A file sent with one message, read in for that message only.
class Attachment {
  /// An attachment of [bytes] named [name], typed by [attachmentMime].
  Attachment.of(this.name, this.bytes) : mime = attachmentMime(name);

  final String name;

  /// `image/...` for a picture, or [documentMime] for any other file.
  final String mime;
  final Uint8List bytes;

  bool get isImage => mime.startsWith('image/');
}

/// The type the server takes for an attached document, which it reads in for that message.
const documentMime = 'application/anythingllm-document';

/// The largest file one message may carry.
const maxAttachmentBytes = 20 * 1024 * 1024;

const _imageTypes = {
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.webp': 'image/webp',
  '.gif': 'image/gif',
};

/// `image/png` for `photo.PNG`, or [documentMime] for any file that is not a picture.
String attachmentMime(String name) {
  return _imageTypes[extensionOf(name)] ?? documentMime;
}

/// Why [name], of [size] bytes, cannot go with a message, or null.
String? attachmentProblem(String name, int size) => size > maxAttachmentBytes
    ? '$name is ${(size / (1024 * 1024)).toStringAsFixed(1)} MB; a message takes '
          '${maxAttachmentBytes ~/ (1024 * 1024)} MB at most. Add it in Sources instead.'
    : null;

/// An answer split into the model's reasoning and the answer itself.
typedef Reasoned = ({String reasoning, String answer, bool thinking});

/// A code block or span, kept as it is, or a reasoning block, open until its closing tag.
final _thought = RegExp(
  r'(```[\s\S]*?(?:```|$)|`[^`\n]*`)|<(think|thinking)>([\s\S]*?)(?:</\2>|$)',
);

/// Splits [text] into the reasoning a model wrapped in `<think>` or `<thinking>` tags and the
/// answer around it. A tag inside a code span or block is answer. [Reasoned.thinking] is true while a block is still open, as when the
/// answer is streaming. Text with no such block is all answer, except the start of an opening
/// tag that has not all arrived yet, which is held back.
Reasoned splitReasoning(String text) {
  final start = text.trimLeft();
  if (start.isNotEmpty &&
      start.length < '<thinking>'.length &&
      ('<thinking>'.startsWith(start) || '<think>'.startsWith(start))) {
    return (reasoning: '', answer: '', thinking: true);
  }
  final parts = <String>[];
  var thinking = false;
  final answer = text.replaceAllMapped(_thought, (match) {
    if (match[1] case final code?) return code;
    parts.add(match[3]!.trim());
    thinking = !match[0]!.endsWith('</${match[2]}>');
    return '';
  });
  return (
    reasoning: parts.where((p) => p.isNotEmpty).join('\n\n'),
    answer: answer.trim(),
    thinking: thinking,
  );
}
