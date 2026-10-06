import 'dart:convert';

import '../core/chat.dart';
import '../core/ports.dart';
import '../core/server_models.dart';

/// The answer in a `stream-chat` response: server-sent events, each a `data:` line of JSON.
///
/// A chat or query answer streams `textResponse` pieces, and the closing chunk (`close: true`)
/// has the `sources`. An agent answer also streams `agentThought` chunks, which become
/// [StatusChunk]s; its pieces include what it wrote before and between tools, so the whole
/// answer then comes as one `textResponse` chunk, a [WholeAnswer]. A `finalizeResponseStream`
/// chunk after the close has an agent's `sources`.
///
/// Ends with one [ChatDone], at `finalizeResponseStream` or when the stream ends. Fails with
/// [ApiException] when the server reports an error.
Stream<ChatEvent> chatEvents(Stream<List<int>> bytes) async* {
  var citations = const <String>[];
  var whole = false;
  await for (final line
      in bytes.transform(utf8.decoder).transform(const LineSplitter())) {
    if (!line.startsWith('data:')) continue;
    final Object? chunk;
    try {
      chunk = jsonDecode(line.substring(5).trim());
    } on FormatException {
      continue;
    }
    if (chunk is! Map<String, dynamic>) continue;
    final error = chunk['error'];
    if (error is String && error.trim().isNotEmpty) {
      throw ApiException(error.trim());
    }
    final text = chunk['textResponse'];
    final found = citationsOf(chunk['sources']);
    if (found.isNotEmpty) citations = found;
    switch (chunk['type']) {
      case 'abort':
        throw const ApiException('The server stopped the answer.');
      case 'agentThought':
        if (chunk['thought'] case final String thought
            when thought.trim().isNotEmpty) {
          yield StatusChunk(agentStatus(thought));
        }
      case 'textResponse':
        if (text is String) {
          whole = true;
          yield WholeAnswer(text);
        }
      case 'finalizeResponseStream':
        if (!whole && text is String && text.isNotEmpty) {
          yield WholeAnswer(text);
        }
        yield ChatDone(citations);
        return;
      case 'usageMetrics':
        break;
      default:
        if (text is String && text.isNotEmpty) yield TextChunk(text);
    }
  }
  yield ChatDone(citations);
}
