import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import '../../core/chat.dart';
import '../../core/outputs.dart';
import '../../core/shortcuts.dart';
import '../../core/server_models.dart';

/// One turn on screen. An answer grows while it streams, and notifies only its own listeners
/// as it does, so a chunk rebuilds the answer and nothing else.
class Turn extends ChangeNotifier {
  Turn.user(this.text, {this.attachments = const [], this.shortcutUse})
    : role = Role.user,
      streaming = false,
      asked = null;

  Turn.answer()
    : role = Role.assistant,
      text = '',
      streaming = true,
      asked = clock.now();

  Turn.saved(ChatMessage message, {this.shortcutUse})
    : role = message.role,
      text = message.text,
      citations = message.citations,
      attachments = message.attachments,
      files = message.files,
      metrics = message.metrics,
      chatId = message.chatId,
      streaming = false,
      asked = null;

  final Role role;
  String text;

  /// When an answer's question was sent, or null for a question or a saved answer.
  final DateTime? asked;

  /// The files sent with a question.
  List<SentFile> attachments = const [];
  List<Citation> citations = const [];

  /// The local shortcut and detail that produced this question, if known.
  ShortcutUse? shortcutUse;

  /// What an agent made with the answer.
  List<GeneratedFile> files = const [];

  /// How the answer ran, when the server measured it.
  AnswerMetrics? metrics;

  /// The server's id for the exchange, once it has said, which tells a saved answer from the
  /// ones before it.
  int? chatId;
  bool streaming;

  /// Why the answer failed, or null.
  String? error;

  /// Whether this question never reached the server: the chat shows it as Not sent, to try
  /// again or edit.
  bool notSent = false;

  /// Whether the person stopped the answer.
  bool stopped = false;

  /// Whether the connection dropped while the server may still be writing the answer: the chat
  /// is read until the server has saved it ([ChatController.checkWaiting]).
  bool waiting = false;

  /// Whether the server may finish this answer after the app let go of it: it failed, was
  /// stopped or is [waiting].
  bool get unfinished =>
      role == Role.assistant && (error != null || stopped || waiting);

  /// What an agent is doing while the answer runs, such as a tool it runs, or null.
  String? status;

  /// Ends the wait for a [waiting] answer, showing whatever was set on it meanwhile.
  void stopWaiting() {
    waiting = false;
    notifyListeners();
  }

  /// Takes [event] of the streamed answer: more text, a status line, the whole answer, or what
  /// came with its end. Only what is drawn as it streams notifies.
  void take(ChatEvent event) {
    switch (event) {
      case TextChunk(:final text):
        this.text += text;
      case StatusChunk(:final text):
        status = text;
      case WholeAnswer(:final text):
        this.text = text;
      case ChatDone(
        :final citations,
        :final files,
        :final metrics,
        :final chatId,
      ):
        this
          ..citations = citations
          ..files = files
          ..metrics = metrics
          ..chatId = chatId;
        return;
    }
    notifyListeners();
  }
}
