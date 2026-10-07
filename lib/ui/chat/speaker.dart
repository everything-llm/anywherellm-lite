import 'package:flutter/foundation.dart';

import '../../core/chat.dart';
import '../../core/markdown.dart';
import '../state/chat_controller.dart';

/// Reads text aloud with the device's own speech.
abstract interface class Speaker {
  /// Reads [text] aloud, stopping anything read before. Resolves when the reading ends, whether
  /// it finished or [stop] ended it. Throws [Exception] when the device cannot speak.
  Future<void> speak(String text);

  /// Ends the reading.
  Future<void> stop();
}

/// Which answer is being read aloud, if any. One reads at a time, and it stops when its answer
/// leaves the screen: another chat, workspace or server is shown.
class ReadAloud extends ChangeNotifier {
  ReadAloud(this._speaker, this._chat) {
    _chat.addListener(_follow);
  }

  final Speaker _speaker;
  final ChatController _chat;

  /// The answer being read.
  Turn? reading;

  /// Reads [turn]'s answer, without its reasoning or Markdown, or stops it when it is the one
  /// being read. A failure shows as the chat's problem.
  Future<void> toggle(Turn turn) async {
    if (identical(reading, turn)) return stop();
    reading = turn;
    notifyListeners();
    try {
      await _speaker.speak(plainText(splitReasoning(turn.text).answer));
    } on Exception catch (error) {
      if (identical(reading, turn)) {
        _chat.report(
          'Could not read the answer aloud',
          '$error'.replaceFirst(RegExp('^Exception: '), ''),
        );
      }
    }
    if (identical(reading, turn)) {
      reading = null;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    if (reading == null) return;
    reading = null;
    notifyListeners();
    await _speaker.stop();
  }

  void _follow() {
    if (reading case final turn? when !_chat.turns.contains(turn)) stop();
  }

  @override
  void dispose() {
    _chat.removeListener(_follow);
    _speaker.stop();
    super.dispose();
  }
}
