// Asking a workspace: what a streamed answer is made of, and how a chat gets its name.

/// How the server answers: [query] only from the workspace's documents, [chat] from general
/// knowledge too.
enum ChatMode { query, chat }

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

/// The answer is complete. [citations] are the titles of the documents it drew on.
class ChatDone extends ChatEvent {
  const ChatDone(this.citations);
  final List<String> citations;
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
  const Attachment({
    required this.name,
    required this.mime,
    required this.bytes,
  });

  /// An attachment of [bytes] named [name], typed by [attachmentMime].
  Attachment.of(this.name, this.bytes) : mime = attachmentMime(name);

  final String name;

  /// `image/...` for a picture, or [documentMime] for any other file.
  final String mime;
  final List<int> bytes;

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
  final dot = name.lastIndexOf('.');
  final extension = dot <= 0 ? '' : name.substring(dot).toLowerCase();
  return _imageTypes[extension] ?? documentMime;
}

/// Why [name], of [size] bytes, cannot go with a message, or null.
String? attachmentProblem(String name, int size) => size > maxAttachmentBytes
    ? '$name is ${(size / (1024 * 1024)).toStringAsFixed(1)} MB; a message takes '
          '${maxAttachmentBytes ~/ (1024 * 1024)} MB at most. Add it in Sources instead.'
    : null;
