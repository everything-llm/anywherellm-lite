// Asking a workspace: what a streamed answer is made of, and how a chat gets its name.

import 'dart:typed_data';

import 'package:characters/characters.dart';

import 'connection.dart';
import 'outputs.dart';
import 'server_models.dart';
import 'upload.dart';

/// A workspace's chat mode on the server, which every message in it answers in. Its [name] is
/// the server's value: Agent (`automatic`), Chat or Query.
enum ChatMode {
  automatic(
    'Files, knowledge & tools',
    'Can also search the web and use skills.',
  ),
  chat('Files & knowledge', 'No tools: no web search or skills.'),
  query('Files only', 'Says so when the files do not cover it.');

  const ChatMode(this.title, this.detail);

  /// What the mode answers from, in plain words, as the composer's Answer from chip names it.
  final String title;

  /// The line under [title] in the Answer from menu.
  final String detail;

  /// The mode the server calls [value], or null for none it knows.
  static ChatMode? fromServer(Object? value) =>
      values.where((m) => m.name == value).firstOrNull;
}

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

/// What the agent is doing now, such as running a tool. It is not part of the answer.
class StatusChunk extends ChatEvent {
  const StatusChunk(this.text);
  final String text;
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
/// is verbose: ``@agent is executing `web-browsing` tool {...}``, the tool's [name] and its
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

/// [address] as an answer means it: a path from the root, such as `/browser-lean/3kQ.html`,
/// which an agent skill writes for AnythingLLM's own chat, is on [server]'s origin, as that chat
/// reads it; any other address is as written.
Uri onServer(Uri address, Uri? server) =>
    server != null &&
        !address.hasScheme &&
        !address.hasAuthority &&
        address.path.startsWith('/')
    ? server.resolveUri(address)
    : address;

/// The address [link] in an answer opens, or null for one the app will not open. Only web
/// pages and mail open; `javascript:`, `file:` and app schemes do not, and a relative path only
/// as a path from the root of [server] ([onServer]).
Uri? openableLink(Uri link, {Uri? server}) {
  final uri = onServer(link, server);
  if (isWebAddress(uri)) return uri;
  return uri.scheme == 'mailto' && uri.path.contains('@') ? uri : null;
}

/// Whether [uri] is a web page's address: http or https, with a host.
bool isWebAddress(Uri uri) =>
    (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;

/// Whether an image at [uri] in an answer may load: only from [server]'s own host, on any port,
/// over https, or over http on a private network ([keySafe]). So an answer cannot make the app
/// fetch an address off that host.
bool loadableImage(Uri uri, Uri? server) =>
    server != null && uri.host == server.host && keySafe(uri);

/// The failure an agent's [answer] reports in place of an answer, or null when it is an answer.
/// AnythingLLM's agent sends a model's failure as the answer's text, starting with
/// `The agent model failed to respond`, and stores it so.
String? modelFailure(String answer) {
  final text = answer.trim();
  return text.startsWith('The agent model failed to respond') ? text : null;
}

/// The ways a model's provider says it takes text only, as when a picture was sent: Z.ai's
/// `allowed values: ['text']`, OpenAI's `image_url is only supported by certain models`,
/// OpenRouter's `No endpoints found that support image input`, and the plain `does not support
/// image(s)` or `vision` others send.
final _textOnly = RegExp(
  r"allowed values: \[\s*'text'\s*\]"
  r'|image_url is only supported'
  r'|support(s)? image input'
  r'|(does not|doesn.t|not) support (images?|vision|multimodal)\b(?! generation)',
  caseSensitive: false,
);

/// Whether [failure], a model's failure or a failed answer's error, says the model refused a
/// picture because it takes text only.
bool refusesPictures(String failure) => _textOnly.hasMatch(failure);

/// The ways a model's provider says it has too much to do: a 429 or 529, a rate limit, an
/// overloaded or busy model, Gemini's `RESOURCE_EXHAUSTED`.
final _busy = RegExp(
  r'\b(429|529)\b|rate.?limit|too many requests|overloaded|\bbusy\b|resource.?exhausted',
  caseSensitive: false,
);

/// The seconds a provider says to wait, as in OpenAI's `Please try again in 20s.` or a
/// `retry after 20 seconds`.
final _waitFor = RegExp(
  r'(?:try again|retry)(?: after| in)(?: about)? (\d+(?:\.\d+)?) ?(?:s\b|secs?\b|seconds?\b)',
  caseSensitive: false,
);

/// What a failed answer's [error] says in few words, as the chat shows it under Answer
/// stopped.: a provider with too much to do is `The model is busy right now.`, with how long to
/// wait when it says, and any other error as it came, since nothing shorter says as much.
String failureText(String error) {
  if (!_busy.hasMatch(error)) return error;
  final wait = switch (_waitFor.firstMatch(error)) {
    final match? => double.parse(match[1]!).ceil(),
    null => null,
  };
  final when = wait == null || wait > 120
      ? 'a minute'
      : wait <= 1
      ? 'about a second'
      : 'about $wait seconds';
  return 'The model is busy right now. Ask again in $when.';
}

/// The name a chat takes from its first [message]: its first line, cut to 42 characters.
String defaultTitle(String message) {
  final line = message.trim().split('\n').first.trim();
  return line.isEmpty ? newChatName : clip(line, 42);
}

/// [text] cut to [max] characters as a person sees them, so an emoji is never split, ending in
/// an ellipsis when it was cut.
String clip(String text, int max) {
  final shown = text.characters;
  if (shown.length <= max) return text;
  return '${shown.take(max - 1).toString().trimRight()}…';
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

  /// This file as a sent question shows it: a picture with its bytes, any other by its name.
  SentFile get sent => isImage ? SentFile.picture(name, bytes) : SentFile(name);
}

/// The type the server takes for an attached document, which it reads in for that message.
const documentMime = 'application/anythingllm-document';

/// The mode a message with [attachments] is sent in, over the workspace's [mode], or null to
/// leave it to the workspace: [ChatMode.chat] when a document goes in [ChatMode.automatic].
/// AnythingLLM 1.16.2 reads a document in only outside an agent run; its agent sends every
/// attachment to the model as a picture.
ChatMode? modeForFiles(ChatMode? mode, List<Attachment> attachments) =>
    mode == ChatMode.automatic && attachments.any((a) => !a.isImage)
    ? ChatMode.chat
    : null;

/// Whether AnythingLLM 1.16.2 finishes an answer to [message], asked in [mode], and saves it
/// whole after the connection drops: an agent runs to its end, in [ChatMode.automatic] or for a
/// message that starts with `@agent`, while a chat or query answer stops once the server notices
/// the drop and saves what was written by then. Null when [mode] is not known.
bool? finishesWhenDropped(ChatMode? mode, String message) =>
    message.trimLeft().startsWith('@agent')
    ? true
    : switch (mode) {
        ChatMode.automatic => true,
        ChatMode.chat || ChatMode.query => false,
        null => null,
      };

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

/// The picture types a message can carry, such as `image/png`.
final imageMimes = _imageTypes.values.toSet();

/// A name for a pasted picture of type [mime] that none of [taken] has, such as
/// `Pasted image 2.png`, or null when [mime] is not one of [imageMimes].
String? pastedImageName(String mime, Iterable<String> taken) {
  final extension = _imageTypes.entries
      .where((e) => e.value == mime.toLowerCase())
      .firstOrNull
      ?.key;
  if (extension == null) return null;
  final names = taken.toSet();
  for (var n = 1; ; n++) {
    final name = 'Pasted image${n == 1 ? '' : ' $n'}$extension';
    if (!names.contains(name)) return name;
  }
}

/// Why [name], of [size] bytes, cannot go with a message, or null.
String? attachmentProblem(String name, int size) => size > maxAttachmentBytes
    ? '$name is ${sizeText(size)}; a message takes '
          '${maxAttachmentBytes ~/ (1024 * 1024)} MB at most. Add it in Documents instead.'
    : null;

/// An answer split into the model's reasoning and the answer itself.
typedef Reasoned = ({String reasoning, String answer, bool thinking});

/// A code block or span, kept as it is, or a reasoning block, open until its closing tag.
final _thought = RegExp(
  r'(```[\s\S]*?(?:```|$)|`[^`\n]*`)|<(think|thinking)>([\s\S]*?)(?:</\2>|$)',
);

/// Splits [text] into the reasoning a model wrapped in `<think>` or `<thinking>` tags and the
/// answer around it. A tag inside a code span or block is answer. [Reasoned.thinking] is true
/// while a block is still open, as when the answer is streaming. Text with no such block is all
/// answer, except, while [streaming], the start of an opening tag that has not all arrived yet,
/// which is held back. Once the text is no longer
/// [streaming], a block that never closed is answer unless the text opens with it, since a
/// bare tag in prose would otherwise take the rest of the answer with it.
Reasoned splitReasoning(String text, {bool streaming = false}) {
  final start = text.trimLeft();
  if (streaming &&
      start.isNotEmpty &&
      start.length < '<thinking>'.length &&
      ('<thinking>'.startsWith(start) || '<think>'.startsWith(start))) {
    return (reasoning: '', answer: '', thinking: true);
  }
  final parts = <String>[];
  var thinking = false;
  final answer = text.replaceAllMapped(_thought, (match) {
    if (match[1] case final code?) return code;
    final open = !match[0]!.endsWith('</${match[2]}>');
    if (open &&
        !streaming &&
        text.substring(0, match.start).trim().isNotEmpty) {
      return match[0]!;
    }
    parts.add(match[3]!.trim());
    thinking = open;
    return '';
  });
  return (
    reasoning: parts.where((p) => p.isNotEmpty).join('\n\n'),
    answer: answer.trim(),
    thinking: thinking,
  );
}
