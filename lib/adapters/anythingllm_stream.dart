import 'dart:convert';

import '../core/chat.dart';
import '../core/ports.dart';
import '../core/server_models.dart';

/// The answer in a `stream-chat` response: server-sent events, each a `data:` line of JSON
/// with `textResponse`, `sources`, `close` and `error`. The sources come with the last chunk.
///
/// Ends with one [ChatDone], when the server closes the answer or the stream ends. Fails with
/// [ApiException] when the server reports an error.
Stream<ChatEvent> chatEvents(Stream<List<int>> bytes) async* {
  var citations = const <String>[];
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
    if (chunk['type'] == 'abort') {
      throw const ApiException('The server stopped the answer.');
    }
    final text = chunk['textResponse'];
    if (text is String && text.isNotEmpty) yield TextChunk(text);
    final found = citationsOf(chunk['sources']);
    if (found.isNotEmpty) citations = found;
    if (chunk['close'] == true) {
      yield ChatDone(citations);
      return;
    }
  }
  yield ChatDone(citations);
}
