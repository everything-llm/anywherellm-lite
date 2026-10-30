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
      asked = clock.now() {
    heard = asked;
  }

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

  /// When the server last sent something for a streaming answer: its question going out, then
  /// each piece of it, or a check that the server is still there ([listened]).
  DateTime? heard;

  /// How long an answer streams with nothing from the server before it counts as [quiet].
  static const quietAfter = Duration(seconds: 30);

  /// Whether this answer streams and nothing came from the server for [quietAfter].
  bool get quiet =>
      streaming &&
      heard != null &&
      clock.now().difference(heard!) >= quietAfter;

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

  /// How this answer stands since its connection dropped, or null for one whose connection held.
  Dropped? dropped;

  /// Whether this answer was read from the server after its connection dropped, in a mode in
  /// which AnythingLLM stops an answer once it notices the drop and saves what was written: it
  /// may be cut short ([finishesWhenDropped]).
  bool mayBeCut = false;

  /// Whether the server may finish this answer after the app let go of it: it failed, was
  /// stopped or is [waiting].
  bool get unfinished =>
      role == Role.assistant && (error != null || stopped || waiting);

  /// What an agent is doing while the answer runs, such as a tool it runs, or null.
  String? status;

  /// Says how this dropped answer stands now.
  void droppedAs(Dropped how) {
    if (dropped == how) return;
    dropped = how;
    notifyListeners();
  }

  /// Ends the wait for a [waiting] answer, showing whatever was set on it meanwhile.
  void stopWaiting() {
    waiting = false;
    notifyListeners();
  }

  /// Starts [quietAfter] again from now, as when the person checks on a [quiet] answer.
  void listened() {
    heard = clock.now();
    notifyListeners();
  }

  /// Takes [event] of the streamed answer: more text, a status line, the whole answer, or what
  /// came with its end. Only what is drawn as it streams notifies.
  void take(ChatEvent event) {
    heard = clock.now();
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

/// How an answer whose connection dropped stands, while and after its chat is read for what the
/// server saved.
enum Dropped {
  /// No read since the drop has reached the server: the connection is lost.
  lost,

  /// A read reached the server, which has not saved the answer yet: it is still answering.
  answering,

  /// The server saved no answer in all the time the chat was read for one.
  unsaved,

  /// The chat moved on before the server's answer was read.
  movedOn,
}
