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

/// The name a chat takes from its first [message]: its first line, cut to 42 characters.
String defaultTitle(String message) {
  final line = message.trim().split('\n').first.trim();
  if (line.isEmpty) return newChatName;
  return line.length <= 42 ? line : '${line.substring(0, 41).trimRight()}…';
}
