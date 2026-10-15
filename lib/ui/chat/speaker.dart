import 'package:flutter/foundation.dart';

import '../../core/chat.dart';
import '../../core/errors.dart';
import '../../core/markdown.dart';
import '../../core/prefs.dart';
import '../state/chat_controller.dart';
import '../state/prefs_controller.dart';

/// Reads text aloud with the device's own speech.
abstract interface class Speaker {
  /// Reads [text] aloud, stopping anything read before. Resolves when the reading ends, whether
  /// it finished or [stop] ended it. Throws [Exception] when the device cannot speak.
  Future<void> speak(String text);

  /// Ends the reading.
  Future<void> stop();
}

/// Which answer is being read aloud, if any. One reads at a time, and it stops when its answer
/// leaves the screen: another chat, workspace or server is shown. With [ChatSwitch.readAnswers]
/// on, each answer that runs to its end is read as it finishes.
class ReadAloud extends ChangeNotifier {
  ReadAloud(this._speaker, this._chat, this._prefs) : _heard = _chat.finished {
    _chat.addListener(_follow);
  }

  final Speaker _speaker;
  final ChatController _chat;
  final PrefsController _prefs;

  /// The finished answer last seen, so each is read once.
  Turn? _heard;

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
        _chat.report('Could not read the answer aloud', plainMessage(error));
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
    final finished = _chat.finished;
    if (identical(finished, _heard)) return;
    _heard = finished;
    if (finished != null &&
        _prefs.prefs.isOn(ChatSwitch.readAnswers) &&
        _chat.turns.contains(finished) &&
        _readable(finished)) {
      toggle(finished);
    }
  }

  /// Whether [turn] has an answer to read, as the chat shows Read aloud for it: some answer
  /// beside its reasoning, and not the model's failure.
  static bool _readable(Turn turn) {
    final answer = splitReasoning(turn.text).answer;
    return answer.isNotEmpty && modelFailure(answer) == null;
  }

  @override
  void dispose() {
    _chat.removeListener(_follow);
    _speaker.stop();
    super.dispose();
  }
}
