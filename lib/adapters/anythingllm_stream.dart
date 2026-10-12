import 'dart:convert';

import '../core/chat.dart';
import '../core/outputs.dart';
import '../core/ports.dart';
import '../core/server_models.dart';

/// The answer in a `stream-chat` response: server-sent events, each a `data:` line of JSON.
///
/// See [chatEventsOf] for what the chunks become.
Stream<ChatEvent> chatEvents(Stream<List<int>> bytes) =>
    chatEventsOf(_dataChunks(bytes));

/// The answer in the `stream-chat` [chunks], each a chunk's JSON as the server sent it.
///
/// A chat or query answer streams `textResponse` pieces, and the closing chunk (`close: true`)
/// has the `sources`. An agent answer also streams `agentThought` chunks, which become
/// [StatusChunk]s; its pieces include what it wrote before and between tools, so the whole
/// answer then comes as one `textResponse` chunk, a [WholeAnswer]. The pieces on either side of
/// a tool come without space between them, so a piece after a status line starts a new
/// paragraph, unless either side already has space there. A `finalizeResponseStream`
/// chunk after the close has an agent's `sources`, and the `outputs` it made, as files.
/// Whichever chunk carries the answer's `metrics` hands them on.
///
/// Ends with one [ChatDone], at `finalizeResponseStream` or when the chunks end. Fails with
/// [ApiException] when the server reports an error.
Stream<ChatEvent> chatEventsOf(Stream<Map<String, dynamic>> chunks) async* {
  var citations = const <Citation>[];
  var files = const <GeneratedFile>[];
  AnswerMetrics? metrics;
  int? chatId;
  var whole = false;
  // The last character of text yielded, and whether a status line came after it.
  String? last;
  var afterStatus = false;
  await for (final chunk in chunks) {
    final error = chunk['error'];
    if (error is String && error.trim().isNotEmpty) {
      throw ApiException(error.trim());
    }
    final text = chunk['textResponse'];
    final found = citationsOf(chunk['sources']);
    if (found.isNotEmpty) citations = found;
    final made = generatedFilesOf(chunk['outputs']);
    if (made.isNotEmpty) files = made;
    metrics = metricsOf(chunk['metrics']) ?? metrics;
    if (chunk['chatId'] case final int id) chatId = id;
    switch (chunk['type']) {
      case 'abort':
        throw const ApiException('The server stopped the answer.');
      case 'agentThought':
        if (chunk['thought'] case final String thought
            when thought.trim().isNotEmpty) {
          afterStatus = true;
          yield StatusChunk(agentStatus(thought));
        }
      case 'textResponse':
        if (text is String && text.isNotEmpty) {
          whole = true;
          last = text[text.length - 1];
          yield WholeAnswer(text);
        }
      case 'finalizeResponseStream':
        if (!whole && text is String && text.isNotEmpty) {
          yield WholeAnswer(text);
        }
        yield ChatDone(
          citations,
          files: files,
          metrics: metrics,
          chatId: chatId,
        );
        return;
      case 'usageMetrics':
        break;
      default:
        if (text is String && text.isNotEmpty) {
          final apart =
              afterStatus && last != null && !_spaced.hasMatch(last + text[0]);
          afterStatus = false;
          last = text[text.length - 1];
          yield TextChunk(apart ? '\n\n$text' : text);
        }
    }
  }
  yield ChatDone(citations, files: files, metrics: metrics, chatId: chatId);
}

final _spaced = RegExp(r'\s');

/// The JSON object of each `data:` line in [bytes]; any other line is skipped.
Stream<Map<String, dynamic>> _dataChunks(Stream<List<int>> bytes) async* {
  await for (final line
      in bytes.transform(utf8.decoder).transform(const LineSplitter())) {
    if (!line.startsWith('data:')) continue;
    if (jsonOrNull(line.substring(5).trim())
        case final Map<String, dynamic> c) {
      yield c;
    }
  }
}

/// The decoded JSON of [text], or null when it is not JSON.
Object? jsonOrNull(String text) {
  try {
    return jsonDecode(text);
  } on FormatException {
    return null;
  }
}
